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
- Android：compileSdk/targetSdk 35，minSdk 23；
- iOS：最低 12.0；
- CocoaPods：以 `ios/Podfile.lock` 中记录的版本为准，当前为 1.16.2。

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
- Base URL 不带结尾 `/`；
- `ISPACE_COOKIE_DOMAIN` 和 `BNBU_COOKIE_DOMAIN` 只能配置为学校实际控制的最小可信域边界，禁止使用公共后缀；
- `config/dart_defines.local.json` 不得提交；
- 密码、token、签名口令和私钥不得放入 Dart define、源码、日志或 Git。

## 安全与隐私

- 登录凭据只能通过 `CredentialStore` 保存到系统安全存储；
- Android 使用 `flutter_secure_storage` 的加密存储，iOS 使用 Keychain；
- 原生 `SharedPreferences`/`UserDefaults` 通道只允许迁移和清除旧版本遗留凭据，禁止重新写入密码；
- 退出登录必须等待持久化凭据、通知和 Web 会话清理完成；
- 文件名、URL、HTML 和平台通道参数均视为不可信输入；
- token 只能发送到其配置来源的同源地址；Cookie 只能发送到明确配置的平台来源，父域 Cookie 只能在配置的最小可信域边界内共享；禁止向其他外部 URL 装饰或转发凭据；
- HTML 邮件默认禁用 JavaScript、持久化 Web 存储、第三方 Cookie 和远程内容；
- 不得记录密码、token、Cookie、邮件正文或其他个人信息；
- 修改数据处理行为时，必须同步更新登录页说明、README 和 `handsbnbu` 隐私政策。

## 测试要求

- 修复缺陷时先增加能够复现问题的测试；
- 新增配置、解析、状态或平台通道包装时增加单元测试；
- 页面交互使用 Widget 测试；
- 网络测试必须使用 fake/mock，不得依赖真实学校账号；
- Android/iOS 通道名称和参数改动时，两端实现及 Dart 测试必须同步更新。

CI 会检查格式、静态分析、测试、Android debug 构建和 iOS 无签名构建。

## 发布要求

应用标识统一为：

```text
com.rainchen537.handsbnbu
```

Android release 禁止使用 debug 签名。发布前：

```bash
cp android/key.properties.example android/key.properties
# 填入真实上传密钥配置后再执行：
flutter build appbundle --release
```

`android/key.properties`、`.jks`、`.keystore`、Apple 证书和 Provisioning Profile 均不得提交。

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

提交应保持单一目的。推送前检查 `git diff`、`git status` 和测试结果，不得提交构建产物、本机路径或敏感配置。
