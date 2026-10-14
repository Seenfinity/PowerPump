import SwiftUI
import Charts

struct WeightChartCard: View {
    @ObservedObject private var progress = ProgressStore.shared
    @ObservedObject private var profile  = UserProfile.shared
    @ObservedObject private var foodLog  = FoodLogStore.shared
    @State private var range: Range = .month

    enum Range: String, CaseIterable, Identifiable {
        case month   = "30D"
        case quarter = "90D"
        var id: String { rawValue }
        var days: Int { self == .month ? 30 : 90 }
    }

    private var entries: [WeightEntry] { progress.entries(days: range.days) }

    /// The target line is only worth drawing when it's near enough not to
    /// flatten the weight line into the top or bottom of the chart.
    private var showsTarget: Bool {
        abs(profile.targetWeightKg - (entries.last?.weightKg ?? profile.weightKg)) <= 6
    }

    private var minY: Double {
        var v = entries.map(\.weightKg).min() ?? profile.weightKg
        if showsTarget { v = min(v, profile.targetWeightKg) }
        return floor(v - 1)
    }

    private var maxY: Double {
        var v = entries.map(\.weightKg).max() ?? profile.weightKg
        if showsTarget { v = max(v, profile.targetWeightKg) }
        return ceil(v + 1)
    }

    /// Projected weekly change in kg; positive means losing. nil when there
    /// isn't enough data to say anything honest.
    ///
    /// The measured trend of the weigh-ins comes first. Otherwise the
    /// calorie balance, averaged over the days actually logged — averaging
    /// over all seven counted unlogged days as zero, so one logged day
    /// "projected" a loss of 2 kg a week.
    private var weeklyProjectionKg: Double? {
        let recent = progress.entries(days: 28).sorted { $0.date < $1.date }
        if recent.count >= 3, let first = recent.first, let last = recent.last,
           last.date.timeIntervalSince(first.date) >= 7 * 86_400 {
            // Least-squares slope, kg per day.
            let t0 = first.date
            let xs = recent.map { $0.date.timeIntervalSince(t0) / 86_400 }
            let ys = recent.map(\.weightKg)
            let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
            let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
            let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
            guard den > 0 else { return nil }
            return -(num / den) * 7
        }
        let logged = foodLog.dailyCalories(lastDays: 7).map(\.calories).filter { $0 > 0 }
        guard logged.count >= 3 else { return nil }
        let avgIntake = logged.reduce(0, +) / Double(logged.count)
        let tdee = Double(profile.rawCalorieTarget) - Double(profile.goal.dailyCalorieAdjustment)
        return (tdee - avgIntake) * 7 / 7700.0
    }

    var body: some View {
        SBCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                if entries.isEmpty {
                    emptyState
                } else {
                    chart
                    if let pace = weeklyProjectionKg { projectionRow(pace) }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(String(format: "%.1f", profile.weightKg))
                        .font(SBFont.heading(22))
                        .foregroundColor(.sbTextPrimary)
                        .monospacedDigit()
                    Text("kg")
                        .font(SBFont.body())
                        .foregroundColor(.sbTextSecondary)
                }
                if let delta = progress.weightChange, abs(delta) >= 0.05 {
                    Text(delta >= 0
                         ? String(format: "+%.1f kg", delta)
                         : String(format: "%.1f kg", delta))
                        .font(SBFont.label(11))
                        .foregroundColor(delta == 0 ? .sbTextSecondary
                                        : (delta < 0 ? .sbGreen : .sbRed))
                }
            }
            Spacer()
            rangePicker
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 0) {
            ForEach(Range.allCases) { r in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { range = r }
                } label: {
                    Text(LocalizedStringKey(r.rawValue))
                        .font(SBFont.label(11))
                        .foregroundColor(range == r ? .white : .sbTextSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(range == r ? Color.sbAccent : Color.clear)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.sbSurfaceRaised)
        .cornerRadius(10)
    }

    private var chart: some View {
        Chart {
            // Target weight reference line
            if showsTarget {
            RuleMark(y: .value("Target", profile.targetWeightKg))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .foregroundStyle(Color.sbAccent.opacity(0.5))
                .annotation(position: .top, alignment: .leading) {
                    Text("Target")
                        .font(SBFont.label(9))
                        .foregroundColor(.sbAccent)
                }
            }

            ForEach(entries) { entry in
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Weight", entry.weightKg)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.sbAccent)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                // From the bottom of the visible scale, not from zero: the
                // default baseline drew the fill down over the axis labels.
                AreaMark(
                    x: .value("Date", entry.date),
                    yStart: .value("Base", minY),
                    yEnd: .value("Weight", entry.weightKg)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.sbAccent.opacity(0.35), Color.sbAccent.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .frame(height: 160)
        .chartYScale(domain: minY...maxY)
        .chartPlotStyle { $0.clipped() }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                    .foregroundStyle(Color.sbTextSecondary.opacity(0.18))
                AxisValueLabel {
                    if let v = val.as(Double.self) {
                        Text("\(Int(v))")
                            .font(SBFont.label(10))
                            .foregroundColor(.sbTextSecondary.opacity(0.7))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { val in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated),
                               centered: false)
                    .font(SBFont.label(10))
                    .foregroundStyle(Color.sbTextSecondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "scalemass")
                .font(.system(size: 28))
                .foregroundColor(.sbTextSecondary.opacity(0.5))
            Text("No weight history yet")
                .font(SBFont.body())
                .foregroundColor(.sbTextSecondary)
            Text("Tap Log Weight to start your history.")
                .font(SBFont.label(11))
                .foregroundColor(.sbTextSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func projectionRow(_ pace: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: pace >= 0 ? "arrow.down.right" : "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(pace >= 0 ? .sbGreen : .sbRed)
            Text("At current pace")
                .font(SBFont.label(11))
                .foregroundColor(.sbTextSecondary)
            Spacer()
            Text(projectionLabel(pace))
                .font(SBFont.label(11))
                .fontWeight(.semibold)
                .foregroundColor(.sbTextPrimary)
        }
        .padding(10)
        .background(Color.sbSurfaceRaised)
        .cornerRadius(10)
    }

    private func projectionLabel(_ pace: Double) -> String {
        let kg = abs(pace)
        if kg < 0.05 { return NSLocalizedString("Maintaining weight", comment: "") }
        let sign = pace < 0 ? "+" : "-"
        return String(format: NSLocalizedString("weight.pace %@", comment: ""),
                      sign + String(format: "%.2f", locale: .current, kg))
    }
}
