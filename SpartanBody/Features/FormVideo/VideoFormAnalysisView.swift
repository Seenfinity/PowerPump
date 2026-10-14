import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

/// Pick an exercise, choose a video of your set, get a rep-by-rep review.
/// Everything runs on the phone; the video is copied to a temporary file for
/// the analysis and deleted when the screen closes.
struct VideoFormAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var history = FormReportStore.shared

    @State private var exercise: VideoExercise?
    @State private var pickerItem: PhotosPickerItem?
    @State private var phase: Phase = .choosing

    enum Phase {
        case choosing
        case loading
        case analysing(Double)
        case result(FormReport, VideoPoseExtractor.Output, URL)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sbBackground.ignoresSafeArea()
                content
            }
            .navigationTitle(Text("form.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .foregroundColor(.sbTextPrimary)
                }
            }
        }
        .onChange(of: pickerItem) { item in
            guard let item, let exercise else { return }
            Task { await analyse(item, exercise) }
        }
        .onAppear { PickedMovie.removeLeftovers() }
        .onDisappear { removeVideo() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .choosing:
            if let exercise { ExerciseSetupView(exercise: exercise, pickerItem: $pickerItem) { self.exercise = nil } }
            else { ExerciseChooser(history: history.reports) { exercise = $0 } }
        case .loading:
            ProcessingView(progress: nil, icon: exercise?.icon)
        case .analysing(let p):
            ProcessingView(progress: p, icon: exercise?.icon)
        case .result(let report, let output, let url):
            FormResultView(report: report, output: output, videoURL: url,
                           previous: history.previous(to: report)) { reset() }
        case .failed(let key):
            FailureView(messageKey: key, exercise: exercise) { reset(keepExercise: true) }
        }
    }

    // MARK: Flow

    private func analyse(_ item: PhotosPickerItem, _ ex: VideoExercise) async {
        phase = .loading
        var copied: URL?
        // The copy is only kept while its result is on screen.
        func discard() { if let copied { try? FileManager.default.removeItem(at: copied) } }
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                phase = .failed("form.error.video"); return
            }
            copied = movie.url
            let output = try await VideoPoseExtractor.extract(from: movie.url) { phase = .analysing($0) }
            switch VideoFormEngine.analyze(output.frames, exercise: ex) {
            case .success(let report):
                history.add(report)
                HapticManager.success()
                phase = .result(report, output, movie.url)
            case .failure(let error):
                discard()
                phase = .failed(error == .bodyNotVisible ? "form.error.body" : "form.error.noReps")
            }
        } catch VideoPoseExtractor.Failure.tooShort {
            discard()
            phase = .failed("form.error.short")
        } catch {
            discard()
            phase = .failed("form.error.video")
        }
    }

    private func reset(keepExercise: Bool = false) {
        removeVideo()
        pickerItem = nil
        if !keepExercise { exercise = nil }
        phase = .choosing
    }

    private func removeVideo() {
        if case .result(_, _, let url) = phase { try? FileManager.default.removeItem(at: url) }
    }
}

/// A video from the library, copied into our temporary folder.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("form-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }

    /// Copies left behind if the app was closed with a result on screen.
    static func removeLeftovers() {
        let tmp = FileManager.default.temporaryDirectory
        let files = (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []
        for name in files where name.hasPrefix("form-") {
            try? FileManager.default.removeItem(at: tmp.appendingPathComponent(name))
        }
    }
}

// MARK: - Choose exercise

private struct ExerciseChooser: View {
    let history: [FormReport]
    let onPick: (VideoExercise) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                intro
                ForEach(FormCategory.allCases) { category in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalizedStringKey(category.labelKey))
                            .font(SBFont.heading(18))
                            .foregroundColor(.sbTextPrimary)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(VideoExercise.allCases.filter { $0.category == category }) { ex in
                                Button { HapticManager.selection(); onPick(ex) } label: { tile(ex) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if !history.isEmpty { historySection }
            }
            .padding(20)
        }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 22))
                .foregroundColor(.sbGreen)
            VStack(alignment: .leading, spacing: 4) {
                Text("form.intro.title")
                    .font(SBFont.heading(16))
                    .foregroundColor(.sbTextPrimary)
                Text("form.intro.body")
                    .font(SBFont.caption())
                    .foregroundColor(.sbTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sbGreen.opacity(0.08))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbGreen.opacity(0.3)))
    }

    private func tile(_ ex: VideoExercise) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ex.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.sbAccent)
                .frame(width: 36, height: 36)
                .background(Color.sbAccentDim)
                .cornerRadius(10)
            Text(LocalizedStringKey(ex.nameKey))
                .font(SBFont.caption(14))
                .fontWeight(.semibold)
                .foregroundColor(.sbTextPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(Color.sbSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sbBorder))
        .contentShape(Rectangle())
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("form.history")
                .font(SBFont.heading(18))
                .foregroundColor(.sbTextPrimary)
            ForEach(history.prefix(10)) { r in
                HStack(spacing: 12) {
                    ReviewScoreRing(score: r.score, size: 40, line: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(r.exercise.nameKey))
                            .font(SBFont.body(15)).fontWeight(.semibold)
                            .foregroundColor(.sbTextPrimary)
                        Text(r.date, format: .dateTime.day().month().hour().minute())
                            .font(SBFont.caption(12))
                            .foregroundColor(.sbTextSecondary)
                    }
                    Spacer()
                    if let hold = r.holdSeconds {
                        Text(verbatim: "\(Int(hold)) s").font(SBFont.caption()).foregroundColor(.sbTextSecondary)
                    } else {
                        Text("form.reps.count \(r.reps.count)").font(SBFont.caption()).foregroundColor(.sbTextSecondary)
                    }
                }
                .padding(12)
                .background(Color.sbSurface)
                .cornerRadius(14)
            }
        }
    }
}

// MARK: - Camera setup + pick video

private struct ExerciseSetupView: View {
    let exercise: VideoExercise
    @Binding var pickerItem: PhotosPickerItem?
    let onBack: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Button(action: onBack) {
                    Label("form.change", systemImage: "chevron.left")
                        .font(SBFont.caption())
                        .foregroundColor(.sbAccent)
                }
                HStack(spacing: 14) {
                    Image(systemName: exercise.icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(LinearGradient.sbAccentGradient)
                        .cornerRadius(16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(exercise.nameKey))
                            .font(SBFont.heading(22))
                            .foregroundColor(.sbTextPrimary)
                        SBTag(text: exercise.category.labelKey)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("form.tips.title")
                        .font(SBFont.heading(16))
                        .foregroundColor(.sbTextPrimary)
                    tip("camera.fill", LocalizedStringKey(exercise.cameraKey))
                    tip("figure.stand", "form.tips.body")
                    tip("iphone", "form.tips.still")
                    tip(exercise.isHold ? "timer" : "number", exercise.isHold ? "form.tips.hold" : "form.tips.reps")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sbSurface)
                .cornerRadius(18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.sbBorder))

                PhotosPicker(selection: $pickerItem, matching: .videos, photoLibrary: .shared()) {
                    HStack {
                        Image(systemName: "video.badge.checkmark")
                        Text("form.pick")
                            .fontWeight(.bold)
                    }
                    .font(SBFont.body())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient.sbAccentGradient)
                    .cornerRadius(14)
                }

                Text("form.pick.hint")
                    .font(SBFont.caption(12))
                    .foregroundColor(.sbTextSecondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
    }

    private func tip(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.sbAccent)
                .frame(width: 22)
            Text(text)
                .font(SBFont.caption(14))
                .foregroundColor(.sbTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Processing / failure

private struct ProcessingView: View {
    let progress: Double?
    let icon: String?

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().stroke(Color.sbSurfaceRaised, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress ?? 0.05)
                    .stroke(LinearGradient.sbAccentGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: progress)
                Image(systemName: icon ?? "figure.strengthtraining.traditional")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.sbAccent)
            }
            .frame(width: 120, height: 120)
            Text(progress == nil ? "form.loading" : "form.analysing")
                .font(SBFont.heading(18))
                .foregroundColor(.sbTextPrimary)
            if let progress {
                Text(verbatim: "\(Int(progress * 100)) %")
                    .font(SBFont.caption())
                    .foregroundColor(.sbTextSecondary)
                    .monospacedDigit()
            }
            Label("form.private", systemImage: "lock.fill")
                .font(SBFont.caption(12))
                .foregroundColor(.sbTextSecondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FailureView: View {
    let messageKey: String
    let exercise: VideoExercise?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("form.error.title")
                .font(SBFont.heading(20))
                .foregroundColor(.sbTextPrimary)
            Text(LocalizedStringKey(messageKey))
                .font(SBFont.body(15))
                .foregroundColor(.sbTextSecondary)
                .multilineTextAlignment(.center)
            if let exercise {
                Label(LocalizedStringKey(exercise.cameraKey), systemImage: "camera.fill")
                    .font(SBFont.caption())
                    .foregroundColor(.sbTextSecondary)
                    .multilineTextAlignment(.center)
            }
            SBPrimaryButton(title: "form.retry", action: onRetry)
                .padding(.top, 8)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Result

private struct FormResultView: View {
    let report: FormReport
    let output: VideoPoseExtractor.Output
    let videoURL: URL
    let previous: FormReport?
    let onDone: () -> Void

    @StateObject private var playback: FormPlayback

    init(report: FormReport, output: VideoPoseExtractor.Output, videoURL: URL,
         previous: FormReport?, onDone: @escaping () -> Void) {
        self.report = report
        self.output = output
        self.videoURL = videoURL
        self.previous = previous
        self.onDone = onDone
        _playback = StateObject(wrappedValue: FormPlayback(url: videoURL))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                summary
                player
                if !report.reps.isEmpty { repStrip }
                issuesSection
                if report.fatigue { note("battery.25", "form.fatigue", .orange) }
                ForEach(report.warnings, id: \.self) { note("camera.metering.unknown", LocalizedStringKey($0), .sbTextSecondary) }
                note("lock.fill", "form.deleted", .sbTextSecondary)
                SBSecondaryButton(title: "form.another", action: onDone)
            }
            .padding(20)
        }
        .onDisappear { playback.pause() }
    }

    private var summary: some View {
        HStack(spacing: 16) {
            ReviewScoreRing(score: report.score, size: 84, line: 8)
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey(report.exercise.nameKey))
                    .font(SBFont.heading(20))
                    .foregroundColor(.sbTextPrimary)
                if let hold = report.holdSeconds {
                    Text("form.hold.seconds \(Int(hold.rounded()))")
                        .font(SBFont.caption()).foregroundColor(.sbTextSecondary)
                } else {
                    Text("form.reps.count \(report.reps.count)")
                        .font(SBFont.caption()).foregroundColor(.sbTextSecondary)
                }
                if let previous {
                    let delta = report.score - previous.score
                    Text(verbatim: delta == 0 ? "=" : delta > 0 ? "▲ +\(delta)" : "▼ \(delta)")
                        .font(SBFont.caption(12)).fontWeight(.bold)
                        .foregroundColor(delta == 0 ? .sbTextSecondary : delta > 0 ? .sbGreen : .sbRed)
                    + Text(verbatim: " ")
                    + Text("form.vsLast")
                        .font(SBFont.caption(12))
                        .foregroundColor(.sbTextSecondary)
                }
                Text(LocalizedStringKey(verdictKey))
                    .font(SBFont.caption(13))
                    .foregroundColor(ReviewScoreRing.color(report.score))
            }
            Spacer(minLength: 0)
        }
    }

    private var verdictKey: String {
        report.score >= 85 ? "form.verdict.great" : report.score >= 65 ? "form.verdict.good" : "form.verdict.work"
    }

    // Video with the detected skeleton drawn on top.
    private var player: some View {
        ZStack {
            PlayerLayerView(player: playback.player)
            SkeletonOverlay(frame: currentFrame, aspect: output.aspect, color: currentColor)
        }
        .aspectRatio(output.aspect, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: 460)
        .background(Color.black)
        .cornerRadius(18)
        .overlay(alignment: .bottomLeading) {
            Button { playback.toggle() } label: {
                Image(systemName: playback.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(12)
        }
        .onTapGesture { playback.toggle() }
    }

    private var currentFrame: PoseFrame? {
        let t = playback.time
        var lo = 0, hi = output.frames.count - 1
        guard hi >= 0 else { return nil }
        while lo < hi {
            let mid = (lo + hi) / 2
            if output.frames[mid].time < t { lo = mid + 1 } else { hi = mid }
        }
        let f = output.frames[lo]
        return abs(f.time - t) < 0.25 ? f : nil
    }

    private var currentRep: RepResult? {
        report.reps.first { playback.time >= $0.start && playback.time <= $0.end }
    }

    private var currentColor: Color {
        guard let rep = currentRep else { return .sbCyan }
        return rep.issues.isEmpty ? .sbGreen : .orange
    }

    private var repStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("form.reps.tap")
                .font(SBFont.caption(12))
                .foregroundColor(.sbTextSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(report.reps, id: \.number) { rep in
                        Button { playback.play(from: rep.start) } label: {
                            VStack(spacing: 2) {
                                Text(verbatim: "\(rep.number)")
                                    .font(SBFont.heading(16))
                                Text(verbatim: "\(rep.score)")
                                    .font(SBFont.label(10))
                                    .monospacedDigit()
                            }
                            .foregroundColor(currentRep?.number == rep.number ? .white : ReviewScoreRing.color(rep.score))
                            .frame(width: 46, height: 50)
                            .background(currentRep?.number == rep.number
                                        ? ReviewScoreRing.color(rep.score)
                                        : ReviewScoreRing.color(rep.score).opacity(0.14))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var issuesSection: some View {
        if report.issues.isEmpty {
            note("checkmark.seal.fill", "form.clean", .sbGreen)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("form.focus")
                    .font(SBFont.heading(18))
                    .foregroundColor(.sbTextPrimary)
                ForEach(Array(report.issues.enumerated()), id: \.element.id) { i, issue in
                    issueCard(issue, index: i + 1)
                }
                if let worst = report.worstRep, report.reps.count > 1 {
                    Button { playback.play(from: worst.start) } label: {
                        Label("form.worst \(worst.number)", systemImage: "play.rectangle.fill")
                            .font(SBFont.caption(14)).fontWeight(.semibold)
                            .foregroundColor(.sbAccent)
                    }
                }
            }
        }
    }

    private func issueCard(_ issue: FormIssue, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(verbatim: "\(index)")
                    .font(SBFont.label(12))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.orange))
                Text(LocalizedStringKey("form.rule." + issue.rule + ".title"))
                    .font(SBFont.body(15)).fontWeight(.semibold)
                    .foregroundColor(.sbTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(LocalizedStringKey("form.rule." + issue.rule + ".fix"))
                .font(SBFont.caption(14))
                .foregroundColor(.sbTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !issue.reps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("form.issue.inReps").font(SBFont.label(11)).foregroundColor(.sbTextSecondary)
                        ForEach(issue.reps, id: \.self) { n in
                            Button {
                                if let rep = report.reps.first(where: { $0.number == n }) { playback.play(from: rep.start) }
                            } label: {
                                Text(verbatim: "\(n)")
                                    .font(SBFont.label(12))
                                    .foregroundColor(.orange)
                                    .frame(minWidth: 26, minHeight: 24)
                                    .background(Color.orange.opacity(0.14))
                                    .cornerRadius(7)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text("form.issue.share \(Int((issue.share * 100).rounded()))")
                    .font(SBFont.label(11)).foregroundColor(.sbTextSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sbSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
    }

    private func note(_ icon: String, _ text: LocalizedStringKey, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(color)
            Text(text)
                .font(SBFont.caption(13))
                .foregroundColor(.sbTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }
}

// MARK: - Playback

@MainActor
final class FormPlayback: ObservableObject {
    let player: AVPlayer
    @Published var time: Double = 0
    @Published var playing = false
    private var observer: Any?
    private var endObserver: NSObjectProtocol?

    init(url: URL) {
        player = AVPlayer(url: url)
        player.isMuted = true
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 30, preferredTimescale: 600),
                                                  queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.time = t.seconds }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.playing = false
                self?.player.seek(to: .zero)
            }
        }
    }

    deinit {
        if let observer { player.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func toggle() { playing ? pause() : resume() }
    func pause() { player.pause(); playing = false }
    func resume() { player.play(); playing = true }

    func play(from seconds: Double) {
        HapticManager.selection()
        player.seek(to: CMTime(seconds: max(0, seconds - 0.2), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        resume()
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let v = PlayerUIView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        return v
    }
    func updateUIView(_ uiView: PlayerUIView, context: Context) {}

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// The joints Vision found, drawn over the video.
private struct SkeletonOverlay: View {
    let frame: PoseFrame?
    let aspect: CGFloat
    let color: Color

    private static let bones: [(BodyJoint, BodyJoint)] = [
        (.leftShoulder, .rightShoulder), (.leftHip, .rightHip),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.neck, .nose),
    ]

    var body: some View {
        Canvas { ctx, size in
            guard let frame else { return }
            func pt(_ j: BodyJoint) -> CGPoint? {
                guard let p = frame.points[j] else { return nil }
                return CGPoint(x: p.x / aspect * size.width, y: (1 - p.y) * size.height)
            }
            var path = Path()
            for (a, b) in Self.bones {
                guard let pa = pt(a), let pb = pt(b) else { continue }
                path.move(to: pa); path.addLine(to: pb)
            }
            ctx.stroke(path, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            for j in BodyJoint.allCases {
                guard let p = pt(j) else { continue }
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(.white))
            }
        }
        .allowsHitTesting(false)
    }
}
