# 项目维护日志

按日期倒序记录重要工程变更、迁移、验证结果和已知限制。不得记录密码、token、Cookie、私钥或个人邮件内容。

## 2026-07-19

### 安全与隐私复核

- 登录凭据改为 `bnbu.credentials.v1` 单 JSON 记录；Android 使用原生 `EncryptedSharedPreferences` 在工作线程执行 checked `commit()`，同时兼容并收敛清理旧 `flutter_secure_storage` combined/split key 和原生明文记录；
- logout 在清理前写 durable no-restore tombstone：Android 使用独立同步 `SharedPreferences`，iOS 同时使用 `UserDefaults` 和 Keychain；新登录在主记录持久化后先清除 tombstone，再清理旧副本，避免 cleanup failure 删除下一次启动的有效登录；
- 凭据迁移损坏、写入、读取和清理失败不再折叠为“无凭据”；启动恢复增加 bounded retry，并在应用恢复前台时允许重试；明确 `invalidlogin` 才删除凭据；
- login、restore、relogin、refresh、详情请求和 Web session 统一使用 auth generation；并发 logout 共享同一 Future，logout 期间拒绝新 login，并在第一次 await 前撤销内存会话；
- 提醒 enable/disable/synchronize/cancel 和邮件连接安装使用独立 mutation/generation 防止 logout/close 后旧异步结果重新发布；
- 所有携带凭据的 Base URL 强制为无 userinfo、query、fragment 和结尾 `/` 的 HTTPS，拒绝裸 `?`、裸 `#` 和空 userinfo；
- Moodle Web Cookie 改为按来源、Domain、host-only、Path、Secure、Expires/Max-Age 约束保存和发送，并且 Web session snapshot 只导出与 iSpace Base URL 同源的 Cookie；
- Web session snapshot 和 Android/iOS 原生 Cookie 注入保留 host-only、Secure 和过期时间语义；父域 Cookie 导出到原生 WebView 时会收窄到 iSpace 来源 host，避免扩大可见范围；
- Android 原生 WebView 对 Platform Channel 的 Cookie 列表使用运行时类型过滤，跳过格式错误的元素，避免未检查泛型转换导致原生崩溃；
- Moodle 与 MIS 手动 Cookie jar 只接受来源 host 或显式配置的最小可信 Cookie 域边界内的 Domain，拒绝更宽的公共后缀范围，并且只向配置的可信来源发送 Cookie；
- Moodle Cookie 按名称、Domain 和 Path 替换，避免 host-only 与显式 Domain 版本并存并产生重复旧会话值；
- Moodle `/pluginfile.php` URL 仅在与配置的 iSpace Base URL 同源时附加 token，拒绝向外部 host、不同 scheme 或不同有效端口泄露 token；
- MIS/SSO 手动重定向改为完整同源判断；跨来源 307/308 若会保留请求体则直接拒绝，安全的跨来源重定向会移除 Authorization、Cookie、Referer、Origin 等敏感 header；
- logout 会同步清除 Moodle 与 MIS 内存 Cookie；遇到原生清理插件缺失时按清理未完成处理并显示概括性错误，不再误报为完整成功；
- Android 原生下载统一使用受控 `HttpURLConnection` 重定向：API 29+ 通过 MediaStore 原子发布到公共 Downloads，API 23–28 在取得旧版存储权限后通过唯一 `.partial` 文件发布到公共 Downloads；
- Android/iOS 原生下载仅在 Cookie origin 同源时发送 Cookie，跨来源重定向移除 Cookie，并拒绝 HTTPS 降级；同源 `Set-Cookie` 更新可用于后续同源跳转，文件名优先来自响应元数据并按 UTF-8 字节限制过滤路径与控制字符，意外登录 HTML 不会保存为目标文件；
- Android/iOS 分享文件使用独立 UUID 缓存目录；iOS 在分享完成、取消或失败后清理，Android 清理失败任务并在后续分享时删除超过 24 小时的旧缓存；
- 所有 `MailClient` 操作经同一队列串行执行；邮件附件缓存身份包含账号、mailbox、UIDVALIDITY、Message-ID、UID 和 MIME part，读取、附件、分页、删除、恢复和草稿替换校验 mailbox epoch，新草稿同时保存 APPENDUID 返回的 UID 与 UIDVALIDITY；附件写入使用唯一 `.partial` 文件后原子 rename；
- TA 课程及截止时间可见性偏好改为按规范化用户名隔离，旧版设备全局键会删除且不会迁移到当前账号。

### 工程和发布

- 发布身份恢复为历史连续值：Android `applicationId` 为 `com.example.ispace_timeline`、代码 `namespace` 为 `com.rainchen537.handsbnbu`；iOS Bundle ID 为 `com.example.ispaceTimeline`，对应 App Store ID `6760137657`；版本更新为 `1.1.1+2026071901`；
- Google Play/upload signing lineage 无法从仓库和公开资料独立验证，正式发布前仍需发布负责人核对现有证书与 Play App Signing 记录；
- GitHub Actions 第三方 action 固定到 immutable commit SHA，并禁止 checkout 持久化仓库凭据；locked dependency resolution、Android unsigned release gate、CocoaPods 1.16.2 和 lockfile stability 均纳入 CI；Android/iOS job 会在解析前快照 lockfile，并通过 `if: always()` 在前序失败后仍执行比较；
- Android release 签名门禁改为检查 Gradle task graph，`assemble`、`bundle`、`package`、`sign`、`validateSigning` 及聚合 `build` 无法在缺少 release keystore 时绕过；
- `tool/check.sh` 在执行前后比较 lockfile 快照，不再把已有的有意 lockfile 修改误判为依赖解析漂移；
- `.gitignore` 补充 Android 直接 Gradle 构建目录，APK、签名文件、本地 dart define 和临时依赖缓存均不纳入版本控制。

### 本地验证

- `dart format lib test`：成功，46 个 Dart 文件均符合格式；
- 邮箱串行化、UIDVALIDITY 与配置校验增量完成后，`flutter analyze` 为 `No issues found!`，完整 `flutter test` 为 `+81: All tests passed!`；随后增加的严格草稿 APPENDUID 身份传递已由最终 Android/iOS 编译覆盖，最终测试结果以本次推送后的 GitHub Actions 为准；
- Android：最终工作树执行 `flutter build apk --debug` 成功，Gradle `assembleDebug` 耗时 7.8s；生成 APK 仅为本地构建产物，未纳入 Git；
- iOS：最终工作树执行 `flutter build ios --debug --no-codesign` 成功，Xcode 构建耗时 10.5s；`flutter build ios --simulator --debug` 也成功，最终耗时 13.8s；
- Android release 门禁：执行 release 构建时在缺少 `android/key.properties` 的环境按预期以 `Release signing is not configured` 和退出码 1 拒绝构建；
- iPhone 16e（iOS 26.2）模拟器成功安装并启动最终构建，登录页、安全存储/退出清除凭据说明和非官方客户端说明正常显示；截图证据仅保存在仓库外且未纳入 Git；
- 未使用真实学校账号执行 Mail IMAP、真实 HTML 邮件、附件打开、认证下载、logout 清理及 MIS/Portal SSO 的端到端验证；自动化测试禁止使用真实账号；
- 此前 GitHub Actions CI 运行 `29658287590` 和隐私政策 Pages 工作流 `29658323587` 已成功；它们早于本次最终安全增量，当前提交的 CI 和 Pages 结果将在推送后补记。

### 已知限制

- 正式支持平台仍仅为 Android 和 iOS；桌面端和 Web 目录只是保留脚手架；
- 正式 Android 发布仍需要仓库外的原上传密钥并确认 Play App Signing lineage；iOS 发布仍需要有效的 Apple 签名配置；
- Android API 23–28 将下载写入公共 Downloads 时依赖用户授予旧版存储权限；拒绝权限时下载会失败并返回明确错误；
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
- 当日曾尝试把 Android/iOS/macOS/Linux 标识统一为 `com.rainchen537.handsbnbu`；该变更后来被确认会破坏商店更新连续性，并已在 2026-07-19 恢复为平台原有发布身份；
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
