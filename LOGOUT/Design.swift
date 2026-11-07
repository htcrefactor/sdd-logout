import SwiftUI
import LOGOUTCore

enum LogoutPalette {
    static let cyan = Color(red: 0, green: 0.81, blue: 0.92)
    static let lime = Color(red: 0.72, green: 0.94, blue: 0)
    static let orange = Color(red: 1, green: 0.42, blue: 0.08)
    static let teal = Color(red: 0, green: 0.79, blue: 0.71)
    static let secondary = Color(white: 0.67)
    static let border = Color(white: 0.19)
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 20) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(LogoutPalette.border, lineWidth: 1))
    }
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.black)
            .background(LogoutPalette.orange.opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.35),
                        in: RoundedRectangle(cornerRadius: 16))
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    var unit: String = ""
    var color: Color = LogoutPalette.cyan
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit().foregroundStyle(color).minimumScaleFactor(0.65).lineLimit(1)
            Text(unit.isEmpty ? label : "\(label) (\(unit))")
                .font(.caption).foregroundStyle(LogoutPalette.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label), \(value) \(unit)")
    }
}

enum RunFormat {
    static func duration(_ seconds: Double) -> String {
        guard !seconds.isFinite || seconds < 1_000_000_000 else { return "—" }
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
    static func pace(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0, seconds < 3600 else { return "—" }
        let total = Int(seconds.rounded())
        return String(format: "%d′%02d″", total / 60, total % 60)
    }
    static func distance(_ meters: Double) -> String { String(format: "%.2f", meters / 1000) }
}

extension CoachID {
    var imageName: String { "Coach" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    func name(_ language: AppLanguage) -> String {
        switch self {
        case .mina: language == .ko ? "미나" : "Mina"
        case .jae: language == .ko ? "재" : "Jae"
        case .noa: language == .ko ? "노아" : "Noa"
        case .sol: language == .ko ? "솔" : "Sol"
        }
    }
    func style(_ language: AppLanguage) -> String {
        switch self {
        case .mina: language == .ko ? "차분하게, 부담 없이" : "Calm and unhurried"
        case .jae: language == .ko ? "단호하게, 목표를 향해" : "Focused on your next best"
        case .noa: language == .ko ? "이해하며, 나에게 맞게" : "Understand your training"
        case .sol: language == .ko ? "작은 걸음으로, 꾸준하게" : "Small steps, lasting habits"
        }
    }
    func objective(_ language: AppLanguage) -> String {
        switch self {
        case .mina: language == .ko ? "편안하게 달리고 싶어요" : "Run with less pressure"
        case .jae: language == .ko ? "기록에 도전하고 싶어요" : "Work toward a personal best"
        case .noa: language == .ko ? "훈련을 이해하고 싶어요" : "Learn as I run"
        case .sol: language == .ko ? "꾸준히 달리고 싶어요" : "Build a running habit"
        }
    }
}

extension WorkoutKind {
    var symbol: String {
        switch self { case .free: "wind"; case .easy: "sun.max"; case .distance: "point.topleft.down.to.point.bottomright.curvepath"; case .intervals: "bolt" }
    }
    var color: Color {
        switch self { case .free: LogoutPalette.teal; case .easy: LogoutPalette.lime; case .distance: LogoutPalette.cyan; case .intervals: LogoutPalette.orange }
    }
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .free: language == .ko ? "자유 달리기" : "Free run"
        case .easy: language == .ko ? "이지런" : "Easy run"
        case .distance: language == .ko ? "거리 목표" : "Distance goal"
        case .intervals: language == .ko ? "인터벌" : "Intervals"
        }
    }
}

struct SaveStatus: View {
    @EnvironmentObject private var model: AppModel
    let state: HealthSaveState
    let label: String
    private var status: String {
        switch state {
        case .saved: model.t("저장됨", "Saved")
        case .pending: model.t("확인 중", "Pending")
        case .failed: model.t("저장 실패", "Save failed")
        case .uncertain: model.t("저장 여부 확인 필요", "Save unconfirmed")
        case .notRequested: model.t("저장하지 않음", "Not saved")
        }
    }
    var body: some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(LogoutPalette.secondary)
            Spacer(minLength: 12)
            Text(status).multilineTextAlignment(.trailing)
        }.font(.subheadline)
    }
}
