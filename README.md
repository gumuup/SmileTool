# SmileTool 1.1.1

独立的 macOS 硬件配置工具，从 [CodeXMicro++ v6.0.0](https://github.com/gumuup/CodeXMicro-Plus/releases/tag/v6.0.0) 提取。

本项目以 [MIT 许可证](LICENSE) 开源。第三方代码和设备图片的来源及原许可证保留在 `ThirdParty/`；仓库不包含本机用户配置、备份、构建产物或系统授权数据。

## 使用

打开 `dist/SmileTool.app`。需要 macOS 14 或更新版本；当前本机构建为 Apple Silicon。

- **设备工作台**：MX Master 3S、DJI Mic Mini 2、NUT65、Chromecast Voice Remote、X6 Remote。设备卡片可拖动排序。
- **按键配置**：每种遥控器/鼠标独立保存 10 组预设，支持快捷键、应用、网址、文本、文件夹、macOS 快捷指令；支持按下/松开动作、按住释放、监听实体按键定位。
- **NUT65**：通过 USB 读取完整键盘层，单键写前备份、写后回读，以及实际按键测试。默认选择 Mac 层。
- **音频与语音**：系统输入输出、音量与静音、输入测试、混音、遥控器麦克风、X6 微信输入法联动及诊断。
- **数据管理**：自选本地目录、SQLite 事务保存、完整 ZIP 导入导出、数据库检查修复、可恢复重置、重复素材整理及保留原件的图片压缩。
- **系统权限**：按需前往 macOS 授予辅助功能、输入监控、麦克风、蓝牙权限。
- **菜单栏入口**：关掉窗口后仍可通过菜单栏笑脸重新打开；退出应用才会停止设备服务。

设备映射默认关闭。请先连接设备，再开启对应映射。使用同一设备时，应关闭其他软件的对应映射，避免重复处理事件。NUT65 板载改键在硬件页显式操作，不会在启动时自动写入。

DJI 蓝牙音频连接和 USB 按键连接分别显示；仅连接键单击可配置，其余按键行为由固件处理。遥控器语音需要已安装的虚拟音频设备，SmileTool 不安装驱动。

## 独立数据

应用标识：`com.gumu.smiletool`。偏好设置保存在 SmileTool 自己的 macOS 偏好域，不导入或修改 CodeXMicro++ 的配置。

默认数据目录：`~/Library/Application Support/SmileTool/Data/`。

NUT65 备份随数据目录保存到 `NUT65/Backups/`；首次启动复制旧版 `~/Library/Application Support/SmileTool/NUT65/Backups/` 中的文件，保留原件。

恢复 ZIP：`~/Library/Application Support/SmileTool/Recovery/`；未完成写入的应急设置：`~/Library/Application Support/SmileTool/Pending/`。这两个目录独立于可移动的主数据目录。

数据管理细节与边界见 [DATA.md](DATA.md)。

已移除 Codex 任务管理、悬浮键盘、轮盘、剪贴板侧栏及 Codex 专用动作。通用硬件动作使用独立执行器，不读取 Codex 日志或任务数据库。

## 开发与打包

```sh
swift build
swift test
./scripts/build-app.sh
open dist/SmileTool.app
```

一键构建并启动：`./script/build_and_run.sh`；启动进程核验：`./script/build_and_run.sh --verify`。Codex 项目的 Run 按钮使用同一入口。

真实素材端到端回归：`./scripts/e2e-real-assets.sh`。该脚本使用仓库内五张设备产品图片，验证 SQLite 设置保存、完整 ZIP 导出与恢复、图片字节一致性、应用打包资源和 macOS 应用启动。全部素材均为随项目公开的设备配图；不会读取个人数据目录，也不会修改实体硬件。需要实体音频设备的可选测试开关见 `.env.example`，默认关闭。

建议运行打包的 `.app`，以获得完整产品图片和正确的权限身份。`swift run SmileTool` 可用于代码调试，但不包含应用包内图片。

打包脚本生成本机架构版本，使用 ad-hoc 签名，未进行 Apple 公证；适合本机预览与开发。

## 来源与验证

上游标签：`v6.0.0`，提交：`3a104608a1682e036c868a211d457a38531376cc`。

保留上游硬件协议、设备适配、NUT65 备份与回读，以及音频实现。相关原始说明在 `docs/upstream/`，其中原产品导航和历史验证记录仅供参考。授权与第三方声明见 `LICENSE`、`ThirdParty/`。

测试套件包含 58 项用例，本次 54 项通过、4 项按条件跳过；4 项实体音频测试默认跳过，需真实设备和麦克风权限后显式启用。程序测试不能代替每款实体设备的按键、板载写入和收音验收。

本次启动修复：移除主线程上的 IOBluetooth 配对列表同步查询，改用后台系统蓝牙报告，避免新应用权限初始化阻塞窗口。蓝牙电量缺失时保留有效缓存或显示未知。

监听状态检查（1.1.1）：设备页会显示 HID 打开失败和系统已识别但监听通道未就绪的状态；DJI、Chromecast、MX 在打开失败后自动重试。授权和实体设备验收需在目标 Mac 单独完成，详见 `docs/verification/LISTENING-1.1.1.md`。
