import SwiftUI

struct SettingsView: View {
    /// Smallest content height the window allows; `AppDelegate.fitWindow` clamps to the same.
    static let minContentHeight: CGFloat = 540

    @ObservedObject var model: Model
    /// Reports the height the window needs to show everything without scrolling, so the
    /// window can size itself instead of leaving a blank half under a short device list.
    var onFittingHeight: (CGFloat) -> Void = { _ in }

    private let labelWidth: CGFloat = 170

    var body: some View {
        VStack(spacing: 0) {
            measured(.header) { header }
            Divider()
            ScrollView { measured(.content) { content } }
            Divider()
            measured(.footer) { footer }
        }
        .frame(minWidth: 540, minHeight: Self.minContentHeight)
        .onPreferenceChange(FittingHeightKey.self) { parts in
            guard parts.content > 0 else { return }
            onFittingHeight(parts.total)
        }
    }

    /// The body without the `ScrollView`. Used as-is by `body`, and separately it lets the
    /// window be rendered to an image with `ImageRenderer`, which cannot draw scroll views.
    var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let problem = model.problem { warning(problem, level: .orange) }
            devices
            linkHealth
            performance
            options
        }
        .padding(20)
    }

    /// The same window without scrolling: for development previews only.
    var previewBody: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            Divider()
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: model.isBoosting ? "bolt.fill" : "bolt")
                .font(.system(size: 26))
                .foregroundStyle(model.isBoosting ? Color.accentColor : Color.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("KeyAwake").font(.title2).bold()
                Text("Keeps Bluetooth LE keyboards on a low-latency link.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Enabled", isOn: binding(\.enabled) { .setEnabled($0) })
                .help(L("When off, KeyAwake leaves every link alone."))
            Text(model.headline)
                .font(.callout).bold()
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(model.stateColor.opacity(0.16)))
                .foregroundStyle(model.stateColor)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: - Sections

    private var devices: some View {
        // Pointing devices are never boosted, so listing them only adds noise. Everything
        // else stays: a keyboard the inventory has not classified yet must not vanish.
        let all = model.status.devices
        let visible = all.filter { $0.kind != .pointing }
        return section(L("Bluetooth LE devices")) {
            VStack(alignment: .leading, spacing: 8) {
                if visible.isEmpty {
                    Text("No keyboard in sight.")
                        .foregroundStyle(.secondary).font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(visible) { device in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { device.wanted },
                                set: { model.setBoosted(device, $0) }))
                                .labelsHidden()
                                .disabled(!model.settings.enabled || device.kind != .keyboard)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.name)
                                Text("\(device.kind.label) · \(device.address)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(device.detail(enabled: model.settings.enabled))
                                .font(.caption).monospacedDigit()
                                .foregroundStyle(device.boosted ? Color.green : Color.secondary)
                        }
                    }
                }
                if all.contains(where: { $0.kind != .keyboard }) {
                    caption(L("Only keyboards are boosted. On macOS 27, requesting low latency for a pointing device as well makes the system push the keyboard back to its idle latency."))
                }
            }
        }
    }

    /// What the link is actually doing. Without this, an intermittent fault leaves no
    /// trace and the only way to diagnose it is to guess at whatever changed recently.
    private var linkHealth: some View {
        section(L("Link health")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("Signal")).frame(width: labelWidth, alignment: .leading)
                    Text(model.signalText).monospacedDigit()
                    Spacer()
                    Text(model.healthLabel)
                        .font(.callout).bold()
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(model.healthColor.opacity(0.16)))
                        .foregroundStyle(model.healthColor)
                }
                HStack {
                    Text(L("Packet loss")).frame(width: labelWidth, alignment: .leading)
                    Text(model.lossText).monospacedDigit()
                    Spacer()
                }
                if model.status.radioCyclesLastHour > 0 {
                    HStack {
                        Text(L("Radio drops (1 h)")).frame(width: labelWidth, alignment: .leading)
                        Text("\(model.status.radioCyclesLastHour)").monospacedDigit()
                        Spacer()
                    }
                }
                if let issue = model.status.healthProblem {
                    warning(issue, level: model.status.health == .poor ? .red : .orange)
                }
                HStack {
                    caption(L("Recorded every minute, so a fault that comes and goes leaves a trail."))
                    Button(L("History…")) {
                        NSWorkspace.shared.selectFile(Paths.history.path, inFileViewerRootedAtPath: "")
                    }
                }
            }
        }
    }

    private var performance: some View {
        section(L("Performance")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(L("Link latency"))
                            Spacer(minLength: 4)
                            Picker("", selection: binding(\.latencyLevel) { .setLatencyLevel($0) }) {
                                ForEach(Settings.latencyChoices, id: \.level) { choice in
                                    Text(choice.label).tag(choice.level)
                                }
                            }
                            .labelsHidden()
                            .controlSize(.small)
                        }
                        if let detail = model.latencyDetail { caption(detail) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(L("Release when idle"))
                            Spacer(minLength: 4)
                            Picker("", selection: binding(\.idleReleaseSeconds) { .setIdleReleaseSeconds($0) }) {
                                ForEach(Settings.idleChoices, id: \.seconds) { choice in
                                    Text(choice.label).tag(choice.seconds)
                                }
                            }
                            .labelsHidden()
                            .controlSize(.small)
                        }
                        caption(L("After releasing, the keyboard goes back to saving power. The next "
                                  + "keystroke arrives a little late; everything after it is instant."))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let text = model.latencyWarning {
                    warning(text, level: model.settings.latencyLevel == 2 ? .red : .orange)
                }
            }
        }
    }

    private var options: some View {
        section(nil) {
            HStack(alignment: .top, spacing: 28) {
                Toggle("Show in the menu bar", isOn: binding(\.showMenuBarIcon) { .setShowMenuBarIcon($0) })
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Start at login", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }))
                    caption(L("Without this, KeyAwake stops working when you restart the Mac."))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            Text("Closing this window does not stop the boost.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Show log…") {
                NSWorkspace.shared.selectFile(Paths.log.path, inFileViewerRootedAtPath: "")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: - Reusable pieces

    /// A section box, hand-built rather than a `GroupBox`, because `GroupBox` does not draw
    /// when the view is rendered to an image — and a UI you cannot see is a UI you cannot review.
    private func section<C: View>(_ title: String?, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.subheadline).bold().foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9)
                    .fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Color.primary.opacity(0.10)))
        }
    }

    /// `GeometryReader` in the background reports the laid-out height of a part whatever the
    /// window's current size; a preference carries it up to `body`.
    private func measured<V: View>(_ part: MeasuredPart, @ViewBuilder _ view: () -> V) -> some View {
        view().background(GeometryReader { proxy in
            Color.clear.preference(key: FittingHeightKey.self,
                                   value: FittingParts(height: proxy.size.height, part: part))
        })
    }

    /// A two-way binding into settings; every control maps its edit to one command.
    private func binding<T>(_ keyPath: KeyPath<Settings, T>,
                            _ command: @escaping (T) -> SettingsCommand) -> Binding<T> {
        Binding(get: { model.settings[keyPath: keyPath] },
                set: { value in model.edit(command(value)) })
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func warning(_ text: String, level: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(level)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 7).fill(level.opacity(0.12)))
    }
}

private enum MeasuredPart { case header, content, footer }

private struct FittingParts: Equatable {
    var header: CGFloat = 0
    var content: CGFloat = 0
    var footer: CGFloat = 0

    init(height: CGFloat = 0, part: MeasuredPart? = nil) {
        guard let part else { return }
        switch part {
        case .header:  header = height
        case .content: content = height
        case .footer:  footer = height
        }
    }

    /// The two 1 pt dividers that sit between the parts.
    var total: CGFloat { header + content + footer + 2 }
}

private struct FittingHeightKey: PreferenceKey {
    static var defaultValue = FittingParts()
    static func reduce(value: inout FittingParts, nextValue: () -> FittingParts) {
        let next = nextValue()
        value.header = max(value.header, next.header)
        value.content = max(value.content, next.content)
        value.footer = max(value.footer, next.footer)
    }
}
