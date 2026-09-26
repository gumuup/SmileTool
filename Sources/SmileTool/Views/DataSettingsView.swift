// Adapted from CodeXMicro++ v6.0.0 DataSettingsView; independent SmileTool data only.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DataSettingsView: View {
    @ObservedObject private var manager = SmileDataManager.shared
    @State private var selected: URL?
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                card("本地存储", icon: "externaldrive.fill") {
                    Text("设置与预设优先写入本地 SQLite 数据库；每次提交同时保留配置镜像。无需浏览器存储。")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: manager.problem == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(manager.problem == nil ? .green : .orange)
                        Text(manager.directory.path).font(.callout.monospaced()).textSelection(.enabled).lineLimit(2)
                        Spacer()
                        Button("打开目录") { manager.openDirectory() }
                        Button("选择存储路径") { chooseDirectory() }
                    }
                    if let date = manager.lastSaved { Text("最近成功保存：\(date.formatted(date: .abbreviated, time: .standard))").font(.caption).foregroundStyle(.secondary) }
                    if let selected {
                        Text("所选位置：\(selected.appendingPathComponent("SmileToolData").path)").font(.caption.monospaced()).textSelection(.enabled)
                        HStack {
                            Button("从路径中恢复数据") {
                                confirm("恢复所选路径中的数据？", detail: "当前数据会先自动备份，恢复后需要重新启动。") { try await manager.changeDirectory(selected, restore: true) }
                            }
                            Button("迁移当前数据并设为默认") { run { try await manager.changeDirectory(selected, restore: false) } }
                        }
                    }
                    Text("选择父文件夹后使用独立的 SmileToolData 子目录。已有数据不会被直接覆盖，原路径保留。外置盘离线时显示错误并保留本机待写入副本。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                card("完整备份与导入", icon: "square.and.arrow.up") {
                    Text("ZIP 包含硬件映射、十组预设、音频配置、设备排序、NUT65 写前备份，以及本地素材和压缩原件。导入前验证文件清单、SHA-256 和数据库完整性。")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("导出 ZIP 备份", systemImage: "square.and.arrow.up") { export() }
                        Button("导入 ZIP 备份", systemImage: "square.and.arrow.down") { importArchive() }
                        Spacer()
                        Button("打开自动恢复备份") { manager.openRecovery() }
                    }
                }
                card("数据库高级维护", icon: "wrench.and.screwdriver") {
                    row("检查数据库状态", detail: "只读检查 SQLite、配置格式与镜像一致性。", button: "检查") { run { try await manager.check() } }
                    Divider()
                    row("修复数据一致性", detail: "先保存原数据，再使用有效数据库或镜像修复；不会直接删除无法识别的数据。", button: "修复") {
                        confirm("修复数据存储？", detail: "操作前自动创建恢复备份，完成后需重启。") { try await manager.repair() }
                    }
                    Divider()
                    row("高级重置数据库", detail: "成功创建旧数据备份后才建立空库；旧目录额外保留。", button: "重置") {
                        confirm("重置 SmileTool 数据？", detail: "所有当前设置将恢复默认。旧数据自动保存为 ZIP 和目录副本，完成后需重启；不会改写实体键盘。") { try await manager.reset() }
                    }
                }
                card("数据清理", icon: "trash") {
                    Text("按内容校验识别本地素材库中的完全重复图片，保留一份，将其余副本移入恢复区。不会清理键盘备份、Codex 日志或其他应用数据。")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("检查重复数据", systemImage: "magnifyingglass") { run { try await manager.cleanup(remove: false) } }
                        Button("整理重复数据", systemImage: "archivebox") {
                            confirm("整理重复素材？", detail: "先创建完整 ZIP 备份，再将多余副本移到数据目录的 RecoveredDuplicates。") { try await manager.cleanup(remove: true) }
                        }
                    }
                }
                card("图片压缩", icon: "photo") {
                    Text("仅处理本地素材库 Assets 内的单帧图片，最长边 1080；透明图片使用 PNG，其余使用 HEIC。保留原件，只替换体积更小的结果。应用内设备配图不受影响。")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("添加图片副本…") { addImages() }
                        Button("执行压缩", systemImage: "bolt") {
                            confirm("压缩素材库图片？", detail: "会先创建完整备份，原图另存到 ImageOriginals；压缩副本使用对应的 HEIC / PNG 扩展名。") { try await manager.compress() }
                        }
                    }
                    Text("原件与恢复副本仍占空间，本次不会自动删除。保留备份后再自行归档到其他磁盘。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(24)
        }
        .alert("数据管理", isPresented: Binding(get: { manager.result != nil || error != nil }, set: { if !$0 { manager.result = nil; error = nil } })) {
            Button("知道了") { manager.result = nil; error = nil }
        } message: { Text(error ?? manager.result ?? "") }
    }
    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon).font(.title3.bold()).foregroundStyle(.primary)
            content()
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.07)))
    }
    private func row(_ title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(button, action: action)
        }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { do { try await operation() } catch { self.error = error.localizedDescription } }
    }
    private func confirm(_ title: String, detail: String, operation: @escaping @MainActor () async throws -> Void) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.alertStyle = .warning
        alert.addButton(withTitle: "继续"); alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { run(operation) }
    }
    private func chooseDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.title = "选择 SmileTool 数据的父文件夹"; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { selected = panel.url }
    }
    private func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "SmileTool-Backup-\(Int(Date().timeIntervalSince1970)).zip"
        if panel.runModal() == .OK, let url = panel.url { run { try await manager.backup(to: url) } }
    }
    private func importArchive() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.zip]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            confirm("导入此 ZIP 备份？", detail: "验证通过后才切换数据。现有数据自动备份，导入完成后需要重新启动。") { try await manager.restore(from: url) }
        }
    }
    private func addImages() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { let urls = panel.urls; run { try await manager.importImages(urls) } }
    }
}
