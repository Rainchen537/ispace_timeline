# AGENTS.md

本文件是本仓库的开发与自动化代理规范。修改代码前先阅读本文件；当架构、命令、平台能力或安全约束变化时，同步更新本文件和 `log.md`。

## 项目定位

“掌上BNBU”是面向 BNBU 学生的非官方 Flutter 校园移动客户端。主要能力包括：

- iSpace/Moodle 登录、课程、Timeline、论坛、作业与附件提交；
- BNBU SSO、MIS 课表和统一门户资料；
- BNBU 邮箱的 IMAP/SMTP 收发、搜索和附件处理；
- DDL 本地通知；
- Android/iOS 原生网页、下载、打开文件和分享。

正式支持平台只有 Android 和 iOS。`web/`、`windows/`、`linux/`、`macos/` 是保留的 Flutter 脚手架，不得宣称为已支持平台。

## 工具链

- Flutter：3.32.6 stable，见 `.fvmrc`；
- Dart：3.8.1；
- Java：17，见 `.java-version`；
- Ruby：3.3.6，见 `.ruby-version`；
- Android：compileSdk/targetSdk 35，minSdk 23；
- iOS：最低 12.0；
- CocoaPods：1.16.2。iOS 依赖操作必须使用仓库固定的 Ruby 与 CocoaPods 版本；Ruby 版本会影响本地 podspec 的 `SPEC CHECKSUMS`，不得用其他 Ruby 版本重写 `ios/Podfile.lock`。

优先使用 FVM：

```bash
fvm flutter pub get
fvm flutter run
```

未安装 FVM 时，可以使用与 `.fvmrc` 一致的全局 Flutter。

## 常用命令

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --debug --no-codesign
```

提交前必须执行：

```bash
./tool/check.sh
```

如果某项因本机缺少 SDK、模拟器或签名材料而无法执行，必须在提交说明和 `log.md` 中如实记录，不能把“未执行”写成“已通过”。

## 目录与依赖方向

```text
lib/config/      编译期环境配置
lib/models/      领域模型、DTO 和解析结果
lib/pages/       页面及页面内组件
lib/services/    Moodle、MIS、邮箱、通知、安全存储、原生动作
lib/state/       跨页面会话与业务编排
lib/widgets/     可复用组件和 Platform View 包装
test/            Widget 与单元测试
```

依赖方向应保持为：

```text
pages/widgets -> state/services -> models/config
```

- 页面不要直接实现网络协议或持久化逻辑；
- 新的外部系统访问应放入 `services/`；
- 跨页面状态应由 `AppSessionController` 或明确的新状态对象管理；
- 服务应支持构造器注入，便于无网络测试；
- 大型页面新增功能时优先拆分组件，避免继续扩大已有的超大文件。

## 代码风格

- 遵循 `dart format` 和 `flutter_lints`；
- 文件名使用 `snake_case.dart`；
- 类型使用 `UpperCamelCase`；变量和方法使用 `lowerCamelCase`；
- 私有成员使用 `_` 前缀；
- 导入顺序为 `dart:*`、`package:*`、项目相对导入，各组之间空一行；
- 禁止提交行尾空白、调试输出、生成缓存和本地配置；
- 注释解释“为什么”，不要重复代码已经表达的“做什么”。

## 配置管理

服务端点统一定义在 `lib/config/app_config.dart`，通过 `--dart-define` 或 `--dart-define-from-file` 覆盖。示例：

```bash
cp config/dart_defines.example.json config/dart_defines.local.json
flutter run --dart-define-from-file=config/dart_defines.local.json
```

规则：

- 不得在页面或服务中新增硬编码环境地址；
- 所有携带凭据的 Base URL 必须使用 HTTPS，且不得包含 userinfo、query、fragment 或结尾 `/`；
- `ISPACE_COOKIE_DOMAIN` 和 `BNBU_COOKIE_DOMAIN` 只能配置为学校实际控制的最小可信域边界，禁止使用公共后缀；
- `config/dart_defines.local.json` 不得提交；
- 密码、token、签名口令和私钥不得放入 Dart define、源码、日志或 Git。

## 安全与隐私

- 登录凭据只能通过 `CredentialStore` 保存；凭据记录固定为 `bnbu.credentials.v1` 单 JSON 记录；
- Android 主记录由原生 `EncryptedSharedPreferences` 在工作线程执行 checked `commit()`；不得退回安全敏感写入使用异步 `apply()` 的实现。iOS 主记录使用 Keychain；
- logout 必须先写 durable no-restore tombstone，再撤销内存会话并删除所有凭据副本。Android tombstone 使用独立同步 `SharedPreferences`，iOS 同时使用 `UserDefaults` 和 Keychain；成功保存新主记录后先移除 tombstone，再清理旧副本；
- 旧 combined/split secure record 和原生明文记录采用 secure-first、cleanup-convergent 迁移；清理失败必须可观察并在后续 load 重试，损坏 combined record 禁止降级到旧凭据；
- `AppSessionController` 的 credential mutation、auth generation、共享 logout Future 和 reminder mutation 串行化不得绕过；logout 期间禁止启动新 login，异步结果必须在发布前检查 generation；
- 文件名、URL、HTML、重定向目标和平台通道参数均视为不可信输入；附件/下载必须使用唯一临时文件和原子发布，邮件缓存身份至少包含账号、mailbox、UIDVALIDITY、Message-ID、UID 和 MIME part；
- 所有 `MailClient` 操作必须经过同一串行队列；读取、附件、分页、草稿替换、删除和恢复不得只凭 UID 操作，必须携带并校验 mailbox 与 UIDVALIDITY。邮件详情不得预取完整附件，附件必须按 MIME part 获取并优先复用按完整身份隔离的本地缓存；新草稿的 APPENDUID 结果必须同时保留 UID 和 UIDVALIDITY；
- token 只能发送到其配置来源的同源地址；Cookie 只能发送到明确配置的平台来源，跨来源重定向必须移除 Cookie，HTTPS 下载不得降级到 HTTP；同源重定向中的 Cookie 更新可继续用于后续同源请求；
- Android/iOS 原生下载必须拒绝意外登录 HTML、优先采用响应文件名并清理文件名。Android API 23–28 写公共 Downloads 前请求旧版存储权限，API 29+ 使用 MediaStore；分享缓存必须使用随机目录并执行失败清理和过期清理；
- HTML 邮件默认禁用 JavaScript、持久化 Web 存储、第三方 Cookie 和远程内容；
- 不得记录密码、token、Cookie、邮件正文或其他个人信息；
- 修改数据处理行为时，必须同步更新登录页说明、README 和 `handsbnbu` 隐私政策。

## 测试要求

- 修复缺陷时先增加能够复现问题的测试；
- 新增配置、解析、状态或平台通道包装时增加单元测试；
- 页面交互使用 Widget 测试；
- 网络测试必须使用 fake/mock，不得依赖真实学校账号；
- Android/iOS 通道名称和参数改动时，两端实现及 Dart 测试必须同步更新。

CI 会检查 locked dependency resolution、格式、静态分析、测试、Android debug 构建、Android unsigned-release 门禁和 iOS 无签名构建；lockfile 在解析前快照，最终比较必须使用 `if: always()`，不得因前序失败而跳过。

## 发布要求

发布身份按平台保持现有商店连续性，不得“统一”改写：

```text
Android applicationId: com.example.ispace_timeline
Android namespace:     com.rainchen537.handsbnbu
iOS Bundle ID:         com.example.ispaceTimeline
App Store ID:          6760137657
当前版本:              1.1.1+2026071901
```

Android `namespace` 不是商店身份。Android release 禁止使用 debug 签名。发布前：

```bash
cp android/key.properties.example android/key.properties
# 填入真实上传密钥配置后再执行：
flutter build appbundle --release
```

`android/key.properties`、`.jks`、`.keystore`、`.p12`、`.mobileprovision`、Apple 证书和签名口令均不得提交。Android upload key/Play App Signing lineage 无法从仓库独立证明，正式发布前必须由发布负责人核对现有商店记录；不得生成新密钥冒充既有发布身份。

发布前还必须：

1. 更新 `pubspec.yaml` 的版本号；
2. 执行 `./tool/check.sh`；
3. 在真机验证登录、邮箱附件、课表、DDL 通知和退出登录；
4. 检查隐私政策与实际行为一致；
5. 在 `log.md` 记录版本、验证结果和已知限制。

## 文档与日志

- `README.md` 面向使用者和新开发者；
- `AGENTS.md` 维护工程规范；
- `log.md` 按日期倒序记录重要变更、验证结果、迁移和已知问题；
- 不记录任何凭据、Cookie、token、私钥或个人邮件内容。

## Git 规范

推荐 Conventional Commits：

```text
feat: ...
fix: ...
test: ...
docs: ...
chore: ...
```

提交应保持单一目的。推送前检查 `git diff`、`git status`、`git diff --check`、lockfile 和验证结果；不得提交 `config/dart_defines.local.json`、`android/key.properties`、签名材料、APK、`build/`、`_site/`、`/tmp/ispace-*` 或其他本机缓存和敏感配置。
