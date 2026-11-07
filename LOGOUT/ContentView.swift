import SwiftUI
import LOGOUTCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab = 0
    @State private var settings = false
    var body: some View {
        Group {
            if !model.onboarded { OnboardingView() }
            else if model.activeRun != nil { ActiveRunView() }
            else {
                TabView(selection: $tab) {
                    page(0, title: model.t("홈", "Home"), symbol: "safari") { HomeView(tab: $tab) }
                    page(1, title: model.t("달리기", "Run"), symbol: "figure.run") { WorkoutListView() }
                    page(2, title: model.t("플랜", "Plan"), symbol: "calendar") { PlanView() }
                    page(3, title: model.t("활동", "Activity"), symbol: "chart.bar.xaxis") { ActivityView() }
                }.toolbarBackground(.black, for: .tabBar).toolbarBackground(.visible, for: .tabBar)
            }
        }
        .background(model.isNight ? Color.black : Color(white: 0.065))
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(item: $model.summary) { run in NavigationStack { RunDetailView(record: run, isNew: true) } }
        .alert(model.t("상태 확인", "Check status"), isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button(model.t("확인", "OK"), role: .cancel) { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }
    private func page<V: View>(_ index: Int, title: String, symbol: String, @ViewBuilder content: () -> V) -> some View {
        NavigationStack {
            content().background(model.isNight ? Color.black : Color(white: 0.065))
                .navigationTitle("LOGOUT").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { settings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel(model.t("설정", "Settings")).accessibilityIdentifier("settings")
                    }
                }
        }.tabItem { Label(title, systemImage: symbol) }.tag(index)
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var tab: Int
    private var runs: [RunRecord] { model.history.filter { $0.activeSeconds > 0 } }
    private var coachRuns: [RunRecord] { runs.filter { $0.coach == model.coach } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.t("조금 더, 바깥으로", "A little further, outside")).font(.subheadline).foregroundStyle(LogoutPalette.secondary)
                    Text(model.t("오늘의 한 걸음.", "Your next step.")).font(.largeTitle.weight(.bold))
                }.padding(.top, 12)
                Panel {
                    Label(model.t("나의 달리기", "Your run"), systemImage: "figure.run").font(.headline).foregroundStyle(LogoutPalette.teal)
                    Text(model.t("달릴 준비가 되셨나요?", "Ready to head out?")).font(.title2.weight(.semibold))
                    Text(model.t("거리와 시간을 기록하고, 나만의 리듬을 찾아보세요.", "Track your distance and time. Find your own rhythm.")).foregroundStyle(LogoutPalette.secondary)
                    Button { tab = 1 } label: {
                        HStack { Text(model.t("달리기 선택", "Choose a run")); Spacer(); Image(systemName: "arrow.right") }.padding(.horizontal)
                    }.buttonStyle(PrimaryButton()).accessibilityIdentifier("chooseRun")
                }
                Panel {
                    Text(model.t("지금까지의 나", "Your running so far")).font(.headline)
                    HStack(alignment: .top) {
                        MetricTile(label: model.t("거리", "Distance"), value: RunFormat.distance(runs.reduce(0) { $0 + $1.distanceMeters }), unit: "km")
                        MetricTile(label: model.t("달리기", "Runs"), value: "\(runs.count)", color: LogoutPalette.lime)
                        MetricTile(label: model.t("시간", "Time"), value: "\(Int(runs.reduce(0) { $0 + $1.activeSeconds } / 60))", unit: model.t("분", "min"), color: LogoutPalette.teal)
                    }
                }
                Panel {
                    HStack(spacing: 16) {
                        Image(model.coach.imageName).resizable().scaledToFit().frame(width: 76, height: 88).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(model.t("나의 코치", "Your coach")).font(.caption).foregroundStyle(LogoutPalette.secondary)
                            Text(model.coach.name(model.language)).font(.title.weight(.semibold))
                            Text(model.coach.style(model.language)).font(.subheadline)
                        }
                    }
                    Divider()
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                        MetricTile(label: model.t("함께한 달리기", "Runs together"), value: "\(coachRuns.count)", color: LogoutPalette.lime)
                        MetricTile(label: model.t("함께한 시간", "Time together"), value: "\(Int(coachRuns.reduce(0) { $0 + $1.activeSeconds } / 60))", unit: model.t("분", "min"))
                        MetricTile(label: model.t("함께한 거리", "Distance together"), value: RunFormat.distance(coachRuns.reduce(0) { $0 + $1.distanceMeters }), unit: "km", color: LogoutPalette.teal)
                        MetricTile(label: model.t("함께한 날", "Days together"), value: "\(Set(coachRuns.compactMap(\.startedAt).map { Calendar.current.startOfDay(for: $0) }).count)", color: LogoutPalette.orange)
                    }
                    Text(model.t("선택한 코치로 기록한 달리기 기준. AI 코칭은 아직 연결되지 않았어요.", "Runs with this coach selected. AI coaching is not connected yet.")).font(.caption).foregroundStyle(LogoutPalette.secondary)
                }
                Panel {
                    HStack { Text(model.t("한 걸음의 방향.", "A direction to run toward.")).font(.headline); Spacer(); Image(systemName: "flag").foregroundStyle(LogoutPalette.cyan) }
                    HStack(spacing: 0) {
                        Circle().fill(LogoutPalette.lime).frame(width: 9, height: 9)
                        Rectangle().fill(LogoutPalette.border).frame(height: 1)
                        Circle().stroke(LogoutPalette.cyan, lineWidth: 2).frame(width: 9, height: 9)
                        Rectangle().fill(LogoutPalette.border).frame(height: 1)
                        Image(systemName: "flag").foregroundStyle(LogoutPalette.cyan)
                    }.accessibilityHidden(true)
                    Text(model.t("나에게 맞는 다음 목표", "Your next goal")).font(.title2.weight(.semibold))
                    Button { tab = 2 } label: { Label(model.t("나의 목표 보기", "View my goal"), systemImage: "arrow.right") }.frame(minHeight: 44)
                }
            }.padding(20)
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var step = 0
    @State private var adult = false
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("LOGOUT").font(.title3.weight(.black)); Spacer(); Text("\(step + 1) / 3").foregroundStyle(LogoutPalette.secondary) }.padding(24)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if step == 0 {
                        Image(systemName: "figure.run").font(.system(size: 64)).foregroundStyle(LogoutPalette.lime).padding(.top, 36)
                        Text(model.t("나를 위한\n달리기의 시작.", "A run.\nJust for you.")).font(.largeTitle.weight(.bold))
                        Text(model.t("iPhone으로 달리기를 기록하고, Apple Watch가 있다면 더 많은 측정값을 확인하세요.", "Record runs with your iPhone. Add your Apple Watch for more measurements.")).foregroundStyle(LogoutPalette.secondary)
                        Picker(model.t("언어", "Language"), selection: $model.language) {
                            Text("한국어").tag(AppLanguage.ko); Text("English").tag(AppLanguage.en)
                        }.pickerStyle(.segmented).accessibilityIdentifier("onboardingLanguage")
                        Panel {
                            Text(model.t("기록은 내 기기에", "History stays on your devices")).font(.headline)
                            Text(model.t("달리기 기록과 경로는 이 기기에 저장돼요. 앱을 삭제하거나 기기를 잃어버리면 복원할 수 없어요. Apple 건강 기록은 별도로 관리됩니다.", "Your runs and routes stay on this device. They cannot be restored after app deletion or device loss. Apple Health records are managed separately.")).font(.subheadline).foregroundStyle(LogoutPalette.secondary)
                        }
                        Toggle(model.t("저는 만 18세 이상입니다", "I am 18 or older"), isOn: $adult).accessibilityIdentifier("adultConsent")
                    } else if step == 1 {
                        Text(model.t("어떤 목표로 달릴까요?", "What brings you outside?")).font(.largeTitle.weight(.bold))
                        GoalChoices()
                        Text(model.t("목표는 설정에서 언제든 바꿀 수 있어요.", "You can change your goal in Settings.")).foregroundStyle(LogoutPalette.secondary)
                    } else {
                        Text(model.t("나의 러닝 스타일", "Your coaching style")).font(.largeTitle.weight(.bold))
                        Text(model.t("원하는 경험을 선택하세요. 기본 코치는 설정에서 바꿀 수 있어요.", "Choose your experience. Change your default coach in Settings.")).foregroundStyle(LogoutPalette.secondary)
                        CoachChoices()
                    }
                }.padding(24)
            }
            HStack {
                if step > 0 { Button(model.t("이전", "Back")) { step -= 1 }.frame(minWidth: 60, minHeight: 54) }
                Button(step == 2 ? model.t("시작하기", "Get started") : model.t("다음", "Continue")) {
                    if step < 2 { step += 1 } else { model.onboarded = true }
                }.buttonStyle(PrimaryButton()).disabled(step == 0 && !adult).accessibilityIdentifier("onboardingContinue")
            }.padding(24)
        }.background(.black)
    }
}

struct GoalChoices: View {
    @EnvironmentObject private var model: AppModel
    let goals = [("habit", "꾸준한 러닝 습관", "A regular running habit"), ("5k", "나의 첫 5K", "My first 5K"), ("improve", "기록 향상", "Improve my performance")]
    var body: some View {
        VStack(spacing: 12) {
            ForEach(goals, id: \.0) { goal in
                Button { model.goal = goal.0 } label: {
                    HStack { Text(model.t(goal.1, goal.2)); Spacer(); Image(systemName: model.goal == goal.0 ? "checkmark.circle.fill" : "circle") }
                        .padding(20).frame(minHeight: 64).background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16))
                }.foregroundStyle(model.goal == goal.0 ? LogoutPalette.cyan : .white)
                    .accessibilityAddTraits(model.goal == goal.0 ? .isSelected : [])
            }
        }
    }
}

struct CoachChoices: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            ForEach(CoachID.allCases, id: \.self) { coach in
                Button { model.coach = coach } label: {
                    HStack(spacing: 12) {
                        Image(coach.imageName).resizable().scaledToFit().frame(width: 62, height: 70).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(coach.name(model.language)).font(.headline)
                            Text(coach.objective(model.language)).font(.subheadline)
                            Text(coach.style(model.language)).font(.caption).foregroundStyle(LogoutPalette.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if model.coach == coach { Image(systemName: "checkmark.circle.fill").foregroundStyle(LogoutPalette.lime) }
                    }.padding(16).background(Color(white: 0.055), in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(model.coach == coach ? LogoutPalette.cyan : LogoutPalette.border))
                }.foregroundStyle(.white).accessibilityAddTraits(model.coach == coach ? .isSelected : [])
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section(model.t("나의 러닝", "Your running")) {
                    NavigationLink {
                        ScrollView { CoachChoices().padding(20) }.navigationTitle(model.t("기본 코치", "Default coach"))
                    } label: { HStack { Text(model.t("기본 코치", "Default coach")); Spacer(); Text(model.coach.name(model.language)).foregroundStyle(LogoutPalette.cyan) } }
                    NavigationLink(model.t("러닝 목표", "Running goal")) { GoalChoices().padding(20).frame(maxHeight: .infinity, alignment: .top) }
                }
                Section(model.t("앱 설정", "Preferences")) {
                    Picker(model.t("언어", "Language"), selection: $model.language) {
                        Text("한국어").tag(AppLanguage.ko); Text("English").tag(AppLanguage.en)
                    }.accessibilityIdentifier("settingsLanguage")
                    Picker(model.t("화면", "Appearance"), selection: $model.appearance) {
                        Text(model.t("자동 (19시–7시 야간)", "Automatic (night 19:00–07:00)")).tag("auto")
                        Text(model.t("야간 / 트루 블랙", "Night / true black")).tag("dark")
                        Text(model.t("주간 / 그래파이트", "Day / graphite")).tag("light")
                    }
                    LabeledContent(model.t("단위", "Units"), value: model.t("킬로미터", "Kilometers"))
                }
                Section(model.t("연결", "Connections")) {
                    LabeledContent("Apple Watch", value: model.link.isCompanionInstalled ? model.t("앱 설치됨", "App installed") : model.t("앱 미설치", "App not installed"))
                    Button(model.t("건강 권한 확인", "Review Health access")) { Task { await model.requestHealth() } }
                }
                Section(model.t("데이터와 개인정보", "Data and privacy")) {
                    Text(model.t("달리기 기록과 경로는 기기에만 저장돼요. 개별 기록은 활동 상세 화면에서 삭제할 수 있어요. 앱에서 삭제해도 Apple 건강 기록은 유지됩니다.", "Runs and routes stay on your devices. Delete individual runs in Activity details. Deleting from LOGOUT keeps the separate Apple Health record."))
                    Text(model.t("현재 마이크와 AI 서버 연결은 사용하지 않아요.", "Microphone capture and AI services are not enabled in this build."))
                }.font(.subheadline)
            }.scrollContentBackground(.hidden)
                .background(model.isNight ? Color.black : Color(white: 0.065))
                .navigationTitle(model.t("설정", "Settings"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(model.t("완료", "Done")) { dismiss() }.accessibilityIdentifier("settingsDone") } }
        }
    }
}

struct PlanView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(model.t("나의 다음 이야기", "Your next chapter")).font(.largeTitle.weight(.bold))
                Panel { Label(model.t("나의 목표", "Your goal"), systemImage: "flag").foregroundStyle(LogoutPalette.cyan); GoalChoices() }
                Panel {
                    Text(model.t("나의 러닝 기반", "Your running foundation")).font(.title2.weight(.semibold))
                    let recent = model.history.filter { ($0.startedAt ?? .distantPast) >= Date().addingTimeInterval(-28 * 86400) && $0.activeSeconds > 0 }
                    HStack {
                        MetricTile(label: model.t("최근 28일 달리기", "Runs in 28 days"), value: "\(recent.count)", color: LogoutPalette.lime)
                        MetricTile(label: model.t("거리", "Distance"), value: RunFormat.distance(recent.reduce(0) { $0 + $1.distanceMeters }), unit: "km")
                    }
                    Text(model.t("개인 맞춤 플랜은 아직 제공되지 않아요. 기록은 이 기기에 쌓이며, 플랜 기능이 준비되면 나의 목표와 최근 달리기를 바탕으로 사용할 수 있어요.", "Personalized plans are not available yet. Your history stays on this device and will inform plans alongside your goals when the service is ready.")).font(.subheadline).foregroundStyle(LogoutPalette.secondary)
                }
            }.padding(20)
        }
    }
}
