import SwiftUI

enum PopoverRoute: Hashable {
    case home
    case fan(String)
    case purifier(String)
    case lock(String)
    case settings
    case faq
}

/// Route container for the menu bar popover. Each screen reports its own height, and the panel
/// glides to it. A route change is a cross-fade only, so nothing moves inside the glass.
struct PopoverRoot: View {
    let onReplaceCredentials: () -> Void
    let onAbout: () -> Void
    let onQuit: () -> Void
    let onHeightChange: (CGFloat) -> Void
    @State private var route: PopoverRoute = .home
    @State private var heights: [PopoverRoute: CGFloat] = [:]
    /// The glass surface's height, animated between screens. nil until the first screen is measured.
    @State private var surfaceHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PopoverNavigator.self) private var navigator

    init(onReplaceCredentials: @escaping () -> Void,
         onAbout: @escaping () -> Void,
         onQuit: @escaping () -> Void,
         onHeightChange: @escaping (CGFloat) -> Void) {
        self.onReplaceCredentials = onReplaceCredentials
        self.onAbout = onAbout
        self.onQuit = onQuit
        self.onHeightChange = onHeightChange
    }

    var body: some View {
        GlassPopover(height: surfaceHeight) {
            ZStack(alignment: .top) {
                screen
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [route] in
                        heights[route] = $0
                    }
                    .id(route)
                    .transition(.opacity)
            }
        }
        .onChange(of: navigator.request) { _, request in
            guard let request else { return }
            navigator.request = nil
            guard request.route != route else { return }
            if request.animated {
                show(request.route)
            } else {
                heights[request.route] = nil
                route = request.route
            }
        }
        .onChange(of: heights[route]) { _, height in
            guard let height else { return }
            if surfaceHeight == nil {
                surfaceHeight = height
            } else {
                withAnimation(Motion.pick(Motion.resize, reduceMotion)) { surfaceHeight = height }
            }
            onHeightChange(height)
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch route {
        case .home:
            HomeView(onOpen: show, onReplaceCredentials: onReplaceCredentials, onQuit: onQuit)
        case .fan(let id):
            FanDetail(id: id, onBack: showHome)
        case .purifier(let id):
            PurifierDetail(id: id, onBack: showHome)
        case .lock(let id):
            LockDetail(id: id, onBack: showHome)
        case .settings:
            SettingsDetail(onBack: showHome, onReplaceCredentials: onReplaceCredentials, onAbout: onAbout,
                           onOpenFaq: { show(.faq) })
        case .faq:
            FaqDetail(onBack: { show(.settings) })
        }
    }

    private func show(_ next: PopoverRoute) {
        // A height kept from the last visit would glide the panel to the old size first.
        heights[next] = nil
        withAnimation(Motion.pick(Motion.popover, reduceMotion)) { route = next }
    }

    private func showHome() {
        show(.home)
    }
}

// MARK: - Home

private struct HomeView: View {
    let onOpen: (PopoverRoute) -> Void
    let onReplaceCredentials: () -> Void
    let onQuit: () -> Void
    @Environment(DeviceStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum ListState { case devices, loading, empty, hidden }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 8) {
                if let notice {
                    NoticeCard(notice: notice, perform: perform)
                        .transition(.opacity)
                }
                switch listState {
                case .devices: Card { deviceList }
                case .loading: Card { LoadingRow() }
                case .empty: Card { EmptyRow(onRefresh: refresh) }
                case .hidden: EmptyView()
                }
            }
            .padding(.bottom, 8)
        }
        .animation(Motion.pick(Motion.popover, reduceMotion), value: notice)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("Atomberg Console")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.label)
                .lineLimit(1)
            Spacer(minLength: 8)
            if store.isRefreshing {
                Spinner(size: 12)
                    .padding(.trailing, 8)
                    .transition(.opacity)
            }
            localControlButton
            IconButton(symbol: "slider.horizontal.3", label: "Settings", filled: true) { onOpen(.settings) }
            IconButton(symbol: "power", label: "Quit Atomberg Console", filled: true, action: onQuit)
        }
        .padding(.leading, Metric.side)
        .padding(.trailing, 6)
        .frame(height: Metric.header)
        .animation(Motion.reduced, value: store.isRefreshing)
    }

    /// One tap checks the local network now: a fresh listener, a probe, and a few seconds for a fan's beacon. The
    /// glyph says what was found: off, on and hearing a fan, or on and hearing none. Turning local control off
    /// is in Settings.
    private var localControlButton: some View {
        let on = store.localControlEnabled
        let heard = store.links.values.contains(.local)
        let symbol = !on ? "wifi.slash" : (heard ? "wifi" : "wifi.exclamationmark")
        let state = !on
            ? "Local control is off."
            : (heard ? "Fans are controlled over your network." : "No fan found on this network.")
        let label = store.isCheckingLocal ? "Looking for fans…" : "\(state) Check local network now."
        return IconButton(symbol: symbol, label: label, filled: true,
                          tint: on && heard ? Palette.fanTint : nil, busy: store.isCheckingLocal) {
            Task { await store.checkLocalNow() }
        }
    }

    private var listState: ListState {
        if !store.snapshots.isEmpty { return .devices }
        if store.needsOnboarding { return .hidden }
        if store.isRefreshing || !store.isConfigured { return .loading }
        if store.lastError != nil { return .hidden }
        return .empty
    }

    @ViewBuilder
    private var deviceList: some View {
        if store.snapshots.count > Metric.maxVisibleRows {
            FadingScroll { rows }
                .frame(height: Metric.listViewport)
        } else {
            rows
        }
    }

    private var rows: some View {
        let duplicates = duplicateNames
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(store.snapshots) { device in
                let named = duplicates.contains(device.info.name)
                row(device, suffix: named ? DeviceFacts.modelName(device.info) : nil)
            }
        }
    }

    private var duplicateNames: Set<String> {
        var seen = Set<String>()
        var duplicates = Set<String>()
        for device in store.snapshots where !seen.insert(device.info.name).inserted {
            duplicates.insert(device.info.name)
        }
        return duplicates
    }

    @ViewBuilder
    private func row(_ device: DeviceSnapshot, suffix: String?) -> some View {
        switch device.info.kind {
        case .fan: FanRow(device: device, suffix: suffix) { onOpen(.fan(device.id)) }
        case .waterPurifier: PurifierRow(device: device, suffix: suffix) { onOpen(.purifier(device.id)) }
        case .lock: LockRow(device: device, suffix: suffix) { onOpen(.lock(device.id)) }
        }
    }

    private func refresh() {
        Task { await store.refreshFromUser() }
    }

    private func perform(_ action: NoticeAction) {
        switch action {
        case .tryAgain: refresh()
        case .replaceCredentials, .connect: onReplaceCredentials()
        case .turnOffLocalControl: Task { await store.setLocalControl(false) }
        case .openLocalNetworkSettings:
            guard let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"),
                  let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") else { return }
            openURL(pane) { accepted in
                if !accepted { openURL(fallback) }
            }
        }
    }

    /// One global state above the list, first match wins. Rows stay enabled: fans on the LAN work without the cloud.
    private var notice: Notice? {
        let triangle = "exclamationmark.triangle.fill"
        let stillLocal = store.links.values.contains(.local) ? " Fans on your network still respond." : ""
        if store.needsOnboarding {
            return Notice(symbol: "key", text: "Connect your Atomberg account to see your devices.", action: .connect)
        }
        let issue = store.lastError
        switch issue?.kind {
        case .keychain?:
            return Notice(symbol: triangle, attention: true, text: "Allow Keychain access to use your saved credentials.", action: .tryAgain)
        case .credentials?:
            return Notice(symbol: triangle, attention: true, text: "Atomberg didn’t accept your credentials.", action: .replaceCredentials)
        case .developerMode?:
            return Notice(symbol: triangle, attention: true, text: "Turn on Developer Mode in the Atomberg Home app.", action: .tryAgain)
        case .localNetwork?:
            return Notice(symbol: triangle, attention: true, text: "Allow Local Network access to control fans directly.", action: .openLocalNetworkSettings)
        case .network?:
            return Notice(symbol: "wifi.slash", text: "Can’t reach the Atomberg cloud." + stillLocal, action: .tryAgain)
        case .other?:
            return Notice(symbol: "exclamationmark.circle", text: issue?.message ?? "", action: .tryAgain)
        case .quotaExhausted?, .quotaReserved?, nil:
            break
        }
        switch store.lanProblem {
        case .blocked?:
            return Notice(symbol: triangle, attention: true,
                          text: "Local Network is off for this app.",
                          action: .openLocalNetworkSettings)
        case .silent?:
            let network = store.snapshots.lazy.filter { $0.info.kind == .fan }.compactMap { $0.info.ssid }.first
            let text = network.map { "Fans are on “\($0)”. Join it on this Mac." }
                ?? "No fans heard. Put this Mac on the fans’ Wi‑Fi."
            return Notice(symbol: "wifi.exclamationmark", text: text, action: .turnOffLocalControl)
        case nil:
            break
        }
        if issue?.kind == .quotaExhausted || store.quota?.remaining == 0 {
            let until = store.quota.map { "until \(DeviceFacts.clock($0.resetsAt))" } ?? "today"
            return Notice(symbol: "hourglass", text: "No cloud calls left \(until)." + stillLocal)
        }
        if issue?.kind == .quotaReserved {
            return Notice(symbol: "hourglass", text: "Updates paused to keep \(QuotaPolicy.reserve) cloud calls for your controls.")
        }
        if let quota = store.quota, quota.remaining <= DeviceFacts.lowQuotaRemaining {
            let count = quota.remaining == 1 ? "1 cloud call" : "\(quota.remaining) cloud calls"
            return Notice(symbol: "hourglass", text: "\(count) left today. Resets at \(DeviceFacts.clock(quota.resetsAt)).")
        }
        return nil
    }
}

private struct LoadingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Spinner(size: 12).frame(width: Metric.well)
            Text("Loading devices…")
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metric.side)
        .frame(height: Metric.deviceRow)
    }
}

private struct EmptyRow: View {
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Well {
                Image(systemName: "fan")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.tertiary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("No devices yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.label)
                Text("Add them in Atomberg Home.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Button("Refresh", action: onRefresh)
                .buttonStyle(CapsuleButtonStyle())
        }
        .padding(.horizontal, Metric.side)
        .frame(height: Metric.subtitleRow)
    }
}

// MARK: - Device rows

private struct FanRow: View {
    let device: DeviceSnapshot
    var suffix: String? = nil
    let onOpen: () -> Void
    @Environment(DeviceStore.self) private var store
    @State private var speedDraft: Int?

    private var fan: FanState? { DeviceFacts.fan(device) }
    private var link: LinkState? { store.links[device.id] }
    private var offline: Bool { link == .offline }
    private var phase: CommandPhase { store.phases[device.id] ?? .idle }
    private var controllable: Bool { fan != nil && !offline }
    private var running: Int? { store.runningSpeed(of: device.id) }

    private var badge: StatusGlyph? {
        DeviceFacts.rowGlyph(for: device, link: link)
    }

    /// How this fan is being reached right now, or that it is not. Always shown, in one column, so the symbols
    /// line up down the list.
    private var transport: (glyph: StatusGlyph, help: String)? {
        if offline { return (.offline, DeviceFacts.lastSeenText(device) ?? "Offline") }
        switch link {
        case .local?: return (.local, "Controlled over your local network")
        case .cloud?: return (.cloud, "Controlled through the cloud")
        case .offline?, nil: return nil
        }
    }

    private var bladeColor: Color {
        if offline || fan == nil { return Palette.tertiary }
        return running != nil ? Palette.label : Palette.secondary
    }

    private var accessibilityValue: String {
        if offline { return DeviceFacts.offlineSpoken(device) }
        guard let fan else { return "No status" }
        let state = running.map { "On, speed \($0) of 6" } ?? (fan.power ? "On" : "Off")
        switch link {
        case .local?: return "\(state), local network"
        case .cloud?: return "\(state), cloud"
        case .offline?, nil: return state
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DeviceRow(title: device.info.name, suffix: suffix, badge: badge,
                      badgeHelp: DeviceFacts.attentionText(device) ?? "",
                      transport: transport?.glyph, transportHelp: transport?.help ?? "",
                      chevron: offline || fan == nil,
                      dimmed: offline, accessibilityValue: accessibilityValue, onOpen: onOpen) {
                FanBlade(speed: running ?? 0, running: running != nil, size: 12, color: bladeColor)
            } value: {
                if fan == nil, !offline {
                    if store.isRefreshing { Spinner(size: 12) } else { RowValue("No status") }
                }
            } control: {
                if controllable {
                    Toggle("\(device.info.name) power", isOn: Binding(get: { fan?.power ?? false }, set: { send(.power($0)) }))
                        .toggleStyle(DeviceSwitchStyle(tint: Palette.fanTint, phase: phase))
                        .labelsHidden()
                }
            }
            // A running fan carries its own speed control: the same six-step detent as the detail screen, at row
            // scale, under the name. Setting a speed needs no trip into the detail.
            if let running, controllable {
                SpeedDetent(
                    speed: DeviceFacts.speedBinding(draft: $speedDraft, committed: running),
                    width: Metric.content - 32,
                    compact: true,
                    enabled: true
                ) { value in
                    if value != fan?.speed { send(.speed(value)) }
                    speedDraft = nil
                }
                .modifier(PendingPulse(active: DeviceFacts.inFlight(phase)))
                .padding(.leading, Metric.side + Metric.well + 8)
                .padding(.trailing, Metric.side)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
            if let message = DeviceFacts.failureMessage(phase) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 48)
                    .padding(.trailing, Metric.side)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .animation(Motion.reveal, value: DeviceFacts.failureMessage(phase))
        .animation(Motion.reveal, value: running != nil)
    }

    private func send(_ command: FanCommand) {
        Task { await store.send(.fan(command), to: device.id) }
    }
}

private struct PurifierRow: View {
    let device: DeviceSnapshot
    var suffix: String? = nil
    let onOpen: () -> Void
    @Environment(DeviceStore.self) private var store

    private var reading: PurifierState? { DeviceFacts.purifier(device) }
    private var link: LinkState? { store.links[device.id] }
    private var offline: Bool { link == .offline }

    private var accessibilityValue: String {
        if offline { return DeviceFacts.offlineSpoken(device) }
        var parts: [String] = []
        if DeviceFacts.needsAttention(device, link: link), let text = DeviceFacts.attentionText(device) {
            parts.append("Needs attention, \(text)")
        }
        if let tds = reading?.storedTDS { parts.append("Stored water \(DeviceFacts.whole(tds)) ppm") }
        if reading == nil { parts.append("No status") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        DeviceRow(title: device.info.name, suffix: suffix,
                  badge: DeviceFacts.rowGlyph(for: device, link: link),
                  badgeHelp: DeviceFacts.attentionText(device) ?? "",
                  transport: offline ? .offline : nil,
                  transportHelp: DeviceFacts.lastSeenText(device) ?? "Offline",
                  chevron: true,
                  dimmed: offline, accessibilityValue: accessibilityValue, onOpen: onOpen) {
            Image(systemName: "drop.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(offline ? Palette.tertiary : Palette.secondary)
        } value: {
            if !offline, let tds = reading?.storedTDS {
                RowValue("\(DeviceFacts.whole(tds)) ppm")
            }
        } control: {
            EmptyView()
        }
    }
}

private struct LockRow: View {
    let device: DeviceSnapshot
    var suffix: String? = nil
    let onOpen: () -> Void
    @Environment(DeviceStore.self) private var store

    private var link: LinkState? { store.links[device.id] }
    private var offline: Bool { link == .offline }
    private var battery: Int? { DeviceFacts.lock(device)?.batteryPercent }

    private var accessibilityValue: String {
        if offline { return DeviceFacts.offlineSpoken(device) }
        guard let battery else { return "Battery unknown" }
        let low = battery <= DeviceFacts.lowBatteryPercent
        return "Battery \(battery) percent" + (low ? ", needs attention" : "")
    }

    var body: some View {
        DeviceRow(title: device.info.name, suffix: suffix,
                  badge: DeviceFacts.rowGlyph(for: device, link: link),
                  badgeHelp: DeviceFacts.attentionText(device) ?? "",
                  transport: offline ? .offline : nil,
                  transportHelp: DeviceFacts.lastSeenText(device) ?? "Offline",
                  chevron: true,
                  dimmed: offline, accessibilityValue: accessibilityValue, onOpen: onOpen) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(offline ? Palette.tertiary : Palette.secondary)
        } value: {
            if !offline, let battery {
                Text("\(Image(systemName: DeviceFacts.batterySymbol(battery))) \(battery)%")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondary)
            }
        } control: {
            EmptyView()
        }
    }
}
