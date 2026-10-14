import SwiftUI

// MARK: - Photos

extension SportCategory {
    /// Black-and-white banner shown above the category's sports.
    var photoName: String {
        switch self {
        case .outdoor: return "sportcat_outdoor"
        case .indoor:  return "sportcat_indoor"
        case .water:   return "sportcat_water"
        case .team:    return "sportcat_team"
        }
    }
}

extension SportActivity {
    /// The sport's own photo when one exists in the asset catalog as
    /// `sport_<id>` (only yoga for now), otherwise its category's. Adding a
    /// photo for another sport is just dropping in that asset — no code.
    var photoName: String {
        let own = "sport_\(id)"
        return UIImage(named: own) != nil ? own : category.photoName
    }
}

/// Grid catalog of trackable sport activities, organised by category.
/// Presented as a sheet; wraps the reusable `SportsCatalogContent`.
struct SportsCatalogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sbBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    SportsCatalogContent(showHeader: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(verbatim: PT("Sports"))
                        .font(SBFont.heading(16))
                        .foregroundColor(.sbTextPrimary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.sbTextSecondary)
                            .font(.system(size: 20))
                    }
                }
            }
        }
    }
}

/// The category picker + sports grid, without any navigation chrome, so it can
/// be embedded both in the sheet and inline in the Workouts "Sports" tab.
/// Requires a NavigationStack ancestor for the detail links.
struct SportsCatalogContent: View {
    var showHeader: Bool = false
    /// Extra bottom room for pushed detail screens — non-zero only when this
    /// is embedded in a tab, under the floating tab bar.
    var detailBottomInset: CGFloat = 0
    @State private var selectedCategory: SportCategory = .outdoor

    var body: some View {
        VStack(spacing: 16) {
            if showHeader { header }
            categoryPicker
            categoryBanner
            sportsGrid
            Spacer(minLength: 24)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: PT("Track any sport"))
                .font(SBFont.heading(20))
                .foregroundColor(.sbTextPrimary)
            Text(verbatim: PT("Pick a sport to start a tracked session. Outdoor sports use GPS; results sync to Apple Health."))
                .font(SBFont.caption())
                .foregroundColor(.sbTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Category picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SportCategory.allCases) { cat in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedCategory = cat }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(verbatim: PT(cat.rawValue))
                                .font(SBFont.label(12))
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(selectedCategory == cat ? .white : .sbTextPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(selectedCategory == cat ? Color.sbAccent : Color.sbSurfaceRaised)
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Category banner

    /// One photo per category rather than per card: with a photo on every
    /// card, all twelve indoor sports would repeat the same image and lose the
    /// icon that tells them apart.
    private var categoryBanner: some View {
        let count = SportLibrary.byCategory(selectedCategory).count
        return ZStack(alignment: .bottomLeading) {
            SBPhoto(name: selectedCategory.photoName)
                .frame(height: 132)

            LinearGradient(
                colors: [.black.opacity(0.88), .black.opacity(0.3), .black.opacity(0.05)],
                startPoint: .bottom, endPoint: .top)

            VStack(alignment: .leading, spacing: 7) {
                Text(verbatim: String(format: NSLocalizedString("profile.sport.count", comment: ""), count))
                    .font(SBFont.label(10))
                    .foregroundColor(.white)
                    .textCase(.uppercase)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.sbAccent))
                Text(verbatim: PT(selectedCategory.rawValue))
                    .font(SBFont.display(22))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 8, y: 1)
            }
            .padding(14)
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.sbAccent.opacity(0.4), lineWidth: 1.5))
        // A new identity per category makes the photo cross-fade instead of
        // snapping when the picker changes.
        .id(selectedCategory)
        .transition(.opacity)
    }

    // MARK: - Sports grid

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private var sportsGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(SportLibrary.byCategory(selectedCategory)) { sport in
                NavigationLink(destination: SportDetailView(sport: sport, bottomInset: detailBottomInset)) {
                    SportCard(sport: sport)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Card

private struct SportCard: View {
    let sport: SportActivity

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.sbAccent.opacity(0.32),
                                     Color.sbAccent.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                Image(systemName: sport.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.sbAccent)
            }

            Text(verbatim: PT(sport.nameKey))
                .font(SBFont.body())
                .fontWeight(.semibold)
                .foregroundColor(.sbTextPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if sport.usesGPS {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 9))
                    Text(verbatim: PT("GPS"))
                        .font(SBFont.label(9))
                }
                .foregroundColor(.sbAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.sbAccent.opacity(0.15))
                .cornerRadius(6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 8)
        .background(Color.sbSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder, lineWidth: 1))
    }
}
