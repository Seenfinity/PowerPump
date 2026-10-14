import SwiftUI

/// L M X J V S D toggles for the days the user practises their sport.
///
/// Shared by onboarding and the Profile so both ask the same question — which
/// days, not just how many. The coach needs the days to keep heavy gym work
/// away from class days and to give those days more carbohydrates.
struct SportWeekdayPicker: View {
    /// Calendar weekdays: 1 = Sunday … 7 = Saturday.
    @Binding var weekdays: [Int]
    @ObservedObject private var language = LanguageManager.shared

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ordered, id: \.self) { wd in
                let on = weekdays.contains(wd)
                Button {
                    HapticManager.selection()
                    if on { weekdays.removeAll { $0 == wd } }
                    else  { weekdays = (weekdays + [wd]).sorted() }
                } label: {
                    Text(verbatim: initial(wd))
                        .font(SBFont.heading(14))
                        .foregroundColor(on ? .white : .sbTextSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(on ? Color.sbCyan : Color.sbSurfaceRaised))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Monday-first or Sunday-first, as the user's calendar has it.
    private var ordered: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private func initial(_ wd: Int) -> String {
        var cal = Calendar.current
        cal.locale = language.locale
        return cal.veryShortWeekdaySymbols[wd - 1]
    }
}
