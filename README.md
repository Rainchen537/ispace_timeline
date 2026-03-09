# iSpace Timeline (Flutter)

一个基础的 iOS/Android Flutter 客户端，支持：

- 底栏五页：`home / life / ispace / schedule / user`
- `user` 页账号登录与会话管理
- `ispace` 页侧边栏（原生功能入口：Dashboard / My Courses / Assignments / Resources）
- `ispace` 页完整 Timeline 交互：
  - 日期筛选：All / Overdue / Next 7 days / Next 30 days / Next 3 months / Next 6 months
  - 排序：Sort by dates / Sort by courses
  - 时间顺序：按时间升序（更近/更早到期的事件在上）
  - 搜索：activity type 或 name
  - 点击事件进入应用内详情页
- Dashboard 搬运补充：
  - iSpace News and Update 区块
  - Recently accessed courses 区块（`core_course_get_recent_courses`）
- 作业类事件详情：
  - 拉取提交状态与评分状态
  - 支持在线文本提交通道（`mod_assign_save_submission`）
  - 若服务端返回 `assign` 记录缺失，自动降级展示，避免页面崩溃

## 关键接口

- 登录换 token：`POST /login/token.php`
  - 参数：`username`, `password`, `service=moodle_mobile_app`
- 获取站点用户信息：`core_webservice_get_site_info`
- 获取我的课程：`core_enrol_get_users_courses`
- 拉取 Timeline：`core_calendar_get_action_events_by_timesort`
  - 参数：`timesortfrom`, `timesortto`, `limitnum`, `aftereventid`
  - 注意：`limitnum` 必须在 `1..50`
- 作业详情与提交：
  - `mod_assign_get_assignments`
  - `mod_assign_get_submission_status`
  - `mod_assign_save_submission`

## 本地运行

```bash
cd /Users/lixingchen/bnbu/ispace_timeline
flutter pub get
flutter run -d ios
# 或
flutter run -d android
```

## 安全说明

- 当前示例不会持久化保存密码，token 仅在内存中保留。
- 开发验证结束后，建议重置账号密码并清理旧 token。
