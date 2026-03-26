import AppKit
import Combine
import ServiceManagement
import SwiftUI

private enum AppIconStyle {
    static func hourglass(pointSize: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        return NSImage(systemSymbolName: "hourglass", accessibilityDescription: "hourglass")?
            .withSymbolConfiguration(config)
    }
}

private struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
    }
}

private struct MenuGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}

struct CountdownItem: Identifiable {
    let id: UUID
    let originalMinutes: Int
    let startDate: Date
    let endDate: Date

    init(id: UUID = UUID(), originalMinutes: Int, startDate: Date, endDate: Date) {
        self.id = id
        self.originalMinutes = originalMinutes
        self.startDate = startDate
        self.endDate = endDate
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh"

    var id: String { rawValue }
}

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconOnly = "icon_only"
    case iconWithCount = "icon_with_count"
    case iconWithCountAndMMSS = "icon_with_count_mmss"
    case iconWithMMSS = "icon_with_mmss"
    case iconWithSeconds = "icon_with_seconds"

    var id: String { rawValue }
}

@MainActor
final class CountdownStore: ObservableObject {
    private static let presetMinutesKey = "preset_minutes"
    private static let languageKey = "app_language"
    private static let menuBarDisplayModeKey = "menu_bar_display_mode"
    private static let defaultPresetMinutes = [1, 3, 5, 10, 20, 60]

    @Published var customMinutesInput = ""
    @Published private(set) var currentTime = Date()
    @Published private(set) var activeCountdowns: [CountdownItem] = []
    @Published private(set) var presetMinutes: [Int] = defaultPresetMinutes
    @Published var language: AppLanguage = .english
    @Published var menuBarDisplayMode: MenuBarDisplayMode = .iconWithCountAndMMSS
    @Published var launchAtLoginEnabled = false

    var activeCount: Int { activeCountdowns.count }

    private var timerCancellable: AnyCancellable?
    private var completionQueue: [CountdownItem] = []
    private var isPresentingAlert = false

    init() {
        if let saved = UserDefaults.standard.array(forKey: Self.presetMinutesKey) as? [Int], !saved.isEmpty {
            presetMinutes = saved
        }
        if let savedLanguage = UserDefaults.standard.string(forKey: Self.languageKey),
           let parsedLanguage = AppLanguage(rawValue: savedLanguage) {
            language = parsedLanguage
        }
        if let savedMenuBarMode = UserDefaults.standard.string(forKey: Self.menuBarDisplayModeKey),
           let parsedMenuBarMode = MenuBarDisplayMode(rawValue: savedMenuBarMode) {
            menuBarDisplayMode = parsedMenuBarMode
        }
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    func localized(_ english: String, _ chinese: String) -> String {
        language == .english ? english : chinese
    }

    func setLanguage(_ value: AppLanguage) {
        language = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.languageKey)
    }

    func setMenuBarDisplayMode(_ value: MenuBarDisplayMode) {
        menuBarDisplayMode = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.menuBarDisplayModeKey)
    }

    func menuBarDisplayModeLabel(_ mode: MenuBarDisplayMode) -> String {
        switch mode {
        case .iconOnly:
            return localized("Icon only", "单独图标")
        case .iconWithCount:
            return localized("Icon + Count", "图标+数量")
        case .iconWithCountAndMMSS:
            return localized("Icon + Count + mm:ss", "图标+数量+分秒")
        case .iconWithMMSS:
            return localized("Icon + mm:ss", "图标+分秒")
        case .iconWithSeconds:
            return localized("Icon + Seconds", "图标+秒数")
        }
    }

    func addCountdown(minutes: Int) {
        guard minutes > 0 else { return }
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(TimeInterval(minutes * 60))
        activeCountdowns.append(CountdownItem(originalMinutes: minutes, startDate: startDate, endDate: endDate))
    }

    func startCustomCountdown() {
        let trimmed = customMinutesInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = Int(trimmed), minutes > 0 else { return }
        addCountdown(minutes: minutes)
        customMinutesInput = ""
    }

    func stopCountdown(id: UUID) {
        activeCountdowns.removeAll { $0.id == id }
    }

    func countFor(minutes: Int) -> Int {
        activeCountdowns.reduce(into: 0) { result, item in
            if item.originalMinutes == minutes {
                result += 1
            }
        }
    }

    func remainingText(for item: CountdownItem, now: Date = Date()) -> String {
        let seconds = max(0, Int(item.endDate.timeIntervalSince(now)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    func hoverDetailsText(for item: CountdownItem, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .english ? "en_US" : "zh_CN")
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        let remainingSeconds = max(0, Int(item.endDate.timeIntervalSince(now)))
        if language == .english {
            return "Start: \(formatter.string(from: item.startDate))\nEnd: \(formatter.string(from: item.endDate))\nRemaining: \(remainingSeconds)s"
        }
        return "开始：\(formatter.string(from: item.startDate))\n结束：\(formatter.string(from: item.endDate))\n剩余：\(remainingSeconds) 秒"
    }

    var nearestRemainingMMSS: String? {
        guard let nearestItem = activeCountdowns.min(by: { $0.endDate < $1.endDate }) else {
            return nil
        }
        let totalSeconds = max(0, Int(nearestItem.endDate.timeIntervalSince(currentTime)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var nearestRemainingSeconds: Int? {
        guard let nearestItem = activeCountdowns.min(by: { $0.endDate < $1.endDate }) else {
            return nil
        }
        return max(0, Int(nearestItem.endDate.timeIntervalSince(currentTime)))
    }

    var hasActiveTimers: Bool { activeCount > 0 }

    var menuBarMMSS: String {
        nearestRemainingMMSS ?? "00:00"
    }

    var menuBarCountAndMMSS: String {
        "\(activeCount)-\(menuBarMMSS)"
    }

    var menuBarSeconds: String {
        if let nearestRemainingSeconds {
            return "\(nearestRemainingSeconds)"
        }
        return "0"
    }

    var menuBarDisplayText: String {
        switch menuBarDisplayMode {
        case .iconOnly:
            return ""
        case .iconWithCount:
            return "\(activeCount)"
        case .iconWithCountAndMMSS:
            return hasActiveTimers ? menuBarCountAndMMSS : "0-00:00"
        case .iconWithMMSS:
            return menuBarMMSS
        case .iconWithSeconds:
            return menuBarSeconds
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = enabled
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = localized("Failed to set launch at login", "开机自启设置失败")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: localized("OK", "我知道了"))
            alert.runModal()
        }
    }

    func updatePresetMinutes(from rawText: String) {
        let separators = CharacterSet(charactersIn: ",， \n\t")
        let tokens = rawText
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let parsed = tokens.compactMap(Int.init).filter { $0 > 0 }
        var unique: [Int] = []
        for minute in parsed where !unique.contains(minute) {
            unique.append(minute)
        }

        guard !unique.isEmpty else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = localized("Invalid preset values", "预设分钟无效")
            alert.informativeText = localized(
                "Enter positive integers separated by commas, e.g. 1,3,5,10",
                "请输入正整数，并用逗号分隔，例如：1,3,5,10"
            )
            alert.addButton(withTitle: localized("OK", "我知道了"))
            alert.runModal()
            return
        }

        presetMinutes = unique
        UserDefaults.standard.set(unique, forKey: Self.presetMinutesKey)
    }

    private func tick() {
        let now = Date()
        currentTime = now
        let finished = activeCountdowns.filter { $0.endDate <= now }
        guard !finished.isEmpty else { return }

        activeCountdowns.removeAll { $0.endDate <= now }
        completionQueue.append(contentsOf: finished)
        processCompletionQueueIfNeeded()
    }

    private func processCompletionQueueIfNeeded() {
        guard !isPresentingAlert else { return }
        guard !completionQueue.isEmpty else { return }

        let item = completionQueue.removeFirst()
        presentCompletionAlert(for: item)
    }

    private func presentCompletionAlert(for item: CountdownItem) {
        isPresentingAlert = true
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = localized("Timer Finished", "倒计时结束")
        alert.informativeText = localized(
            "\(item.originalMinutes)-minute timer is complete.",
            "\(item.originalMinutes) 分钟倒计时已完成。"
        )
        alert.icon = AppIconStyle.hourglass(pointSize: 48)
        alert.addButton(withTitle: localized("Restart \(item.originalMinutes) min", "重新计时 \(item.originalMinutes) 分钟"))
        alert.addButton(withTitle: localized("Got it", "我知道了"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            addCountdown(minutes: item.originalMinutes)
        }

        isPresentingAlert = false
        processCompletionQueueIfNeeded()
    }
}

struct CountdownMenuBarView: View {
    @ObservedObject var store: CountdownStore

    @State private var hoveredQuickMinute: Int?
    @State private var hoveredCountdownID: UUID?
    @State private var showSettings = false
    @State private var presetMinutesInput = ""

    private func confirmAndQuit() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = store.localized("Confirm Quit?", "确认退出？")
        alert.informativeText = store.localized(
            "All active timers will stop after quitting.",
            "退出后将停止所有进行中的倒计时。"
        )
        alert.addButton(withTitle: store.localized("Quit", "退出"))
        alert.addButton(withTitle: store.localized("Cancel", "取消"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.localized("Settings", "设置"))
                .font(.headline)

            Text(store.localized("Language", "语言"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { store.language },
                set: { store.setLanguage($0) }
            )) {
                Text("English").tag(AppLanguage.english)
                Text("中文").tag(AppLanguage.chinese)
            }
            .pickerStyle(.segmented)

            Text(store.localized("Menu Bar Display", "菜单栏展示"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { store.menuBarDisplayMode },
                set: { store.setMenuBarDisplayMode($0) }
            )) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Text(store.menuBarDisplayModeLabel(mode)).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Text(store.localized("Preset Minutes (comma-separated)", "预设分钟（逗号分隔）"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(store.localized("e.g. 1,3,5,10", "例如 1,3,5,10"), text: $presetMinutesInput)
                    .textFieldStyle(.roundedBorder)
                Button(store.localized("Save", "保存")) {
                    store.updatePresetMinutes(from: presetMinutesInput)
                    presetMinutesInput = store.presetMinutes.map(String.init).joined(separator: ",")
                }
                .buttonStyle(.bordered)
            }

            Divider()

            Toggle(store.localized("Launch at Login", "开机自启"), isOn: Binding(
                get: { store.launchAtLoginEnabled },
                set: { store.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)

            HStack {
                Spacer()
                Button(store.localized("Quit", "退出")) {
                    showSettings = false
                    confirmAndQuit()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(store.localized("Set Timer", "设置倒计时"))
                        .font(.headline)
                    Spacer()
                    Button {
                        presetMinutesInput = store.presetMinutes.map(String.init).joined(separator: ",")
                        showSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                    .help(store.localized("Settings", "设置"))
                    .popover(isPresented: $showSettings, arrowEdge: .top) {
                        settingsPanel
                    }
                }

                ForEach(store.presetMinutes, id: \.self) { minute in
                    let count = store.countFor(minutes: minute)
                    Button {
                        store.addCountdown(minutes: minute)
                    } label: {
                        HStack {
                            Text(store.localized("\(minute) min", "\(minute) 分钟"))
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }
                        }
                        .foregroundStyle(count > 0 ? Color.white : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Group {
                                if count > 0 {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color(red: 0.22, green: 0.54, blue: 0.96), Color(red: 0.16, green: 0.46, blue: 0.90)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                }
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white.opacity(hoveredQuickMinute == minute ? (count > 0 ? 0.16 : 0.28) : 0.0))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(hoveredQuickMinute == minute ? 0.7 : 0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovering in
                        hoveredQuickMinute = isHovering ? minute : nil
                    }
                }

                HStack(spacing: 8) {
                    TextField(store.localized("Enter n minutes", "输入 n 分钟"), text: $store.customMinutesInput)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .glassCard()
                        .submitLabel(.done)
                        .onSubmit {
                            store.startCustomCountdown()
                        }

                    Button(store.localized("Start", "开始")) {
                        store.startCustomCountdown()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .frame(maxWidth: .infinity)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(store.localized("Active Timers", "进行中的倒计时"))
                    .font(.headline)

                if store.activeCountdowns.isEmpty {
                    Text(store.localized("No active timers", "暂无进行中的倒计时"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.activeCountdowns.sorted(by: { $0.endDate < $1.endDate })) { item in
                        HStack {
                            Text(store.localized("\(item.originalMinutes) min", "\(item.originalMinutes) 分钟"))
                                .frame(width: 90, alignment: .leading)

                            Spacer()

                            Text(store.remainingText(for: item, now: store.currentTime))
                                .monospacedDigit()
                                .font(.system(.body, design: .monospaced))

                            Button {
                                store.stopCountdown(id: item.id)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.plain)
                            .help(store.localized("Stop this timer", "关闭这个计时"))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(hoveredCountdownID == item.id ? 0.32 : 0.0))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(hoveredCountdownID == item.id ? 0.45 : 0.0), lineWidth: 1)
                        )
                        .onHover { isHovering in
                            hoveredCountdownID = isHovering ? item.id : nil
                        }
                        .overlay(alignment: .topTrailing) {
                            if hoveredCountdownID == item.id {
                                Text(store.hoverDetailsText(for: item, now: store.currentTime))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(8)
                                    .frame(width: 180, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.black.opacity(0.72))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.55), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
                                    .offset(x: -8, y: -70)
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            }
                        }
                        .zIndex(hoveredCountdownID == item.id ? 20 : 0)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 310)
        .background(MenuGlassBackground().opacity(0.78))
    }
}

@main
struct MacOSTimerApp: App {
    @StateObject private var store = CountdownStore()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        if let appIcon = AppIconStyle.hourglass(pointSize: 256) {
            NSApplication.shared.applicationIconImage = appIcon
        }
    }

    var body: some Scene {
        MenuBarExtra {
            CountdownMenuBarView(store: store)
        } label: {
            Label {
                Text(store.menuBarDisplayText)
                    .monospacedDigit()
            } icon: {
                Image(systemName: "hourglass")
            }
            .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
