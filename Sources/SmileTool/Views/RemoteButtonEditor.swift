import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RemoteButtonEditor: View {
    let remote: SupportedRemoteID
    let button: RemoteButtonDefinition
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RemoteButtonMapping
    @State private var nativeDefault: Bool
    @State private var releaseSelected = false
    @State private var recording = false
    private let hardware = RemoteMappingStore.shared
    init(remote: SupportedRemoteID, button: RemoteButtonDefinition) {
        self.remote = remote; self.button = button
        _draft = State(initialValue: RemoteMappingStore.shared.mapping(remote, button.id) ?? .init(action: .unconfigured))
        _nativeDefault = State(initialValue: RemoteMappingStore.shared.mapping(remote, button.id) == nil)
    }
    private var action: Binding<HardwareAction> {
        Binding(get: { releaseSelected ? draft.releaseAction : draft.action }, set: {
            nativeDefault = false
            if releaseSelected { draft.releaseAction = $0 } else { draft.action = $0 }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Image(systemName: button.symbol).font(.title).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(button.title).font(.title2.bold())
                    Text(remote.title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if remote != .djiMicMini2 {
                Picker("触发时机", selection: $releaseSelected) {
                    Text("按下时").tag(false); Text("松开时").tag(true)
                }.pickerStyle(.segmented).disabled(recording)
            }
            Toggle("保留设备默认功能", isOn: $nativeDefault).disabled(recording)
            if !nativeDefault {
                Picker("操作类型", selection: Binding(get: { action.wrappedValue.kind }, set: { action.wrappedValue = .defaultAction(for: $0) })) {
                    ForEach(HardwareActionKind.allCases) { kind in Text(kind.title).tag(kind) }
                }.disabled(recording)
                actionFields
                if !releaseSelected, remote != .djiMicMini2, case .keyboardShortcut = draft.action {
                    Toggle("持续按住，直到实体按键松开", isOn: $draft.holdShortcut)
                }
            } else {
                Label("此按键使用设备的原生行为。", systemImage: "arrow.uturn.backward").foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("编辑期间暂停设备映射。保存只影响当前设备的当前预设。").font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("恢复此键默认") { nativeDefault = true; recording = false }
                Spacer()
                Button("保存映射") { hardware.setMapping(nativeDefault ? nil : draft, remote: remote, button: button.id); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(recording || !valid)
            }
        }.padding(28).frame(width: 540, height: 440)
        .background(ShortcutCapture(active: $recording) { action.wrappedValue = .keyboardShortcut($0) }.frame(width: 0, height: 0))
        .onAppear { hardware.cancelLearning(); for device in SupportedRemoteID.allCases { hardware.releaseAll(for: device) }; hardware.editing = true }
        .onDisappear { recording = false; hardware.editing = false }
    }
    @ViewBuilder private var actionFields: some View {
        switch action.wrappedValue {
        case let .keyboardShortcut(binding):
            Button { recording.toggle() } label: {
                HStack {
                    Image(systemName: "keyboard")
                    Text(recording ? "请按下按键或组合键…" : binding.displayName).font(.title3.monospaced())
                    Spacer()
                    Text(recording ? "点击取消" : "点击录制").font(.caption)
                }.padding(18).frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
        case .unconfigured: Text("按键触发时不执行操作。").foregroundStyle(.secondary)
        default:
            TextField(placeholder, text: Binding(get: { textValue }, set: { setText($0) }), axis: .vertical)
                .lineLimit(1...5).textFieldStyle(.roundedBorder)
            if [.application, .systemApplication, .folder].contains(action.wrappedValue.kind) {
                Button("浏览…") { browse() }
            }
        }
    }
    private var textValue: String {
        switch action.wrappedValue {
        case let .application(value), let .systemApplication(value), let .folder(value), let .website(value), let .pasteText(value), let .shortcut(value): value
        default: ""
        }
    }
    private var placeholder: String {
        switch action.wrappedValue.kind {
        case .website: "https://example.com"
        case .shortcut: "macOS 快捷指令名称"
        case .pasteText: "输入要发送的文本"
        default: "选择路径"
        }
    }
    private var valid: Bool {
        if nativeDefault { return true }
        switch action.wrappedValue {
        case .unconfigured, .keyboardShortcut: return true
        case let .website(value): return URL(string: value).map { ["http", "https"].contains($0.scheme ?? "") && $0.host != nil } ?? false
        default: return !textValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    private func setText(_ value: String) {
        switch action.wrappedValue.kind {
        case .application: action.wrappedValue = .application(path: value)
        case .systemApplication: action.wrappedValue = .systemApplication(path: value)
        case .website: action.wrappedValue = .website(url: value)
        case .folder: action.wrappedValue = .folder(path: value)
        case .pasteText: action.wrappedValue = .pasteText(value)
        case .shortcut: action.wrappedValue = .shortcut(name: value)
        default: break
        }
    }
    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = action.wrappedValue.kind == .folder
        panel.canChooseFiles = !panel.canChooseDirectories
        panel.allowsMultipleSelection = false
        if panel.canChooseFiles { panel.allowedContentTypes = [.applicationBundle] }
        panel.begin { response in if response == .OK, let url = panel.url { setText(url.path) } }
    }
}

private struct ShortcutCapture: NSViewRepresentable {
    @Binding var active: Bool
    var onCapture: (KeyboardShortcutBinding) -> Void
    func makeNSView(context: Context) -> CaptureView { CaptureView() }
    func updateNSView(_ view: CaptureView, context: Context) {
        view.onCapture = { binding in onCapture(binding); active = false }
        view.setActive(active)
    }
    static func dismantleNSView(_ view: CaptureView, coordinator: ()) { view.setActive(false) }
    @MainActor final class CaptureView: NSView {
        var onCapture: ((KeyboardShortcutBinding) -> Void)?
        private var monitor: Any?
        private var modifier: UInt16?
        func setActive(_ active: Bool) {
            if !active { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; modifier = nil; return }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                guard let self else { return event }
                if event.type == .keyDown {
                    self.onCapture?(.init(keyCode: event.keyCode, modifiers: .init(eventFlagsRawValue: UInt64(event.modifierFlags.rawValue)), keyLabel: ShortcutKeyCatalog.label(for: event.keyCode) ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"))
                } else if event.type == .flagsChanged {
                    if self.modifier == event.keyCode {
                        self.onCapture?(.init(keyCode: event.keyCode, modifiers: [], keyLabel: ShortcutKeyCatalog.label(for: event.keyCode) ?? "修饰键"))
                    } else { self.modifier = event.keyCode }
                }
                return nil
            }
        }
    }
}
