import SwiftUI
import LOGOUTCore

private enum WatchPalette {
    static let cyan = Color(red: 0, green: 0.79, blue: 0.91)
    static let lime = Color(red: 0.73, green: 0.94, blue: 0)
    static let orange = Color(red: 1, green: 0.42, blue: 0.04)
    static let muted = Color(red: 0.65, green: 0.70, blue: 0.73)
}

struct ContentView: View {
    @EnvironmentObject private var model: WatchRunModel
    @State private var page = 0
    @State private var showingControls = false

    var body: some View {
        NavigationStack {
            Group {
                if model.restoring {
                    ProgressView(model.text("기록 확인 중", "Checking your run"))
                } else if let record = model.record {
                    switch record.phase {
                    case .preparing: preparing
                    case .running, .paused: activeRun(record)
                    case .ending: saving
                    case .saved, .interrupted: WatchSummaryView()
                    }
                } else {
                    WatchWaitingView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .containerBackground(.black, for: .navigation)
        }
        .tint(WatchPalette.cyan)
        .sheet(isPresented: $showingControls) { WatchControlsView() }
        .onChange(of: model.record?.id) { _, _ in chooseInitialPage() }
        .onChange(of: model.record?.phase) { _, phase in
            if phase == .saved || phase == .interrupted { showingControls = false }
        }
        .onAppear { chooseInitialPage() }
    }

    private var preparing: some View {
        ScrollView {
            VStack(spacing: 14) {
                ProgressView().tint(WatchPalette.cyan)
                Text(model.text("달리기 준비 중", "Preparing your run"))
                    .font(.headline).multilineTextAlignment(.center)
                Text(model.text("iPhone의 시작 확인을 기다리고 있어요.", "Waiting for your iPhone to confirm the start."))
                    .font(.footnote).foregroundStyle(WatchPalette.muted).multilineTextAlignment(.center)
                if let error = model.errorMessage { WatchNotice(text: error) }
                WatchPermissionButtons()
            }
            .padding(.horizontal, 8)
        }
    }

    private var saving: some View {
        VStack(spacing: 14) {
            ProgressView().tint(WatchPalette.lime)
            Text(model.text("달리기를 저장하고 있어요", "Saving your run"))
                .font(.headline).multilineTextAlignment(.center)
            if let error = model.errorMessage { WatchNotice(text: error) }
        }
        .padding(.horizontal, 8)
    }

    private func activeRun(_ record: RunRecord) -> some View {
        TabView(selection: $page) {
            WatchOverviewView().tag(0)
            if record.prescription.kind != .free { WatchWorkoutView().tag(1) }
            WatchMoreView().tag(2)
        }
        .tabViewStyle(.verticalPage)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { showingControls = true } label: {
                Label(model.text("운동 제어", "Controls"), systemImage: "slider.horizontal.3")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
            .tint(record.phase == .paused ? WatchPalette.orange : WatchPalette.cyan)
            .padding(.horizontal, 4)
            .background(.black)
            .accessibilityHint(model.text("일시 정지, 재개 또는 종료", "Pause, resume, or finish this run"))
        }
    }

    private func chooseInitialPage() { page = model.record?.prescription.kind == .free ? 0 : 1 }
}

private struct WatchWaitingView: View {
    @EnvironmentObject private var model: WatchRunModel
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run").font(.system(size: 24, weight: .medium))
                        .foregroundStyle(WatchPalette.lime).accessibilityHidden(true)
                    Text("LOGOUT").font(.headline.weight(.bold))
                }
                Text(model.text("iPhone에서\n시작하세요", "Start on\nyour iPhone"))
                    .font(.headline).multilineTextAlignment(.center)
                WatchConnectionView()
                if let error = model.errorMessage { WatchNotice(text: error) }
                WatchPermissionButtons()
            }
            .padding(.horizontal, 8)
        }
    }
}

private struct WatchPermissionButtons: View {
    @EnvironmentObject private var model: WatchRunModel
    var body: some View {
        WatchHealthAccessView(recorder: model.recorder)
        WatchLocationAccessView(location: model.location)
    }
}

private struct WatchHealthAccessView: View {
    @EnvironmentObject private var model: WatchRunModel
    @ObservedObject var recorder: WorkoutRecorder
    var body: some View {
        if recorder.authorization != .authorized {
            Button(model.text("건강 접근 설정", "Set up Health access")) {
                Task { await model.authorizeHealth() }
            }
            .disabled(model.busy)
            .buttonStyle(.bordered)
        }
    }
}

private struct WatchLocationAccessView: View {
    @EnvironmentObject private var model: WatchRunModel
    @ObservedObject var location: LocationTracker
    var body: some View {
        if !location.isAuthorized {
            Button(model.text("경로 기록 허용", "Allow route recording")) { location.requestAuthorization() }
                .buttonStyle(.bordered)
            Text(model.text("위치는 달린 경로를 기록하는 데 사용됩니다.", "Location records your running route."))
                .font(.caption2).foregroundStyle(WatchPalette.muted).multilineTextAlignment(.center)
        }
    }
}

private struct WatchConnectionView: View {
    @EnvironmentObject private var model: WatchRunModel
    @ObservedObject private var link = WatchRunModel.shared.link
    var body: some View {
        Label(link.isReachable ? model.text("iPhone 연결됨", "iPhone connected") : model.text("iPhone 연결 대기", "Waiting for iPhone"),
              systemImage: link.isReachable ? "iphone" : "iphone.slash")
        .font(.caption2)
        .foregroundStyle(link.isReachable ? WatchPalette.cyan : WatchPalette.muted)
    }
}

private struct WatchRunStatus: View {
    @EnvironmentObject private var model: WatchRunModel
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: model.record?.phase == .paused ? "pause.fill" : "figure.run")
            Text(model.record?.phase == .paused ? model.text("일시 정지", "Paused") : model.text("달리는 중", "Running"))
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(model.record?.phase == .paused ? WatchPalette.orange : WatchPalette.lime)
        .accessibilityElement(children: .combine)
    }
}

private struct WatchOverviewView: View {
    @EnvironmentObject private var model: WatchRunModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                WatchRunStatus()
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(format: "%.2f", (model.record?.distanceMeters ?? 0) / 1_000))
                        .font(.system(size: 42, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("km").font(.callout)
                }
                .foregroundStyle(WatchPalette.cyan)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(model.text("거리", "Distance"))
                .accessibilityValue(String(format: "%.2f km", (model.record?.distanceMeters ?? 0) / 1_000))
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) { timing; pace }
                    VStack(alignment: .leading, spacing: 8) { timing; pace }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "heart.fill").foregroundStyle(.red).accessibilityHidden(true)
                    Text(freshMetric(model.record?.heartRate)).font(.title3.weight(.semibold)).monospacedDigit()
                    Text("BPM").font(.caption2).foregroundStyle(WatchPalette.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(model.text("심박수", "Heart rate"))
                .accessibilityValue(freshMetric(model.record?.heartRate))
            }
            .padding(.horizontal, 5)
            .padding(.bottom, 4)
        }
    }

    private var timing: some View {
        WatchMetric(label: model.text("운동 시간", "Running time"), value: watchDuration(model.seconds), color: .white)
    }
    private var pace: some View {
        WatchMetric(label: model.text("현재 페이스 /km", "Current pace /km"),
                    value: model.currentPace.flatMap { $0.isFresh() ? watchPace($0.value) : nil } ?? "—", color: WatchPalette.cyan)
    }
}

private struct WatchWorkoutView: View {
    @EnvironmentObject private var model: WatchRunModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                WatchRunStatus()
                if let prescription = model.record?.prescription {
                    if let goal = prescription.goalMeters {
                        let remaining = max(0, goal - (model.record?.distanceMeters ?? 0))
                        Text(remaining > 0 ? model.text("남은 거리", "Distance remaining") : model.text("목표 달성", "Goal reached"))
                            .font(.headline)
                        Text(String(format: "%.2f km", remaining / 1_000))
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .monospacedDigit().foregroundStyle(WatchPalette.lime)
                        ProgressView(value: min(1, (model.record?.distanceMeters ?? 0) / goal)).tint(WatchPalette.lime)
                        if remaining == 0 { keepRunning }
                    } else if let current = prescription.stage(at: model.seconds) {
                        Text(current.stage.label(in: model.language)).font(.headline)
                        Text(watchDuration(current.remaining.rounded(.up)))
                            .font(.system(size: 42, weight: .semibold, design: .rounded))
                            .monospacedDigit().foregroundStyle(WatchPalette.lime)
                        ProgressView(value: min(1, max(0, 1 - current.remaining / current.stage.durationSeconds)))
                            .tint(WatchPalette.lime)
                        if current.index + 1 < prescription.stages.count {
                            Text(model.text("다음: ", "Next: ") + prescription.stages[current.index + 1].label(in: model.language))
                                .font(.caption).foregroundStyle(WatchPalette.muted)
                        }
                    } else {
                        Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(WatchPalette.lime)
                        Text(model.text("목표 달성", "Goal reached")).font(.headline)
                        keepRunning
                    }
                }
            }
            .padding(.horizontal, 5)
        }
    }
    private var keepRunning: some View {
        Text(model.text("종료할 때까지 기록을 이어갑니다.", "Recording continues until you finish."))
            .font(.caption).foregroundStyle(WatchPalette.muted)
    }
}

private struct WatchMoreView: View {
    @EnvironmentObject private var model: WatchRunModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                WatchRunStatus()
                WatchMetric(label: model.text("평균 페이스 /km", "Average pace /km"),
                            value: model.record?.averagePaceSecondsPerKilometer.flatMap(watchPace) ?? "—", color: WatchPalette.cyan)
                WatchMetric(label: model.text("케이던스 /분", "Cadence /min"), value: freshMetric(model.record?.cadence), color: .white)
                WatchMetric(label: model.text("러닝 파워 W", "Running power W"), value: freshMetric(model.record?.power), color: .white)
                Text(model.text("수신되지 않았거나 오래된 측정값은 —로 표시됩니다.", "Missing or stale measurements appear as —."))
                    .font(.caption2).foregroundStyle(WatchPalette.muted)
                WatchConnectionView()
                Label(model.record?.phase == .paused ? model.text("GPS 경로 일시 정지", "GPS route paused") : model.routeAvailable ? model.text("GPS 경로 기록 중", "GPS route recording") : model.text("GPS 경로 대기", "Waiting for GPS route"),
                      systemImage: "location")
                    .font(.caption2).foregroundStyle(WatchPalette.muted)
                if let error = model.errorMessage { WatchNotice(text: error) }
            }
            .padding(.horizontal, 5)
        }
    }
}

private struct WatchControlsView: View {
    @EnvironmentObject private var model: WatchRunModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingFinish = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if model.record?.phase == .ending {
                        ProgressView(model.text("저장 중", "Saving your run"))
                    } else { WatchRunStatus() }
                    Button {
                        Task {
                            await model.perform(model.record?.phase == .paused ? .resume : .pause)
                            dismiss()
                        }
                    } label: {
                        Label(model.record?.phase == .paused ? model.text("다시 달리기", "Resume") : model.text("일시 정지", "Pause"),
                              systemImage: model.record?.phase == .paused ? "play.fill" : "pause.fill")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent).tint(WatchPalette.orange).foregroundStyle(.black)
                    .disabled(model.busy)
                    Button(role: .destructive) { confirmingFinish = true } label: {
                        Label(model.text("달리기 종료", "Finish run"), systemImage: "stop.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered).disabled(model.busy)
                    Button(model.text("측정 화면으로", "Back to metrics")) { dismiss() }.buttonStyle(.plain)
                    if let error = model.errorMessage { WatchNotice(text: error) }
                }
                .padding(.horizontal, 4)
            }
            .background(.black)
            .navigationTitle(model.text("운동 제어", "Controls"))
            .confirmationDialog(model.text("달리기를 마칠까요?", "Finish this run?"), isPresented: $confirmingFinish, titleVisibility: .visible) {
                Button(model.text("종료하고 저장", "Finish & save"), role: .destructive) {
                    Task { await model.perform(.finish); dismiss() }
                }
                Button(model.text("돌아가기", "Go back"), role: .cancel) {}
            } message: {
                Text(String(format: "%.2f km", (model.record?.distanceMeters ?? 0) / 1_000) + "\n" + watchDuration(model.seconds))
            }
        }
    }
}

private struct WatchSummaryView: View {
    @EnvironmentObject private var model: WatchRunModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.record?.phase == .interrupted ? model.text("중단된 달리기", "Interrupted run") : model.text("달리기 완료", "Run complete"))
                    .font(.headline)
                Text(String(format: "%.2f km", (model.record?.distanceMeters ?? 0) / 1_000))
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(WatchPalette.cyan)
                WatchMetric(label: model.text("운동 시간", "Running time"), value: watchDuration(model.seconds), color: .white)
                WatchMetric(label: model.text("평균 페이스 /km", "Average pace /km"),
                            value: model.record?.averagePaceSecondsPerKilometer.flatMap(watchPace) ?? "—", color: .white)
                Divider()
                status(model.localSaved ? model.text("워치에 저장됨", "Saved on Watch") : model.text("워치 저장 확인 필요", "Watch save needs attention"), success: model.localSaved)
                status(healthLabel(model.record?.healthState ?? .notRequested), success: model.record?.healthState == .saved)
                status(routeLabel(model.record?.routeState ?? .notRequested), success: model.record?.routeState == .saved)
                status(model.phoneSynced ? model.text("iPhone 동기화됨", "Synced with iPhone") : model.text("iPhone 동기화 대기 중", "Waiting to sync with iPhone"), success: model.phoneSynced)
                if let error = model.errorMessage { WatchNotice(text: error) }
                if !model.localSaved {
                    Button(model.text("워치 저장 다시 시도", "Retry Watch save")) { Task { await model.retryLocalSave() } }
                        .buttonStyle(.bordered).disabled(model.busy)
                } else if !model.phoneSynced {
                    Button(model.text("동기화 다시 시도", "Retry sync")) { model.retryPhoneSync() }.buttonStyle(.bordered)
                }
                Button(model.text("완료", "Done")) { model.dismissSummary() }
                    .buttonStyle(.borderedProminent).tint(WatchPalette.cyan).foregroundStyle(.black)
                    .disabled(!model.localSaved)
            }
            .padding(.horizontal, 5)
        }
    }

    private func status(_ label: String, success: Bool) -> some View {
        Label(label, systemImage: success ? "checkmark.circle" : "clock")
            .font(.caption).foregroundStyle(success ? WatchPalette.lime : WatchPalette.muted)
    }
    private func healthLabel(_ state: HealthSaveState) -> String {
        switch state {
        case .saved: model.text("건강 앱에 저장됨", "Saved to Health")
        case .pending: model.text("건강 앱 저장 대기 중", "Waiting to save to Health")
        case .failed: model.text("건강 앱 저장 실패", "Health save failed")
        case .uncertain: model.text("건강 앱 저장 확인 필요", "Health save needs checking")
        case .notRequested: model.text("건강 앱에 저장되지 않음", "Not saved to Health")
        }
    }
    private func routeLabel(_ state: HealthSaveState) -> String {
        switch state {
        case .saved: model.text("건강 앱 경로 저장됨", "Health route saved")
        case .pending: model.text("건강 앱 경로 확인 대기", "Waiting for Health route")
        case .failed: model.text("건강 앱 경로 저장 실패", "Health route save failed")
        case .uncertain: model.text("건강 앱 경로 확인 필요", "Health route needs checking")
        case .notRequested: model.text("건강 앱 경로 없음", "No Health route")
        }
    }
}

private struct WatchMetric: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(WatchPalette.muted)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct WatchNotice: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.caption2).foregroundStyle(WatchPalette.orange)
    }
}

private func freshMetric(_ metric: TimedMetric?) -> String {
    guard let metric, metric.isFresh(), metric.value > 0 else { return "—" }
    return String(format: "%.0f", metric.value)
}

private func watchDuration(_ value: Double) -> String {
    let value = Int(max(0, value.isFinite ? value : 0))
    if value >= 3_600 { return String(format: "%d:%02d:%02d", value / 3_600, value / 60 % 60, value % 60) }
    return String(format: "%02d:%02d", value / 60, value % 60)
}

private func watchPace(_ value: Double) -> String? {
    guard value.isFinite, value > 0 else { return nil }
    let rounded = Int(value.rounded())
    return String(format: "%d′%02d″", rounded / 60, rounded % 60)
}
