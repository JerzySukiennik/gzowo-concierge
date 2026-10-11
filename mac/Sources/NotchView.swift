// Gzowo Concierge for macOS - the notch dock UI: a black pill that springs open into avatar, quick chat, approvals and the next event.
import SwiftUI

struct NotchView: View {
    @ObservedObject var m: NotchModel
    @FocusState private var focused: Bool

    private let openSpring = Animation.spring(response: 0.36, dampingFraction: 0.82)
    private let closeSpring = Animation.spring(response: 0.38, dampingFraction: 1.0)

    var body: some View {
        let pillW = m.closedSize.width + m.pillExtra
        let agentOn = m.agent.visible && !m.expanded
        let w = m.expanded ? m.openSize.width : (agentOn ? m.agentSize.width : pillW)
        let h = m.expanded ? contentHeight : (agentOn ? m.agentSize.height : m.closedSize.height)
        let shape = NotchShape(topRadius: m.expanded ? 16 : (agentOn ? 12 : 5), bottomRadius: m.expanded ? 26 : (agentOn ? 22 : 8))
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            collapsed
                .frame(width: pillW, height: m.closedSize.height, alignment: .top)
                .opacity(m.expanded || agentOn ? 0 : 1)
                .animation(.easeOut(duration: 0.12), value: m.expanded)
                .contentShape(Rectangle())
                .onTapGesture { m.openApp() }
                .allowsHitTesting(!m.expanded && !agentOn)
            agentBar
                .frame(width: m.agentSize.width, height: m.agentSize.height, alignment: .top)
                .opacity(agentOn ? 1 : 0)
                .animation(.easeOut(duration: 0.18), value: agentOn)
                .allowsHitTesting(agentOn)
            expanded
                .frame(width: m.openSize.width, height: contentHeight, alignment: .top)
                .opacity(m.expanded ? 1 : 0)
                .animation(m.expanded ? .easeOut(duration: 0.22).delay(0.1) : .easeIn(duration: 0.08), value: m.expanded)
                .allowsHitTesting(m.expanded)
        }
        .frame(width: w, height: h, alignment: .top)
        .clipShape(shape)
        .contextMenu {
            Button("Otwórz Concierge") { m.openApp() }
            Button("Rozmowa na żywo") { m.openLive() }
            Button("Ustawienia") { m.openSettings() }
            Divider()
            Button("Zakończ Concierge") { m.quitApp() }
        }
        .shadow(color: .black.opacity(m.expanded ? 0.4 : 0), radius: 16, y: 8)
        .animation(m.expanded ? openSpring : closeSpring, value: m.expanded)
        .animation(openSpring, value: contentHeight)
        .animation(openSpring, value: m.dictation)
        .animation(openSpring, value: m.agent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var contentHeight: CGFloat { m.openHeight }

    private func bot(_ size: CGFloat) -> some View {
        NotchBot(kind: m.avatarShape, color: "white", size: size, busy: m.busy || m.streaming, alert: !m.pending.isEmpty, look: m.look, blink: m.blink)
    }

    private var collapsed: some View {
        HStack(spacing: 8) {
            bot(20).padding(.leading, 8)
            Spacer(minLength: 0)
            if m.dictation != .idle {
                dictationIndicator.padding(.trailing, 14)
            } else if !m.pending.isEmpty {
                Text("\(m.pending.count)").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                    .frame(minWidth: 16, minHeight: 16).background(Color.white, in: Capsule()).padding(.trailing, 12)
            } else if m.busy || m.streaming {
                BusyBars().padding(.trailing, 14)
            } else if !m.online {
                Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.2).frame(width: 7, height: 7).padding(.trailing, 14)
            }
        }
    }

    private var agentHistoryBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ZADANIA AGENTA").font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button("Wyczyść") { m.agentHistory = [] }.buttonStyle(.plain).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(m.agentHistory.prefix(3)) { run in
                HStack(alignment: .top, spacing: 8) {
                    switch run.state {
                    case .running: ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 14, height: 14)
                    case .ok: Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).frame(width: 14, height: 14)
                    case .failed: Image(systemName: "exclamationmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(red: 1, green: 0.45, blue: 0.43)).frame(width: 14, height: 14)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(run.task).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                        Text(run.state == .running ? "W trakcie…" : run.summary).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 40, alignment: .top)
            }
            if m.agentHistory.count > 3 { Text("+\(m.agentHistory.count - 3) starszych").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4)) }
        }
    }

    private var agentBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                bot(18)
                if m.agent.finished {
                    Image(systemName: m.agent.ok ? "checkmark" : "exclamationmark").font(.system(size: 11, weight: .bold)).foregroundStyle(m.agent.ok ? Color.white : Color(red: 1, green: 0.45, blue: 0.43))
                    Text(m.agent.summary).font(.system(size: 12)).foregroundStyle(.white).lineLimit(2)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        if m.agent.total > 0 { Text("KROK \(max(m.agent.step, 1)) Z \(m.agent.total)").font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(.white.opacity(0.55)) }
                        Text(m.agent.narration).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if m.agent.active {
                    Button { m.stopAgent() } label: {
                        Image(systemName: "xmark").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white).frame(width: 22, height: 22).background(Color.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain).help("Zatrzymaj (Esc)").accessibilityLabel("Zatrzymaj agenta")
                }
            }
            if m.agent.active && m.agent.total > 0 {
                HStack(spacing: 4) {
                    ForEach(0..<m.agent.total, id: \.self) { i in
                        Capsule().fill(Color.white.opacity(i < max(m.agent.step, 1) ? 0.95 : 0.2)).frame(height: 3)
                    }
                }
            }
            if let q = m.agent.ask {
                HStack(spacing: 10) {
                    Text(q).font(.system(size: 12)).foregroundStyle(.white).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Nie") { m.answerAgent(false) }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 13).padding(.vertical, 6).background(Color.white.opacity(0.14), in: Capsule())
                    Button("Tak") { m.answerAgent(true) }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 15).padding(.vertical, 6).background(Color.white, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 9)
    }

    @ViewBuilder
    private var dictationIndicator: some View {
        switch m.dictation {
        case .listening: LevelBars(level: CGFloat(m.level))
        case .thinking: BusyBars()
        case .done: Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
        case .failed(let msg): Text(msg).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(red: 1, green: 0.45, blue: 0.43)).lineLimit(1)
        case .idle: EmptyView()
        }
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                bot(36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Concierge").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text(m.status).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                roundButton("waveform", "Rozmowa na żywo") { m.openLive() }
                roundButton("macwindow", "Otwórz Concierge") { m.openApp() }
            }
            .contentShape(Rectangle())
            .onTapGesture { m.openApp() }
            if !m.agentHistory.isEmpty { agentHistoryBlock }
            ForEach(m.pending.prefix(2)) { item in approvalCard(item) }
            if !m.reply.isEmpty || m.streaming || !m.errorText.isEmpty { replyBlock }
            else if !m.nextEvent.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "calendar").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    Text("Następne: \(m.nextEvent)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            inputBar
        }
        .padding(.horizontal, 26)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    private func roundButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Color.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    private func approvalCard(_ item: PendingItem) -> some View {
        HStack(spacing: 10) {
            Text(item.summary).font(.system(size: 12.5)).foregroundStyle(.white).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Button("Nie") { m.approve(item, false) }
                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7).background(Color.white.opacity(0.14), in: Capsule())
            Button("Tak") { m.approve(item, true) }
                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                .padding(.horizontal, 16).padding(.vertical, 7).background(Color.white, in: Capsule())
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var replyBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !m.steps.isEmpty {
                HStack(spacing: 6) {
                    ForEach(m.steps.suffix(2), id: \.self) { s in
                        Text(s).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Color.white.opacity(0.1), in: Capsule())
                    }
                }
            }
            ScrollView(showsIndicators: false) {
                if m.errorText.isEmpty {
                    Text(NotchText.attributed(m.replyShown)).font(.system(size: 13)).lineSpacing(2).foregroundStyle(.white).tint(.white).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
                } else {
                    Text(m.errorText).font(.system(size: 12.5)).foregroundStyle(Color(red: 1, green: 0.42, blue: 0.4)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: m.replyHeight)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.93), .init(color: .black.opacity(m.replyHeight >= NotchModel.replyMax ? 0 : 1), location: 1)], startPoint: .top, endPoint: .bottom))
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(m.agentMode ? "Co mam zrobić na ekranie?" : "Napisz do Concierge", text: $m.text)
                .textFieldStyle(.plain).font(.system(size: 13.5)).foregroundStyle(.white)
                .focused($focused)
                .onSubmit { m.send() }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.white.opacity(0.1), in: Capsule())
                .accessibilityLabel("Napisz do Concierge")
            Button { m.agentMode.toggle() } label: {
                Image(systemName: "cursorarrow.click.2").font(.system(size: 13, weight: .semibold)).foregroundStyle(m.agentMode ? Color.black : Color.white)
                    .frame(width: 30, height: 30).background(m.agentMode ? Color.white : Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain).help("Agent ekranu: wykona zadanie na Twoim ekranie").accessibilityLabel("Tryb agenta ekranu")
            Button { m.send() } label: {
                Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 30, height: 30).background(Color.white.opacity(m.text.isEmpty ? 0.35 : 1), in: Circle())
            }
            .buttonStyle(.plain).disabled(m.text.isEmpty || m.streaming).accessibilityLabel("Wyślij")
        }
        .onChange(of: m.expanded) { _, on in if on && m.wantsFocus { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focused = true } } }
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
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.18)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(Color.white).frame(width: 2.5, height: 5 + 9 * abs(sin(t * 3.2 + Double(i) * 0.9)))
                }
            }
            .frame(height: 14)
        }
    }
}
