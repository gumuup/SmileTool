# SmileTool 1.0.0 验证记录

- 平台：macOS 26.3.1 / Apple Silicon，最低运行版本 macOS 14。
- `swift test`：44 项执行通过，4 项依赖实体音频设备及显式环境变量的用例跳过。
- `./scripts/build-app.sh`：release 构建通过，生成 arm64 应用包。
- `codesign --verify --deep --strict`：通过，ad-hoc 签名，未经 Apple 公证。
- 原生窗口：已启动并通过 UI 工具读取；设备列表、映射、十组预设、设备产品图、顶部导航和底栏均可见，已截图检查默认设备工作台。
- 修复启动阻塞：采样定位到主线程 `IOBluetoothDevice.pairedDevices()` 阻塞；移除该同步查询后重新启动，窗口可读取。
- 未执行实体键盘板载写入、设备映射触发或实际音频播放/收音。本次 UI 验证没有启用硬件映射或授予系统权限。
- 原工程的 `git status --short` 为空，未做修改。
