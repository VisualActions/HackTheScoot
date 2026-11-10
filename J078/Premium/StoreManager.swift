import Foundation
import StoreKit

/// StoreKit 2 + the labelled test unlock. TEST MODE ONLY in v4.1.
///
/// What can be tested where (honest version):
/// - Xcode with Support/HackTheScoot.storekit: real StoreKit 2 purchase / restore /
///   renew / expire flows against a LOCAL config, no Apple account needed.
/// - App Store sandbox / TestFlight: needs an Apple Developer account (an adult),
///   the products created in App Store Connect and a signed build.
/// - The unsigned sideloaded IPA from GitHub: the App Store has no products for it,
///   so the paywall says "store unavailable". Use Developer settings > Test unlock.
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchased: Set<String> = []
    @Published private(set) var loading = false
    @Published private(set) var message: String?
    @Published private(set) var storeChecked = false
    @Published private(set) var introEligible = false
    @Published var testUnlock: Tier = Tier(rawValue: UserDefaults.standard.integer(forKey: StoreManager.testKey)) ?? .free {
        didSet { UserDefaults.standard.set(testUnlock.rawValue, forKey: StoreManager.testKey) }
    }

    static let testKey = "premium.testUnlockTier"
    private var updates: Task<Void, Never>?

    init() {
        updates = Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refreshEntitlements()
            }
        }
    }

    deinit { updates?.cancel() }

    var tier: Tier { return Billing.effectiveTier(purchased: purchased, testUnlock: testUnlock) }
    var boughtTier: Tier { return Billing.effectiveTier(purchased: purchased, testUnlock: .free) }
    var isTestUnlocked: Bool { return testUnlock > .free && testUnlock > boughtTier }

    func allows(_ f: ProFeature) -> Bool { return Billing.allows(f, tier: tier) }

    var monthly: Product? { return products.first { $0.id == Billing.proMonthlyID } }
    var yearly: Product? { return products.first { $0.id == Billing.proYearlyID } }

    private func onMain(_ f: @escaping () -> Void) {
        if Thread.isMainThread { f() } else { DispatchQueue.main.async(execute: f) }
    }

    func load() async {
        onMain { self.loading = true }
        do {
            let list = try await Product.products(for: Billing.productIDs)
            let sorted = list.sorted { $0.price < $1.price }
            var eligible = false
            if let sub = sorted.first?.subscription { eligible = await sub.isEligibleForIntroOffer }
            onMain {
                self.products = sorted
                self.introEligible = eligible
                self.message = sorted.isEmpty ? "The App Store has no HackTheScoot products for this build (sideloaded or not on the App Store yet). Use Test unlock in Developer settings to try Pro." : nil
            }
        } catch {
            onMain { self.message = "Store unavailable: \(error.localizedDescription)" }
        }
        await refreshEntitlements()
        onMain { self.loading = false; self.storeChecked = true }
    }

    func refreshEntitlements() async {
        var ids = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil {
                if let exp = t.expirationDate, exp < Date() { continue }
                ids.insert(t.productID)
            }
        }
        onMain { self.purchased = ids }
    }

    func buy(_ p: Product) async {
        do {
            let result = try await p.purchase()
            switch result {
            case .success(let v):
                if case .verified(let t) = v {
                    await t.finish()
                    onMain { self.message = "Thanks! Pro is on." }
                } else {
                    onMain { self.message = "The purchase could not be verified, so nothing was unlocked." }
                }
            case .userCancelled:
                break
            case .pending:
                onMain { self.message = "Waiting for approval (Ask to Buy or the bank)." }
            @unknown default:
                break
            }
        } catch {
            onMain { self.message = "Purchase failed: \(error.localizedDescription)" }
        }
        await refreshEntitlements()
    }

    func restore() async {
        do {
            try await AppStore.sync()
            onMain { self.message = "Purchases restored." }
        } catch {
            onMain { self.message = "Restore failed: \(error.localizedDescription)" }
        }
        await refreshEntitlements()
    }
}
