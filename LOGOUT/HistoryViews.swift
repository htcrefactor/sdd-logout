import Charts
import MapKit
import SwiftUI
import LOGOUTCore

private enum ActivityPeriod: CaseIterable {
    case week, month, year
    var component: Calendar.Component {
        switch self { case .week: .weekOfYear; case .month: .month; case .year: .year }
    }
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .week: language == .ko ? "주" : "Week"
        case .month: language == .ko ? "월" : "Month"
        case .year: language == .ko ? "년" : "Year"
        }
    }
}

private struct ActivityBar: Identifiable {
    var date: Date
    var meters: Double
    var id: Date { date }
}

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    @State private var period: ActivityPeriod = .week
    @State private var offset = 0

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: model.language == .ko ? "ko_KR" : "en_US")
        calendar.firstWeekday = 2
        return calendar
    }
    private var interval: DateInterval {
        let date = calendar.date(byAdding: period.component, value: offset, to: Date()) ?? Date()
        return calendar.dateInterval(of: period.component, for: date) ?? DateInterval(start: date, duration: 86_400)
    }
    private var runs: [RunRecord] {
        model.history.filter {
            guard let date = $0.startedAt, $0.activeSeconds > 0 else { return false }
            return date >= interval.start && date < interval.end
        }.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }
    private var totalMeters: Double { runs.reduce(0) { $0 + $1.distanceMeters } }
    private var totalSeconds: Double { runs.reduce(0) { $0 + $1.activeSeconds } }
    private var runningDays: Int { Set(runs.compactMap(\.startedAt).map { calendar.startOfDay(for: $0) }).count }
    private var bars: [ActivityBar] {
        let unit: Calendar.Component = period == .year ? .month : .day
        var date = interval.start
        var result: [ActivityBar] = []
        while date < interval.end, result.count < 32 {
            guard let next = calendar.date(byAdding: unit, value: 1, to: date), next > date else { break }
            let meters = runs.filter { ($0.startedAt ?? .distantPast) >= date && ($0.startedAt ?? .distantPast) < next }
                .reduce(0) { $0 + $1.distanceMeters }
            result.append(ActivityBar(date: date, meters: meters))
            date = next
        }
        return result
    }
    private var periodTitle: String {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale
        if period == .year { formatter.dateFormat = "yyyy"; return formatter.string(from: interval.start) }
        if period == .month {
            formatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")
            return formatter.string(from: interval.start)
        }
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return "\(formatter.string(from: interval.start)) – \(formatter.string(from: interval.end.addingTimeInterval(-1)))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(model.t("나의 활동", "Your activity")).font(.largeTitle.weight(.bold)).padding(.top, 12)
                Picker(model.t("기간", "Period"), selection: $period) {
                    ForEach(ActivityPeriod.allCases, id: \.self) { Text($0.title(model.language)).tag($0) }
                }.pickerStyle(.segmented).onChange(of: period) { offset = 0 }
                HStack {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .accessibilityLabel(model.t("이전 기간", "Previous period"))
                    Spacer()
                    Text(periodTitle).font(.headline).monospacedDigit()
                    Spacer()
                    Button { offset += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(offset >= 0).accessibilityLabel(model.t("다음 기간", "Next period"))
                }
                Panel {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(RunFormat.distance(totalMeters)).font(.system(size: 54, weight: .semibold, design: .rounded))
                            .monospacedDigit().foregroundStyle(LogoutPalette.cyan).minimumScaleFactor(0.7).lineLimit(1)
                        Text("km").font(.title3).foregroundStyle(LogoutPalette.secondary)
                        Spacer()
                    }.accessibilityElement(children: .combine)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 22) {
                        MetricTile(label: model.t("달리기", "Runs"), value: "\(runs.count)", color: LogoutPalette.lime)
                        MetricTile(label: model.t("달린 시간", "Running time"), value: RunFormat.duration(totalSeconds), color: LogoutPalette.teal)
                        MetricTile(label: model.t("평균 페이스", "Average pace"), value: RunFormat.pace(totalMeters > 0 ? totalSeconds / totalMeters * 1_000 : nil), unit: "/km", color: LogoutPalette.orange)
                        MetricTile(label: model.t("달린 날", "Running days"), value: "\(runningDays)", color: LogoutPalette.cyan)
                    }
                    if !runs.isEmpty {
                        Chart(bars) { bar in
                            BarMark(x: .value(model.t("날짜", "Date"), bar.date, unit: period == .year ? .month : .day),
                                    y: .value(model.t("거리", "Distance"), bar.meters / 1_000))
                                .foregroundStyle(LogoutPalette.cyan.gradient).cornerRadius(3)
                                .accessibilityLabel(bar.date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue("\(RunFormat.distance(bar.meters)) km")
                        }
                        .chartXScale(domain: interval.start...interval.end)
                        .chartYScale(domain: 0...max(1, (bars.map { $0.meters / 1_000 }.max() ?? 0) * 1.15))
                        .chartYAxis { AxisMarks(position: .leading) }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: period == .year ? .month : .day, count: period == .week ? 1 : (period == .month ? 7 : 2))) {
                                AxisValueLabel(format: period == .year ? .dateTime.month(.narrow) : .dateTime.day())
                            }
                        }.frame(height: 170)
                        Text(model.t("평균 페이스는 총 달린 시간을 총 거리로 나누어 계산해요.", "Average pace uses total running time divided by total distance."))
                            .font(.caption).foregroundStyle(LogoutPalette.secondary)
                    }
                }
                HStack { Text(model.t("달리기 기록", "Run history")).font(.title2.weight(.semibold)); Spacer(); Text("\(runs.count)").foregroundStyle(LogoutPalette.secondary) }
                if runs.isEmpty {
                    Panel {
                        Image(systemName: "figure.run").font(.largeTitle).foregroundStyle(LogoutPalette.cyan)
                        Text(model.t("이 기간에는 기록이 없어요", "No runs in this period")).font(.headline)
                        Text(model.t("달리기를 마치면 거리, 시간과 경로가 여기에 모여요.", "Finished runs appear here with distance, time and route."))
                            .foregroundStyle(LogoutPalette.secondary)
                    }
                } else {
                    ForEach(runs) { run in
                        NavigationLink { RunDetailView(record: run) } label: { ActivityRunRow(record: run) }
                            .buttonStyle(.plain)
                    }
                }
            }.padding(20)
        }.environment(\.locale, Locale(identifier: model.language == .ko ? "ko_KR" : "en_US"))
    }
}

private struct ActivityRunRow: View {
    @EnvironmentObject private var model: AppModel
    let record: RunRecord
    var body: some View {
        Panel {
            HStack(alignment: .top) {
                Image(systemName: record.prescription.kind.symbol)
                    .font(.title3).foregroundStyle(record.prescription.kind.color)
                    .frame(width: 44, height: 44).background(record.prescription.kind.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.prescription.kind.title(model.language)).font(.headline)
                    if let date = record.startedAt {
                        Text(date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(LogoutPalette.secondary)
                    }
                    if record.phase == .interrupted { Text(model.t("중단된 달리기", "Interrupted run")).font(.caption).foregroundStyle(LogoutPalette.orange) }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(LogoutPalette.secondary)
            }
            HStack {
                MetricTile(label: model.t("거리", "Distance"), value: RunFormat.distance(record.distanceMeters), unit: "km")
                MetricTile(label: model.t("시간", "Time"), value: RunFormat.duration(record.activeSeconds), color: LogoutPalette.teal)
                MetricTile(label: model.t("페이스", "Pace"), value: RunFormat.pace(record.averagePaceSecondsPerKilometer), unit: "/km", color: LogoutPalette.orange)
            }
        }
    }
}

struct RunDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let record: RunRecord
    var isNew = false
    @State private var hydrated: RunRecord?
    @State private var loading = true
    @State private var localConfirmed = false
    @State private var confirmDelete = false
    @State private var deleting = false
    private var run: RunRecord { hydrated ?? record }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(run.prescription.kind.title(model.language)).font(.largeTitle.weight(.bold))
                    if let date = run.startedAt {
                        Text(date, format: .dateTime.year().month().day().weekday().hour().minute())
                            .font(.subheadline).foregroundStyle(LogoutPalette.secondary)
                    }
                    if run.phase == .interrupted {
                        Label(model.t("중단된 달리기. 확인된 기록만 표시해요.", "Interrupted run. Only recorded measurements are shown."), systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(LogoutPalette.orange)
                    }
                }
                Panel {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(RunFormat.distance(run.distanceMeters)).font(.system(size: 60, weight: .semibold, design: .rounded))
                            .monospacedDigit().foregroundStyle(LogoutPalette.cyan).lineLimit(1).minimumScaleFactor(0.7)
                        Text("km").font(.title2).foregroundStyle(LogoutPalette.secondary)
                    }.accessibilityElement(children: .combine)
                    HStack {
                        MetricTile(label: model.t("달린 시간", "Running time"), value: RunFormat.duration(run.activeSeconds), color: LogoutPalette.teal)
                        MetricTile(label: model.t("평균 페이스", "Average pace"), value: RunFormat.pace(run.averagePaceSecondsPerKilometer), unit: "/km", color: LogoutPalette.orange)
                    }
                    HStack {
                        Label(run.owner == .watch ? "Apple Watch" : "iPhone", systemImage: run.owner == .watch ? "applewatch" : "iphone")
                        Spacer()
                        Text(run.coach.name(model.language))
                    }.font(.subheadline).foregroundStyle(LogoutPalette.secondary)
                }
                routePanel
                Panel {
                    Text(model.t("마지막 측정값", "Last recorded measurements")).font(.headline)
                    Text(model.t("달리기 전체의 평균이 아닌, 마지막으로 받은 측정값이에요.", "These are the last received samples, not whole-run averages."))
                        .font(.caption).foregroundStyle(LogoutPalette.secondary)
                    measurementRow(model.t("심박수", "Heart rate"), metric: run.heartRate, unit: "BPM", symbol: "heart.fill", color: .red)
                    Divider()
                    measurementRow(model.t("케이던스", "Cadence"), metric: run.cadence, unit: "SPM", symbol: "shoeprints.fill", color: LogoutPalette.lime)
                    Divider()
                    measurementRow(model.t("러닝 파워", "Running power"), metric: run.power, unit: "W", symbol: "bolt.fill", color: LogoutPalette.orange)
                }
                Panel {
                    Text(model.t("저장 상태", "Save status")).font(.headline)
                    HStack {
                        Text(model.t("이 기기의 기록", "History on this device")).foregroundStyle(LogoutPalette.secondary)
                        Spacer()
                        Text(loading ? model.t("확인 중", "Checking") : (localConfirmed ? model.t("저장됨", "Saved") : model.t("확인 필요", "Needs verification")))
                    }.font(.subheadline)
                    SaveStatus(state: run.healthState, label: model.t("건강 앱 운동", "Health workout"))
                    SaveStatus(state: run.routeState, label: model.t("건강 앱 경로", "Health route"))
                    if run.healthState == .uncertain || run.routeState == .uncertain || run.routeState == .pending {
                        Text(model.t("건강 앱 저장 여부가 아직 확인되지 않았어요. 중복 기록을 만들지 않도록 자동으로 다시 저장하지 않아요.", "Health saving is not yet confirmed. It will not be repeated automatically to avoid duplicate records."))
                            .font(.caption).foregroundStyle(LogoutPalette.secondary)
                    }
                }
                if localConfirmed {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label(model.t("이 기기에서 기록 삭제", "Delete history from this device"), systemImage: "trash")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.disabled(deleting)
                }
            }.padding(20)
        }
        .background(model.isNight ? Color.black : Color(white: 0.065))
        .navigationTitle(model.t("달리기 기록", "Run details")).navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, Locale(identifier: model.language == .ko ? "ko_KR" : "en_US"))
        .toolbar {
            if isNew {
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.t("완료", "Done")) { dismiss() }
                }
            }
        }
        .task(id: record.id) {
            loading = true
            if let stored = await model.loadDetail(record.id) { hydrated = stored; localConfirmed = true }
            loading = false
        }
        .alert(model.t("이 기록을 삭제할까요?", "Delete this run?"), isPresented: $confirmDelete) {
            Button(model.t("취소", "Cancel"), role: .cancel) {}
            Button(model.t("삭제", "Delete"), role: .destructive) {
                Task {
                    deleting = true
                    if await model.deleteRun(run.id) { dismiss() }
                    deleting = false
                }
            }
        } message: {
            Text(model.t("이 iPhone에 저장된 기록과 경로가 삭제돼요. Apple 건강 앱 기록은 별도로 관리됩니다.", "The run and route stored on this iPhone will be deleted. Apple Health records are managed separately."))
        }
    }

    private var routePanel: some View {
        Panel {
            HStack { Text(model.t("달린 경로", "Recorded route")).font(.headline); Spacer(); if loading { ProgressView().tint(LogoutPalette.cyan) } }
            if run.route.count > 1 {
                RecordedRouteMap(points: run.route)
                    .frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 16))
                Text(model.t("GPS 측정이 10초 넘게 끊긴 구간은 선으로 연결하지 않아요.", "GPS gaps longer than 10 seconds are not connected."))
                    .font(.caption).foregroundStyle(LogoutPalette.secondary)
            } else if !loading {
                Label(model.t("저장된 경로가 없어요", "No saved route"), systemImage: "map")
                    .foregroundStyle(LogoutPalette.secondary).frame(maxWidth: .infinity, minHeight: 100)
            }
        }
    }

    private func measurementRow(_ title: String, metric: TimedMetric?, unit: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline)
                if let metric {
                    Text(metric.observedAt, format: .dateTime.hour().minute().second()).font(.caption).foregroundStyle(LogoutPalette.secondary)
                } else {
                    Text(model.t("측정값 없음", "Not measured")).font(.caption).foregroundStyle(LogoutPalette.secondary)
                }
            }
            Spacer()
            Text(metric.map { "\($0.value.formatted(.number.precision(.fractionLength(0)))) \(unit)" } ?? "—")
                .font(.headline.monospacedDigit()).foregroundStyle(metric == nil ? LogoutPalette.secondary : color)
        }.accessibilityElement(children: .combine)
    }
}

private struct RouteSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
}

private struct RecordedRouteMap: View {
    let points: [RoutePoint]
    private var segments: [RouteSegment] {
        var output: [RouteSegment] = []
        var current: [CLLocationCoordinate2D] = []
        var previous: RoutePoint?
        func flush() {
            if !current.isEmpty { output.append(RouteSegment(id: output.count, coordinates: current)) }
            current = []
        }
        for point in points {
            guard point.latitude.isFinite, point.longitude.isFinite,
                  (-90...90).contains(point.latitude), (-180...180).contains(point.longitude) else {
                flush(); previous = nil; continue
            }
            if let previous {
                let gap = point.timestamp.timeIntervalSince(previous.timestamp)
                if gap > 10 || gap <= 0 { flush() }
            }
            current.append(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            previous = point
        }
        flush()
        return output
    }
    var body: some View {
        Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
            ForEach(segments) { segment in
                if segment.coordinates.count > 1 {
                    MapPolyline(coordinates: segment.coordinates).stroke(LogoutPalette.cyan, lineWidth: 4)
                } else if let coordinate = segment.coordinates.first {
                    Annotation("", coordinate: coordinate) { Circle().fill(LogoutPalette.cyan).frame(width: 6, height: 6) }
                }
            }
        }.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
    }
}
