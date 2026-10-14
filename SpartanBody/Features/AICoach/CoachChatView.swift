import SwiftUI

/// Ask the coach anything about training, food, supplements or recovery.
struct CoachChatView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var chat = CoachChatStore.shared
    @ObservedObject private var profile = UserProfile.shared
    @ObservedObject private var memory = SpartanMemory.shared
    @State private var draft = ""
    @State private var style: SpartanStyle? = SpartanStyle.saved
    @State private var showMemory = false
    @FocusState private var focused: Bool

    private static let suggestions = [
        "chat.suggest.proteinAmount", "chat.suggest.eatToday", "chat.suggest.howSquat",
        "chat.suggest.glutes", "chat.suggest.foodEgg", "chat.suggest.creatine",
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sbBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    if case .basic(let reason) = chat.mode { basicBanner(reason) }
                    messageList
                    inputBar
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .foregroundColor(.sbTextPrimary)
                }
                ToolbarItem(placement: .principal) { titleView }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Menu {
                            ForEach(SpartanStyle.allCases) { st in
                                Button { choose(st) } label: {
                                    Label {
                                        Text(verbatim: st.emoji + " " + NSLocalizedString(st.nameKey, comment: ""))
                                    } icon: {
                                        if style == st { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: { Label("spartan.menu.style", systemImage: "theatermasks") }
                        Button { showMemory = true } label: {
                            Label("spartan.menu.memory", systemImage: "brain.head.profile")
                        }
                        Button(role: .destructive) { chat.clear() } label: {
                            Label("chat.clear", systemImage: "trash")
                        }
                        .disabled(chat.messages.isEmpty || chat.isResponding)
                    } label: { Image(systemName: "ellipsis.circle") }
                        .foregroundColor(.sbTextPrimary)
                }
            }
        }
        .onAppear {
            chat.prepare()
            chat.checkInIfNeeded()
        }
        .sheet(isPresented: $showMemory) { SpartanMemoryView() }
    }

    private func choose(_ st: SpartanStyle) {
        HapticManager.selection()
        let first = style == nil
        SpartanStyle.saved = st
        withAnimation { style = st }
        if first { chat.checkInIfNeeded() }
    }

    private var titleView: some View {
        HStack(spacing: 8) {
            CoachAvatar(size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("chat.title")
                    .font(SBFont.heading(15))
                    .foregroundColor(.sbTextPrimary)
                Label {
                    Text(verbatim: (style.map { $0.emoji + " " + NSLocalizedString($0.nameKey, comment: "") + " · " } ?? "")
                         + NSLocalizedString("chat.private", comment: ""))
                } icon: { Image(systemName: "lock.fill") }
                    .font(SBFont.label(10))
                    .foregroundColor(.sbTextSecondary)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private func basicBanner(_ reasonKey: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundColor(.orange)
            Text(LocalizedStringKey(reasonKey))
                .font(SBFont.caption(12))
                .foregroundColor(.sbTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    welcome
                    ForEach(chat.messages) { m in
                        ChatBubble(message: m, typing: chat.isResponding && m.id == chat.messages.last?.id) { action in
                            chat.perform(action, in: m.id)
                        }
                        .id(m.id)
                    }
                    if style == nil {
                        stylePicker
                    } else if chat.messages.isEmpty {
                        suggestionList
                    } else if !chat.isResponding, !chat.followUps.isEmpty {
                        followUpChips
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages) { _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var welcome: some View {
        HStack(alignment: .top, spacing: 10) {
            CoachAvatar(size: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.name.isEmpty ? String(localized: "chat.hello") : String(format: String(localized: "chat.helloName %@"), profile.name))
                    .font(SBFont.heading(16))
                    .foregroundColor(.sbTextPrimary)
                Text("chat.intro")
                    .font(SBFont.body(15))
                    .foregroundColor(.sbTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color.sbSurface)
            .cornerRadius(18, corners: [.topRight, .bottomLeft, .bottomRight])
            Spacer(minLength: 30)
        }
    }

    /// First open: the user picks how Spartan talks to them.
    private var stylePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("spartan.pick.title")
                .font(SBFont.heading(16))
                .foregroundColor(.sbTextPrimary)
            ForEach(SpartanStyle.allCases) { st in
                Button { choose(st) } label: {
                    HStack(spacing: 12) {
                        Text(verbatim: st.emoji).font(.system(size: 26))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(st.nameKey))
                                .font(SBFont.body(16)).fontWeight(.bold)
                                .foregroundColor(.sbTextPrimary)
                            Text(LocalizedStringKey(st.blurbKey))
                                .font(SBFont.caption(13))
                                .foregroundColor(.sbTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.sbTextSecondary)
                    }
                    .padding(14)
                    .background(Color.sbSurface)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sbBorder))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 42)
    }

    /// After each answer: questions to keep going.
    private var followUpChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chat.followUps, id: \.self) { key in
                    Button {
                        HapticManager.selection()
                        chat.send(String(localized: String.LocalizationValue(key)))
                    } label: {
                        Text(LocalizedStringKey(key))
                            .font(SBFont.caption(13))
                            .foregroundColor(.sbAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.sbAccentDim)
                            .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 42)
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("chat.suggest.title")
                .font(SBFont.label(12))
                .foregroundColor(.sbTextSecondary)
                .padding(.leading, 42)
            ForEach(Self.suggestions, id: \.self) { key in
                Button {
                    HapticManager.selection()
                    chat.send(String(localized: String.LocalizationValue(key)))
                } label: {
                    HStack {
                        Text(LocalizedStringKey(key))
                            .font(SBFont.caption(14))
                            .foregroundColor(.sbAccent)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.sbAccent.opacity(0.7))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.sbAccentDim)
                    .cornerRadius(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 42)
            }
        }
    }

    // MARK: Input

    private var inputBar: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("chat.placeholder", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(SBFont.body(16))
                    .foregroundColor(.sbTextPrimary)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.sbSurface)
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sbBorder))
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background(canSend ? AnyShapeStyle(LinearGradient.sbAccentGradient) : AnyShapeStyle(Color.sbSurfaceRaised))
                        .clipShape(Circle())
                }
                .disabled(!canSend)
            }
            VStack(spacing: 3) {
                Text("chat.disclaimer")
                    .font(SBFont.label(10))
                    .foregroundColor(.sbTextSecondary)
                    .multilineTextAlignment(.center)
                SourcesLink(compact: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.sbBackground)
    }

    private var canSend: Bool {
        !chat.isResponding && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        HapticManager.light()
        chat.send(draft)
        draft = ""
    }
}

// MARK: - Pieces

struct CoachAvatar: View {
    var size: CGFloat = 32
    var body: some View {
        // Spartan's mark: a shield with an S.
        ZStack {
            Circle().fill(LinearGradient.sbAccentGradient)
            Image(systemName: "shield.fill")
                .font(.system(size: size * 0.62, weight: .bold))
                .foregroundColor(.white.opacity(0.22))
            Text(verbatim: "S")
                .font(.system(size: size * 0.48, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let typing: Bool
    var onAction: (ChatAction) -> Void = { _ in }

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 50)
                Text(message.text)
                    .font(SBFont.body(15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.sbAccent)
                    .cornerRadius(18, corners: [.topLeft, .topRight, .bottomLeft])
                    .textSelection(.enabled)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                CoachAvatar(size: 32)
                Group {
                    if message.text.isEmpty {
                        TypingDots()
                    } else {
                        Text(Self.markdown(message.text))
                            .font(SBFont.body(15))
                            .foregroundColor(.sbTextPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.sbSurface)
                .cornerRadius(18, corners: [.topRight, .bottomLeft, .bottomRight])
                Spacer(minLength: 30)
            }
            if let actions = message.actions, !actions.isEmpty {
                SpartanActionButtons(actions: actions, onAction: onAction)
                    .padding(.leading, 42)
            }
        }
    }

    /// Bold and italics from the model's markdown, keeping its line breaks
    /// and turning "* " list markers into bullets.
    static func markdown(_ s: String) -> AttributedString {
        let bullets = s.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("* ") || t.hasPrefix("- ") { return "• " + t.dropFirst(2) }
            if t.hasPrefix("#") { return "**" + t.drop(while: { $0 == "#" || $0 == " " }) + "**" }
            return String(line)
        }.joined(separator: "\n")
        return (try? AttributedString(markdown: bullets,
                                      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

private struct TypingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate * 4
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.sbTextSecondary)
                        .frame(width: 7, height: 7)
                        .opacity(0.35 + 0.65 * max(0, sin(t - Double(i) * 0.8)))
                }
            }
            .frame(height: 20)
        }
    }
}

/// Chat-bubble corners: rounded everywhere except where the bubble points.
private struct BubbleShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

private extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(BubbleShape(radius: radius, corners: corners))
    }
}


/// Everything Spartan remembers about the user, to review or delete.
struct SpartanMemoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var memory = SpartanMemory.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sbBackground.ignoresSafeArea()
                if memory.facts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 40))
                            .foregroundColor(.sbTextSecondary)
                        Text("spartan.memory.empty")
                            .font(SBFont.body(15))
                            .foregroundColor(.sbTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else {
                    List {
                        Section {
                            ForEach(memory.facts.reversed()) { f in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: f.kind.icon)
                                        .foregroundColor(.sbAccent)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(verbatim: "«\(f.text)»")
                                            .font(SBFont.body(15))
                                            .foregroundColor(.sbTextPrimary)
                                        Text(f.date, format: .dateTime.day().month())
                                            .font(SBFont.caption(12))
                                            .foregroundColor(.sbTextSecondary)
                                    }
                                }
                                .listRowBackground(Color.sbSurface)
                                .swipeActions {
                                    Button(role: .destructive) { memory.forget(f) } label: {
                                        Label("spartan.memory.forget", systemImage: "trash")
                                    }
                                }
                            }
                        } footer: {
                            Text("spartan.memory.footer")
                        }
                        Section {
                            Button(role: .destructive) { memory.forgetAll() } label: {
                                Text("spartan.memory.forgetAll")
                            }
                            .listRowBackground(Color.sbSurface)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(Text("spartan.menu.memory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .foregroundColor(.sbTextPrimary)
                }
            }
        }
    }
}


/// The buttons under a Spartan message. Once one is used they all go grey.
struct SpartanActionButtons: View {
    let actions: [ChatAction]
    let onAction: (ChatAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(actions) { a in
                Button { onAction(a) } label: {
                    HStack(spacing: 8) {
                        // The effort buttons already start with an emoji.
                        if a.done || a.kind != .rpe {
                            Image(systemName: a.done ? "checkmark.circle.fill" : icon(a.kind))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(verbatim: a.label)
                            .font(SBFont.caption(14)).fontWeight(.semibold)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(a.done ? .sbTextSecondary : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(a.done ? AnyShapeStyle(Color.sbSurfaceRaised) : AnyShapeStyle(LinearGradient.sbAccentGradient))
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)
                .disabled(a.done)
            }
        }
    }

    private func icon(_ k: ChatAction.Kind) -> String {
        switch k {
        case .shorten:  return "timer"
        case .ease:     return "leaf.fill"
        case .move:     return "calendar"
        case .swapMeal: return "arrow.triangle.2.circlepath"
        case .rebuild:  return "wand.and.stars"
        case .rpe:      return "flame.fill"
        }
    }
}

/// Spartan's comment right after a workout, with the "how hard was it" buttons.
struct SpartanRecapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var chat = CoachChatStore.shared
    let messageID: UUID

    private var message: ChatMessage? { chat.messages.first { $0.id == messageID } }

    var body: some View {
        ZStack {
            Color.sbBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        CoachAvatar(size: 40)
                        Text("chat.title").font(SBFont.heading(20)).foregroundColor(.sbTextPrimary)
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark").foregroundColor(.sbTextSecondary) }
                    }
                    if let m = message {
                        Text(verbatim: m.text)
                            .font(SBFont.body(16))
                            .foregroundColor(.sbTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let actions = m.actions {
                            SpartanActionButtons(actions: actions) { a in
                                chat.perform(a, in: m.id)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
                            }
                        }
                        // Spartan's reply to the button, before the sheet closes.
                        if let reply = chat.messages.last, reply.id != m.id, m.actions?.contains(where: \.done) == true {
                            Text(verbatim: reply.text)
                                .font(SBFont.body(15)).foregroundColor(.sbAccent)
                        }
                    }
                }
                .padding(20)
            }
        }
        .presentationDetents([.medium, .large])
    }
}
