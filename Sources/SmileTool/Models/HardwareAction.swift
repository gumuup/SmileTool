import Foundation

enum HardwareAction: Codable, Hashable, Sendable {
    case unconfigured
    case keyboardShortcut(KeyboardShortcutBinding)
    case application(path: String)
    case systemApplication(path: String)
    case website(url: String)
    case pasteText(String)
    case folder(path: String)
    case shortcut(name: String)

    var kind: HardwareActionKind {
        switch self {
        case .unconfigured: .unconfigured
        case .keyboardShortcut: .keyboardShortcut
        case .application: .application
        case .systemApplication: .systemApplication
        case .website: .website
        case .pasteText: .pasteText
        case .folder: .folder
        case .shortcut: .shortcut
        }
    }

    var summary: String {
        switch self {
        case .unconfigured: "待配置"
        case let .keyboardShortcut(binding): binding.displayName
        case let .application(path): URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        case let .systemApplication(path): URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        case let .website(url): url
        case let .pasteText(text): text.isEmpty ? "尚未填写文本" : text
        case let .folder(path): URL(fileURLWithPath: path).lastPathComponent
        case let .shortcut(name): name
        }
    }

    static func defaultAction(for kind: HardwareActionKind) -> HardwareAction {
        switch kind {
        case .unconfigured: .unconfigured
        case .keyboardShortcut:
            .keyboardShortcut(KeyboardShortcutBinding(keyCode: 49, modifiers: .command, keyLabel: "Space"))
        case .application: .application(path: "")
        case .systemApplication: .systemApplication(path: "")
        case .website: .website(url: "https://")
        case .pasteText: .pasteText("")
        case .folder: .folder(path: "")
        case .shortcut: .shortcut(name: "")
        }
    }
}
enum HardwareActionKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case unconfigured
    case keyboardShortcut
    case application
    case systemApplication
    case website
    case pasteText
    case folder
    case shortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unconfigured: "未设置"
        case .keyboardShortcut: "快捷键"
        case .application: "应用程序"
        case .systemApplication: "系统应用"
        case .website: "网址"
        case .pasteText: "粘贴文本"
        case .folder: "文件夹"
        case .shortcut: "快捷指令"
        }
    }

    var systemImage: String {
        switch self {
        case .unconfigured: "plus"
        case .keyboardShortcut: "keyboard"
        case .application: "app.fill"
        case .systemApplication: "macwindow"
        case .website: "globe"
        case .pasteText: "doc.on.clipboard.fill"
        case .folder: "folder.fill"
        case .shortcut: "square.stack.3d.up.fill"
        }
    }
}
