# 掌上BNBU

面向 BNBU 学生的**非官方** Flutter 校园移动客户端，整合 iSpace/Moodle、学校邮箱、MIS 课表、统一门户资料和 DDL 本地提醒。

> 本项目不是 BNBU 官方应用。学校平台接口、页面结构或服务策略变化可能影响部分功能。

## 功能

底部导航包含：

- `home`：首页，当前仍在建设中；
- `mail`：学校邮箱收取、搜索、发送、草稿、删除、恢复和附件处理；
- `ispace`：Timeline、课程、作业、论坛、文件与网页镜像；
- `schedule`：MIS 课表、本地 TA 课程和 iSpace DDL；
- `user`：门户资料、通知设置和会话管理。

主要能力：

- iSpace/Moodle 用户名密码登录与 token 自动刷新；
- Timeline 日期筛选、排序、搜索和详情；
- 课程内容、论坛讨论、在线文本和附件作业提交；
- BNBU SSO、MIS 课表和统一门户资料；
- 腾讯企业邮箱 IMAP/SMTP 收发与附件下载；
- Android/iOS DDL 本地通知；
- Android WebView / iOS WKWebView 原生网页镜像；
- 下载、打开外部链接、打开文件和系统分享。

## 支持平台

| 平台 | 状态 |
|---|---|
| Android | 正式支持，minSdk 23、targetSdk 35 |
| iOS | 正式支持，最低 iOS 12.0 |
| Web / Windows / Linux / macOS | 仅保留 Flutter 脚手架，当前不受支持 |

## 工具链

- Flutter 3.32.6 stable，见 `.fvmrc`；
- Dart 3.8.1；
- Java 17，见 `.java-version`；
- CocoaPods 1.16.2；
- Android SDK 35。

推荐安装 [FVM](https://fvm.app/) 并执行：

```bash
fvm install
fvm flutter pub get
fvm flutter run
```

也可以使用版本一致的全局 Flutter：

```bash
flutter pub get
flutter run
```

## 环境配置

生产端点集中定义在 `lib/config/app_config.dart`。默认配置可以直接运行；如需覆盖端点：

```bash
cp config/dart_defines.example.json config/dart_defines.local.json
flutter run --dart-define-from-file=config/dart_defines.local.json
```

本地配置不会提交到 Git。Base URL 请勿添加结尾 `/`。`ISPACE_COOKIE_DOMAIN` 和 `BNBU_COOKIE_DOMAIN` 是允许接收父域 Cookie 的最小可信边界，必须填写学校实际控制的域名，禁止填写 `com`、`cn`、`edu.cn` 等公共后缀。不要把密码、token、Cookie 或签名材料写入 Dart define 文件。

支持的配置键：

- `APP_ENV`
- `ISPACE_BASE_URL`
- `ISPACE_COOKIE_DOMAIN`
- `BNBU_SSO_BASE_URL`
- `BNBU_MIS_BASE_URL`
- `BNBU_PORTAL_BASE_URL`
- `BNBU_COOKIE_DOMAIN`
- `BNBU_MIS_SERVICE_ID`
- `BNBU_PORTAL_SERVICE_ID`
- `BNBU_MAIL_IMAP_HOST`
- `BNBU_MAIL_SMTP_HOST`
- `BNBU_MAIL_WEB_BASE_URL`

## 安全说明

- 用户名和密码只用于登录 iSpace、BNBU SSO/MIS/门户和学校邮箱；
- 凭据会保存在设备系统安全存储中，以便恢复登录：Android 使用加密存储，iOS 使用 Keychain；
- 同一应用标识下，旧版本保存在 `SharedPreferences`/`UserDefaults` 的凭据会先写入安全存储，再从旧存储清除；更换应用标识后无法跨应用沙盒迁移；
- token 仅发送到对应学校平台的同源地址；Cookie 只发送到明确配置的平台来源，父域 Cookie 仅在配置的最小可信域边界内共享，不会写入项目日志或转发到外部站点；
- HTML 邮件默认阻止脚本、表单和远程资源，用户点击的 HTTP(S) 链接交给系统浏览器打开；
- 退出登录会等待持久化凭据、通知和当前 Web 会话完成清理；iOS Keychain 数据可能在卸载后保留，重新安装后应主动退出登录以清除；
- 项目不集成广告或第三方用户追踪 SDK。

公开隐私政策由独立仓库维护：

- <https://github.com/Rainchen537/handsbnbu>

## 目录

```text
lib/config/      编译期环境配置
lib/models/      数据模型和解析结果
lib/pages/       页面
lib/services/    Moodle、MIS、邮箱、通知、安全存储和原生动作
lib/state/       全局会话与业务编排
lib/widgets/     可复用组件和 Platform View 包装
test/            Widget 与单元测试
android/         Android Gradle/Kotlin 实现
ios/             iOS CocoaPods/Swift 实现
```

完整开发规范见 [`AGENTS.md`](AGENTS.md)，维护记录见 [`log.md`](log.md)。

## 质量检查

提交前运行：

```bash
./tool/check.sh
```

等价的主要命令：

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --debug --no-codesign
```

GitHub Actions 会在 push 和 pull request 上执行格式、分析、测试、Android debug 构建和 iOS 无签名构建。

## Android 发布签名

应用标识：

```text
com.rainchen537.handsbnbu
```

release 构建禁止使用 debug 签名。先准备上传密钥，然后：

```bash
cp android/key.properties.example android/key.properties
# 填写真实的 storePassword、keyPassword、keyAlias 和 storeFile
flutter build appbundle --release
```

`android/key.properties`、`.jks` 和 `.keystore` 已被 Git 忽略。密钥丢失可能导致无法更新已发布应用，请在仓库外安全备份。

## iOS 发布

在 Xcode 中为 `Runner` 配置正确的 Apple Developer Team、Bundle ID 和 Provisioning Profile，然后执行：

```bash
flutter build ipa --release
```

仓库不会包含 Apple 证书或签名私钥。

## 主要学校接口

- iSpace：`POST /login/token.php`
- Moodle Web Service：
  - `core_webservice_get_site_info`
  - `core_enrol_get_users_courses`
  - `core_calendar_get_action_events_by_timesort`
  - `core_course_get_contents`
  - `mod_assign_get_assignments`
  - `mod_assign_get_submission_status`
  - `mod_assign_save_submission`
  - `mod_forum_get_forums_by_courses`
  - `mod_forum_get_forum_discussions_paginated`
  - `mod_forum_get_discussion_posts`
- BNBU SSO/MIS/Portal：由 `BnbuMisClient` 访问并解析；
- 学校邮箱：腾讯企业邮箱 IMAP/SMTP。

## 反馈

应用内问题反馈邮箱：`v530026091@mail.bnbu.edu.cn`。
