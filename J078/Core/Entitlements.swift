import Foundation

// HackTheScoot billing rules (v4.1, TEST MODE). Pure Foundation so they are unit-tested.
//
// Tiers are exactly Credence's spec + docs/business/billing-plan.md:
//   FREE: discovery, compatibility database, verified basic controls, speedometer,
//         factory riding modes, battery when available, essential diagnostics,
//         safety information, basic trip history. Plus everything 4.0.1 already had
//         (themes, designer, layouts, replay, terminal, export summary): nothing that
//         was free before 4.1 is ever moved behind the paywall.
//   PRO ($3.99/mo, $29.99/yr): NEW extras only.
//   DEVELOPER: "consider later" in the spec. Not for sale yet; previewable with the
//         test unlock in Developer settings.
// Never paywalled: safety, fault warnings, basic scooter controls, connecting,
// compatibility info. There is NO speed-unlock entitlement.

enum Tier: Int, Codable, CaseIterable, Comparable, Identifiable {
    case free = 0, pro = 1, developer = 2

    var id: Int { rawValue }
    static func < (a: Tier, b: Tier) -> Bool { return a.rawValue < b.rawValue }

    var name: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .developer: return "Developer"
        }
    }
}

/// The paid extras. Every case is cosmetic, analysis or export. Nothing here touches
/// what the scooter does.
enum ProFeature: String, CaseIterable, Identifiable, Codable {
    case premiumThemes          // the extra Pro theme pack (the 4.0.1 presets stay free)
    case tripAnalytics          // all-rides analytics: totals, speed histogram, time in mode, records
    case dataExport             // CSV + GPX export (the 4.0.1 text summary stays free)
    case extendedLogAnalysis    // packet log statistics per channel / command
    case protocolWorkspace      // developer: compare frames byte by byte
    case developerExport        // developer: JSON log export for fixtures

    var id: String { rawValue }

    var requiredTier: Tier {
        switch self {
        case .premiumThemes, .tripAnalytics, .dataExport, .extendedLogAnalysis: return .pro
        case .protocolWorkspace, .developerExport: return .developer
        }
    }

    var title: String {
        switch self {
        case .premiumThemes: return "Pro theme pack"
        case .tripAnalytics: return "Advanced trip analytics"
        case .dataExport: return "CSV + GPX export"
        case .extendedLogAnalysis: return "Extended log analysis"
        case .protocolWorkspace: return "Frame compare workspace"
        case .developerExport: return "Developer JSON export"
        }
    }

    var detail: String {
        switch self {
        case .premiumThemes: return "Six extra dashboard looks."
        case .tripAnalytics: return "Totals, records, speed histogram and time in each mode across all rides, per scooter."
        case .dataExport: return "Rides as CSV (spreadsheets) and GPX (maps, when GPS was on)."
        case .extendedLogAnalysis: return "Frames per channel, command counts, rates and gaps from the packet log."
        case .protocolWorkspace: return "Paste two frames and see every byte that changed."
        case .developerExport: return "The packet log as JSON, for test fixtures."
        }
    }

    var icon: String {
        switch self {
        case .premiumThemes: return "paintbrush.pointed"
        case .tripAnalytics: return "chart.bar.xaxis"
        case .dataExport: return "square.and.arrow.up.on.square"
        case .extendedLogAnalysis: return "waveform.path.ecg"
        case .protocolWorkspace: return "rectangle.split.2x1"
        case .developerExport: return "curlybraces"
        }
    }
}

enum Billing {
    /// v4.1 is TEST MODE ONLY. Nothing in this build charges real money.
    static let testMode = true

    static let proMonthlyID = "com.hackthescoot.pro.monthly"
    static let proYearlyID = "com.hackthescoot.pro.yearly"
    static let subscriptionGroup = "HackTheScoot Pro"
    static let productIDs: [String] = [proMonthlyID, proYearlyID]

    /// Fallback prices shown when the App Store has no products (sideloaded build).
    static let proMonthlyPrice = "$3.99"
    static let proYearlyPrice = "$29.99"

    /// The download page's Stripe TEST checkout section.
    static let webTestURL = "https://j078-app.sites.tab.bot/#pro"

    /// What a purchase of each product unlocks.
    static func tier(forProduct id: String) -> Tier {
        switch id {
        case proMonthlyID, proYearlyID: return .pro
        default: return .free
        }
    }

    /// The effective tier: the best of what was bought and the labelled test unlock.
    static func effectiveTier(purchased: Set<String>, testUnlock: Tier) -> Tier {
        let bought = purchased.map { tier(forProduct: $0) }.max() ?? .free
        return max(bought, testUnlock)
    }

    static func allows(_ f: ProFeature, tier: Tier) -> Bool {
        return tier >= f.requiredTier
    }

    /// Scooter capabilities are NEVER sold. Safety, controls and diagnostics are free.
    static func requiredTier(for capability: Capability) -> Tier { return .free }

    /// Shown on the paywall so nobody thinks a basic feature is for sale.
    static let alwaysFree: [String] = [
        "Connecting to your scooter",
        "Speed, modes, light, park and every control",
        "Speed limits, including the above-stock sliders",
        "Fault warnings and safety information",
        "Compatibility database and checker",
        "Garage with all your scooters",
        "Dashboard themes, designer and saved layouts",
        "Trip history, replay and summary export",
        "Diagnostics, Developer Lab, packet log and terminal"
    ]

    static let yearlySavingPercent: Int = {
        let monthlyYear = 3.99 * 12
        return Int(((monthlyYear - 29.99) / monthlyYear * 100).rounded())
    }()
}
