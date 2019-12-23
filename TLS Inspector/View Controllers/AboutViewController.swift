import UIKit
import CertificateKit

class AboutTableViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let projectGithubURL = "https://tlsinspector.com/github.html"
    let projectURL = "https://tlsinspector.com/"
    let projectContributeURL = "https://tlsinspector.com/contribute.html"
    let testflightURL = "https://tlsinspector.com/beta.html"

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    // MARK: - Table view data source
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 3
        } else if section == 1 {
            return 2
        }

        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Basic", for: indexPath)
        if indexPath.section == 0 && indexPath.row == 0 {
            cell.textLabel?.text = lang(key: "Share TLS Inspector")
        } else if indexPath.section == 0 && indexPath.row == 1 {
            cell.textLabel?.text = lang(key: "Rate in App Store")
        } else if indexPath.section == 0 && indexPath.row == 2 {
            cell.textLabel?.text = lang(key: "Provide Feedback")
        } else if indexPath.section == 1 && indexPath.row == 0 {
            cell.textLabel?.text = lang(key: "Contribute to TLS Inspector")
        } else if indexPath.section == 1 && indexPath.row == 1 {
            cell.textLabel?.text = lang(key: "Test New Features")
        }
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return lang(key: "Share & Feedback")
        } else if section == 1 {
            return lang(key: "Get Involved")
        }

        return nil
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            let info = Bundle.main.infoDictionary ?? [:]
            let appVersion: String = (info["CFBundleShortVersionString"] as? String) ?? "Unknown"
            let build: String = (info[kCFBundleVersionKey as String] as? String) ?? "Unknown"
            let opensslVersion = CertificateKit.opensslVersion() ?? "Unknown"
            let libcurlVersion = CertificateKit.libcurlVersion() ?? "Unknown"
            return "App: \(appVersion) (\(build)), OpenSSL: \(opensslVersion), cURL: \(libcurlVersion)"
        } else if section == 1 {
            return lang(key: "copyright_license_footer")
        }

        return nil
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) else {
            return
        }

        if indexPath.section == 0 && indexPath.row == 0 {
            let blub = lang(key: "Trust & Safety On-The-Go with TLS Inspector: {url}", args: [projectURL])
            let activityController = UIActivityViewController(activityItems: [blub], applicationActivities: nil)
            ActionTipTarget(view: cell).attach(to: activityController.popoverPresentationController)
            self.present(activityController, animated: true, completion: nil)
        } else if indexPath.section == 0 && indexPath.row == 1 {
            AppLinks().showAppStore(self, dismissed: nil)
        } else if indexPath.section == 0 && indexPath.row == 2 {
            ContactTableViewController.show(self) { (support) in
                AppLinks.current.showEmailCompose(viewController: self, object: support, includeLogs: false, dismissed: nil)
            }
        } else if indexPath.section == 1 && indexPath.row == 0 {
            OpenURLInSafari(projectContributeURL)
        } else if indexPath.section == 1 && indexPath.row == 1 {
            OpenURLInSafari(testflightURL)
        }
    }
}
