import SwiftUI
import CoreLocation
import LOGOUTCore

struct WorkoutListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected: WorkoutPrescription?
    private let workouts: [WorkoutPrescription] = [.free, .easy30, .distance5K, .intervals]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(model.t("오늘은 어떻게 달릴까요?", "How will you run today?")).font(.largeTitle.weight(.bold))
                ForEach(workouts) { workout in
                    Button { selected = workout } label: {
                        Panel {
                            HStack {
                                Image(systemName: workout.kind.symbol).font(.title2).foregroundStyle(workout.kind.color)
                                Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(LogoutPalette.cyan)
                            }
                            Text(workout.kind.title(model.language)).font(.title2.weight(.semibold)).foregroundStyle(.white)
                            Text(description(workout)).foregroundStyle(LogoutPalette.secondary)
                        }
                    }.accessibilityIdentifier("workout.\(workout.kind.rawValue)")
                }
            }.padding(20)
        }.sheet(item: $selected) { workout in PreflightView(prescription: workout) }
    }
    private func description(_ workout: WorkoutPrescription) -> String {
        switch workout.kind {
        case .free: model.t("목표 없이, 나의 리듬대로", "Your rhythm, no set target")
        case .easy: model.t("편안한 강도로 30분", "30 minutes at a comfortable effort")
        case .distance: model.t("한 걸음씩, 5 km를 향해", "One step at a time, toward 5 km")
        case .intervals: model.t("준비 5분 + 달리기/회복 1분씩 6회 + 마무리 8분", "5 min warm up + 6 × 1 min run / 1 min recovery + 8 min cool down")
        }
    }
}

struct PreflightView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let prescription: WorkoutPrescription
    @State private var owner: RecordingOwner = .phone
    @State private var distanceKM = 5.0
    @State private var easyMinutes = 30
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(prescription.kind.title(model.language)).font(.largeTitle.weight(.bold))
                    if prescription.kind == .distance {
                        Stepper(value: $distanceKM, in: 1...100, step: 1) { Text("\(Int(distanceKM)) km").font(.title2.monospacedDigit()) }
                    } else if prescription.kind == .easy {
                        Stepper(value: $easyMinutes, in: 5...180, step: 5) { Text("\(easyMinutes) " + model.t("분", "min")).font(.title2.monospacedDigit()) }
                    }
                    Panel {
                        Label(model.t("기록 기기", "Recording device"), systemImage: "iphone").font(.headline)
                        Picker(model.t("기록 기기", "Recording device"), selection: $owner) {
                            Text("iPhone").tag(RecordingOwner.phone)
                            Text("Apple Watch").tag(RecordingOwner.watch)
                        }.pickerStyle(.segmented)
                        Text(owner == .phone
                             ? model.t("iPhone GPS로 거리와 경로를 기록해요. 심박수는 측정하지 않아요.", "iPhone GPS records distance and route. Heart rate is unavailable.")
                             : model.t("Watch가 운동을 기록하고 iPhone에 측정값을 보내요. Watch 앱과 건강 권한이 필요해요.", "Watch records the workout and sends measurements to iPhone. The Watch app and Health access are required."))
                            .font(.subheadline).foregroundStyle(LogoutPalette.secondary)
                        if owner == .watch {
                            Label(model.link.isCompanionInstalled ? model.t("Watch 앱 설치됨", "Watch app installed") : model.t("Watch 앱을 먼저 설치해 주세요", "Install the Watch app first"), systemImage: model.link.isCompanionInstalled ? "checkmark.circle" : "exclamationmark.circle")
                                .foregroundStyle(model.link.isCompanionInstalled ? LogoutPalette.lime : LogoutPalette.orange)
                        }
                    }
                    Panel {
                        Label(model.t("위치", "Location"), systemImage: "location").font(.headline)
                        Text(model.location.isAuthorized
                             ? (model.location.accuracyAuthorization == .fullAccuracy ? model.t("사용 가능. 시작하면 GPS를 찾습니다.", "Available. GPS acquisition begins at start.") : model.t("정확한 위치가 꺼져 있어요. 거리 정확도가 낮아질 수 있어요.", "Precise Location is off. Distance accuracy may be reduced."))
                             : model.t("거리를 기록하려면 위치 접근이 필요해요.", "Location access is required to record distance."))
                            .font(.subheadline).foregroundStyle(LogoutPalette.secondary)
                        if !model.location.isAuthorized {
                            if model.location.authorizationStatus == .denied || model.location.authorizationStatus == .restricted {
                                Button(model.t("iPhone 설정 열기", "Open iPhone Settings")) {
                                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                                }
                            } else {
                                Button(model.t("위치 접근 허용", "Allow location access")) { model.location.requestAuthorization() }.accessibilityIdentifier("allowLocation")
                            }
                        }
                    }
                    Panel {
                        Label(model.t("Apple 건강", "Apple Health"), systemImage: "heart").font(.headline)
                        Text(model.t("선택 사항. 허용하면 완료한 운동을 건강에 저장합니다. 읽기 권한이 없는 측정값은 표시하지 않아요.", "Optional. Allow access to save completed workouts to Health. Measurements without read access are not shown."))
                            .font(.subheadline).foregroundStyle(LogoutPalette.secondary)
                        Button(model.t("건강 권한 확인", "Review Health access")) { Task { await model.requestHealth() } }
                    }
                    HStack(spacing: 12) {
                        Image(model.coach.imageName).resizable().scaledToFit().frame(width: 44, height: 52).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.coach.name(model.language)).font(.headline)
                            Text(model.t("이 달리기에는 AI 음성 코칭이 없어요.", "AI voice coaching is unavailable for this run.")).font(.caption).foregroundStyle(LogoutPalette.secondary)
                        }
                    }
                    Button(model.t("기록 시작", "Start recording")) {
                        var workout = prescription
                        if workout.kind == .distance { workout.goalMeters = distanceKM * 1000 }
                        if workout.kind == .easy { workout.stages[0].durationSeconds = Double(easyMinutes * 60) }
                        dismiss()
                        Task { await model.start(workout, owner: owner) }
                    }.buttonStyle(PrimaryButton())
                        .disabled(!model.ready || !model.location.isAuthorized || model.busy || (owner == .watch && !model.link.isCompanionInstalled))
                        .accessibilityIdentifier("startRecording")
                }.padding(20)
            }.background(model.isNight ? Color.black : Color(white: 0.065))
                .navigationTitle(model.t("출발 준비", "Before you go")).navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(model.isNight ? Color.black : Color(white: 0.065), for: .navigationBar)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(model.t("닫기", "Close")) { dismiss() } } }
        }
    }
}

struct ActiveRunView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmFinish = false
    @State private var moreMetrics = false
    var body: some View {
        if let run = model.activeRun {
            VStack(spacing: 0) {
                HStack {
                    Text("LOGOUT").font(.headline.weight(.black))
                    Spacer()
                    Label(run.owner == .watch ? "Watch" : "iPhone", systemImage: run.owner == .watch ? "applewatch" : "iphone").font(.caption).foregroundStyle(LogoutPalette.secondary)
                }.padding(.horizontal, 24).padding(.top, 16)
                ScrollView {
                    VStack(spacing: 24) {
                        Text(run.prescription.kind.title(model.language)).font(.title3.weight(.semibold)).padding(.top)
                        if run.phase == .preparing {
                            ProgressView().tint(LogoutPalette.cyan).padding(30)
                            Text(model.t("기록 준비 중", "Preparing to record")).font(.title2.weight(.bold))
                            Text(model.t("Watch 연결을 확인하고 있어요. 기록이 시작되면 시간이 표시됩니다.", "Confirming the recording device. Time appears after recording starts.")).multilineTextAlignment(.center).foregroundStyle(LogoutPalette.secondary)
                            Button(model.t("시작 취소", "Cancel start")) { Task { await model.cancelPreparation() } }.disabled(model.busy).frame(minHeight: 44)
                        } else {
                            if run.phase == .paused { Text(model.t("일시 정지", "PAUSED")).font(.headline).foregroundStyle(LogoutPalette.orange) }
                            if run.phase == .ending { ProgressView(model.t("기록 저장 중", "Saving your run")) }
                            VStack(spacing: 4) {
                                Text(RunFormat.distance(run.distanceMeters)).font(.system(size: 82, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(LogoutPalette.cyan)
                                Text(model.t("킬로미터", "kilometers")).font(.subheadline).foregroundStyle(LogoutPalette.secondary)
                            }.accessibilityElement(children: .ignore).accessibilityLabel("\(RunFormat.distance(run.distanceMeters)) " + model.t("킬로미터", "kilometers"))
                            HStack(alignment: .top) {
                                MetricTile(label: model.t("달린 시간", "Running time"), value: RunFormat.duration(model.displaySeconds), color: .white)
                                MetricTile(label: run.owner == .phone ? model.t("현재 페이스", "Current pace") : model.t("평균 페이스", "Average pace"), value: RunFormat.pace(run.owner == .phone ? model.freshCurrentPace : run.averagePaceSecondsPerKilometer), unit: "/km", color: LogoutPalette.lime)
                            }
                            if let stage = run.prescription.stage(at: model.displaySeconds) {
                                Panel {
                                    HStack { Text(stage.stage.label(in: model.language)).font(.headline); Spacer(); Text(RunFormat.duration(stage.remaining)).monospacedDigit().foregroundStyle(LogoutPalette.orange) }
                                    ProgressView(value: 1 - stage.remaining / stage.stage.durationSeconds).tint(LogoutPalette.orange)
                                }
                            } else if let goal = run.prescription.goalMeters {
                                ProgressView(value: min(run.distanceMeters / goal, 1)) {
                                    Text(run.distanceMeters >= goal ? model.t("목표 달성. 준비되면 종료하세요.", "Goal reached. Finish when you are ready.") : model.t("목표", "Goal") + " \(Int(goal / 1000)) km")
                                }.tint(LogoutPalette.cyan)
                            } else if !run.prescription.stages.isEmpty {
                                Text(model.t("운동 구간 완료. 준비되면 종료하세요.", "Workout stages complete. Finish when you are ready.")).foregroundStyle(LogoutPalette.lime)
                            }
                            HStack {
                                MetricTile(label: model.t("심박수", "Heart rate"), value: metric(run.heartRate), unit: "bpm", color: .red)
                                MetricTile(label: model.t("케이던스", "Cadence"), value: metric(run.cadence), unit: "spm", color: LogoutPalette.teal)
                            }
                            if run.owner == .watch && !model.watchValuesFresh {
                                Label(model.t("Watch 업데이트 기다리는 중. 마지막 수치를 표시합니다.", "Waiting for Watch. Showing the last received totals."), systemImage: "antenna.radiowaves.left.and.right.slash").font(.caption).foregroundStyle(LogoutPalette.orange)
                            }
                            if let recovery = model.recoveryMessage { Text(recovery).font(.caption).foregroundStyle(LogoutPalette.orange) }
                            DisclosureGroup(model.t("추가 측정값", "More measurements"), isExpanded: $moreMetrics) {
                                HStack {
                                    MetricTile(label: model.t("러닝 파워", "Running power"), value: metric(run.power), unit: "W", color: LogoutPalette.orange)
                                    MetricTile(label: model.t("평균 페이스", "Average pace"), value: RunFormat.pace(run.averagePaceSecondsPerKilometer), unit: "/km")
                                }.padding(.top)
                            }
                            Text(model.t("측정되지 않거나 오래된 값은 — 로 표시해요.", "Unavailable or stale measurements appear as —.")).font(.caption).foregroundStyle(LogoutPalette.secondary)
                        }
                    }.padding(24)
                }
                if run.phase.isActive {
                    HStack(spacing: 16) {
                        Button { Task { await model.control(run.phase == .paused ? .resume : .pause) } } label: {
                            Label(run.phase == .paused ? model.t("계속", "Resume") : model.t("일시 정지", "Pause"), systemImage: run.phase == .paused ? "play.fill" : "pause.fill")
                        }.buttonStyle(PrimaryButton()).accessibilityIdentifier("pauseResume")
                        Button { confirmFinish = true } label: { Image(systemName: "stop.fill").font(.title2).frame(width: 64, height: 54).background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 16)) }
                            .foregroundStyle(.red).accessibilityLabel(model.t("달리기 종료", "Finish run")).accessibilityIdentifier("finishRun")
                    }.disabled(model.busy || model.pendingControl).padding(24)
                    if model.pendingControl { Text(model.t("Watch 확인 기다리는 중", "Waiting for Watch confirmation")).font(.caption).padding(.bottom) }
                }
                if model.canRetrySave {
                    Button(model.t("기기 저장 다시 시도", "Retry local save")) { Task { await model.retryLocalSave() } }
                        .buttonStyle(PrimaryButton()).padding(24)
                }
            }.background(.black)
                .confirmationDialog(model.t("달리기를 종료할까요?", "Finish this run?"), isPresented: $confirmFinish, titleVisibility: .visible) {
                    Button(model.t("종료하고 저장", "Finish and save"), role: .destructive) { Task { await model.control(.finish) } }.accessibilityIdentifier("confirmFinish")
                    Button(model.t("취소", "Cancel"), role: .cancel) { }
                }
        }
    }
    private func metric(_ value: TimedMetric?) -> String {
        guard let value, value.isFresh(), model.activeRun?.phase == .running else { return "—" }
        return String(Int(value.value.rounded()))
    }
}
