import UIKit

@MainActor
final class ChatHubViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating {
    private let repository: ChatRepository
    private let onOpenDuty: (String) -> Void
    private let onOpenWork: (String) -> Void
    private let onUnread: (Int) -> Void
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let filters = IconTabBar(items: [
        IconTabBar.Item(title: "Tất cả", systemImage: "bubble.left.and.bubble.right"),
        IconTabBar.Item(title: "Công tác", systemImage: "briefcase"),
        IconTabBar.Item(title: "Công việc", systemImage: "checkmark.seal"),
        IconTabBar.Item(title: "Nhóm", systemImage: "person.2"),
    ])
    private let syncLabel = UILabel()
    private var inbox: ChatInboxSnapshot?
    private var visible: [ChatConversation] = []
    private var loading = true
    private var listError: String?
    private var pollTask: Task<Void, Never>?
    private var backfillTask: Task<Void, Never>?
    private var searchText = ""

    init(
        repository: ChatRepository,
        onOpenDuty: @escaping (String) -> Void,
        onOpenWork: @escaping (String) -> Void,
        onUnread: @escaping (Int) -> Void
    ) {
        self.repository = repository
        self.onOpenDuty = onOpenDuty
        self.onOpenWork = onOpenWork
        self.onUnread = onUnread
        super.init(nibName: nil, bundle: nil)
        title = "Trao đổi"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func installAccountHeader(_ item: UIBarButtonItem) {
        let create = UIBarButtonItem(title: "Tạo nhóm", style: .plain, target: self, action: #selector(createGroup))
        navigationItem.rightBarButtonItems = [item, create]
    }

    func openThread(kind: ChatKind, entityId: String, threadTitle: String = "") {
        let match = inbox?.conversations.first { $0.kind == kind && $0.entityId == entityId }
        showThread(match ?? ChatConversation(
            threadKey: chatThreadKey(kind, entityId),
            kind: kind,
            entityId: entityId,
            title: threadTitle,
            lastBodyText: "",
            lastMessageAt: 0,
            lastAuthorUserId: "",
            unreadCount: 0
        ))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemBackground
        filters.selectedIndex = 0
        filters.accessibilityLabel = "Lọc cuộc trò chuyện"
        filters.addAction(UIAction { [weak self] _ in self?.applyFilter() }, for: .valueChanged)
        filters.translatesAutoresizingMaskIntoConstraints = false
        syncLabel.font = .preferredFont(forTextStyle: .footnote)
        syncLabel.textColor = .secondaryLabel
        syncLabel.numberOfLines = 0
        syncLabel.text = "Đang đồng bộ cuộc trò chuyện cũ…"
        syncLabel.isHidden = true
        syncLabel.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ChatConversationCell.self, forCellReuseIdentifier: ChatConversationCell.reuseId)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self] _ in Task { await self?.reload(manual: true) } }, for: .valueChanged)
        tableView.refreshControl = refresh
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Tìm cuộc trò chuyện…"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        view.addSubview(filters)
        view.addSubview(syncLabel)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            filters.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            filters.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            filters.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            syncLabel.topAnchor.constraint(equalTo: filters.bottomAnchor, constant: 8),
            syncLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            syncLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableView.topAnchor.constraint(equalTo: syncLabel.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.reload(manual: false)
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if navigationController?.viewControllers.contains(self) != true {
            pollTask?.cancel()
            backfillTask?.cancel()
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        applyFilter()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(visible.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if visible.isEmpty {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.selectionStyle = .none
            var content = cell.defaultContentConfiguration()
            if loading && inbox == nil {
                content.text = "Đang tải…"
            } else if let listError, inbox == nil {
                content.text = listError
                content.textProperties.color = .systemRed
            } else if inbox?.conversations.isEmpty != false {
                content.text = "Chưa có cuộc trò chuyện. Hãy tạo nhóm hoặc nhắn trong Công tác, Công việc."
            } else {
                content.text = "Không có cuộc trò chuyện phù hợp."
            }
            content.textProperties.numberOfLines = 0
            content.textProperties.color = content.textProperties.color == .systemRed ? .systemRed : .secondaryLabel
            cell.contentConfiguration = content
            return cell
        }
        let item = visible[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatConversationCell.reuseId, for: indexPath) as! ChatConversationCell
        cell.configure(item: item, currentUserId: inbox?.currentUserId ?? "")
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !visible.isEmpty else { return }
        showThread(visible[indexPath.row])
    }

    private func showThread(_ item: ChatConversation) {
        let heading = item.title.isEmpty ? chatKindLabel(item.kind) : item.title
        let controller = ChatViewController(
            repository: repository,
            target: ChatTarget(kind: item.kind, entityId: item.entityId, title: heading)
        )
        controller.hubActions = true
        controller.onOpenEntity = { [weak self] in
            guard let self else { return }
            if item.kind == .duty { self.onOpenDuty(item.entityId) }
            else if item.kind == .work { self.onOpenWork(item.entityId) }
        }
        controller.onManageGroup = { [weak self] in
            self?.presentManage(groupId: item.entityId)
        }
        controller.onArchive = { [weak self, weak controller] in
            guard let self else { return }
            Task {
                try? await self.repository.archiveMine(threadKey: item.threadKey)
                controller?.navigationController?.popViewController(animated: true)
                await self.reload(manual: false)
            }
        }
        navigationController?.pushViewController(controller, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func presentManage(groupId: String) {
        let controller = ChatManageGroupViewController(repository: repository, groupId: groupId) { [weak self] in
            self?.navigationController?.popToRootViewController(animated: true)
            Task { await self?.reload(manual: false) }
        }
        navigationController?.pushViewController(controller, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    @objc private func createGroup() {
        let controller = ChatCreateGroupViewController(repository: repository) { [weak self] groupId in
            self?.openThread(kind: .group, entityId: groupId, threadTitle: "Nhóm")
            Task { await self?.reload(manual: false) }
        }
        navigationController?.pushViewController(controller, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func reload(manual: Bool) async {
        do {
            let snapshot = try await repository.inbox()
            inbox = snapshot
            listError = nil
            loading = false
            syncLabel.isHidden = !snapshot.backfillPending
            syncLabel.text = snapshot.backfillPending ? "Đang đồng bộ cuộc trò chuyện cũ…" : ""
            let unread = (try? await repository.unreadTotal()) ?? snapshot.conversations.reduce(0) { $0 + $1.unreadCount }
            onUnread(unread)
            applyFilter()
            if snapshot.backfillPending { startBackfill() }
        } catch {
            loading = false
            if inbox == nil {
                listError = chatHubFailureMessage(error.localizedDescription)
            }
            applyFilter()
        }
        if manual { tableView.refreshControl?.endRefreshing() }
    }

    private func startBackfill() {
        guard backfillTask == nil else { return }
        backfillTask = Task { [weak self] in
            guard let self else { return }
            var steps = 0
            while steps < 40 && !Task.isCancelled {
                steps += 1
                let done = (try? await repository.continueBackfill()) ?? false
                if done { break }
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
            backfillTask = nil
            await reload(manual: false)
        }
    }

    private func applyFilter() {
        let kind: ChatKind?
        switch filters.selectedIndex {
        case 1: kind = .duty
        case 2: kind = .work
        case 3: kind = .group
        default: kind = nil
        }
        visible = (inbox?.conversations ?? []).filter { item in
            if let kind, item.kind != kind { return false }
            return chatSearchMatch("\(item.title) \(item.lastBodyText)", searchText)
        }
        tableView.reloadData()
    }
}

private final class ChatConversationCell: UITableViewCell {
    static let reuseId = "ChatConversationCell"
    private let mark = UILabel()
    private let nameLabel = UILabel()
    private let previewLabel = UILabel()
    private let kindLabel = UILabel()
    private let timeLabel = UILabel()
    private let unreadLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        mark.font = .preferredFont(forTextStyle: .caption1)
        mark.textAlignment = .center
        mark.backgroundColor = .systemIndigo.withAlphaComponent(0.15)
        mark.layer.cornerRadius = 22
        mark.clipsToBounds = true
        mark.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = UIFont.preferredFont(forTextStyle: .body).chatHubBold()
        nameLabel.numberOfLines = 1
        previewLabel.font = .preferredFont(forTextStyle: .footnote)
        previewLabel.textColor = .secondaryLabel
        previewLabel.numberOfLines = 1
        kindLabel.font = .preferredFont(forTextStyle: .caption2)
        kindLabel.textColor = .systemIndigo
        timeLabel.font = .preferredFont(forTextStyle: .caption2)
        timeLabel.textColor = .secondaryLabel
        unreadLabel.font = .preferredFont(forTextStyle: .caption2)
        unreadLabel.textColor = .white
        unreadLabel.backgroundColor = .systemRed
        unreadLabel.textAlignment = .center
        unreadLabel.layer.cornerRadius = 10
        unreadLabel.clipsToBounds = true
        let copy = UIStackView(arrangedSubviews: [nameLabel, previewLabel, kindLabel])
        copy.axis = .vertical
        copy.spacing = 2
        let meta = UIStackView(arrangedSubviews: [timeLabel, unreadLabel])
        meta.axis = .vertical
        meta.alignment = .trailing
        meta.spacing = 6
        let row = UIStackView(arrangedSubviews: [mark, copy, meta])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 44),
            mark.heightAnchor.constraint(equalToConstant: 44),
            unreadLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
            unreadLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(item: ChatConversation, currentUserId: String) {
        let heading = item.title.isEmpty ? (item.kind == .group ? "Nhóm" : "Trao đổi") : item.title
        nameLabel.text = heading
        let preview = chatListPreview(
            lastBodyText: item.lastBodyText,
            lastAuthorUserId: item.lastAuthorUserId,
            currentUserId: currentUserId
        )
        previewLabel.text = preview
        previewLabel.font = preview == chatRecalledPlaceholder
            ? .italicSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize)
            : .preferredFont(forTextStyle: .footnote)
        kindLabel.text = chatKindLabel(item.kind)
        timeLabel.text = formatChatListTime(item.lastMessageAt)
        if item.kind == .group {
            mark.text = chatHubInitials(heading)
        } else {
            mark.text = item.kind == .duty ? "CT" : "CV"
        }
        if item.unreadCount > 0 {
            unreadLabel.isHidden = false
            unreadLabel.text = item.unreadCount > 99 ? "99+" : "\(item.unreadCount)"
        } else {
            unreadLabel.isHidden = true
        }
        accessibilityLabel = "\(chatKindLabel(item.kind)). \(heading). \(preview)"
    }
}

private func chatHubInitials(_ title: String) -> String {
    let parts = title.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    if parts.isEmpty { return "N" }
    return parts.prefix(2).compactMap { $0.first }.map { String($0).uppercased(with: Locale(identifier: "vi_VN")) }.joined()
}

private extension UIFont {
    func chatHubBold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
