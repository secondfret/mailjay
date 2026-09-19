import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    var phase: AppPhase = .disconnected
    var results: [TriageResult] = []
    var selectedCategoryID: String = CategoryID.all
    var selectedMessageID: String?
    var categories: [MailCategory] = MailCategory.defaults
    var isPresentingCategoryEditor = false
    var isPresentingOnboarding = false

    private(set) var configuration: AppConfiguration
    private(set) var accounts: [MailAccount] = []
    private(set) var activeAccountEmail: String?

    private let keychain = KeychainStore()
    private let oauth = GoogleOAuthService()
    private let gmail = GmailService()
    private let jev = JevService()
    private var cache: TriageCache
    private var categoryStore: CategoryStore?
    private var autoFetchTask: Task<Void, Never>?
    private var isSyncingAll = false

    /// Quiet status for background auto-fetch (does not lock the UI).
    var backgroundSyncStatus: String?

    init(cache: TriageCache = TriageCache()) {
        self.cache = cache
        let secrets = keychain.loadSecrets()
        // Drop obsolete preference from an earlier local-classifier experiment.
        UserDefaults.standard.removeObject(forKey: "classifier-provider")
        let storedMax = UserDefaults.standard.object(forKey: "max-messages") as? Int
        let storedInterval = UserDefaults.standard.object(forKey: "auto-fetch-interval-minutes") as? Int
        configuration = AppConfiguration(
            googleClientID: BundledGoogleOAuth.clientID,
            googleClientSecret: BundledGoogleOAuth.clientSecret,
            jevAPIKey: secrets.jevAPIKey,
            maxMessages: storedMax.map { min(1000, max(10, $0)) } ?? AppConfiguration.defaultMaxMessages,
            confidenceThreshold: UserDefaults.standard.object(forKey: "confidence-threshold") as? Double ?? 0.45,
            autoFetchIntervalMinutes: Self.normalizedAutoFetchInterval(
                storedInterval ?? AppConfiguration.defaultAutoFetchIntervalMinutes
            )
        )
        accounts = secrets.accounts
        activeAccountEmail = secrets.activeAccountEmail ?? secrets.accounts.first?.email
        if let email = activeAccountEmail {
            TriageCache.migrateLegacyCacheIfNeeded(into: email)
            self.cache = .forAccount(email: email)
            let store = CategoryStore.forAccount(email: email)
            categoryStore = store
            categories = store.load()
        }
        results = self.cache.load().sorted { ($0.message.date ?? .distantPast) > ($1.message.date ?? .distantPast) }
        selectedMessageID = results.first?.id
        phase = activeAccount == nil ? .disconnected : .ready
        isPresentingOnboarding = !UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey)
        restartAutoFetchLoop()
    }

    private static let onboardingCompletedKey = "onboarding-completed"

    func presentOnboarding() {
        isPresentingOnboarding = true
    }

    func dismissOnboarding() {
        isPresentingOnboarding = false
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
    }

    var activeAccount: MailAccount? {
        accounts.first { $0.email == activeAccountEmail }
    }

    var sidebarItems: [String] {
        [CategoryID.all] + categories.map(\.id) + [CategoryID.uncertain]
    }

    var filteredResults: [TriageResult] {
        let pending = results.filter(\.isPending)
        switch selectedCategoryID {
        case CategoryID.all:
            return pending
        default:
            return pending.filter { $0.bucket == selectedCategoryID }
        }
    }

    var selectedResult: TriageResult? {
        filteredResults.first { $0.id == selectedMessageID }
    }

    var currentBucketSelectedCount: Int { selectableResults(selected: true).count }
    var currentBucketSelectableCount: Int { selectableResults(selected: nil).count }
    var isConnected: Bool { activeAccount != nil }
    var allVisibleSelected: Bool {
        let selectable = selectableResults(selected: nil)
        return !selectable.isEmpty && selectable.allSatisfy(\.isSelected)
    }

    private func selectableResults(selected: Bool?) -> [TriageResult] {
        filteredResults.filter { result in
            guard !result.isApplied else { return false }
            if let selected { return result.isSelected == selected }
            return true
        }
    }

    func category(for id: String) -> MailCategory? {
        if id == CategoryID.uncertain { return .uncertain }
        return categories.first { $0.id == id }
    }

    func title(forCategoryID id: String) -> String {
        switch id {
        case CategoryID.all: "All Results"
        case CategoryID.uncertain: MailCategory.uncertain.title
        default: category(for: id)?.title ?? "Unknown"
        }
    }

    func systemImage(forCategoryID id: String) -> String {
        switch id {
        case CategoryID.all: "tray.full"
        case CategoryID.uncertain: MailCategory.uncertain.systemImage
        default: category(for: id)?.systemImage ?? "folder"
        }
    }

    func count(forCategoryID id: String) -> Int {
        let pending = results.filter(\.isPending)
        switch id {
        case CategoryID.all: return pending.count
        default: return pending.filter { $0.bucket == id }.count
        }
    }

    func saveCategories(_ newValue: [MailCategory]) throws {
        let cleaned = try validatedCategories(newValue)
        categories = cleaned
        if let categoryStore {
            try categoryStore.save(cleaned)
        } else if let email = activeAccountEmail {
            let store = CategoryStore.forAccount(email: email)
            categoryStore = store
            try store.save(cleaned)
        } else {
            throw StoreError.notConnected
        }
        // Drop selection if the selected category was removed.
        if selectedCategoryID != CategoryID.all,
           selectedCategoryID != CategoryID.uncertain,
           !categories.contains(where: { $0.id == selectedCategoryID }) {
            selectedCategoryID = CategoryID.all
        }
        // Remap results that pointed at deleted categories.
        let validIDs = Set(categories.map(\.id) + [CategoryID.uncertain])
        var changed = false
        for index in results.indices where !validIDs.contains(results[index].bucket) {
            results[index].bucket = CategoryID.uncertain
            changed = true
        }
        if changed { saveResults() }
    }

    func resetCategoriesToDefaults() throws {
        try saveCategories(MailCategory.defaults)
    }

    private func validatedCategories(_ input: [MailCategory]) throws -> [MailCategory] {
        var seenIDs = Set<String>()
        var output: [MailCategory] = []
        for (index, raw) in input.enumerated() {
            var category = raw
            category.title = category.title.trimmingCharacters(in: .whitespacesAndNewlines)
            category.systemImage = category.systemImage.trimmingCharacters(in: .whitespacesAndNewlines)
            category.modelDescription = category.modelDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if let gmail = category.gmailLabelName?.trimmingCharacters(in: .whitespacesAndNewlines), !gmail.isEmpty {
                category.gmailLabelName = gmail
            } else {
                category.gmailLabelName = nil
            }
            category.sortOrder = index

            guard !category.title.isEmpty else {
                throw StoreError.invalidCategories("Each category needs a title.")
            }
            guard !category.systemImage.isEmpty else {
                throw StoreError.invalidCategories("Each category needs an SF Symbol name.")
            }
            guard !category.modelDescription.isEmpty else {
                throw StoreError.invalidCategories("Each category needs a model description for Jev.")
            }
            guard category.id != CategoryID.all, category.id != CategoryID.uncertain else {
                throw StoreError.invalidCategories("Reserved category ids cannot be reused.")
            }
            guard seenIDs.insert(category.id).inserted else {
                throw StoreError.invalidCategories("Duplicate category id.")
            }
            output.append(category)
        }
        guard !output.isEmpty else {
            throw StoreError.invalidCategories("Add at least one category.")
        }
        return output
    }

    func saveConfiguration(_ newValue: AppConfiguration) throws {
        var normalized = newValue
        normalized.googleClientID = BundledGoogleOAuth.clientID
        normalized.googleClientSecret = BundledGoogleOAuth.clientSecret
        normalized.maxMessages = min(1000, max(10, normalized.maxMessages))
        normalized.autoFetchIntervalMinutes = Self.normalizedAutoFetchInterval(normalized.autoFetchIntervalMinutes)
        configuration = normalized
        var secrets = keychain.loadSecrets()
        secrets.googleClientID = ""
        secrets.googleClientSecret = ""
        secrets.jevAPIKey = normalized.jevAPIKey
        secrets.accounts = accounts
        secrets.activeAccountEmail = activeAccountEmail
        try keychain.saveSecrets(secrets)
        UserDefaults.standard.removeObject(forKey: "classifier-provider")
        UserDefaults.standard.set(normalized.maxMessages, forKey: "max-messages")
        UserDefaults.standard.set(normalized.confidenceThreshold, forKey: "confidence-threshold")
        UserDefaults.standard.set(normalized.autoFetchIntervalMinutes, forKey: "auto-fetch-interval-minutes")
        restartAutoFetchLoop()
    }

    func addAccount() async {
        guard configuration.isComplete else {
            phase = .failed(setupIncompleteMessage)
            return
        }
        phase = .loading("Waiting for Google sign-in…")
        do {
            let token = try await oauth.authorize(
                clientID: configuration.googleClientID,
                clientSecret: configuration.googleClientSecret
            )
            let email = try await gmail.profileEmail(accessToken: token.accessToken)
            persistCurrentResults()
            if let index = accounts.firstIndex(where: { $0.email == email }) {
                accounts[index].token = token
            } else {
                accounts.append(MailAccount(email: email, token: token))
            }
            activeAccountEmail = email
            try persistAccounts()
            loadResultsForActiveAccount()
            phase = .ready
            restartAutoFetchLoop()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Backwards-compatible alias used by existing Connect buttons.
    func connect() async {
        await addAccount()
    }

    func switchAccount(to email: String) {
        guard email != activeAccountEmail,
              accounts.contains(where: { $0.email == email }) else { return }
        persistCurrentResults()
        activeAccountEmail = email
        try? persistAccounts()
        loadResultsForActiveAccount()
        selectedCategoryID = CategoryID.all
        phase = .ready
    }

    func removeAccount(_ email: String) {
        persistCurrentResults()
        accounts.removeAll { $0.email == email }
        if activeAccountEmail == email {
            activeAccountEmail = accounts.first?.email
        }
        try? persistAccounts()
        try? TriageCache.forAccount(email: email).clear()
        try? CategoryStore.forAccount(email: email).clear()
        if activeAccountEmail != nil {
            loadResultsForActiveAccount()
            phase = .ready
            restartAutoFetchLoop()
        } else {
            results = []
            selectedMessageID = nil
            categories = MailCategory.defaults
            categoryStore = nil
            cache = TriageCache()
            phase = .disconnected
            stopAutoFetchLoop()
        }
    }

    func disconnect() {
        guard let email = activeAccountEmail else {
            phase = .disconnected
            return
        }
        removeAccount(email)
    }

    func scanInbox() async {
        guard configuration.isComplete else {
            phase = .failed(setupIncompleteMessage)
            return
        }
        guard activeAccount != nil else {
            phase = .failed("Connect a Gmail account first.")
            return
        }
        await scanAllInboxes(interactive: true)
    }

    /// Fetches and classifies new inbox mail for every connected account.
    /// Interactive runs show the usual busy phase; background runs stay non-blocking.
    func scanAllInboxes(interactive: Bool) async {
        guard configuration.isComplete else {
            if interactive { phase = .failed(setupIncompleteMessage) }
            return
        }
        guard !accounts.isEmpty else {
            if interactive { phase = .failed("Connect a Gmail account first.") }
            return
        }
        guard !isSyncingAll else { return }
        if !interactive, phase.isBusy { return }

        isSyncingAll = true
        defer {
            isSyncingAll = false
            backgroundSyncStatus = nil
        }

        let emails = accounts.map(\.email)
        for (accountIndex, email) in emails.enumerated() {
            let accountLabel = emails.count > 1
                ? "\(email) (\(accountIndex + 1)/\(emails.count))"
                : email
            if interactive {
                phase = .loading("Fetching recent inbox mail for \(accountLabel)…")
            } else {
                backgroundSyncStatus = "Checking \(accountLabel)…"
            }

            do {
                try await scanAccount(
                    email: email,
                    interactive: interactive,
                    progressLabel: accountLabel
                )
            } catch {
                if interactive {
                    phase = .failed(error.localizedDescription)
                    return
                }
                // Background failures are non-fatal; the next interval retries.
            }
        }
        if interactive {
            phase = .reviewing
        }
    }

    private func scanAccount(
        email: String,
        interactive: Bool,
        progressLabel: String
    ) async throws {
        if activeAccountEmail == email {
            persistCurrentResults()
        }

        let accessToken = try await validAccessToken(for: email)
        let accountCache = TriageCache.forAccount(email: email)
        let accountCategories = CategoryStore.forAccount(email: email).load()

        var working: [TriageResult] = activeAccountEmail == email
            ? results
            : accountCache.load()

        let messages = try await gmail.inboxMessages(
            accessToken: accessToken,
            maximum: configuration.maxMessages,
            excluding: Set(working.map(\.id))
        )
        guard !messages.isEmpty else {
            if activeAccountEmail == email {
                selectedMessageID = selectedMessageID ?? working.first?.id
            }
            return
        }

        for (index, message) in messages.enumerated() {
            if interactive {
                phase = .loading("\(progressLabel): \(classificationProgress(index + 1, of: messages.count))")
            } else {
                backgroundSyncStatus = "\(progressLabel): \(classificationProgress(index + 1, of: messages.count))"
            }

            let result = try await jev.classify(
                message,
                apiKey: configuration.jevAPIKey,
                threshold: configuration.confidenceThreshold,
                categories: accountCategories
            )
            working.append(result)
            working.sort { ($0.message.date ?? .distantPast) > ($1.message.date ?? .distantPast) }
            try? accountCache.save(working)

            if activeAccountEmail == email {
                results = working
                cache = accountCache
                if selectedMessageID == nil || !working.contains(where: { $0.id == selectedMessageID }) {
                    selectedMessageID = message.id
                }
            }
        }
    }

    func reclassifyLoaded() async {
        guard configuration.isComplete else {
            phase = .failed(setupIncompleteMessage)
            return
        }
        let pending = results.filter(\.isPending)
        guard !pending.isEmpty else {
            phase = .failed("No loaded emails to re-categorize.")
            return
        }
        do {
            for (index, existing) in pending.enumerated() {
                phase = .loading(reclassifyProgress(index + 1, of: pending.count))
                var updated = try await classify(existing.message)
                updated.isSelected = existing.isSelected
                if let resultIndex = results.firstIndex(where: { $0.id == existing.id }) {
                    results[resultIndex] = updated
                    sortAndSaveResults()
                }
            }
            selectedMessageID = filteredResults.first?.id ?? selectedMessageID
            phase = .reviewing
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func classify(_ message: MailMessage) async throws -> TriageResult {
        try await jev.classify(
            message,
            apiKey: configuration.jevAPIKey,
            threshold: configuration.confidenceThreshold,
            categories: categories
        )
    }

    private var setupIncompleteMessage: String {
        if !BundledGoogleOAuth.isConfigured {
            return "Google OAuth is not embedded. Add Config/GoogleOAuth.plist (see Config/GoogleOAuth.plist.example) and rebuild with ./script/build_and_run.sh."
        }
        return "Add your TypeSafe Jev API key in Settings first."
    }

    private func classificationProgress(_ index: Int, of total: Int) -> String {
        "Asking Jev about \(index) of \(total)…"
    }

    private func reclassifyProgress(_ index: Int, of total: Int) -> String {
        "Re-categorizing with Jev \(index) of \(total)…"
    }

    func selectCategory(_ categoryID: String) {
        selectedCategoryID = categoryID
        if categoryID == CategoryID.all {
            return
        }
        setAllVisibleSelected(true)
    }

    /// ⌘↑ / ⌘↓ — move through sidebar categories (All → buckets → Needs Review).
    func navigateCategory(by delta: Int) {
        let items = sidebarItems
        guard !items.isEmpty else { return }
        let current = items.firstIndex(of: selectedCategoryID) ?? 0
        let next = (current + delta + items.count) % items.count
        selectCategory(items[next])
    }

    /// ⌘⇧↑ / ⌘⇧↓ — move through connected Gmail accounts.
    func navigateAccount(by delta: Int) {
        guard accounts.count > 1,
              let current = accounts.firstIndex(where: { $0.email == activeAccountEmail }) else { return }
        let next = (current + delta + accounts.count) % accounts.count
        switchAccount(to: accounts[next].email)
    }

    func setSelected(_ id: String, selected: Bool) {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        results[index].isSelected = selected
        saveResults()
    }

    func setAllVisibleSelected(_ selected: Bool) {
        let ids = Set(selectableResults(selected: nil).map(\.id))
        guard !ids.isEmpty else { return }
        for index in results.indices where ids.contains(results[index].id) {
            results[index].isSelected = selected
        }
        saveResults()
    }

    func move(_ id: String, to categoryID: String) {
        guard categoryID != CategoryID.all,
              let index = results.firstIndex(where: { $0.id == id }) else { return }
        results[index].bucket = categoryID
        saveResults()
    }

    func applySelected(_ action: MailAction) async {
        let pending = selectableResults(selected: true)
        guard !pending.isEmpty else { return }
        do {
            let accessToken = try await validAccessToken()
            let labels = try await gmail.ensureTriageLabels(accessToken: accessToken, categories: categories)
            phase = .applying("\(action.title) \(pending.count) messages…")
            try await gmail.apply(pending, action: action, accessToken: accessToken, labelIDs: labels)
            let appliedIDs = Set(pending.map(\.id))
            for index in results.indices where appliedIDs.contains(results[index].id) {
                results[index].isApplied = true
                results[index].isSelected = false
            }
            saveResults()
            selectedMessageID = filteredResults.first?.id
            phase = .reviewing
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func sortAndSaveResults() {
        results.sort { ($0.message.date ?? .distantPast) > ($1.message.date ?? .distantPast) }
        saveResults()
    }

    private func saveResults() {
        try? cache.save(results)
    }

    private func persistCurrentResults() {
        guard activeAccountEmail != nil else { return }
        try? cache.save(results)
    }

    private func loadResultsForActiveAccount() {
        guard let email = activeAccountEmail else {
            results = []
            selectedMessageID = nil
            categories = MailCategory.defaults
            categoryStore = nil
            return
        }
        cache = .forAccount(email: email)
        let store = CategoryStore.forAccount(email: email)
        categoryStore = store
        categories = store.load()
        results = cache.load().sorted { ($0.message.date ?? .distantPast) > ($1.message.date ?? .distantPast) }
        selectedMessageID = results.first?.id
    }

    private func validAccessToken() async throws -> String {
        try await validAccessToken(for: activeAccountEmail)
    }

    private func validAccessToken(for email: String?) async throws -> String {
        guard let email,
              var account = accounts.first(where: { $0.email == email }) else {
            throw StoreError.notConnected
        }
        var token = account.token
        if token.needsRefresh {
            token = try await oauth.refreshedToken(
                token,
                clientID: configuration.googleClientID,
                clientSecret: configuration.googleClientSecret
            )
            account.token = token
            if let index = accounts.firstIndex(where: { $0.email == account.email }) {
                accounts[index] = account
            }
            try persistAccounts()
        }
        return token.accessToken
    }

    private static func normalizedAutoFetchInterval(_ minutes: Int) -> Int {
        let allowed = AppConfiguration.autoFetchIntervalChoices
        if allowed.contains(minutes) { return minutes }
        return allowed.min(by: { abs($0 - minutes) < abs($1 - minutes) }) ?? AppConfiguration.defaultAutoFetchIntervalMinutes
    }

    private func restartAutoFetchLoop() {
        stopAutoFetchLoop()
        let intervalMinutes = configuration.autoFetchIntervalMinutes
        guard intervalMinutes > 0, !accounts.isEmpty, configuration.isComplete else { return }

        autoFetchTask = Task { @MainActor [weak self] in
            // Small delay so launch UI can settle before the first background pass.
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.scanAllInboxes(interactive: false)

            while !Task.isCancelled {
                guard let self else { return }
                let minutes = self.configuration.autoFetchIntervalMinutes
                guard minutes > 0 else { return }
                try? await Task.sleep(for: .seconds(minutes * 60))
                guard !Task.isCancelled else { return }
                await self.scanAllInboxes(interactive: false)
            }
        }
    }

    private func stopAutoFetchLoop() {
        autoFetchTask?.cancel()
        autoFetchTask = nil
    }

    private func persistAccounts() throws {
        var secrets = keychain.loadSecrets()
        secrets.accounts = accounts
        secrets.activeAccountEmail = activeAccountEmail
        secrets.oauthTokenJSON = nil
        try keychain.saveSecrets(secrets)
    }

    /// Resolves placeholder "Primary Gmail" accounts created during migration.
    func resolveActiveAccountEmailIfNeeded() async {
        guard let account = activeAccount,
              account.email == "Primary Gmail" else { return }
        do {
            let email = try await gmail.profileEmail(accessToken: try await validAccessToken())
            if let index = accounts.firstIndex(where: { $0.email == account.email }) {
                var updated = accounts[index]
                updated.email = email
                accounts[index] = updated
                TriageCache.migrateLegacyCacheIfNeeded(into: email)
                // Move placeholder cache if any was saved under the placeholder name.
                let placeholderCache = TriageCache.forAccount(email: "Primary Gmail")
                let destination = TriageCache.accountURL(email: email)
                if FileManager.default.fileExists(atPath: placeholderCache.fileURL.path),
                   !FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try? FileManager.default.moveItem(at: placeholderCache.fileURL, to: destination)
                }
                activeAccountEmail = email
                try persistAccounts()
                loadResultsForActiveAccount()
            }
        } catch {
            // Leave placeholder until the user reconnects.
        }
    }

    enum StoreError: LocalizedError {
        case notConnected
        case invalidCategories(String)

        var errorDescription: String? {
            switch self {
            case .notConnected:
                "Connect your Gmail account first."
            case .invalidCategories(let message):
                message
            }
        }
    }
}
