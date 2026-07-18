# 项目维护日志

按日期倒序记录重要工程变更、迁移、验证结果和已知限制。不得记录密码、token、Cookie、私钥或个人邮件内容。

## 2026-07-19

### 安全与隐私复核

- Moodle Web Cookie 改为按来源、Domain、host-only、Path、Secure、Expires/Max-Age 约束保存和发送，并且 Web session snapshot 只导出与 iSpace Base URL 同源的 Cookie；
- Web session snapshot 和 Android/iOS 原生 Cookie 注入保留 host-only、Secure 和过期时间语义；父域 Cookie 导出到原生 WebView 时会收窄到 iSpace 来源 host，避免扩大可见范围；
- Android 原生 WebView 对 Platform Channel 的 Cookie 列表使用运行时类型过滤，跳过格式错误的元素，避免未检查泛型转换导致原生崩溃；
- Moodle 与 MIS 手动 Cookie jar 只接受来源 host 或显式配置的最小可信 Cookie 域边界内的 Domain，拒绝更宽的公共后缀范围，并且只向配置的可信来源发送 Cookie；
- Moodle Cookie 按名称、Domain 和 Path 替换，避免 host-only 与显式 Domain 版本并存并产生重复旧会话值；
- Moodle `/pluginfile.php` URL 仅在与配置的 iSpace Base URL 同源时附加 token，拒绝向外部 host、不同 scheme 或不同有效端口泄露 token；
- MIS/SSO 手动重定向改为完整同源判断；跨来源 307/308 若会保留请求体则直接拒绝，安全的跨来源重定向会移除 Authorization、Cookie、Referer、Origin 等敏感 header；
- logout 会同步清除 Moodle 与 MIS 内存 Cookie；遇到原生清理插件缺失时按清理未完成处理并显示概括性错误，不再误报为完整成功；
- 文件下载、分享和 HTML 内容继续执行同源凭据限制、内容安全策略、HTTP(S) allowlist 和不可信文件名处理；
- TA 课程及截止时间可见性偏好改为按规范化用户名隔离，旧版设备全局键会删除且不会迁移到当前账号。

### 工程和发布

- GitHub Actions 第三方 action 固定到 immutable commit SHA，并禁止 checkout 持久化仓库凭据；
- Android release 签名门禁改为检查 Gradle task graph，`assemble`、`bundle`、`package`、`sign`、`validateSigning` 及聚合 `build` 无法在缺少 release keystore 时绕过；
- `.gitignore` 补充 Android 直接 Gradle 构建目录，APK、签名文件、本地 dart define 和临时依赖缓存均不纳入版本控制。

### 本地验证

- `flutter analyze`：成功，`No issues found!`；
- `flutter test`：成功，`+56: All tests passed!`；
- Android：通过 `app:assembleDebug`，`BUILD SUCCESSFUL in 8s`；生成的 `build/app/outputs/apk/debug/app-debug.apk` 和 `build/app/outputs/flutter-apk/app-debug.apk` 仅为本地构建产物，未纳入 Git；
- iOS：`flutter build ios --debug --no-codesign` 成功，Xcode 构建耗时 9.2s，生成 `build/ios/iphoneos/Runner.app`；
- Android release 门禁：使用本地依赖缓存执行 `app:build --dry-run`，在缺少 `android/key.properties` 时按预期拒绝执行；
- 隐私政策 Pages 的结构、公开文件 allowlist 和构建目录幂等清理校验连续执行两次成功；
- iPhone 16e 模拟器成功启动应用并显示登录页，系统安全存储、退出清除凭据和非官方客户端说明均正常呈现；未输入真实学校账号；
- 本机 Android Gradle/JVM 对 `dl.google.com`、Maven Central 和 Flutter Storage 存在 TLS handshake 故障；验证时使用仓库外 `/tmp/ispace-*` 临时 Maven/Flutter artifact 缓存完成真实 Kotlin/Android 编译，这些临时文件未纳入 Git；
- 未使用真实学校账号执行 Mail IMAP、真实 HTML 邮件、附件打开、logout 清理及 MIS/Portal SSO 的端到端验证；自动化测试禁止使用真实账号；
- GitHub Actions CI 运行 `29658287590` 成功：格式、静态分析、测试、Android debug APK 和 iOS 无签名构建均通过；
- 隐私政策 Pages 工作流运行 `29658323587` 成功，仓库继续使用 GitHub Actions 发布并强制 HTTPS；已验证公开地址 `https://rainchen537.github.io/handsbnbu/` 返回本次更新内容。

### 已知限制

- 正式支持平台仍仅为 Android 和 iOS；桌面端和 Web 目录只是保留脚手架；
- 正式 Android 发布仍需要仓库外的上传密钥；iOS 发布仍需要有效的 Apple 签名配置；
- 学校平台接口和页面结构变化可能导致登录或解析功能失效。

## 2026-07-18

### 安全与隐私

- 使用 `flutter_secure_storage` 保存登录凭据：Android 使用加密存储，iOS 使用 Keychain；
- 原生 `SharedPreferences`/`UserDefaults` 旧凭据采用非破坏性迁移：先成功写入系统安全存储，再清除旧存储；
- 退出登录同时清理安全存储和旧版遗留存储；
- 登录页改为准确说明本地安全存储行为，并标注应用为非官方客户端；
- 邮件附件文件名增加路径穿越和非法字符清理。

### 配置与平台

- 新增 `AppConfig`，支持使用 `--dart-define-from-file` 覆盖 iSpace、SSO、MIS、门户和邮箱服务器；
- 新增 `config/dart_defines.example.json`，本地覆盖文件被 Git 忽略；
- Android/iOS/macOS/Linux 标识统一为 `com.rainchen537.handsbnbu`；
- Android release 不再使用 debug 签名，新增 `android/key.properties.example`；
- Android 固定 Java 17、compileSdk/targetSdk 35、minSdk 23；
- iOS 补齐邮件附件缓存目录和打开文件的原生通道实现；
- Android 原生 WebView 不再硬编码 iSpace Cookie 域名。

### 工程质量

- 固定 Flutter 3.32.6 stable 和 Java 17；
- 新增 `.editorconfig`、`tool/check.sh` 和 GitHub Actions CI；
- CI 检查格式、静态分析、测试、Android debug 构建和 iOS 无签名构建；
- 新增环境配置、会话凭据存储契约和原生附件通道测试；
- 新增 `AGENTS.md`，统一目录、编码、安全、测试、发布和日志规范；
- 更新 README 和各平台应用元数据。
