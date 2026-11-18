import UIKit

@MainActor
final class LoginViewController: UIViewController, UITextFieldDelegate {
    private enum Mode { case signIn, forgotPassword }

    private let authRepository: AuthRepository
    private let quickSignIn: QuickSignInService
    private var mode: Mode = .signIn
    private var isBusy = false
    private var keyboardObservers: [NSObjectProtocol] = []

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let formTitleLabel = UILabel()
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let messageLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let submitButton = UIButton(type: .system)
    private let modeButton = UIButton(type: .system)
    /// Face ID / Touch ID: shown only when this device holds a device credential (label names the account).
    private let biometricButton = UIButton(type: .system)
    /// Passkey: always offered in sign-in mode.
    private let passkeyButton = UIButton(type: .system)

    init(authRepository: AuthRepository, quickSignIn: QuickSignInService) {
        self.authRepository = authRepository
        self.quickSignIn = quickSignIn
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        configureViews()
        configureLayout()
        registerForKeyboardChanges()
        updateMode(animated: false)
        if let warning = authRepository.bootstrapError, !warning.isEmpty {
            showMessage(warning, color: .systemOrange)
        }
    }

    deinit { keyboardObservers.forEach(NotificationCenter.default.removeObserver) }

    private func configureViews() {
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        dismissTap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(dismissTap)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "THCS Lê Văn Tám"
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .systemIndigo
        titleLabel.accessibilityTraits = .header

        subtitleLabel.text = "Hệ thống quản lý công tác nội bộ"
        configureLabel(subtitleLabel, style: .subheadline, color: .secondaryLabel, alignment: .center)

        formTitleLabel.font = .preferredFont(forTextStyle: .title3)
        formTitleLabel.adjustsFontForContentSizeCategory = true
        formTitleLabel.accessibilityTraits = .header

        configureTextField(emailField, placeholder: "Email")
        emailField.keyboardType = .emailAddress
        emailField.textContentType = .username
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.returnKeyType = .next
        emailField.accessibilityLabel = "Email"

        configureTextField(passwordField, placeholder: "Mật khẩu")
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.autocapitalizationType = .none
        passwordField.autocorrectionType = .no
        passwordField.returnKeyType = .go
        passwordField.accessibilityLabel = "Mật khẩu"
        let visibilityButton = UIButton(type: .system)
        visibilityButton.setImage(UIImage(systemName: "eye"), for: .normal)
        visibilityButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        visibilityButton.accessibilityLabel = "Hiện mật khẩu"
        visibilityButton.addTarget(self, action: #selector(togglePasswordVisibility(_:)), for: .touchUpInside)
        passwordField.rightView = visibilityButton
        passwordField.rightViewMode = .always

        configureLabel(messageLabel, style: .footnote, color: .systemRed, alignment: .natural)
        messageLabel.isHidden = true

        configureButton(submitButton, filled: true)
        submitButton.addTarget(self, action: #selector(submit), for: .touchUpInside)
        submitButton.accessibilityHint = "Gửi thông tin xác thực tới máy chủ"

        configureButton(modeButton, filled: false)
        modeButton.addTarget(self, action: #selector(toggleMode), for: .touchUpInside)

        configureQuickButton(biometricButton, symbol: quickSignIn.availability.kind.symbol)
        biometricButton.addTarget(self, action: #selector(signInWithBiometrics), for: .touchUpInside)
        biometricButton.accessibilityHint = "Xác thực trên máy rồi đăng nhập, không cần mật khẩu"
        configureQuickButton(passkeyButton, symbol: "person.badge.key")
        passkeyButton.configuration?.title = "Đăng nhập bằng passkey"
        passkeyButton.addTarget(self, action: #selector(signInWithPasskey), for: .touchUpInside)
        passkeyButton.accessibilityHint = "Chọn passkey đã lưu cho LVT CRM"

        [emailField, passwordField].forEach {
            $0.delegate = self
            $0.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        }

        let submitRow = UIView()
        submitRow.translatesAutoresizingMaskIntoConstraints = false
        submitButton.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = .white
        submitRow.addSubview(submitButton)
        submitRow.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            submitButton.leadingAnchor.constraint(equalTo: submitRow.leadingAnchor),
            submitButton.trailingAnchor.constraint(equalTo: submitRow.trailingAnchor),
            submitButton.topAnchor.constraint(equalTo: submitRow.topAnchor),
            submitButton.bottomAnchor.constraint(equalTo: submitRow.bottomAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: submitButton.centerYAnchor),
            activityIndicator.leadingAnchor.constraint(equalTo: submitButton.leadingAnchor, constant: 16),
        ])

        [titleLabel, subtitleLabel, formTitleLabel, emailField, passwordField, messageLabel, submitRow, biometricButton, passkeyButton, modeButton]
            .forEach(contentStack.addArrangedSubview)
        contentStack.setCustomSpacing(28, after: subtitleLabel)
    }

    private func configureLayout() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        let frameGuide = scrollView.frameLayoutGuide
        let contentGuide = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: contentGuide.topAnchor, constant: 40),
            contentStack.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor, constant: -32),
            contentStack.centerXAnchor.constraint(equalTo: frameGuide.centerXAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: frameGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: frameGuide.trailingAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: frameGuide.widthAnchor, constant: -48).withPriority(.defaultHigh),
            contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
            emailField.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            passwordField.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            submitButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            modeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            biometricButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            passkeyButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
        ])
    }

    private func configureTextField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.borderStyle = .roundedRect
        field.clearButtonMode = .whileEditing
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureLabel(_ label: UILabel, style: UIFont.TextStyle, color: UIColor, alignment: NSTextAlignment) {
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.textAlignment = alignment
        label.numberOfLines = 0
    }

    private func configureButton(_ button: UIButton, filled: Bool) {
        var configuration = filled ? UIButton.Configuration.filled() : UIButton.Configuration.plain()
        configuration.baseBackgroundColor = filled ? .systemIndigo : nil
        configuration.cornerStyle = .large
        button.configuration = configuration
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
    }

    private func configureQuickButton(_ button: UIButton, symbol: String) {
        var configuration = UIButton.Configuration.tinted()
        configuration.baseForegroundColor = .systemIndigo
        configuration.baseBackgroundColor = .systemIndigo
        configuration.cornerStyle = .large
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 8
        configuration.titleLineBreakMode = .byWordWrapping
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = UIFont.preferredFont(forTextStyle: .headline)
            return updated
        }
        button.configuration = configuration
        button.titleLabel?.adjustsFontForContentSizeCategory = true
    }

    /// The Face ID / Touch ID button follows the Keychain record (it disappears after DEVICE_CREDENTIAL_INVALID).
    private func refreshQuickButtons() {
        let isSignIn = mode == .signIn
        let record = quickSignIn.deviceRecord
        let kind = quickSignIn.availability.kind
        biometricButton.isHidden = !isSignIn || record == nil
        biometricButton.configuration?.title = kind.loginTitle(email: record?.email ?? "")
        biometricButton.configuration?.image = UIImage(systemName: kind.symbol)
        biometricButton.accessibilityLabel = kind.loginTitle(email: record?.email ?? "")
        passkeyButton.isHidden = !isSignIn
    }

    @objc private func signInWithBiometrics() {
        guard !isBusy else { return }
        view.endEditing(true)
        setBusy(true)
        clearMessage()
        Task { [weak self] in
            guard let self else { return }
            let result = await quickSignIn.signInWithDeviceKey()
            if case .failure(let error) = result { showQuick(error: error) }
            refreshQuickButtons()
            setBusy(false)
        }
    }

    @objc private func signInWithPasskey() {
        guard !isBusy, let anchor = view.window else { return }
        view.endEditing(true)
        setBusy(true)
        clearMessage()
        Task { [weak self] in
            guard let self else { return }
            let result = await quickSignIn.signInWithPasskey(anchor: anchor)
            if case .failure(let error) = result { showQuick(error: error) }
            setBusy(false)
        }
    }

    /// User cancellation stays silent.
    private func showQuick(error: Error) {
        guard let message = QuickSignInService.message(for: error) else { return }
        showMessage(message, color: .systemRed)
    }

    @objc private func textDidChange() { updateEnabledState() }

    @objc private func togglePasswordVisibility(_ sender: UIButton) {
        passwordField.isSecureTextEntry.toggle()
        sender.setImage(UIImage(systemName: passwordField.isSecureTextEntry ? "eye" : "eye.slash"), for: .normal)
        sender.accessibilityLabel = passwordField.isSecureTextEntry ? "Hiện mật khẩu" : "Ẩn mật khẩu"
    }

    @objc private func toggleMode() {
        guard !isBusy else { return }
        mode = mode == .signIn ? .forgotPassword : .signIn
        clearMessage()
        updateMode(animated: true)
    }

    private func updateMode(animated: Bool) {
        let isSignIn = mode == .signIn
        formTitleLabel.text = isSignIn ? "Đăng nhập" : "Quên mật khẩu"
        passwordField.isHidden = !isSignIn
        submitButton.configuration?.title = isSignIn ? "Đăng nhập" : "Gửi mật khẩu tạm"
        modeButton.configuration?.title = isSignIn ? "Quên mật khẩu?" : "Quay lại đăng nhập"
        emailField.returnKeyType = isSignIn ? .next : .go
        refreshQuickButtons()
        updateEnabledState()
        if animated { UIAccessibility.post(notification: .layoutChanged, argument: formTitleLabel) }
    }

    private func updateEnabledState() {
        let hasEmail = !(emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPassword = !(passwordField.text ?? "").isEmpty
        submitButton.isEnabled = !isBusy && hasEmail && (mode == .forgotPassword || hasPassword)
        emailField.isEnabled = !isBusy
        passwordField.isEnabled = !isBusy
        modeButton.isEnabled = !isBusy
        biometricButton.isEnabled = !isBusy
        passkeyButton.isEnabled = !isBusy
    }

    @objc private func submit() {
        guard submitButton.isEnabled else { return }
        view.endEditing(true)
        setBusy(true)
        clearMessage()
        let email = emailField.text ?? ""
        let password = passwordField.text ?? ""
        Task { [weak self] in
            guard let self else { return }
            switch mode {
            case .signIn:
                let result = await authRepository.signIn(email: email, password: password)
                if case .failure(let error) = result { show(error: error) }
            case .forgotPassword:
                let result = await authRepository.requestPasswordReset(email: email)
                switch result {
                case .success:
                    mode = .signIn
                    updateMode(animated: true)
                    showMessage(
                        "Nếu email tồn tại, mật khẩu tạm sẽ được gửi. Kiểm tra hộp thư và đăng nhập lại.",
                        color: .systemTeal
                    )
                case .failure(let error): show(error: error)
                }
            }
            setBusy(false)
        }
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        busy ? activityIndicator.startAnimating() : activityIndicator.stopAnimating()
        updateEnabledState()
        submitButton.accessibilityLabel = busy ? "Đang xử lý" : nil
    }

    private func show(error: Error) {
        let technicalMessage = (error as? ConvexException)?.message ?? error.localizedDescription
        let message: String
        if technicalMessage.range(of: #"^\[Request ID:[^\]]+\]\s*Server Error\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
            || technicalMessage.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Server Error") == .orderedSame {
            message = "Không thể đăng nhập. Hãy kiểm tra email, mật khẩu rồi thử lại."
        } else {
            message = ConvexHttpClient.humanize(technicalMessage)
        }
        showMessage(
            message,
            color: .systemRed
        )
    }

    private func showMessage(_ text: String, color: UIColor) {
        messageLabel.text = text
        messageLabel.textColor = color
        messageLabel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private func clearMessage() {
        messageLabel.text = nil
        messageLabel.isHidden = true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === emailField, mode == .signIn { passwordField.becomeFirstResponder() }
        else if submitButton.isEnabled { submit() }
        return true
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    private func registerForKeyboardChanges() {
        let center = NotificationCenter.default
        keyboardObservers = [
            center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) {
                [weak self] note in
                MainActor.assumeIsolated { self?.updateKeyboardInset(note) }
            },
            center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scrollView.contentInset.bottom = 0
                    self?.scrollView.verticalScrollIndicatorInsets.bottom = 0
                }
            },
        ]
    }

    private func updateKeyboardInset(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let coveredHeight = max(0, view.bounds.maxY - view.convert(frame, from: nil).minY)
        scrollView.contentInset.bottom = coveredHeight
        scrollView.verticalScrollIndicatorInsets.bottom = coveredHeight
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
