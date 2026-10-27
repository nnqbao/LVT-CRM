import UIKit

/// "Đăng nhập nhanh trên điện thoại này", opened from the web page Thiết bị đăng nhập (`{ type: 'quick-sign-in' }`):
/// Face ID / Touch ID and passkey are phone features, so they stay native (same flows as the former Cá nhân screen).
final class QuickSignInViewController: UITableViewController {
    private enum Row: Int, CaseIterable {
        case biometric
        case passkey
    }

    private let session: UserSession
    private let quickSignIn: QuickSignInService
    private var biometricBusy = false
    private var passkeyBusy = false

    init(session: UserSession, quickSignIn: QuickSignInService) {
        self.session = session
        self.quickSignIn = quickSignIn
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Đăng nhập nhanh"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { Row.allCases.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Trên điện thoại này"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Ứng dụng phiên bản \(AppVersion.marketing)"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        cell.accessoryView = nil
        cell.selectionStyle = .default
        switch Row(rawValue: indexPath.row) {
        case .biometric:
            let availability = quickSignIn.availability
            let enabled = quickSignIn.isDeviceKeyEnabled(for: session)
            content.text = availability.kind.switchTitle
            content.image = UIImage(systemName: availability.kind.symbol)
            if biometricBusy {
                content.secondaryText = "Đang xử lý…"
            } else if let reason = availability.unavailableReason, !enabled {
                content.secondaryText = reason
            } else if enabled {
                content.secondaryText = "Đang bật trên máy này."
            } else if let record = quickSignIn.deviceRecord {
                content.secondaryText = "Máy này đang dùng cho \(record.email). Bật để chuyển sang tài khoản của bạn."
            } else {
                content.secondaryText = "Đăng nhập trên máy này mà không cần nhập mật khẩu."
            }
            let toggle = UISwitch()
            toggle.isOn = enabled
            toggle.isEnabled = !biometricBusy && (enabled || availability.unavailableReason == nil)
            toggle.accessibilityLabel = availability.kind.switchTitle
            toggle.addTarget(self, action: #selector(biometricChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case .passkey:
            content.text = "Tạo passkey"
            content.secondaryText = passkeyBusy ? "Đang xử lý…" : "Đăng nhập bằng Face ID / mã máy, không cần mật khẩu."
            content.image = UIImage(systemName: "person.badge.key")
        case nil:
            break
        }
        content.imageProperties.tintColor = .systemIndigo
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Row(rawValue: indexPath.row) == .passkey, !passkeyBusy, let anchor = view.window else { return }
        passkeyBusy = true
        tableView.reloadData()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await quickSignIn.createPasskey(anchor: anchor)
                passkeyBusy = false
                tableView.reloadData()
                alert("Đã tạo passkey", "Lần sau bấm “Đăng nhập bằng passkey” trên màn hình đăng nhập.")
            } catch {
                passkeyBusy = false
                tableView.reloadData()
                if let message = QuickSignInService.message(for: error) { alert("Chưa tạo được passkey", message) }
            }
        }
    }

    @objc private func biometricChanged(_ sender: UISwitch) {
        guard !biometricBusy else { return }
        let turnOn = sender.isOn
        biometricBusy = true
        tableView.reloadData()
        Task { [weak self] in
            guard let self else { return }
            var failure: Error?
            if turnOn {
                do { try await quickSignIn.enableDeviceKey(for: session) } catch { failure = error }
            } else {
                await quickSignIn.disableDeviceKey(for: session)
            }
            biometricBusy = false
            tableView.reloadData()
            if let failure, let message = QuickSignInService.message(for: failure) {
                alert("Chưa bật được \(quickSignIn.availability.kind.label)", message)
            }
        }
    }

    private func alert(_ title: String, _ message: String) {
        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: "Đóng", style: .default))
        present(controller, animated: true)
    }
}
