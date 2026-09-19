import Foundation

/// Stable reserved IDs used by the sidebar and low-confidence routing.
enum CategoryID {
    static let all = "all"
    static let uncertain = "uncertain"
}

/// A user-editable triage category. IDs for the shipped defaults stay stable
/// (`ads`, `newsletters`, …) so existing triage caches keep working when IDs stay stable.
struct MailCategory: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var title: String
    var systemImage: String
    /// Criteria text sent to Jev (and shown as guidance in the editor).
    var modelDescription: String
    /// When set, Archive applies a Gmail label named `Jev/{gmailLabelName}`.
    var gmailLabelName: String?
    var sortOrder: Int

    var appliesGmailLabel: Bool { gmailLabelName?.isEmpty == false }

    static let uncertain = MailCategory(
        id: CategoryID.uncertain,
        title: "Needs Review",
        systemImage: "questionmark.circle",
        modelDescription: "The content is ambiguous, potentially sensitive, or cannot safely be assigned to another action. Leave it untouched for manual review.",
        gmailLabelName: nil,
        sortOrder: 10_000
    )

    static let defaults: [MailCategory] = [
        MailCategory(
            id: "ads",
            title: "Ads & Promos",
            systemImage: "megaphone",
            modelDescription: "Bulk advertising and promotional campaigns from brands/stores: % off, flash sales, product launches, “new feature” marketing, coupon codes, abandoned-cart nudges, and shop-now CTAs. Often has Unsubscribe and looks like a campaign, not a receipt for something already bought. NOT subscribed editorial newsletters, NOT recruiter/SDR cold pitches, NOT order/shipping confirmations.",
            gmailLabelName: nil,
            sortOrder: 0
        ),
        MailCategory(
            id: "newsletters",
            title: "Newsletters",
            systemImage: "newspaper",
            modelDescription: "Editorial newsletters and topic digests I opted into: “Issue #”, weekly/daily digest, curated links, Substack/Beehiiv-style writing, industry briefings meant to be read. Tone is content, not a hard sell. NOT one-off brand promos/coupons (Ads), NOT product activity emails from apps I use (App Notifications), NOT cold sales pitches.",
            gmailLabelName: "Newsletters",
            sortOrder: 1
        ),
        MailCategory(
            id: "app-notifications",
            title: "App Notifications",
            systemImage: "bell",
            modelDescription: "Automated product/workflow noise from SaaS tools (Figma, GitHub, Notion, Slack, Linear, Stripe dashboard, etc.): comments, @mentions, share/invite to a doc, CI/build status, usage digests, “your workspace”, plan renewal reminders that are not security events. NOT calendar invites/reminders, NOT login/2FA/password security alerts, NOT invoices/receipts, NOT human conversation.",
            gmailLabelName: "App Notifications",
            sortOrder: 2
        ),
        MailCategory(
            id: "people",
            title: "People",
            systemImage: "person.2",
            modelDescription: "Mail from real humans in an ongoing relationship (coworkers, friends, family, known clients): questions, requests, replies in a thread, “can you…”, intros between people I know, personal notes. Written like a person, not a template blast. NOT cold recruiter/sales outreach from strangers, NOT automated app notifications, NOT newsletters or promo campaigns.",
            gmailLabelName: "People",
            sortOrder: 3
        ),
        MailCategory(
            id: "calendar",
            title: "Calendar",
            systemImage: "calendar",
            modelDescription: "Scheduling and calendar traffic: meeting invitations, accepted/declined/tentative replies, time/location updates, cancellations, and calendar reminders (Google Calendar, Outlook, Zoom/Meet join details, .ics). About a specific event on the calendar. NOT general SaaS activity digests, NOT newsletters, NOT security alerts.",
            gmailLabelName: "Calendar",
            sortOrder: 4
        ),
        MailCategory(
            id: "receipts",
            title: "Receipts & Records",
            systemImage: "receipt",
            modelDescription: "Transactional records to file: order confirmations, invoices, payment received/charged, shipping & delivery tracking, bookings/tickets, bank/card statements, tax docs. Evidence of a purchase or payment already made or owed—not a “buy now” promo. Archive for records; no reply needed. NOT marketing sales blasts, NOT cold outreach.",
            gmailLabelName: "Receipts",
            sortOrder: 5
        ),
        MailCategory(
            id: "security",
            title: "Security",
            systemImage: "lock.shield",
            modelDescription: "Account security and access alerts: new sign-in / new device, verification or 2FA codes, password reset links, suspicious login, recovery email changed, “was this you?”. Keep visible; usually act in the product, not by replying. NOT routine app activity digests, NOT billing receipts, NOT calendar invites.",
            gmailLabelName: "Security",
            sortOrder: 6
        ),
        MailCategory(
            id: "cold-outreach",
            title: "Cold Outreach",
            systemImage: "envelope.badge",
            modelDescription: "Unsolicited outreach from strangers pretending to be personal: recruiters, SDRs, agency pitches, “quick chat”, “saw your profile/LinkedIn”, partnership proposals, lead-gen templates. Looks one-to-one but is mass outreach. Safe to trash unless I choose to engage. NOT mail from people I already know (People), NOT brand promo campaigns with Unsubscribe (Ads), NOT newsletters I subscribed to.",
            gmailLabelName: nil,
            sortOrder: 7
        ),
    ]

    static func makeNew(sortOrder: Int) -> MailCategory {
        MailCategory(
            id: UUID().uuidString,
            title: "New Category",
            systemImage: "folder",
            modelDescription: "Describe when an email should land in this category so the classifier can choose it.",
            gmailLabelName: nil,
            sortOrder: sortOrder
        )
    }
}

struct MailMessage: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let threadID: String
    let sender: String
    let subject: String
    let date: Date?
    let snippet: String
    let body: String
    let htmlBody: String?
}

struct TriageResult: Identifiable, Equatable, Codable, Sendable {
    var id: String { message.id }
    let message: MailMessage
    /// Category id (`junk`, custom UUID, or `uncertain`).
    var bucket: String
    let confidence: Double
    var probabilities: [String: Double]
    var isSelected: Bool
    var isApplied: Bool

    var isPending: Bool { !isApplied }

    static func fromPrediction(
        message: MailMessage,
        predicted: String,
        confidence: Double,
        probabilities: [String: Double],
        threshold: Double
    ) -> TriageResult {
        let bucket = confidence >= threshold ? predicted : CategoryID.uncertain
        return TriageResult(
            message: message,
            bucket: bucket,
            confidence: confidence,
            probabilities: probabilities,
            isSelected: false,
            isApplied: false
        )
    }
}

struct AppConfiguration: Equatable, Sendable {
    var googleClientID: String
    var googleClientSecret: String
    var jevAPIKey: String
    var maxMessages: Int
    var confidenceThreshold: Double
    /// Minutes between automatic inbox scans for all accounts. `0` disables auto-fetch.
    var autoFetchIntervalMinutes: Int
    /// When true, HTML email may load remote http(s) images. When false, CSP blocks them for privacy.
    var loadRemoteImages: Bool

    static let defaultMaxMessages = 300
    static let defaultAutoFetchIntervalMinutes = 15
    static let defaultLoadRemoteImages = true
    static let autoFetchIntervalChoices = [0, 5, 10, 15, 30, 60]

    static let empty = AppConfiguration(
        googleClientID: "",
        googleClientSecret: "",
        jevAPIKey: "",
        maxMessages: defaultMaxMessages,
        confidenceThreshold: 0.45,
        autoFetchIntervalMinutes: defaultAutoFetchIntervalMinutes,
        loadRemoteImages: defaultLoadRemoteImages
    )

    var isComplete: Bool {
        BundledGoogleOAuth.isConfigured
            && !jevAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct OAuthToken: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date

    var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 90 }
}

struct MailAccount: Codable, Equatable, Identifiable, Sendable {
    var id: String { email }
    var email: String
    var token: OAuthToken
}

enum MailAction: String, Sendable {
    case archive
    case delete

    var title: String {
        switch self {
        case .archive: "Archive"
        case .delete: "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .archive: "archivebox"
        case .delete: "trash"
        }
    }
}

enum AppPhase: Equatable, Sendable {
    case disconnected
    case ready
    case loading(String)
    case reviewing
    case applying(String)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .loading, .applying: true
        default: false
        }
    }

    /// True while `reclassifyLoaded()` is updating buckets.
    var isRecategorizing: Bool {
        if case .loading(let message) = self {
            return message.hasPrefix("Re-categorizing")
        }
        return false
    }

    /// True while fetching/classifying a new inbox scan (not a re-run).
    var isScanning: Bool {
        if case .loading(let message) = self {
            return !message.hasPrefix("Re-categorizing")
        }
        return false
    }

    var statusMessage: String? {
        switch self {
        case .loading(let message), .applying(let message): message
        default: nil
        }
    }

    var errorMessage: String? {
        if case .failed(let message) = self { message } else { nil }
    }
}
