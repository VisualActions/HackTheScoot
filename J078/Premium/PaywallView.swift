import SwiftUI
import StoreKit

/// HackTheScoot Pro. Clear prices, clear trial, restore, manage, cancel steps, and
/// a list of what is always free so nobody thinks a basic feature is for sale.
struct PaywallView: View {
    @ObservedObject var store = StoreManager.shared
    @Environment(\.openURL) private var openURL
    var highlight: ProFeature? = nil

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("HackTheScoot Pro").font(.title2.bold())
                        Spacer()
                        if Billing.testMode { Text("TEST MODE").font(.caption2.weight(.heavy)).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.orange.opacity(0.25))).foregroundColor(.orange) }
                    }
                    Text("Extras for people who love their dashboard and their data. Everything that controls or protects your scooter stays free.")
                        .font(.subheadline).foregroundColor(.secondary)
                    HStack {
                        Text("Your plan:").foregroundColor(.secondary)
                        Text(store.tier.name).bold()
                        if store.isTestUnlocked { Text("(test unlock)").foregroundColor(.orange) }
                    }
                    .font(.footnote)
                }
                .padding(.vertical, 4)
            }

            Section("Pro adds") {
                ForEach(ProFeature.allCases.filter { $0.requiredTier == .pro }) { f in featureRow(f) }
            }

            Section(header: Text("Plans"), footer: Text(planFooter)) {
                if store.loading && !store.storeChecked {
                    HStack { ProgressView(); Text("Checking the App Store...").foregroundColor(.secondary) }
                }
                planButton(title: "Pro monthly", price: store.monthly?.displayPrice ?? Billing.proMonthlyPrice, period: "month", product: store.monthly)
                planButton(title: "Pro yearly", price: store.yearly?.displayPrice ?? Billing.proYearlyPrice, period: "year", product: store.yearly,
                           note: "save about \(Billing.yearlySavingPercent)%")
                if let m = store.message { Text(m).font(.footnote).foregroundColor(.secondary) }
                Button("Restore purchases") { Task { await store.restore() } }
                Button("Manage subscription") { if let u = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(u) } }
            }

            if Billing.testMode {
                Section(header: Text("Web checkout (Stripe test)"), footer: Text("Opens the download page's Stripe TEST checkout. Pay with the test card 4242 4242 4242 4242, any future date, any CVC. No real money moves. A web purchase can't unlock this build yet (that needs the server from the billing plan), so use Test unlock to see Pro in the app.")) {
                    Button { if let u = URL(string: Billing.webTestURL) { openURL(u) } } label: { Label("Get Pro on the web (test)", systemImage: "safari") }
                }
            }

            Section("Developer (later)") {
                ForEach(ProFeature.allCases.filter { $0.requiredTier == .developer }) { f in featureRow(f) }
                Text("Not for sale yet. Preview it with Test unlock in Developer settings.").font(.footnote).foregroundColor(.secondary)
            }

            Section("Always free") {
                ForEach(Billing.alwaysFree, id: \.self) { Label($0, systemImage: "checkmark").font(.subheadline) }
            }

            Section("Cancel any time") {
                Text("iPhone: Settings › your name › Subscriptions › HackTheScoot › Cancel. You keep Pro until the period you paid for ends, then it switches off by itself. No surprise charges: the price and renewal are shown before you confirm.")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Pro")
        .task { if !store.storeChecked { await store.load() } }
    }

    private var planFooter: String {
        let base = "Auto-renews until you cancel. The App Store shows the price in your currency before you confirm."
        if store.introEligible { return "Free trial for new subscribers (the length is shown before you confirm). " + base }
        return base
    }

    private func featureRow(_ f: ProFeature) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: f.icon).frame(width: 26).foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).font(.subheadline.weight(.semibold))
                Text(f.detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            if store.allows(f) { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
        }
        .padding(.vertical, 2)
        .listRowBackground(highlight == f ? Color.accentColor.opacity(0.15) : nil)
    }

    private func planButton(title: String, price: String, period: String, product: Product?, note: String? = nil) -> some View {
        Button {
            if let p = product { Task { await store.buy(p) } }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let n = note { Text(n).font(.caption).foregroundColor(.green) }
                }
                Spacer()
                Text("\(price) / \(period)").font(.headline.monospacedDigit())
            }
        }
        .disabled(product == nil || store.boughtTier >= .pro)
    }
}

/// Wraps a Pro screen: shows it when unlocked, otherwise a short explanation + the paywall.
struct ProGate<Content: View>: View {
    let feature: ProFeature
    @ViewBuilder var content: () -> Content
    @ObservedObject var store = StoreManager.shared

    var body: some View {
        if store.allows(feature) {
            content()
        } else {
            ProLockedView(feature: feature)
        }
    }
}

struct ProLockedView: View {
    let feature: ProFeature
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: feature.icon).font(.system(size: 44)).foregroundColor(.accentColor)
            Text(feature.title).font(.title3.bold())
            Text(feature.detail).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            Text(feature.requiredTier == .developer ? "Part of Developer (coming later). Preview it with Test unlock in More › Developer settings." : "Part of HackTheScoot Pro.")
                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
            NavigationLink { PaywallView(highlight: feature) } label: {
                Text("See Pro").font(.headline).frame(maxWidth: 240).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor)).foregroundColor(.white)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(feature.title)
    }
}

/// More › Developer settings: the clearly labelled test unlock.
struct DeveloperSettingsView: View {
    @ObservedObject var store = StoreManager.shared
    var body: some View {
        Form {
            Section(header: Text("Test unlock"), footer: Text("TEST ONLY. Turns on Pro or Developer features on this phone without paying, so you can try them on the unsigned beta. It is not a purchase, it never touches the scooter, and a real App Store build would hide it.")) {
                Picker("Unlock", selection: $store.testUnlock) {
                    Text("Off (Free)").tag(Tier.free)
                    Text("Pro (test)").tag(Tier.pro)
                    Text("Developer (test)").tag(Tier.developer)
                }
                .pickerStyle(.inline)
                HStack { Text("Plan right now"); Spacer(); Text(store.tier.name + (store.isTestUnlocked ? " (test)" : "")).foregroundColor(.secondary) }
            }
            Section(header: Text("Store"), footer: Text("An unsigned sideloaded IPA can't buy from the App Store. Real sandbox purchases need App Store Connect (an adult's Apple Developer account) and a signed build. In Xcode, the bundled HackTheScoot.storekit file tests purchases locally.")) {
                HStack { Text("Products found"); Spacer(); Text("\(store.products.count)").foregroundColor(.secondary) }
                HStack { Text("Bought"); Spacer(); Text(store.purchased.isEmpty ? "nothing" : store.purchased.sorted().joined(separator: ", ")).foregroundColor(.secondary).lineLimit(2) }
                Button("Check the App Store again") { Task { await store.load() } }
            }
        }
        .navigationTitle("Developer settings")
    }
}
