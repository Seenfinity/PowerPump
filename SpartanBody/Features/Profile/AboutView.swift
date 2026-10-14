import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPrivacy = false

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sbBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {

                        // App icon + name
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(Color.sbAccent.opacity(0.15))
                                    .frame(width: 90, height: 90)
                                Image(systemName: "dumbbell.fill")
                                    .font(.system(size: 40, weight: .semibold))
                                    .foregroundColor(.sbAccent)
                            }
                            Text("PowerPump")
                                .font(SBFont.display(26))
                                .foregroundColor(.sbTextPrimary)
                            Text(appVersion)
                                .font(SBFont.caption())
                                .foregroundColor(.sbTextSecondary)
                        }
                        .padding(.top, 16)

                        // Links card
                        SBCard {
                            VStack(spacing: 0) {
                                aboutRow(icon: "lock.shield.fill", label: "Privacy Policy") {
                                    showPrivacy = true
                                }
                                Divider().background(Color.sbBorder)
                                aboutRow(icon: "star.fill", label: "Rate PowerPump", color: .orange) {
                                    if let url = URL(string: "itms-apps://itunes.apple.com/app/id\(Config.appStoreID)?action=write-review") {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                Divider().background(Color.sbBorder)
                                aboutRow(icon: "envelope.fill", label: "Contact Support") {
                                    if let url = URL(string: "mailto:\(Config.supportEmail)?subject=PowerPump%20Support") {
                                        UIApplication.shared.open(url)
                                    }
                                }
                            }
                        }

                        // AI notice
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "brain.head.profile")
                                    .foregroundColor(.sbAccent)
                                Text("About AI Features")
                                    .font(SBFont.heading(15))
                                    .foregroundColor(.sbTextPrimary)
                            }
                            Text("Everything runs on your iPhone. Your coach builds each plan from the data already on your device, and form analysis reads your body position with Apple's on-device Vision framework. No account, no servers, and nothing sent to any AI service.")
                                .font(SBFont.caption())
                                .foregroundColor(.sbTextSecondary)
                                .lineSpacing(4)
                        }
                        .padding(16)
                        .background(Color.sbSurface)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))

                        Text("© 2026 PowerPump. All rights reserved.")
                            .font(SBFont.label(11))
                            .foregroundColor(Color.sbTextSecondary.opacity(0.5))
                            .padding(.bottom, 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.sbAccent)
                }
            }
        }
        .sheet(isPresented: $showPrivacy) { PrivacyPolicyView() }
    }

    private func aboutRow(icon: String, label: String, color: Color = .sbAccent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 22)
                Text(LocalizedStringKey(label))
                    .font(SBFont.body())
                    .foregroundColor(.sbTextPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.sbTextSecondary.opacity(0.4))
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sbBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Last updated: September 2026")
                            .font(SBFont.caption())
                            .foregroundColor(.sbTextSecondary)

                        policySection("Data We Collect",
                            "PowerPump stores all your fitness data (workouts, nutrition logs, goals, measurements) locally on your device only. We do not operate any backend servers or databases.")

                        policySection("Coach & Form Analysis",
                            "The AI Coach runs entirely on your device: it builds your plan from the profile and history already stored on your iPhone, and makes no network requests. The coach chat uses Apple's on-device language model (Apple Intelligence) when your iPhone supports it; your questions and its answers are processed and stored only on your iPhone. Form analysis uses Apple's on-device Vision framework to read your body position, either live from the camera or from a video you choose from your library. Live analysis is never recorded. A chosen video is copied temporarily for the analysis and deleted when you close the screen; only the score and corrections are saved. Nothing leaves your iPhone.")

                        policySection("Camera",
                            "Camera access is used only to scan product barcodes and to analyze your exercise form live. Barcode scans send the barcode number alone to the public Open Food Facts database to look up nutrition info. Videos for form analysis are chosen with the system picker, so PowerPump only sees the video you pick, never the rest of your library. Form analysis is processed entirely on your device. PowerPump never uploads your photos or video.")

                        policySection("Location & Routes",
                            "With your permission, PowerPump uses your location to trace your route and measure distance and pace during runs, walks, and outdoor sports. Routes are stored on your device only. When you generate a route, start and destination coordinates are sent to Apple Maps to calculate walking directions, handled under Apple's privacy policy. We never receive, store, or share your location.")

                        policySection("Notifications",
                            "If you enable notifications, reminders are scheduled locally on your device using iOS's notification system. No notification data is transmitted to any server.")

                        policySection("Apple Health",
                            "With your permission, PowerPump reads steps, active energy, heart rate, resting heart rate, heart rate variability, body mass, and sleep from Apple Health, and writes your workouts, nutrition, water, and body mass back to it. Health data is used only to show your stats and your weekly coach review inside the app. It is never sent off your device, never shared, and never used for advertising.")

                        policySection("Analytics & Tracking",
                            "PowerPump does not use any third-party analytics, advertising SDKs, or tracking tools. We do not track you across apps or websites, and we do not use any third-party AI or language-model services.")

                        policySection("Data Deletion",
                            "All your data lives on your device. You can delete it at any time by deleting the PowerPump app.")

                        policySection("Contact",
                            "For privacy questions or concerns, contact us at \(Config.supportEmail).")

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.sbAccent)
                }
            }
        }
    }

    // LocalizedStringKey, not String: Text(String) shows the English text
    // as is, so the policy stayed in English whatever the phone's language.
    private func policySection(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SBFont.heading(15))
                .foregroundColor(.sbTextPrimary)
            Text(body)
                .font(SBFont.body())
                .foregroundColor(.sbTextSecondary)
                .lineSpacing(4)
        }
    }
}
