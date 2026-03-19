import AppKit
import Combine
import SwiftUI

struct CountdownItem: Identifiable {
    let id: UUID
    let originalMinutes: Int
    let endDate: Date

    init(id: UUID = UUID(), originalMinutes: Int, endDate: Date) {
        self.id = id
        self.originalMinutes = originalMinutes
        self.endDate = endDate
    }
}

@MainActor
final class CountdownStore: ObservableObject {
    @Published var customMinutesInput = ""
    @Published private(set) var currentTime = Date()
    @Published private(set) var activeCountdowns: [CountdownItem] = []

    var activeCount: Int { activeCountdowns.count }

    private var timerCancellable: AnyCancellable?
    private var completionQueue: [CountdownItem] = []
    private var isPresentingAlert = false

    init() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    func addCountdown(minutes: Int) {
        guard minutes > 0 else { return }
        let endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        activeCountdowns.append(CountdownItem(originalMinutes: minutes, endDate: endDate))
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
        alert.messageText = "倒计时结束"
        alert.informativeText = "\(item.originalMinutes) 分钟倒计时已完成。"
        alert.addButton(withTitle: "重新计时 \(item.originalMinutes) 分钟")
        alert.addButton(withTitle: "我知道了")

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

    private let quickMinutes = [1, 3, 5, 10, 20, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("设置倒计时")
                    .font(.headline)

                HStack(spacing: 8) {
                    ForEach(quickMinutes, id: \.self) { minute in
                        Button("\(minute)分") {
                            store.addCountdown(minutes: minute)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                HStack(spacing: 8) {
                    TextField("输入 n 分钟", text: $store.customMinutesInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)

                    Button("开始") {
                        store.startCustomCountdown()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("进行中的倒计时")
                    .font(.headline)

                if store.activeCountdowns.isEmpty {
                    Text("暂无进行中的倒计时")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.activeCountdowns.sorted(by: { $0.endDate < $1.endDate })) { item in
                        HStack {
                            Text("\(item.originalMinutes) 分钟")
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
                            .help("关闭这个计时")
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 360)
    }
}

@main
struct MacOSReminderApp: App {
    @StateObject private var store = CountdownStore()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            CountdownMenuBarView(store: store)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                if store.activeCount > 0 {
                    Text("\(store.activeCount)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
