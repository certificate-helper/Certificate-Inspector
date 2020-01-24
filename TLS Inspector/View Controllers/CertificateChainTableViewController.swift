import UIKit
import CertificateKit
import SafariServices

class CertificateChainTableViewController: UITableViewController {

    var certificateChain: CKCertificateChain?
    var serverInfo: CKServerInfo?
    var securityHeadersSorted: [String]?

    var sections: [TableViewSection] = []

    @IBOutlet weak var trustView: UIView!
    @IBOutlet weak var trustIconLabel: UILabel!
    @IBOutlet weak var trustResultLabel: UILabel!
    @IBOutlet weak var trustDetailsButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.certificateChain = CERTIFICATE_CHAIN
        self.serverInfo = SERVER_INFO

        if self.certificateChain != nil {
            self.title = self.certificateChain!.domain
            self.buildTrustHeader()
        }

        buildTable()
    }

    @IBAction func closeButton(_ sender: Any) {
        self.dismiss(animated: true) {
            NotificationCenter.default.post(name: VIEW_CLOSE_NOTIFICATION, object: nil)
        }
    }

    @IBAction func actionButton(_ sender: UIBarButtonItem) {
        guard let chain = self.certificateChain else {
            return
        }

        UIHelper(self).presentActionSheet(target: ActionTipTarget(barButtonItem: sender),
                                          title: self.certificateChain?.domain,
                                          subtitle: nil,
                                          items: [
                                            lang(key: "View on SSL Labs"),
                                            lang(key: "Search on Shodan"),
                                            lang(key: "Search on crt.sh")
                                        ])
        { (index) in
            if index == 0 {
                self.openURL("https://www.ssllabs.com/ssltest/analyze.html?d=" + chain.domain)
            } else if index == 1 {
                self.openURL("https://www.shodan.io/host/" + chain.remoteAddress)
            } else if index == 2 {
                self.openURL("https://crt.sh/?q=" + chain.domain)
            }
        }
    }

    func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }
        self.present(SFSafariViewController(url: url), animated: true, completion: nil)
    }

    func buildTrustHeader() {
        self.trustView.layer.cornerRadius = 5.0

        var trustColor = UIColor.materialPink()
        var trustText = lang(key: "Unknown")
        var trustIcon = FAIcon.FAQuestionCircleSolid
        switch self.certificateChain!.trusted {
        case .trusted:
            trustColor = UIColor.materialGreen()
            trustText = lang(key: "Trusted")
            trustIcon = FAIcon.FACheckCircleSolid
        case .locallyTrusted:
            trustColor = UIColor.materialLightGreen()
            trustText = lang(key: "Locally Trusted")
            trustIcon = FAIcon.FACheckCircleRegular
        case .untrusted, .invalidDate, .wrongHost:
            trustColor = UIColor.materialAmber()
            trustText = lang(key: "Untrusted")
            trustIcon = FAIcon.FAExclamationCircleSolid
        case .sha1Leaf, .sha1Intermediate:
            trustColor = UIColor.materialRed()
            trustText = lang(key: "Insecure")
            trustIcon = FAIcon.FATimesCircleSolid
        case .selfSigned, .revokedLeaf, .revokedIntermediate:
            trustColor = UIColor.materialRed()
            trustText = lang(key: "Untrusted")
            trustIcon = FAIcon.FATimesCircleSolid
        @unknown default:
            // Default already set
            break
        }

        self.trustView.backgroundColor = trustColor
        self.trustResultLabel.textColor = UIColor.white
        self.trustResultLabel.text = trustText
        self.trustIconLabel.textColor = UIColor.white
        self.trustIconLabel.font = trustIcon.font(size: self.trustIconLabel.font.pointSize)
        self.trustIconLabel.text = trustIcon.string()
        self.trustDetailsButton.tintColor = UIColor.white
    }

    func buildTable() {
        self.sections = []

        self.sections.maybeAppend(makeCertificateSection())
        self.sections.maybeAppend(makeConnectionInfoSection())
        self.sections.maybeAppend(makeHeadersSection())

        self.tableView.reloadData()
    }

    func makeCertificateSection() -> TableViewSection? {
        let certificateSection = TableViewSection()
        certificateSection.title = lang(key: "Certificates")
        certificateSection.tag = 1

        guard let certificates = self.certificateChain?.certificates else {
            return nil
        }

        for certificate in certificates {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "Basic") else {
                return nil
            }

            if certificate.isExpired {
                cell.textLabel?.text = lang(key: "{commonName} (Expired)", args: [certificate.summary])
                cell.textLabel?.textColor = UIColor.systemRed
            } else if certificate.isNotYetValid {
                cell.textLabel?.text = lang(key: "{commonName} (Not Yet Valid)", args: [certificate.summary])
                cell.textLabel?.textColor = UIColor.systemRed
            } else if let ev = certificate.extendedValidationAuthority {
                let country = certificate.subject.countryCodes.first ?? ""
                cell.textLabel?.text = lang(key: "{commonName} ({orgName} {countryName})",
                                            args: [certificate.summary, ev, country])
                cell.textLabel?.textColor = UIColor.systemGreen
            } else if certificate.revoked.isRevoked {
                cell.textLabel?.text = lang(key: "{commonName} (Revoked)", args: [certificate.summary])
                cell.textLabel?.textColor = UIColor.systemRed
            } else {
                cell.textLabel?.text = certificate.summary
            }

            certificateSection.cells.append(cell)
        }

        return certificateSection
    }

    func makeConnectionInfoSection() -> TableViewSection? {
        let connectionSection = TableViewSection()
        connectionSection.title = lang(key: "Connection Information")

        guard let chain = self.certificateChain else {
            return nil
        }

        connectionSection.cells.append(TitleValueTableViewCell.Cell(title: lang(key: "Negotiated Ciphersuite"),
                                                                    value: chain.cipherSuite,
                                                                    useFixedWidthFont: true))
        connectionSection.cells.append(TitleValueTableViewCell.Cell(title: lang(key: "Negotiated Version"),
                                                                    value: chain.protocol,
                                                                    useFixedWidthFont: false))
        connectionSection.cells.append(TitleValueTableViewCell.Cell(title: lang(key: "Remote Address"),
                                                                    value: chain.remoteAddress,
                                                                    useFixedWidthFont: true))

        return connectionSection
    }

    func makeHeadersSection() -> TableViewSection? {
        let headersSection = TableViewSection()
        headersSection.title = lang(key: "Security HTTP Headers")
        headersSection.tag = 2

        guard let serverInfo = self.serverInfo else {
            return nil
        }

        for header in serverInfo.securityHeaders.keys.sorted() {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "Icon") else {
                return nil
            }
            guard let titleLabel = cell.viewWithTag(1) as? UILabel else {
                return nil
            }
            guard let iconLabel = cell.viewWithTag(2) as? UILabel else {
                return nil
            }
            titleLabel.text = header
            let hasHeader = (self.serverInfo?.securityHeaders[header] ?? nil) is String
            if hasHeader {
                iconLabel.text = FAIcon.FACheckCircleSolid.string()
                iconLabel.textColor = UIColor.materialGreen()
            } else {
                iconLabel.text = FAIcon.FATimesCircleSolid.string()
                iconLabel.textColor = UIColor.materialRed()
            }
            headersSection.cells.append(cell)
        }

        guard let cell = tableView.dequeueReusableCell(withIdentifier: "Basic") else {
            return nil
        }
        cell.textLabel?.text = lang(key: "View All")
        headersSection.cells.append(cell)

        return headersSection
    }

    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.sections[section].cells.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return self.sections[indexPath.section].cells[indexPath.row]
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return self.sections[section].title
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sectionTag = self.sections[indexPath.section].tag

        if sectionTag == 1 {
            CURRENT_CERTIFICATE = indexPath.row
            guard let controller = self.storyboard?.instantiateViewController(withIdentifier: "Certificate") else {
                return
            }
            SPLIT_VIEW_CONTROLLER?.showDetailViewController(controller, sender: nil)
        } else if sectionTag == 2 {
            guard let controller = self.storyboard?.instantiateViewController(withIdentifier: "Headers") else {
                return
            }
            SPLIT_VIEW_CONTROLLER?.showDetailViewController(controller, sender: nil)
        }
    }

    override func tableView(_ tableView: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    override func tableView(_ tableView: UITableView, canPerformAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        return action == #selector(copy(_:))
    }

    override func tableView(_ tableView: UITableView, performAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) {
        if action == #selector(copy(_:)) {
            var data: String?
            let tableCell = self.sections[indexPath.section].cells[indexPath.row]
            if let titleValueCell = tableCell as? TitleValueTableViewCell {
                data = titleValueCell.valueLabel.text
            } else {
                data = tableCell.textLabel?.text
            }
            UIPasteboard.general.string = data
        }
    }
}
