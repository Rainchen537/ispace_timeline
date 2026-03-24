import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/timeline_item.dart';

class DeadlineReminderService {
  DeadlineReminderService({
    FlutterLocalNotificationsPlugin? notificationsPlugin,
  }) : _notificationsPlugin =
           notificationsPlugin ?? FlutterLocalNotificationsPlugin();

  static const String _enabledPreferenceKey = 'deadline_reminders.enabled';
  static const String _channelId = 'ddl_reminders';
  static const String _channelName = 'DDL reminders';
  static const String _channelDescription = 'Upcoming iSpace deadline reminders';
  static const int _iosPendingNotificationLimit = 64;
  static const List<_ReminderSpec> _reminderSpecs = <_ReminderSpec>[
    _ReminderSpec(Duration(days: 3), '3 days'),
    _ReminderSpec(Duration(days: 1), '24h'),
    _ReminderSpec(Duration(hours: 12), '12h'),
    _ReminderSpec(Duration(hours: 6), '6h'),
    _ReminderSpec(Duration(hours: 3), '3h'),
    _ReminderSpec(Duration(hours: 1), '1h'),
    _ReminderSpec(Duration(minutes: 30), '30min'),
    _ReminderSpec(Duration(minutes: 15), '15min'),
    _ReminderSpec(Duration(minutes: 5), '5min'),
  ];

  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  Future<void>? _initializationFuture;

  Future<bool> loadEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledPreferenceKey) ?? false;
  }

  Future<String?> enable() async {
    if (kIsWeb) {
      return '当前平台暂不支持 DDL 提醒。';
    }
    await _ensureInitialized();
    final permissionError = await _requestPermissions();
    if (permissionError != null) {
      await _setEnabled(false);
      await cancelAll();
      return permissionError;
    }
    await _setEnabled(true);
    return null;
  }

  Future<void> disable() async {
    await _setEnabled(false);
    await cancelAll();
  }

  Future<void> synchronize(List<TimelineItem> items) async {
    if (!await loadEnabled()) {
      return;
    }
    await _ensureInitialized();
    await _notificationsPlugin.cancelAll();

    final reminders = _buildPendingReminders(items);
    final limit = Platform.isIOS
        ? reminders.length.clamp(0, _iosPendingNotificationLimit)
        : reminders.length;

    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        icon: 'ic_notification',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      ),
    );

    for (final reminder in reminders.take(limit)) {
      await _notificationsPlugin.zonedSchedule(
        id: reminder.id,
        title: reminder.title,
        body: reminder.body,
        scheduledDate: tz.TZDateTime.from(reminder.triggerAt, tz.local),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: reminder.payload,
      );
    }
  }

  Future<void> cancelAll() async {
    await _ensureInitialized();
    await _notificationsPlugin.cancelAll();
  }

  Future<void> _ensureInitialized() {
    return _initializationFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    tz.initializeTimeZones();
    if (!kIsWeb) {
      try {
        final timezone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(timezone.identifier));
      } catch (_) {
        // Keep the default timezone if lookup fails.
      }
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _notificationsPlugin.initialize(settings: settings);

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.max,
    );
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  Future<void> _setEnabled(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledPreferenceKey, value);
  }

  Future<String?> _requestPermissions() async {
    if (Platform.isAndroid) {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final notificationsGranted =
          await androidPlugin?.requestNotificationsPermission();
      if (notificationsGranted == false) {
        return '未授予系统通知权限，DDL 提醒未开启。';
      }
      final exactAlarmGranted =
          await androidPlugin?.requestExactAlarmsPermission();
      if (exactAlarmGranted == false) {
        return '未授予精确提醒权限，DDL 提醒未开启。';
      }
      return null;
    }

    if (Platform.isIOS) {
      final iosPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final granted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: false,
        sound: true,
      );
      if (granted == false) {
        return '未授予系统通知权限，DDL 提醒未开启。';
      }
    }

    return null;
  }

  List<_ScheduledReminder> _buildPendingReminders(List<TimelineItem> items) {
    final now = DateTime.now();
    final reminders = <_ScheduledReminder>[];

    for (final item in items) {
      final due = item.sortTime?.toLocal();
      if (due == null || !due.isAfter(now)) {
        continue;
      }

      for (var index = 0; index < _reminderSpecs.length; index++) {
        final spec = _reminderSpecs[index];
        final triggerAt = due.subtract(spec.offset);
        if (!triggerAt.isAfter(now)) {
          continue;
        }
        reminders.add(
          _ScheduledReminder(
            id: _notificationIdFor(item, index),
            title: item.title.trim().isEmpty ? 'DDL 即将截止' : item.title.trim(),
            body:
                '${_courseLabel(item.courseName)} · ${spec.label} 后截止\n${_formatDue(due)}',
            triggerAt: triggerAt,
            payload: item.url,
          ),
        );
      }
    }

    reminders.sort((left, right) => left.triggerAt.compareTo(right.triggerAt));
    return reminders;
  }

  int _notificationIdFor(TimelineItem item, int specIndex) {
    final source =
        '${item.id}:${item.courseId}:${item.instanceId}:${item.sortTime?.millisecondsSinceEpoch ?? 0}:$specIndex';
    var hash = 0;
    for (final codeUnit in source.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }
    return hash;
  }

  String _courseLabel(String courseName) {
    final normalized = courseName.trim();
    return normalized.isEmpty ? 'iSpace' : normalized;
  }

  String _formatDue(DateTime due) {
    final month = due.month.toString().padLeft(2, '0');
    final day = due.day.toString().padLeft(2, '0');
    final hour = due.hour.toString().padLeft(2, '0');
    final minute = due.minute.toString().padLeft(2, '0');
    return '截止时间 $month-$day $hour:$minute';
  }
}

class _ReminderSpec {
  const _ReminderSpec(this.offset, this.label);

  final Duration offset;
  final String label;
}

class _ScheduledReminder {
  const _ScheduledReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.triggerAt,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final DateTime triggerAt;
  final String payload;
}
