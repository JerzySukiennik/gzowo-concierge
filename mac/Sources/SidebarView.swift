// Gzowo Concierge for macOS - the native glass sidebar: actions, conversation list grouped by day, host status.
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 34)

            VStack(spacing: 2) {
                navRow("square.and.pencil", "Nowa rozmowa", key: "⌘N", enabled: model.hasThreads, why: "Wymaga zaktualizowanego hosta") { model.newThread() }
                navRow("puzzlepiece.extension", "Konektory", enabled: model.shellReady, why: "Wymaga nowej wersji interfejsu") { model.openView("connectors") }
                navRow("wand.and.stars", "Umiejętności", enabled: model.shellReady, why: "Wymaga nowej wersji interfejsu") { model.openView("skills") }
                navRow("brain", "Pamięć", enabled: model.shellReady, why: "Wymaga nowej wersji interfejsu") { model.openView("memory") }
                navRow("sun.max", "Dzisiaj", enabled: model.shellReady, why: "Wymaga nowej wersji interfejsu") { model.openView("today") }
            }
            .padding(.horizontal, 10)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                TextField("Szukaj rozmów", text: $model.query)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Szukaj rozmów")
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .padding(.horizontal, 14).padding(.top, 14)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                    ForEach(model.groups) { group in
                        Text(group.id)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 4)
                        ForEach(group.items) { t in threadRow(t) }
                    }
                    if model.groups.isEmpty {
                        Text(model.query.isEmpty ? "Jeszcze nic tu nie ma." : "Brak wyników.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(14)
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 8)
            }

            Spacer(minLength: 0)
            footer
        }
        .frame(maxHeight: .infinity)
    }

    private func navRow(_ symbol: String, _ title: String, key: String? = nil, enabled: Bool = true, why: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 14, weight: .regular)).frame(width: 20)
                Text(title).font(.system(size: 13.5, weight: .medium))
                Spacer()
                if let key { Text(key).font(.system(size: 11)).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(hovered == title ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(enabled ? "" : why)
        .accessibilityLabel(title)
        .onHover { hovered = $0 ? title : (hovered == title ? nil : hovered) }
    }

    private func threadRow(_ t: ThreadInfo) -> some View {
        let selected = t.id == model.activeID
        return Button { model.select(t.id) } label: {
            HStack(spacing: 8) {
                Group {
                    if t.busy { ProgressView().controlSize(.mini).scaleEffect(0.8) }
                    else { Circle().fill(selected ? Color.primary.opacity(0.7) : Color.clear).frame(width: 5, height: 5) }
                }
                .frame(width: 12)
                Text(t.title).font(.system(size: 13.5, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 6)
                Text(Self.relative(t.updated)).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(selected ? Color.primary.opacity(0.095) : (hovered == t.id ? Color.primary.opacity(0.05) : .clear), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hovered = $0 ? t.id : (hovered == t.id ? nil : hovered) }
        .contextMenu {
            Button("Zmień nazwę…") { model.requestRename?(t) }
            if t.id != "main" { Button("Usuń", role: .destructive) { model.delete(t) } } else { Button("Wyczyść rozmowę", role: .destructive) { model.delete(t) } }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(model.online ? Color.green.opacity(0.85) : Color.orange.opacity(0.9)).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.online ? (model.pending > 0 ? "Czeka na Twoją zgodę" : (model.busy ? "Pracuję…" : "Gotowy")) : "Host nie odpowiada")
                    .font(.system(size: 12, weight: .medium))
                if model.pending > 0 { Text("\(model.pending) w kolejce").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer()
            Button { model.openView("settings") } label: {
                Image(systemName: "gearshape").font(.system(size: 14))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!model.shellReady)
            .accessibilityLabel("Ustawienia")
            .opacity(model.shellReady ? 1 : 0.4)
            .help(model.shellReady ? "Ustawienia" : "Wymaga nowej wersji interfejsu")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    static func relative(_ ms: Double) -> String {
        let d = max(0, Date().timeIntervalSince1970 - ms / 1000)
        if d < 60 { return "teraz" }
        if d < 3600 { return "\(Int(d / 60)) min" }
        if d < 86400 { return "\(Int(d / 3600)) godz." }
        if d < 86400 * 14 { return "\(Int(d / 86400)) d" }
        return "\(Int(d / 86400 / 7)) tyg."
    }
}
