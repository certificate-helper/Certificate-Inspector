import UIKit
import CertificateKit

class InputTableViewController: UITableViewController, CKGetterDelegate {
    enum PendingCellStates {
        case none
        case loading
        case error
    }

    var getter: CKGetter?
    var pendingCellState: PendingCellStates = .none
    var placeholderDomains: [String] = []
    let tipKeys: [String] = ["tlstip1", "tlstip2", "tlstip3", "tlstip5", "tlstip6", "tlstip7"]

    var certificateChain: CKCertificateChain?
    var serverInfo: CKServerInfo?
    var chainError: Error?
    var serverError: Error?

    var domainInput: UITextField?
    @IBOutlet weak var inspectButton: UIBarButtonItem!
    @IBOutlet weak var tipView: UIView!
    @IBOutlet weak var tipTextView: UILabel!

    override func viewDidLoad() {
        if let domains = loadPlaceholderDomains() {
            self.placeholderDomains = domains
        }

        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        if let tip = tipKeys.randomElement() {
            self.tipTextView.text = lang(key: tip)
        }

        if let placeholder = placeholderDomains.randomElement() {
            domainInput?.placeholder = placeholder
        }

        super.viewWillAppear(animated)
    }

    func loadPlaceholderDomains() -> [String]? {
        guard let domainListPath = Bundle.main.path(forResource: "DomainList", ofType: "plist") else {
            return nil
        }
        guard let domains = NSArray.init(contentsOfFile: domainListPath) as? [String] else {
            return nil
        }
        return domains
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        if UserOptions.rememberRecentLookups && RecentLookups.GetRecentLookups().count > 0 {
            return 2
        }
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            if self.pendingCellState != .none {
                return 2
            }
            return 1
        } else if section == 1 {
            return RecentLookups.GetRecentLookups().count
        }
        return 0
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 56.0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            if indexPath.row == 1 {
                var cell: UITableViewCell!
                if self.pendingCellState == .loading {
                    cell = tableView.dequeueReusableCell(withIdentifier: "Loading", for: indexPath)
                    if let activity = cell.viewWithTag(1) as? UIActivityIndicatorView {
                        activity.startAnimating()

                        if #available(iOS 13, *) {
                            activity.style = .medium
                        }
                    }
                } else if self.pendingCellState == .error {
                    cell = tableView.dequeueReusableCell(withIdentifier: "Error", for: indexPath)
                }
                return cell
            }

            let cell = tableView.dequeueReusableCell(withIdentifier: "Input", for: indexPath)

            if let textField = cell.viewWithTag(1) as? UITextField {
                self.domainInput = textField
                textField.placeholder = placeholderDomains.randomElement()
                textField.addTarget(self, action: #selector(self.domainInputChanged(sender:)), for: .editingChanged)
            }

            return cell
        } else if indexPath.section == 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "Basic", for: indexPath)
            cell.textLabel?.text = RecentLookups.GetRecentLookups()[indexPath.row]
            return cell
        }

        return UITableViewCell()
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return lang(key: "Domain Name or IP Address")
        } else if section == 1 {
            return lang(key: "Recent Lookups")
        }
        return ""
    }

    @objc func domainInputChanged(sender: UITextField) {
        if let text = sender.text {
            self.inspectButton.isEnabled = text.count > 0
        } else {
            self.inspectButton.isEnabled = false
        }
    }

    @IBAction func inspectButtonPressed(_ sender: UIBarButtonItem) {
        let text = self.domainInput?.text ?? ""
        self.inspectDomain(text: text)
    }

    func inspectDomain(text: String) {
        self.domainInput?.isEnabled = false
        var insertRow = false
        if self.pendingCellState == .none {
            insertRow = true
        }
        self.pendingCellState = .loading

        if insertRow {
            self.tableView.insertRows(at: [IndexPath(row: 1, section: 0)], with: .automatic)
        } else {
            self.tableView.reloadRows(at: [IndexPath(row: 1, section: 0)], with: .automatic)
        }

        self.inspectButton.isEnabled = false

        var domainText = text
        if domainText.hasPrefix("http://") {
            showInputError()
        }

        if !domainText.hasPrefix("https://") {
            domainText = "https://" + domainText
        }

        let options = CKGetterOptions()

        options.checkOCSP = UserOptions.queryOCSP
        options.checkCRL = UserOptions.checkCRL
        options.queryServerInfo = UserOptions.getHTTPHeaders
        options.useOpenSSL = true
        options.ciphers = "HIGH:!aNULL:!MD5:!RC4"
        CertificateKit.setLoggingLevel(.debug)

        self.getter = CKGetter(options: options)
        self.getter?.delegate = self
        if let url = URL(string: domainText) {
            print("Inspecting domain")
            self.getter?.getInfoFor(url)
        } else {
            showInputError()
        }
    }

    func showInputError() {
        UIHelper.presentAlert(viewController: self,
                              title: "Unable to Inspect Domain",
                              body: "The URL or IP Address inputted is not valid") {
            self.pendingCellState = .none
            self.tableView.deleteRows(at: [IndexPath(row: 1, section: 0)], with: .automatic)
            self.domainInput?.isEnabled = true
            self.domainInput?.text = ""
        }
    }

    // MARK: Getter Delegates
    func finishedGetter(_ getter: CKGetter) {
        print("Getter finished")
        guard let chain = self.certificateChain else {
            showInputError()
            return
        }

        if let info = self.serverInfo {
            SERVER_INFO = info
        }

        CERTIFICATE_CHAIN = chain

        DispatchQueue.main.async {
            self.performSegue(withIdentifier: "Inspect", sender: nil)
            self.pendingCellState = .none
            self.tableView.deleteRows(at: [IndexPath(row: 1, section: 0)], with: .automatic)
            self.domainInput?.isEnabled = true
            self.domainInput?.text = ""
            let domainsBefore = RecentLookups.GetRecentLookups().count
            RecentLookups.AddLookup(query: getter.url.host ?? "")
            if RecentLookups.GetRecentLookups().count == 1 && domainsBefore == 0 {
                self.tableView.insertSections(IndexSet(arrayLiteral: 1), with: .automatic)
            } else {
                self.tableView.reloadSections(IndexSet(arrayLiteral: 1), with: .automatic)
            }
        }
    }

    func getter(_ getter: CKGetter, gotCertificateChain chain: CKCertificateChain) {
        print("Got certificate chain")
        self.certificateChain = chain
    }

    func getter(_ getter: CKGetter, gotServerInfo serverInfo: CKServerInfo) {
        self.serverInfo = serverInfo
        print("Got server info")
    }

    func getter(_ getter: CKGetter, errorGettingCertificateChain error: Error) {
        self.pendingCellState = .error
        self.chainError = error
        print("Error getting certificate chain")
        DispatchQueue.main.async {
            self.tableView.reloadRows(at: [IndexPath(row: 1, section: 0)], with: .automatic)
            self.domainInput?.isEnabled = true
        }
    }

    func getter(_ getter: CKGetter, errorGettingServerInfo error: Error) {
        self.pendingCellState = .error
        self.serverError = error
        print("Error getting server info")
        DispatchQueue.main.async {
            self.tableView.reloadRows(at: [IndexPath(row: 1, section: 0)], with: .automatic)
            self.domainInput?.isEnabled = true
        }
    }

    override func tableView(_ tableView: UITableView,
                            editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        if indexPath.section == 0 {
            return nil
        }

        let delete = UITableViewRowAction(style: .destructive, title: lang(key: "Delete")) { (_, _) in
            RecentLookups.RemoveLookup(index: indexPath.row)
            if RecentLookups.GetRecentLookups().count == 0 {
                tableView.deleteSections(IndexSet(arrayLiteral: 1), with: .automatic)
            } else {
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }
        }

        let inspect = UITableViewRowAction(style: .normal, title: lang(key: "Inspect")) { (_, _) in
            let query = RecentLookups.GetRecentLookups()[indexPath.row]
            self.inspectDomain(text: query)
        }
        inspect.backgroundColor = UIColor.systemBlue

        return [delete, inspect]
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            return
        }

        let query = RecentLookups.GetRecentLookups()[indexPath.row]
        self.inspectDomain(text: query)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "Error" {
            let destination = segue.destination as? GetterErrorTableViewController
            destination?.chainError = self.chainError
            destination?.serverError = self.serverError
        }
    }
}