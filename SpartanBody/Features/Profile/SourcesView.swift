import SwiftUI

/// Where the numbers come from: every health or nutrition recommendation in
/// the app, with the published source behind it (App Store guideline 1.4.1).
struct SourcesView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Source: Identifiable {
        let id = UUID()
        let usedFor: String      // localized key: what PowerPump uses it for
        let citation: String     // the reference itself, as published
        let url: String
    }

    private struct Topic: Identifiable {
        let id = UUID()
        let icon: String
        let title: String        // localized key
        let sources: [Source]
    }

    private let topics: [Topic] = [
        Topic(icon: "flame.fill", title: "sources.topic.energy", sources: [
            Source(usedFor: "sources.use.bmr",
                   citation: "Mifflin MD, St Jeor ST, et al. A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr. 1990.",
                   url: "https://pubmed.ncbi.nlm.nih.gov/2305711/"),
            Source(usedFor: "sources.use.activity",
                   citation: "FAO/WHO/UNU. Human energy requirements. Report of a joint expert consultation. 2004.",
                   url: "https://www.fao.org/4/y5686e/y5686e00.htm"),
            Source(usedFor: "sources.use.weightRate",
                   citation: "NIDDK, National Institutes of Health. Treatment for overweight & obesity.",
                   url: "https://www.niddk.nih.gov/health-information/weight-management/adult-overweight-obesity/treatment"),
        ]),
        Topic(icon: "fork.knife", title: "sources.topic.nutrition", sources: [
            Source(usedFor: "sources.use.protein",
                   citation: "Jäger R, et al. International Society of Sports Nutrition Position Stand: protein and exercise. J Int Soc Sports Nutr. 2017.",
                   url: "https://pubmed.ncbi.nlm.nih.gov/28642676/"),
            Source(usedFor: "sources.use.foods",
                   citation: "U.S. Department of Agriculture. FoodData Central.",
                   url: "https://fdc.nal.usda.gov/"),
            Source(usedFor: "sources.use.diet",
                   citation: "World Health Organization. Healthy diet. Fact sheet.",
                   url: "https://www.who.int/news-room/fact-sheets/detail/healthy-diet"),
            Source(usedFor: "sources.use.water",
                   citation: "EFSA Panel on Dietetic Products, Nutrition and Allergies. Scientific Opinion on Dietary Reference Values for water. EFSA Journal. 2010.",
                   url: "https://doi.org/10.2903/j.efsa.2010.1459"),
            Source(usedFor: "sources.use.creatine",
                   citation: "Kreider RB, et al. International Society of Sports Nutrition position stand: safety and efficacy of creatine supplementation in exercise, sport, and medicine. J Int Soc Sports Nutr. 2017.",
                   url: "https://pubmed.ncbi.nlm.nih.gov/28615996/"),
        ]),
        Topic(icon: "figure.strengthtraining.traditional", title: "sources.topic.training", sources: [
            Source(usedFor: "sources.use.activityGuidelines",
                   citation: "World Health Organization. WHO guidelines on physical activity and sedentary behaviour. 2020.",
                   url: "https://www.who.int/publications/i/item/9789240015128"),
            Source(usedFor: "sources.use.volume",
                   citation: "Schoenfeld BJ, Ogborn D, Krieger JW. Dose-response relationship between weekly resistance training volume and increases in muscle mass. J Sports Sci. 2017.",
                   url: "https://pubmed.ncbi.nlm.nih.gov/27433992/"),
            Source(usedFor: "sources.use.steps",
                   citation: "Paluch AE, et al. Daily steps and all-cause mortality: a meta-analysis of 15 international cohorts. Lancet Public Health. 2022.",
                   url: "https://pubmed.ncbi.nlm.nih.gov/35247352/"),
            Source(usedFor: "sources.use.sleep",
                   citation: "Hirshkowitz M, et al. National Sleep Foundation's sleep time duration recommendations. Sleep Health. 2015.",
                   url: "https://pubmed.ncbi.nlm.nih.gov/29073412/"),
        ]),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sbBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("sources.intro")
                            .font(SBFont.body(15))
                            .foregroundColor(.sbTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(topics) { topic in
                            VStack(alignment: .leading, spacing: 10) {
                                SectionTitle(icon: topic.icon, title: NSLocalizedString(topic.title, comment: ""))
                                VStack(spacing: 0) {
                                    ForEach(Array(topic.sources.enumerated()), id: \.element.id) { i, s in
                                        sourceRow(s)
                                        if i < topic.sources.count - 1 { Divider().background(Color.sbBorder) }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .background(Color.sbSurface)
                                .cornerRadius(16)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
                            }
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "stethoscope")
                                .foregroundColor(.orange)
                                .padding(.top, 2)
                            Text("sources.disclaimer")
                                .font(SBFont.caption())
                                .foregroundColor(.sbTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(14)

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle(Text("sources.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.sbAccent)
                }
            }
        }
    }

    private func sourceRow(_ s: Source) -> some View {
        Link(destination: URL(string: s.url)!) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(s.usedFor))
                        .font(SBFont.heading(14))
                        .foregroundColor(.sbTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: s.citation)
                        .font(SBFont.caption(12))
                        .foregroundColor(.sbTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.sbAccent)
                    .padding(.top, 2)
            }
            .multilineTextAlignment(.leading)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A small "Sources and method" link, placed wherever the app shows a health
/// or nutrition recommendation.
struct SourcesLink: View {
    var compact = false
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            Label("sources.link", systemImage: "info.circle")
                .font(compact ? SBFont.label(11) : SBFont.caption())
                .foregroundColor(.sbAccent)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $show) { SourcesView() }
    }
}
