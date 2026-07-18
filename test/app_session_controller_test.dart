import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ispace_timeline/models/course_summary.dart';
import 'package:ispace_timeline/models/portal_account_profile.dart';
import 'package:ispace_timeline/models/recent_course.dart';
import 'package:ispace_timeline/models/timeline_item.dart';
import 'package:ispace_timeline/services/bnbu_mis_client.dart';
import 'package:ispace_timeline/services/credential_store.dart';
import 'package:ispace_timeline/services/deadline_reminder_service.dart';
import 'package:ispace_timeline/services/moodle_api_client.dart';
import 'package:ispace_timeline/services/native_actions.dart';
import 'package:ispace_timeline/state/app_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'successful login persists credentials through CredentialStore',
    () async {
      final store = _MemoryCredentialStore();
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: _OfflineMisClient(),
        credentialStore: store,
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
      );
      addTearDown(controller.dispose);

      await controller.login(username: 'student', password: 'secret');

      expect(controller.isLoggedIn, isTrue);
      expect(store.credentials?.username, 'student');
      expect(store.credentials?.password, 'secret');
    },
  );

  test(
    'restoreSessionIfPossible loads credentials from CredentialStore',
    () async {
      final store = _MemoryCredentialStore(
        const StoredCredentials(username: 'student', password: 'secret'),
      );
      final controller = AppSessionController(
        apiClient: _FakeMoodleApiClient(),
        misClient: _OfflineMisClient(),
        credentialStore: store,
        deadlineReminderService: _FakeDeadlineReminderService(),
        nativeActions: const _FakeNativeActions(),
      );
      addTearDown(controller.dispose);

      await controller.restoreSessionIfPossible();

      expect(controller.isLoggedIn, isTrue);
      expect(controller.username, 'student');
    },
  );

  test('logout clears persisted credentials', () async {
    final store = _MemoryCredentialStore(
      const StoredCredentials(username: 'student', password: 'secret'),
    );
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _OfflineMisClient(),
      credentialStore: store,
    );
    addTearDown(controller.dispose);

    await controller.restoreSessionIfPossible();
    await controller.logout();

    expect(controller.isLoggedIn, isFalse);
    expect(store.credentials, isNull);
  });

  test('logout clears MIS cookies kept in memory', () async {
    final misClient = _OfflineMisClient();
    misClient.storeCookieForTesting(
      Cookie('session', 'secret')..path = '/',
      Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
    );
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: misClient,
      credentialStore: _MemoryCredentialStore(),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.logout();

    expect(
      misClient.cookieHeaderForTesting(
        Uri.parse('https://sso.bnbu.edu.cn/auth/continue'),
      ),
      isEmpty,
    );
  });

  test('logout reports missing native cleanup support', () async {
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _OfflineMisClient(),
      credentialStore: _MemoryCredentialStore(),
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _MissingPluginNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.logout();

    expect(controller.error, contains('部分本地登录数据清理失败'));
  });
}

class _MemoryCredentialStore implements CredentialStore {
  _MemoryCredentialStore([this.credentials]);

  StoredCredentials? credentials;

  @override
  Future<void> clear() async {
    credentials = null;
  }

  @override
  Future<StoredCredentials?> load() async => credentials;

  @override
  Future<void> save(StoredCredentials credentials) async {
    this.credentials = credentials;
  }
}

class _FakeDeadlineReminderService extends DeadlineReminderService {
  @override
  Future<bool> loadEnabled() async => false;

  @override
  Future<void> disable() async {}

  @override
  Future<void> synchronize(List<TimelineItem> items) async {}
}

class _FakeNativeActions extends NativeActions {
  const _FakeNativeActions();

  @override
  Future<void> clearWebSession() async {}
}

class _MissingPluginNativeActions extends NativeActions {
  const _MissingPluginNativeActions();

  @override
  Future<void> clearWebSession() {
    throw MissingPluginException('clearWebSession unavailable');
  }
}

class _FakeMoodleApiClient extends MoodleApiClient {
  _FakeMoodleApiClient() : super(baseUrl: 'https://example.com');

  @override
  Future<AuthSession> loginWithPassword({
    required String username,
    required String password,
  }) async {
    return AuthSession(token: 'token', fullName: username, userId: 1);
  }

  @override
  Future<List<TimelineItem>> fetchAllTimeline({required String token}) async {
    return const [];
  }

  @override
  Future<List<CourseSummary>> fetchMyCourses({
    required String token,
    required int userId,
  }) async {
    return const [];
  }

  @override
  Future<List<RecentCourse>> fetchRecentCourses({
    required String token,
    required int userId,
    int limit = 10,
  }) async {
    return const [];
  }
}

class _OfflineMisClient extends BnbuMisClient {
  @override
  Future<PortalAccountProfile> fetchPortalAccountProfile({
    required String username,
    required String password,
  }) async {
    throw BnbuMisException('offline in tests');
  }
}
