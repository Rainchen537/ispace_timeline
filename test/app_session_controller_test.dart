import 'dart:async';
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

  test('logout revokes memory state before secure cleanup finishes', () async {
    final store = _BlockingClearCredentialStore();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.login(username: 'student', password: 'secret');
    final logoutFuture = controller.logout();
    await store.clearStarted.future;

    expect(controller.isLoggedIn, isFalse);
    expect(controller.username, isNull);
    expect(controller.isLoggingOut, isTrue);

    store.allowClear.complete();
    await logoutFuture;
  });

  test('a login completed after logout cannot restore the session', () async {
    final apiClient = _BlockingLoginMoodleApiClient();
    final store = _MemoryCredentialStore();
    final controller = AppSessionController(
      apiClient: apiClient,
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    final loginFuture = controller.login(
      username: 'student',
      password: 'secret',
    );
    await apiClient.loginStarted.future;
    await controller.logout();
    apiClient.loginResult.complete(
      AuthSession(token: 'late-token', fullName: 'Student', userId: 1),
    );
    await loginFuture;

    expect(controller.isLoggedIn, isFalse);
    expect(store.credentials, isNull);
  });

  test('temporary restore failures preserve saved credentials', () async {
    final store = _MemoryCredentialStore(
      const StoredCredentials(username: 'student', password: 'secret'),
    );
    final controller = AppSessionController(
      apiClient: _FailingLoginMoodleApiClient(
        MoodleApiException('Service unavailable'),
      ),
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.restoreSessionIfPossible();

    expect(controller.isLoggedIn, isFalse);
    expect(store.credentials?.username, 'student');
  });

  test('transient stored login failure can retry on resume', () async {
    final store = _MemoryCredentialStore(
      const StoredCredentials(username: 'student', password: 'secret'),
    );
    final apiClient = _TransientLoginMoodleApiClient();
    final controller = AppSessionController(
      apiClient: apiClient,
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.restoreSessionIfPossible();
    expect(controller.isLoggedIn, isFalse);
    expect(store.credentials?.username, 'student');

    await controller.restoreSessionIfPossible();

    expect(apiClient.loginCount, 2);
    expect(controller.isLoggedIn, isTrue);
  });

  test('invalid stored credentials are removed', () async {
    final store = _MemoryCredentialStore(
      const StoredCredentials(username: 'student', password: 'wrong'),
    );
    final controller = AppSessionController(
      apiClient: _FailingLoginMoodleApiClient(
        MoodleAuthenticationException('Invalid login'),
      ),
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.restoreSessionIfPossible();

    expect(controller.isLoggedIn, isFalse);
    expect(store.credentials, isNull);
  });

  test(
    'logout waits for an in-flight credential load before clearing',
    () async {
      final store = _BlockingLoadCredentialStore(
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

      final restoreFuture = controller.restoreSessionIfPossible();
      await store.loadStarted.future;
      final logoutFuture = controller.logout();
      store.allowLoad.complete();
      await Future.wait([restoreFuture, logoutFuture]);

      expect(controller.isLoggedIn, isFalse);
      expect(store.credentials, isNull);
    },
  );

  test('concurrent logout callers await the same cleanup', () async {
    final store = _BlockingClearCredentialStore();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.login(username: 'student', password: 'secret');
    final first = controller.logout();
    await store.clearStarted.future;
    final second = controller.logout();

    expect(identical(first, second), isTrue);
    store.allowClear.complete();
    await Future.wait([first, second]);
  });

  test('login is rejected while logout cleanup is active', () async {
    final store = _BlockingClearCredentialStore();
    final controller = AppSessionController(
      apiClient: _FakeMoodleApiClient(),
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.login(username: 'student', password: 'secret');
    final logoutFuture = controller.logout();
    await store.clearStarted.future;
    await controller.login(username: 'other', password: 'new-secret');

    expect(controller.isLoggedIn, isFalse);
    expect(controller.error, contains('退出登录处理中'));
    store.allowClear.complete();
    await logoutFuture;
  });

  test('restore retries one transient credential read failure', () async {
    final store = _TransientLoadCredentialStore(
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

    expect(store.loadCount, 2);
    expect(controller.isLoggedIn, isTrue);
  });

  test('invalid credential cleanup failures are surfaced', () async {
    final store = _FailingClearCredentialStore(
      const StoredCredentials(username: 'student', password: 'wrong'),
    );
    final controller = AppSessionController(
      apiClient: _FailingLoginMoodleApiClient(
        MoodleAuthenticationException('Invalid login'),
      ),
      misClient: _OfflineMisClient(),
      credentialStore: store,
      deadlineReminderService: _FakeDeadlineReminderService(),
      nativeActions: const _FakeNativeActions(),
    );
    addTearDown(controller.dispose);

    await controller.restoreSessionIfPossible();

    expect(controller.isLoggedIn, isFalse);
    expect(controller.error, contains('本地登录信息清理失败'));
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

class _BlockingClearCredentialStore extends _MemoryCredentialStore {
  final Completer<void> clearStarted = Completer<void>();
  final Completer<void> allowClear = Completer<void>();

  @override
  Future<void> clear() async {
    clearStarted.complete();
    await allowClear.future;
    await super.clear();
  }
}

class _BlockingLoadCredentialStore extends _MemoryCredentialStore {
  _BlockingLoadCredentialStore(super.credentials);

  final Completer<void> loadStarted = Completer<void>();
  final Completer<void> allowLoad = Completer<void>();

  @override
  Future<StoredCredentials?> load() async {
    loadStarted.complete();
    await allowLoad.future;
    return credentials;
  }
}

class _TransientLoadCredentialStore extends _MemoryCredentialStore {
  _TransientLoadCredentialStore(super.credentials);

  int loadCount = 0;

  @override
  Future<StoredCredentials?> load() async {
    loadCount++;
    if (loadCount == 1) {
      throw PlatformException(code: 'temporary_read_failure');
    }
    return credentials;
  }
}

class _FailingClearCredentialStore extends _MemoryCredentialStore {
  _FailingClearCredentialStore(super.credentials);

  @override
  Future<void> clear() {
    throw PlatformException(code: 'clear_failed');
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

class _BlockingLoginMoodleApiClient extends _FakeMoodleApiClient {
  final Completer<void> loginStarted = Completer<void>();
  final Completer<AuthSession> loginResult = Completer<AuthSession>();

  @override
  Future<AuthSession> loginWithPassword({
    required String username,
    required String password,
  }) async {
    loginStarted.complete();
    return loginResult.future;
  }
}

class _TransientLoginMoodleApiClient extends _FakeMoodleApiClient {
  int loginCount = 0;

  @override
  Future<AuthSession> loginWithPassword({
    required String username,
    required String password,
  }) async {
    loginCount++;
    if (loginCount == 1) {
      throw MoodleApiException('Service unavailable');
    }
    return super.loginWithPassword(username: username, password: password);
  }
}

class _FailingLoginMoodleApiClient extends _FakeMoodleApiClient {
  _FailingLoginMoodleApiClient(this.error);

  final MoodleApiException error;

  @override
  Future<AuthSession> loginWithPassword({
    required String username,
    required String password,
  }) {
    throw error;
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
