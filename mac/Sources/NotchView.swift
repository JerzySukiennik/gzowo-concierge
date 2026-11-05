// Gzowo Concierge for macOS - the island UI: one black shape that springs between live activities (levels, media, timer, next event, agent, dictation) and the open panel with chat, media and timer cards.
import SwiftUI

private struct BlurFade: ViewModifier {
    var blur: CGFloat
    var scale: CGFloat
    var opacity: Double
    var anchor: UnitPoint
    func body(content: Content) -> some View {
        content.blur(radius: blur).scaleEffect(scale, anchor: anchor).opacity(opacity)
    }
}

private extension AnyTransition {
    static func melt(scale: CGFloat, blur: CGFloat, anchor: UnitPoint = .center, delay: Double = 0.05) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(active: BlurFade(blur: blur, scale: scale, opacity: 0, anchor: anchor), identity: BlurFade(blur: 0, scale: 1, opacity: 1, anchor: anchor))
                .animation(.spring(response: 0.4, dampingFraction: 0.86).delay(delay)),
            removal: .modifier(active: BlurFade(blur: blur * 0.7, scale: 1 + (1 - scale) * 0.4, opacity: 0, anchor: anchor), identity: BlurFade(blur: 0, scale: 1, opacity: 1, anchor: anchor))
                .animation(.easeIn(duration: 0.13))
        )
    }
}

enum Island {
    static let open = Animation.spring(response: 0.46, dampingFraction: 0.76)
    static let close = Animation.spring(response: 0.34, dampingFraction: 0.92)
    static let morph = Animation.spring(response: 0.4, dampingFraction: 0.72)
    static let hover = Animation.spring(response: 0.3, dampingFraction: 0.6)
    static let amber = Color(red: 1, green: 0.72, blue: 0.28)
    static let error = Color(red: 1, green: 0.45, blue: 0.43)
}

func clockText(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded(.up)))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

struct NotchView: View {
    @ObservedObject var m: NotchModel
    @FocusState private var focused: Bool

    var body: some View {
        let size = m.shapeSize
        let r = m.radii
        let shape = NotchShape(topRadius: r.top, bottomRadius: r.bottom)
        let showBubble = !m.expanded && m.secondary != nil
        ZStack(alignment: .top) {
            if m.expanded {
                expanded
                    .transition(.melt(scale: 0.9, blur: 12, anchor: .top, delay: 0.06))
            } else {
                compact(m.primary)
                    .frame(width: m.compactSize(m.primary).width, height: m.compactSize(m.primary).height)
                    .contentShape(Rectangle())
                    .onTapGesture { tapCompact() }
                    .id(m.primary)
                    .transition(.melt(scale: 0.82, blur: 7))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .background(alignment: .top) {
            shape.fill(Color.black)
                .shadow(color: .black.opacity(m.expanded ? 0.42 : (m.transient || m.primary == .peek ? 0.22 : 0)), radius: m.expanded ? 22 : 9, y: m.expanded ? 10 : 3)
                .frame(width: size.width, height: size.height)
        }
        .contentShape(shape)
        .overlay(alignment: .topTrailing) {
            if showBubble, let s = m.secondary {
                bubble(s)
                    .offset(x: m.bubbleSize.width + 7)
                    .transition(.asymmetric(insertion: .scale(scale: 0.3, anchor: .leading).combined(with: .opacity).animation(Island.morph.delay(0.08)), removal: .scale(scale: 0.3, anchor: .leading).combined(with: .opacity).animation(.easeIn(duration: 0.14))))
            }
        }
        .contextMenu {
            Button("Otwórz Concierge") { m.openApp() }
            Button("Rozmowa na żywo") { m.openLive() }
            Button("Ustawienia") { m.openSettings() }
            Divider()
            Button("Zakończ Concierge") { m.quitApp() }
        }
        .animation(Island.morph, value: m.primary)
        .animation(Island.morph, value: m.secondary)
        .animation(Island.hover, value: m.hovering)
        .animation(Island.open, value: m.expandedHeight)
        .animation(Island.morph, value: m.agent)
        .animation(Island.morph, value: m.dictation)
        .animation(m.expanded ? Island.open : Island.close, value: m.expanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private func tapCompact() {
        switch m.primary {
        case .agent: if m.agent.finished { m.expandRequest() }
        case .alarm: m.stopAlarm()
        default: m.focusRequest()
        }
    }

    private func bot(_ size: CGFloat) -> some View {
        NotchBot(kind: m.avatarShape, color: "white", size: size, busy: m.busy || m.streaming, alert: !m.pending.isEmpty, look: m.look, blink: m.blink)
    }

    private var side: CGFloat { m.radii.top + 6 }

    // MARK: compact activities

    @ViewBuilder
    private func compact(_ a: Activity) -> some View {
        switch a {
        case .idle: idleCompact
        case .dictation: dictationCompact
        case .agent: agentBar
        case .hud: hudCompact
        case .alarm: alarmCompact
        case .peek: peekCompact
        case .timer: timerCompact
        case .event: eventCompact
        case .media: mediaCompact
        }
    }

    private var idleCompact: some View {
        HStack(spacing: 8) {
            bot(m.hovering ? 21 : 19)
            Spacer(minLength: 0)
            statusGlyph
        }
        .padding(.horizontal, side + 2)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var statusGlyph: some View {
        if !m.pending.isEmpty {
            Text("\(m.pending.count)").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                .frame(minWidth: 16, minHeight: 16).background(Color.white, in: Capsule())
        } else if m.busy || m.streaming {
            BusyBars(color: Island.amber)
        } else if !m.online {
            Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.2).frame(width: 7, height: 7)
        }
    }

    private var dictationCompact: some View {
        HStack(spacing: 8) {
            bot(19)
            Spacer(minLength: 0)
            switch m.dictation {
            case .listening: LevelBars(level: CGFloat(m.level))
            case .thinking: BusyBars(color: .white)
            case .done: Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            case .failed(let msg): Text(msg).font(.system(size: 11, weight: .medium)).foregroundStyle(Island.error).lineLimit(1)
            case .idle: EmptyView()
            }
        }
        .padding(.horizontal, side + 2)
        .frame(maxHeight: .infinity)
    }

    private var hudCompact: some View {
        let e = m.hud ?? LevelEvent(kind: .volume, value: 0)
        let off = e.muted || e.value <= 0.001
        return HStack(spacing: 11) {
            Image(systemName: hudSymbol(e), variableValue: e.kind == .volume ? Double(e.value) : nil)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22)
            LevelTrack(value: CGFloat(e.muted ? 0 : e.value), dim: off)
                .frame(height: 6)
            Text(e.device.isEmpty ? (e.muted ? "wycisz." : "\(Int((e.value * 100).rounded()))") : e.device)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .frame(width: e.device.isEmpty ? 34 : 86, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, side + 8)
        .frame(maxHeight: .infinity)
        .animation(.spring(response: 0.26, dampingFraction: 0.9), value: e.value)
    }

    private func hudSymbol(_ e: LevelEvent) -> String {
        switch e.kind {
        case .volume: return e.muted || e.value <= 0.001 ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .brightness: return e.value < 0.3 ? "sun.min.fill" : "sun.max.fill"
        case .keyboard: return e.value <= 0.01 ? "light.min" : "light.max"
        }
    }

    private var alarmCompact: some View {
        let t = m.alarm
        return HStack(spacing: 12) {
            Image(systemName: "bell.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 0.6)), isActive: m.alarm != nil)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.map { $0.label.isEmpty ? "Timer" : $0.label.capitalizedFirst } ?? "Timer").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text("Koniec, minęło \(clockText(t?.total ?? 0))").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            pillButton("+1 min", strong: false) { if let t { m.timerAction(t, "add") } }
            pillButton("OK", strong: true) { m.stopAlarm() }
        }
        .padding(.horizontal, side + 12)
        .padding(.top, closedPad)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var closedPad: CGFloat { max(4, (m.compactSize(.alarm).height - 40) / 2) }

    private var peekCompact: some View {
        HStack(spacing: 11) {
            Artwork(image: m.mediaArt ?? m.mediaIcon, size: 38, radius: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.media.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(m.media.subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: m.media.playing ? "play.fill" : "pause.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                .contentTransition(.symbolEffect(.replace))
            Equalizer(playing: m.media.playing).frame(width: 18)
        }
        .padding(.horizontal, side + 10)
        .frame(maxHeight: .infinity)
    }

    private var timerCompact: some View {
        let t = m.activeTimer
        let left = t.map { $0.ends.timeIntervalSince(m.clock) } ?? 0
        return HStack(spacing: 8) {
            TimerRing(progress: t.map { $0.total > 0 ? left / $0.total : 0 } ?? 0, line: 2.2).frame(width: 14, height: 14)
            Spacer(minLength: 0)
            Text(clockText(left)).font(.system(size: 12.5, weight: .semibold).monospacedDigit()).foregroundStyle(Island.amber)
                .contentTransition(.numericText(countsDown: true))
        }
        .padding(.horizontal, side + 3)
        .frame(maxHeight: .infinity)
        .animation(.linear(duration: 0.3), value: m.clock)
    }

    private var eventCompact: some View {
        let e = m.soonEvent
        let mins = e.map { Int(ceil($0.start.timeIntervalSince(m.clock) / 60)) } ?? 0
        return HStack(spacing: 7) {
            Image(systemName: "calendar").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            Text(e?.title ?? "").font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white).lineLimit(1)
            Spacer(minLength: 6)
            Text(mins <= 0 ? "teraz" : "za \(mins) min").font(.system(size: 11.5, weight: .semibold).monospacedDigit()).foregroundStyle(mins <= 5 ? Island.amber : .white.opacity(0.7))
                .contentTransition(.numericText(countsDown: true))
        }
        .padding(.horizontal, side + 4)
        .frame(maxHeight: .infinity)
    }

    private var mediaCompact: some View {
        HStack(spacing: 8) {
            Artwork(image: m.mediaArt ?? m.mediaIcon, size: 17, radius: 4.5)
            Spacer(minLength: 0)
            Equalizer(playing: m.media.playing)
        }
        .padding(.horizontal, side + 3)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func bubble(_ a: Activity) -> some View {
        let s = m.bubbleSize
        ZStack {
            NotchShape(topRadius: 4, bottomRadius: s.height / 2).fill(Color.black)
            switch a {
            case .timer:
                let t = m.activeTimer
                TimerRing(progress: t.map { $0.total > 0 ? $0.ends.timeIntervalSince(m.clock) / $0.total : 0 } ?? 0, line: 2).frame(width: 13, height: 13)
            case .event:
                let mins = m.soonEvent.map { Int(ceil($0.start.timeIntervalSince(m.clock) / 60)) } ?? 0
                Text(mins <= 0 ? "•" : "\(mins)′").font(.system(size: 10.5, weight: .bold).monospacedDigit()).foregroundStyle(mins <= 5 ? Island.amber : .white)
            case .media:
                Artwork(image: m.mediaArt ?? m.mediaIcon, size: 14, radius: 3.5)
            default: EmptyView()
            }
        }
        .frame(width: s.width, height: s.height)
        .contentShape(Rectangle())
        .onTapGesture { m.focusRequest() }
    }

    // MARK: agent

    private var agentBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                bot(16)
                if m.agent.finished {
                    Image(systemName: m.agent.ok ? "checkmark" : "exclamationmark").font(.system(size: 10, weight: .bold)).foregroundStyle(m.agent.ok ? Color.white : Island.error)
                    Text(m.agent.summary).font(.system(size: 11.5)).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
                } else {
                    if m.agent.total > 0 { Text("\(max(m.agent.step, 1))/\(m.agent.total)").font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.5)).contentTransition(.numericText()) }
                    Text(m.agent.narration).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1).contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                if m.agent.active {
                    Button { m.stopAgent() } label: {
                        Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.white).frame(width: 18, height: 18).background(Color.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain).help("Zatrzymaj (Esc)").accessibilityLabel("Zatrzymaj agenta")
                }
            }
            if m.agent.active && m.agent.total > 0 {
                HStack(spacing: 3) {
                    ForEach(0..<m.agent.total, id: \.self) { i in
                        Capsule().fill(Color.white.opacity(i < max(m.agent.step, 1) ? 0.9 : 0.18)).frame(height: 2)
                    }
                }
            }
            if let q = m.agent.ask {
                HStack(spacing: 8) {
                    Text(q).font(.system(size: 11.5)).foregroundStyle(.white).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    pillButton("Nie", strong: false) { m.answerAgent(false) }
                    pillButton("Tak", strong: true) { m.answerAgent(true) }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 5)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var agentHistoryBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionLabel("ZADANIA AGENTA")
                Spacer()
                Button("Wyczyść") { withAnimation(Island.open) { m.agentHistory = [] } }.buttonStyle(.plain).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(m.agentHistory.prefix(3)) { run in
                HStack(alignment: .top, spacing: 9) {
                    Group {
                        switch run.state {
                        case .running: ProgressView().controlSize(.small).scaleEffect(0.6)
                        case .ok: Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        case .failed: Image(systemName: "exclamationmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Island.error)
                        }
                    }
                    .frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(run.task).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                        Text(run.state == .running ? "W trakcie…" : run.summary).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            }
            if m.agentHistory.count > 3 { Text("+\(m.agentHistory.count - 3) starszych").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4)) }
        }
    }

    // MARK: expanded

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if hasCards { cards }
            if !m.agentHistory.isEmpty { agentHistoryBlock }
            ForEach(m.pending.prefix(2)) { item in approvalCard(item) }
            if m.hasReply { replyBlock }
            inputBar
        }
        .padding(.horizontal, 30)
        .padding(.top, 13)
        .padding(.bottom, 18)
        .frame(width: m.openSize.width, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
            if abs(h - m.expandedHeight) > 0.5 { m.expandedHeight = h }
        }
        .frame(width: m.openSize.width, height: m.shapeSize.height, alignment: .top)
    }

    private var hasCards: Bool { !m.media.isEmpty || m.activeTimer != nil || m.alarm != nil || m.soonEvent != nil }

    private var header: some View {
        HStack(spacing: 12) {
            bot(34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Concierge").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                HStack(spacing: 6) {
                    statusDot
                    Text(m.status).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
                    if !m.nextEventLine.isEmpty && m.soonEvent == nil {
                        Text("·").foregroundStyle(.white.opacity(0.3))
                        Text("Następne: \(m.nextEventLine)").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            roundButton("waveform", "Rozmowa na żywo") { m.openLive() }
            roundButton("macwindow", "Otwórz Concierge") { m.openApp() }
        }
        .contentShape(Rectangle())
        .onTapGesture { m.openApp() }
    }

    @ViewBuilder
    private var statusDot: some View {
        if !m.online {
            Circle().stroke(Color.white.opacity(0.5), lineWidth: 1).frame(width: 6, height: 6)
        } else if m.busy || m.streaming {
            PulseDot(color: Island.amber)
        } else {
            Circle().fill(Color.white.opacity(m.pending.isEmpty ? 0.75 : 1)).frame(width: 6, height: 6)
        }
    }

    private var cards: some View {
        let timer = m.alarm ?? m.activeTimer
        return HStack(spacing: 10) {
            if !m.media.isEmpty { MediaCard(m: m).transition(.melt(scale: 0.94, blur: 6, anchor: .top)) }
            if let t = timer { TimerCard(m: m, timer: t, compact: !m.media.isEmpty || m.soonEvent != nil).transition(.melt(scale: 0.94, blur: 6, anchor: .top)) }
            if let e = m.soonEvent, m.media.isEmpty || timer == nil { EventCard(event: e, clock: m.clock).transition(.melt(scale: 0.94, blur: 6, anchor: .top)) }
        }
        .animation(Island.open, value: m.media.isEmpty)
        .animation(Island.open, value: timer?.id)
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(.white.opacity(0.45))
    }

    private func roundButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Color.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(PressStyle()).help(help).accessibilityLabel(help)
    }

    private func pillButton(_ title: String, strong: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(strong ? Color.black : Color.white)
                .padding(.horizontal, strong ? 15 : 13).padding(.vertical, 6)
                .background(strong ? Color.white : Color.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private func approvalCard(_ item: PendingItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill").font(.system(size: 12)).foregroundStyle(Island.amber)
            Text(item.summary).font(.system(size: 12.5)).foregroundStyle(.white).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            pillButton("Nie", strong: false) { withAnimation(Island.open) { m.approve(item, false) } }
            pillButton("Tak", strong: true) { withAnimation(Island.open) { m.approve(item, true) } }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .transition(.melt(scale: 0.95, blur: 6, anchor: .top))
    }

    private var replyBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !m.steps.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(m.steps.suffix(2).enumerated()), id: \.element) { i, s in
                        HStack(spacing: 5) {
                            if m.streaming && i == m.steps.suffix(2).count - 1 { PulseDot(color: Island.amber, size: 5) }
                            Text(s).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 4).background(Color.white.opacity(0.09), in: Capsule())
                        .transition(.melt(scale: 0.9, blur: 4, anchor: .leading))
                    }
                }
                .animation(Island.morph, value: m.steps)
            }
            ScrollView(showsIndicators: false) {
                if m.errorText.isEmpty {
                    Text(NotchText.attributed(m.replyShown)).font(.system(size: 13)).lineSpacing(2.5).foregroundStyle(.white).tint(.white).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
                } else {
                    Text(m.errorText).font(.system(size: 12.5)).foregroundStyle(Island.error).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: m.replyHeight)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.92), .init(color: .black.opacity(m.replyHeight >= NotchModel.replyMax ? 0 : 1), location: 1)], startPoint: .top, endPoint: .bottom))
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                if m.agentMode { Image(systemName: "cursorarrow.click.2").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6)).transition(.scale.combined(with: .opacity)) }
                TextField(m.agentMode ? "Co mam zrobić na ekranie?" : "Napisz do Concierge", text: $m.text)
                    .textFieldStyle(.plain).font(.system(size: 13.5)).foregroundStyle(.white)
                    .focused($focused)
                    .onSubmit { m.send() }
                    .accessibilityLabel("Napisz do Concierge")
            }
            .padding(.horizontal, 15).frame(height: 36)
            .background(Color.white.opacity(focused ? 0.13 : 0.09), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(focused ? 0.16 : 0.05), lineWidth: 1))
            .animation(.easeOut(duration: 0.15), value: focused)
            .animation(Island.morph, value: m.agentMode)
            Button { m.agentMode.toggle() } label: {
                Image(systemName: "cursorarrow.click.2").font(.system(size: 13, weight: .semibold)).foregroundStyle(m.agentMode ? Color.black : Color.white)
                    .frame(width: 34, height: 34).background(m.agentMode ? Color.white : Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(PressStyle()).help("Agent ekranu: wykona zadanie na Twoim ekranie").accessibilityLabel("Tryb agenta ekranu")
            Button { m.send() } label: {
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 34, height: 34).background(Color.white.opacity(m.text.isEmpty ? 0.3 : 1), in: Circle())
                    .scaleEffect(m.text.isEmpty ? 0.92 : 1)
                    .animation(Island.hover, value: m.text.isEmpty)
            }
            .buttonStyle(PressStyle()).disabled(m.text.isEmpty || m.streaming).accessibilityLabel("Wyślij")
        }
        .onAppear { if m.wantsFocus { DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { focused = true } } }
    }
}

// MARK: cards

private struct MediaCard: View {
    @ObservedObject var m: NotchModel
    @State private var scrub: Double?

    var body: some View {
        let n = m.media
        HStack(spacing: 12) {
            Artwork(image: m.mediaArt ?? m.mediaIcon, size: 56, radius: 12)
                .scaleEffect(n.playing ? 1 : 0.9)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: n.playing)
            VStack(alignment: .leading, spacing: 3) {
                Text(n.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(n.subtitle).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                if n.duration > 0 {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let pos = scrub ?? n.position(at: ctx.date)
                        VStack(spacing: 3) {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.16))
                                    Capsule().fill(Color.white.opacity(0.9)).frame(width: max(4, g.size.width * pos / n.duration))
                                }
                                .frame(height: scrub == nil ? 4 : 6)
                                .frame(maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { v in scrub = max(0, min(1, v.location.x / g.size.width)) * n.duration }
                                    .onEnded { v in m.mediaSeek(max(0, min(1, v.location.x / g.size.width)) * n.duration); scrub = nil })
                            }
                            .frame(height: 10)
                            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: scrub == nil)
                            HStack {
                                Text(clockText(pos)).monospacedDigit()
                                Spacer()
                                Text("-" + clockText(n.duration - pos)).monospacedDigit()
                            }
                            .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
            }
            HStack(spacing: 2) {
                control("backward.fill", 12) { m.mediaCommand("prev") }
                control(n.playing ? "pause.fill" : "play.fill", 17) { m.mediaCommand("toggle") }
                control("forward.fill", 12) { m.mediaCommand("next") }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func control(_ symbol: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold)).foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32).contentShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.82))
    }
}

private struct TimerCard: View {
    @ObservedObject var m: NotchModel
    var timer: TimerInfo
    var compact: Bool

    var body: some View {
        let done = m.alarm?.id == timer.id
        let left = done ? 0 : timer.ends.timeIntervalSince(m.clock)
        HStack(spacing: 11) {
            ZStack {
                TimerRing(progress: timer.total > 0 ? left / timer.total : 0, line: 3.5)
                Image(systemName: done ? "bell.fill" : "timer").font(.system(size: 12, weight: .semibold)).foregroundStyle(done ? .white : Island.amber)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(done ? "Koniec" : clockText(left)).font(.system(size: 18, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                Text(timer.label.isEmpty ? "Timer" : timer.label.capitalizedFirst).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                small("plus", "Dodaj minutę") { m.timerAction(timer, "add") }
                small(done ? "checkmark" : "xmark", done ? "OK" : "Wyłącz timer") { done ? m.stopAlarm() : m.timerAction(timer, "cancel") }
            }
        }
        .padding(10)
        .frame(width: compact ? 214 : nil)
        .frame(maxWidth: compact ? nil : .infinity)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.linear(duration: 0.3), value: m.clock)
    }

    private func small(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Color.white.opacity(0.13), in: Circle())
        }
        .buttonStyle(PressStyle()).help(help).accessibilityLabel(help)
    }
}

private struct EventCard: View {
    var event: UpcomingEvent
    var clock: Date

    var body: some View {
        let mins = Int(ceil(event.start.timeIntervalSince(clock) / 60))
        let f: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
        HStack(spacing: 11) {
            VStack(spacing: 0) {
                Text(mins <= 0 ? "teraz" : "\(mins)").font(.system(size: mins <= 0 ? 13 : 19, weight: .semibold).monospacedDigit()).foregroundStyle(mins <= 5 ? Island.amber : .white)
                if mins > 0 { Text("min").font(.system(size: 9.5, weight: .medium)).foregroundStyle(.white.opacity(0.5)) }
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text("\(f.string(from: event.start))–\(f.string(from: event.end))").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: small parts

struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.9
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct Artwork: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.12)
                Image(systemName: "music.note").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

struct TimerRing: View {
    var progress: Double
    var line: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: line)
            Circle().trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(Island.amber, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct LevelTrack: View {
    var value: CGFloat
    var dim: Bool

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.17))
                Capsule().fill(Color.white.opacity(dim ? 0.35 : 1)).frame(width: max(g.size.height, g.size.width * max(0, min(1, value))))
            }
        }
    }
}

struct Equalizer: View {
    var playing: Bool
    private let speed: [Double] = [5.3, 7.1, 4.4, 6.2]
    private let phase: [Double] = [0, 1.3, 2.6, 0.7]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 14, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let v = playing ? 0.3 + 0.7 * abs(sin(t * speed[i] + phase[i])) * (0.55 + 0.45 * abs(sin(t * 1.7 + phase[i] * 2))) : 0.22
                    Capsule().fill(Color.white).frame(width: 2.4, height: 2.5 + 10 * v)
                }
            }
            .frame(height: 13)
        }
    }
}

struct PulseDot: View {
    var color: Color
    var size: CGFloat = 6
    @State private var on = false

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .opacity(on ? 1 : 0.35)
            .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { on = true } }
    }
}

struct LevelBars: View {
    var level: CGFloat
    private let weights: [CGFloat] = [0.55, 0.85, 1, 0.8, 0.5]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(Color.white).frame(width: 2.5, height: 4 + 12 * min(1, level * weights[i]))
            }
        }
        .frame(height: 16)
        .animation(.easeOut(duration: 0.09), value: level)
    }
}

struct BusyBars: View {
    var color: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(color).frame(width: 2.5, height: 5 + 9 * abs(sin(t * 3.2 + Double(i) * 0.9)))
                }
            }
            .frame(height: 14)
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
