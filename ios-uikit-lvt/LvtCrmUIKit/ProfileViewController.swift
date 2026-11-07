import UIKit
import PhotosUI

@MainActor
final class ProfileViewController: UITableViewController {
    private enum Appearance: String, CaseIterable {
        case system
        case light
        case dark

        var title: String {
            switch self {
            case .system: return "Theo hệ thống"
            case .light: return "Sáng"
            case .dark: return "Tối"
            }
        }

        var interfaceStyle: UIUserInterfaceStyle {
            switch self {
            case .system: return .unspecified
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    private enum Section: Int, CaseIterable {
        case identity
        case work
        case account
        case appearance
        case changelog
        case signOut
    }

    private let session: UserSession
    private let authRepository: AuthRepository
    private let sessionsRepository: SessionsRepository
    private let avatarRepository: AvatarRepository
    private let quickSignIn: QuickSignInService
    private var avatarImage: UIImage?
    private var avatarBusy = false
    private var biometricBusy = false
    private var passkeyBusy = false

    private enum AccountRow: Int, CaseIterable {
        case devices
        case changePassword
        case biometric
        case passkey
    }

    init(
        session: UserSession,
        authRepository: AuthRepository,
        sessionsRepository: SessionsRepository,
        avatarRepository: AvatarRepository,
        quickSignIn: QuickSignInService
    ) {
        self.session = session
        self.authRepository = authRepository
        self.sessionsRepository = sessionsRepository
        self.avatarRepository = avatarRepository
        self.quickSignIn = quickSignIn
        super.init(style: .insetGrouped)
        title = "Cá nhân"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .systemGroupedBackground
        tableView.cellLayoutMarginsFollowReadableWidth = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .identity: return 2
        case .work: return 3
        case .account: return AccountRow.allCases.count
        case .appearance: return 1
        case .changelog: return 1
        case .signOut: return 2
        case nil: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .identity: return "Tài khoản"
        case .work: return "Thông tin công việc"
        case .account: return "Bảo mật"
        case .appearance: return "Giao diện"
        case .changelog: return "Ứng dụng"
        case .signOut, nil: return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        content.imageProperties.maximumSize = CGSize(width: 44, height: 44)
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .none
        cell.accessibilityTraits = []
        cell.accessibilityLabel = nil
        cell.accessibilityHint = nil

        switch Section(rawValue: indexPath.section) {
        case .identity:
            if indexPath.row == 0 {
                content.text = session.name
                content.secondaryText = avatarBusy
                    ? "Đang cập nhật ảnh đại diện…"
                    : session.email
                content.textProperties.font = .preferredFont(forTextStyle: .title3)
                content.image = avatarImage ?? UIImage(systemName: "person.crop.circle.fill")
                content.imageProperties.tintColor = avatarImage == nil ? .systemIndigo : .clear
                content.imageProperties.cornerRadius = 22
                content.imageProperties.maximumSize = CGSize(width: 44, height: 44)
                content.imageProperties.reservedLayoutSize = CGSize(width: 44, height: 44)
                cell.selectionStyle = avatarBusy ? .none : .default
                cell.accessibilityLabel = "\(session.name), \(session.email)"
                cell.accessibilityHint = "Đổi ảnh đại diện"
                cell.accessibilityTraits = .button
            } else {
                content.text = "Vai trò"
                content.secondaryText = session.roleLabel
                cell.accessibilityLabel = "Vai trò, \(session.roleLabel)"
            }
        case .work:
            let values = [
                ("Vai trò", session.roleLabel),
                ("Tổ hoặc phòng", session.departmentName ?? "Chưa cập nhật"),
                ("Chức vụ", session.positionName ?? "Chưa cập nhật"),
            ]
            content.text = values[indexPath.row].0
            content.secondaryText = values[indexPath.row].1
            cell.accessibilityLabel = "\(values[indexPath.row].0), \(values[indexPath.row].1)"
        case .account where AccountRow(rawValue: indexPath.row) == .biometric:
            configureBiometricRow(cell, content: &content)
        case .account where AccountRow(rawValue: indexPath.row) == .passkey:
            content.text = "Tạo passkey"
            content.secondaryText = passkeyBusy
                ? "Đang tạo passkey…"
                : "Đăng nhập bằng passkey trên màn hình đăng nhập, không cần mật khẩu."
            content.image = UIImage(systemName: "person.badge.key")
            content.imageProperties.tintColor = .systemIndigo
            cell.selectionStyle = passkeyBusy ? .none : .default
            cell.accessibilityTraits = .button
            cell.accessibilityLabel = passkeyBusy ? "Tạo passkey, đang xử lý" : "Tạo passkey"
            cell.accessibilityHint = "Tạo passkey cho tài khoản này trên thiết bị"
        case .account:
            let isDevices = indexPath.row == 0
            content.text = isDevices ? "Thiết bị đã đăng nhập" : "Đổi mật khẩu"
            content.image = UIImage(systemName: isDevices ? "laptopcomputer.and.iphone" : "key")
            content.imageProperties.tintColor = .systemIndigo
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            cell.accessibilityTraits = .button
            cell.accessibilityHint = isDevices
                ? "Mở danh sách các phiên đăng nhập"
                : "Mở màn hình đổi mật khẩu"
        case .appearance:
            content.text = "Chế độ hiển thị"
            content.secondaryText = currentAppearance.title
            content.image = UIImage(systemName: "circle.lefthalf.filled")
            content.imageProperties.tintColor = .systemIndigo
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            cell.accessibilityTraits = .button
            cell.accessibilityLabel = "Chế độ hiển thị, \(currentAppearance.title)"
            cell.accessibilityHint = "Chọn giao diện sáng, tối hoặc theo hệ thống"
        case .changelog:
            content.text = "Lịch sử thay đổi"
            content.secondaryText = "Xem từng phiên bản đã thêm gì"
            content.image = UIImage(systemName: "clock.arrow.circlepath")
            content.imageProperties.tintColor = .systemIndigo
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            cell.accessibilityTraits = .button
            cell.accessibilityLabel = "Lịch sử thay đổi"
            cell.accessibilityHint = "Mở danh sách thay đổi theo phiên bản"
        case .signOut:
            if indexPath.row == 0 {
                content.text = "Đăng xuất"
                content.image = UIImage(systemName: "rectangle.portrait.and.arrow.right")
                content.textProperties.color = .systemRed
                content.imageProperties.tintColor = .systemRed
                cell.selectionStyle = .default
                cell.accessibilityTraits = .button
                cell.accessibilityHint = "Đăng xuất khỏi tài khoản này"
            } else {
                content.text = "Phiên bản \(AppVersion.marketing)"
                content.textProperties.font = .preferredFont(forTextStyle: .footnote)
                content.textProperties.color = .secondaryLabel
                cell.selectionStyle = .none
                cell.accessibilityTraits = .staticText
                cell.accessibilityLabel = "Phiên bản \(AppVersion.marketing)"
            }
        case nil:
            break
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .identity where indexPath.row == 0:
            showAvatarActions()
        case .account where indexPath.row == AccountRow.devices.rawValue:
            navigationController?.pushViewController(
                DevicesViewController(sessionsRepository: sessionsRepository),
                animated: true
            )
        case .account where indexPath.row == AccountRow.changePassword.rawValue:
            showChangePassword()
        case .account where indexPath.row == AccountRow.passkey.rawValue:
            createPasskey()
        case .appearance:
            showAppearancePicker()
        case .changelog:
            navigationController?.pushViewController(ChangelogViewController(), animated: true)
        case .signOut where indexPath.row == 0:
            confirmSignOut()
        default:
            break
        }
    }

    func applyAvatarImage(_ image: UIImage?) {
        avatarImage = image
        if isViewLoaded {
            tableView.reloadRows(at: [IndexPath(row: 0, section: Section.identity.rawValue)], with: .none)
        }
    }

    private func showAvatarActions() {
        guard !avatarBusy else { return }
        let alert = UIAlertController(
            title: "Ảnh đại diện",
            message: session.email,
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Chọn từ thư viện", style: .default) { [weak self] _ in
            self?.presentPhotoLibrary()
        })
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "Chụp ảnh", style: .default) { [weak self] _ in
                self?.presentCamera()
            })
        }
        if avatarImage != nil {
            alert.addAction(UIAlertAction(title: "Gỡ ảnh đại diện", style: .destructive) { [weak self] _ in
                self?.removeAvatar()
            })
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: IndexPath(row: 0, section: Section.identity.rawValue))
        }
        present(alert, animated: true)
    }

    private func presentCrop(_ image: UIImage) {
        let crop = AvatarCropViewController(image: image) { [weak self] cropped in
            self?.uploadAvatar(cropped)
        }
        present(crop, animated: true)
    }

    private func presentPhotoLibrary() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = self
        present(picker, animated: true)
    }

    private func uploadAvatar(_ image: UIImage) {
        avatarBusy = true
        tableView.reloadRows(at: [IndexPath(row: 0, section: Section.identity.rawValue)], with: .none)
        Task {
            do {
                let saved = try await avatarRepository.upload(image: image)
                avatarBusy = false
                applyAvatarImage(saved)
                NotificationCenter.default.post(name: .accountAvatarDidChange, object: saved)
            } catch {
                avatarBusy = false
                tableView.reloadRows(at: [IndexPath(row: 0, section: Section.identity.rawValue)], with: .none)
                presentAvatarError(error)
            }
        }
    }

    private func removeAvatar() {
        avatarBusy = true
        tableView.reloadRows(at: [IndexPath(row: 0, section: Section.identity.rawValue)], with: .none)
        Task {
            do {
                try await avatarRepository.clear()
                avatarBusy = false
                applyAvatarImage(nil)
                NotificationCenter.default.post(name: .accountAvatarDidChange, object: nil)
            } catch {
                avatarBusy = false
                tableView.reloadRows(at: [IndexPath(row: 0, section: Section.identity.rawValue)], with: .none)
                presentAvatarError(error)
            }
        }
    }

    private func presentAvatarError(_ error: Error) {
        let message = (error as? ConvexException)?.message
            ?? ConvexHttpClient.humanize((error as NSError).localizedDescription)
        let alert = UIAlertController(title: "Không đổi được ảnh", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Đóng", style: .default))
        present(alert, animated: true)
    }

    private var currentAppearance: Appearance {
        Appearance(rawValue: UserDefaults.standard.string(forKey: AppAppearance.defaultsKey) ?? "") ?? .system
    }

    private func showAppearancePicker() {
        let alert = UIAlertController(
            title: "Chế độ hiển thị",
            message: "Chọn giao diện cho LVT CRM.",
            preferredStyle: .actionSheet
        )
        for appearance in Appearance.allCases {
            let action = UIAlertAction(title: appearance.title, style: .default) { [weak self] _ in
                self?.apply(appearance: appearance)
            }
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: IndexPath(row: 0, section: Section.appearance.rawValue))
        }
        present(alert, animated: true)
    }

    private func apply(appearance: Appearance) {
        AppAppearance.persist(rawValue: appearance.rawValue, style: appearance.interfaceStyle)
        tableView.reloadSections(IndexSet(integer: Section.appearance.rawValue), with: .none)
    }

    // MARK: Đăng nhập nhanh (Face ID / Touch ID, passkey)

    private var biometricIndexPath: IndexPath { IndexPath(row: AccountRow.biometric.rawValue, section: Section.account.rawValue) }
    private var passkeyIndexPath: IndexPath { IndexPath(row: AccountRow.passkey.rawValue, section: Section.account.rawValue) }

    /// Switch "Đăng nhập bằng Face ID" (label from LAContext.biometryType). On only for the account that enabled it
    /// on this device; disabled with an explanation when the device cannot hold a biometric key (e.g. simulator).
    private func configureBiometricRow(_ cell: UITableViewCell, content: inout UIListContentConfiguration) {
        let availability = quickSignIn.availability
        let enabled = quickSignIn.isDeviceKeyEnabled(for: session)
        let title = availability.kind.switchTitle
        content.text = title
        content.image = UIImage(systemName: availability.kind.symbol)
        content.imageProperties.tintColor = .systemIndigo
        if biometricBusy {
            content.secondaryText = "Đang xử lý…"
        } else if let reason = availability.unavailableReason, !enabled {
            content.secondaryText = reason
        } else if enabled {
            content.secondaryText = "Đang bật trên máy này. Đăng xuất vẫn giữ để lần sau đăng nhập nhanh."
        } else if let record = quickSignIn.deviceRecord {
            content.secondaryText = "Máy này đang dùng cho \(record.email). Bật để chuyển sang tài khoản của bạn."
        } else {
            content.secondaryText = "Đăng nhập trên máy này mà không cần nhập mật khẩu."
        }
        let toggle = UISwitch()
        toggle.isOn = enabled
        toggle.isEnabled = !biometricBusy && (enabled || availability.unavailableReason == nil)
        toggle.accessibilityLabel = title
        toggle.accessibilityHint = content.secondaryText
        toggle.addTarget(self, action: #selector(biometricSwitchChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        cell.selectionStyle = .none
    }

    @objc private func biometricSwitchChanged(_ sender: UISwitch) {
        guard !biometricBusy else { return }
        let turnOn = sender.isOn
        biometricBusy = true
        tableView.reloadRows(at: [biometricIndexPath], with: .none)
        Task { [weak self] in
            guard let self else { return }
            var failure: Error?
            if turnOn {
                do { try await quickSignIn.enableDeviceKey(for: session) } catch { failure = error }
            } else {
                await quickSignIn.disableDeviceKey(for: session)
            }
            biometricBusy = false
            tableView.reloadRows(at: [biometricIndexPath], with: .none)
            let label = quickSignIn.availability.kind.label
            if let failure {
                if let message = QuickSignInService.message(for: failure) {
                    presentQuickSignInAlert(title: "Chưa bật được \(label)", message: message)
                }
            } else {
                UIAccessibility.post(notification: .announcement, argument: turnOn ? "Đã bật đăng nhập bằng \(label)" : "Đã tắt đăng nhập bằng \(label)")
            }
        }
    }

    private func createPasskey() {
        guard !passkeyBusy, let anchor = view.window else { return }
        passkeyBusy = true
        tableView.reloadRows(at: [passkeyIndexPath], with: .none)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await quickSignIn.createPasskey(anchor: anchor)
                passkeyBusy = false
                tableView.reloadRows(at: [passkeyIndexPath], with: .none)
                presentQuickSignInAlert(
                    title: "Đã tạo passkey",
                    message: "Lần sau bấm “Đăng nhập bằng passkey” trên màn hình đăng nhập."
                )
            } catch {
                passkeyBusy = false
                tableView.reloadRows(at: [passkeyIndexPath], with: .none)
                if let message = QuickSignInService.message(for: error) {
                    presentQuickSignInAlert(title: "Chưa tạo được passkey", message: message)
                }
            }
        }
    }

    private func presentQuickSignInAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Đóng", style: .default))
        present(alert, animated: true)
    }

    private func showChangePassword() {
        let controller = ChangePasswordViewController(
            title: "Đổi mật khẩu",
            subtitle: "Đặt mật khẩu mới cho tài khoản của bạn.",
            authRepository: authRepository,
            allowsCancel: true,
            onDone: { [weak self] in self?.navigationController?.popViewController(animated: true) }
        )
        navigationController?.pushViewController(controller, animated: true)
    }

    private func confirmSignOut() {
        let alert = UIAlertController(
            title: "Đăng xuất?",
            message: "Bạn sẽ cần đăng nhập lại để tiếp tục sử dụng LVT CRM.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Đăng xuất", style: .destructive) { [weak self] _ in
            self?.authRepository.signOut()
        })
        present(alert, animated: true)
    }
}

extension ProfileViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            DispatchQueue.main.async { self?.presentCrop(image) }
        }
    }
}

extension ProfileViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        picker.dismiss(animated: true) { [weak self] in
            if let image { self?.presentCrop(image) }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
