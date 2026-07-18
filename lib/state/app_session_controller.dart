import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/course_content.dart';
import '../models/course_summary.dart';
import '../models/mail_models.dart';
import '../models/portal_account_profile.dart';
import '../models/recent_course.dart';
import '../models/timetable_data.dart';
import '../models/timeline_detail_data.dart';
import '../models/timeline_item.dart';
import '../models/upload_file_payload.dart';
import '../models/web_session_snapshot.dart';
import '../services/bnbu_mis_client.dart';
import '../services/credential_store.dart';
import '../services/deadline_reminder_service.dart';
import '../services/moodle_api_client.dart';
import '../services/native_actions.dart';

enum _LoginOutcome { succeeded, permanentFailure, transientFailure, cancelled }

class AppSessionController extends ChangeNotifier {
  AppSessionController({
    MoodleApiClient? apiClient,
    BnbuMisClient? misClient,
    CredentialStore? credentialStore,
    DeadlineReminderService? deadlineReminderService,
    NativeActions? nativeActions,
  }) : _apiClient = apiClient ?? MoodleApiClient(),
       _misClient = misClient ?? BnbuMisClient(),
       _credentialStore = credentialStore ?? SecureCredentialStore(),
       _deadlineReminderService =
           deadlineReminderService ?? DeadlineReminderService(),
       _nativeActions = nativeActions ?? const NativeActions() {
    unawaited(_restoreDeadlineReminderPreference());
  }

  final MoodleApiClient _apiClient;
  final BnbuMisClient _misClient;
  final CredentialStore _credentialStore;
  final DeadlineReminderService _deadlineReminderService;
  final NativeActions _nativeActions;

  AuthSession? _session;
  List<TimelineItem> _timelineItems = const [];
  List<CourseSummary> _courses = const [];
  List<RecentCourse> _recentCourses = const [];
  PortalAccountProfile? _portalProfile;
  TimetableData? _timetable;
  bool _isLoggingIn = false;
  bool _isLoggingOut = false;
  bool _isLoadingTimeline = false;
  bool _isLoadingCourses = false;
  bool _isLoadingRecentCourses = false;
  bool _isLoadingTimetable = false;
  bool _isLoadingPortalProfile = false;
  String? _error;
  String? _portalProfileError;
  String? _timetableError;
  String? _username;
  String? _password;
  bool _isRestoringSession = false;
  bool _didAttemptRestore = false;
  bool _isDeadlineReminderEnabled = false;
  bool _isLoadingDeadlineReminderPreference = true;
  bool _isUpdatingDeadlineReminder = false;
  Future<AuthSession?>? _reloginFuture;
  Future<void>? _logoutFuture;
  Future<void> _credentialMutation = Future<void>.value();
  int _authGeneration = 0;

  AuthSession? get session => _session;
  List<TimelineItem> get timelineItems => _timelineItems;
  List<CourseSummary> get courses => _courses;
  List<RecentCourse> get recentCourses => _recentCourses;
  PortalAccountProfile? get portalProfile => _portalProfile;
  TimetableData? get timetable => _timetable;
  bool get isLoggingIn => _isLoggingIn;
  bool get isLoggingOut => _isLoggingOut;
  bool get isLoadingTimeline => _isLoadingTimeline;
  bool get isLoadingCourses => _isLoadingCourses;
  bool get isLoadingRecentCourses => _isLoadingRecentCourses;
  bool get isLoadingTimetable => _isLoadingTimetable;
  bool get isLoadingPortalProfile => _isLoadingPortalProfile;
  bool get isRestoringSession => _isRestoringSession;
  bool get isDeadlineReminderEnabled => _isDeadlineReminderEnabled;
  bool get isLoadingDeadlineReminderPreference =>
      _isLoadingDeadlineReminderPreference;
  bool get isUpdatingDeadlineReminder => _isUpdatingDeadlineReminder;
  bool get isBusy =>
      _isLoggingIn ||
      _isLoggingOut ||
      _isLoadingTimeline ||
      _isLoadingCourses ||
      _isLoadingRecentCourses ||
      _isLoadingTimetable ||
      _isRestoringSession;
  bool get isLoggedIn => _session != null;
  String? get error => _error;
  String? get portalProfileError => _portalProfileError;
  String? get timetableError => _timetableError;
  String? get username => _username;
  String get baseUrl => _apiClient.baseUrl;

  Future<MailAccessCredentials?> loadMailAccessCredentials() async {
    final credentials = await _currentCredentials();
    if (credentials == null) {
      return null;
    }
    return MailAccessCredentials.fromUserId(
      userId: credentials.$1,
      password: credentials.$2,
    );
  }

  Future<void> login({
    required String username,
    required String password,
    bool fromStorage = false,
    bool persistCredentials = true,
  }) async {
    await _login(
      username: username,
      password: password,
      fromStorage: fromStorage,
      persistCredentials: persistCredentials,
    );
  }

  Future<_LoginOutcome> _login({
    required String username,
    required String password,
    required bool fromStorage,
    required bool persistCredentials,
  }) async {
    if (_isLoggingOut || _logoutFuture != null) {
      _error = '退出登录处理中，请稍后再登录。';
      notifyListeners();
      return _LoginOutcome.cancelled;
    }
    _didAttemptRestore = true;
    final authGeneration = ++_authGeneration;
    _isLoggingIn = true;
    _error = null;
    notifyListeners();

    try {
      final session = await _apiClient.loginWithPassword(
        username: username,
        password: password,
      );
      if (!_isCurrentAuthOperation(authGeneration)) {
        return _LoginOutcome.cancelled;
      }
      _persistSession(session: session, username: username, password: password);
      var credentialsSaved = true;
      if (persistCredentials) {
        credentialsSaved = await _saveCredentials(
          username: username,
          password: password,
          expectedAuthGeneration: authGeneration,
        );
      }
      if (!_isCurrentAuthOperation(authGeneration)) {
        return _LoginOutcome.cancelled;
      }
      notifyListeners();
      await Future.wait([
        refreshTimeline(),
        refreshCourses(),
        refreshRecentCourses(),
        refreshPortalProfile(),
      ]);
      if (!credentialsSaved && _isCurrentAuthOperation(authGeneration)) {
        const warning = '登录成功，但本地安全存储不可用；下次启动时可能需要重新登录。';
        _error = _error == null ? warning : '${_error!}\n$warning';
        notifyListeners();
      }
      return _isCurrentAuthOperation(authGeneration)
          ? _LoginOutcome.succeeded
          : _LoginOutcome.cancelled;
    } on MoodleAuthenticationException catch (error) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return _LoginOutcome.cancelled;
      }
      _error = error.message;
      _clearSessionState();
      if (fromStorage) {
        final cleared = await _clearSavedCredentials(
          expectedAuthGeneration: authGeneration,
        );
        if (!cleared && _isCurrentAuthOperation(authGeneration)) {
          _error = '${error.message}；本地登录信息清理失败，请再次退出登录。';
        }
      }
      if (_isCurrentAuthOperation(authGeneration)) {
        notifyListeners();
      }
      return _LoginOutcome.permanentFailure;
    } on MoodleApiException catch (error) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return _LoginOutcome.cancelled;
      }
      _error = error.message;
      _clearSessionState();
      notifyListeners();
      return _LoginOutcome.transientFailure;
    } catch (_) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return _LoginOutcome.cancelled;
      }
      _error = '登录失败，请检查网络后重试。';
      _clearSessionState();
      notifyListeners();
      return _LoginOutcome.transientFailure;
    } finally {
      if (authGeneration == _authGeneration) {
        _isLoggingIn = false;
        notifyListeners();
      }
    }
  }

  Future<void> restoreSessionIfPossible() async {
    if (_didAttemptRestore || _session != null || _isLoggingOut) {
      return;
    }
    _didAttemptRestore = true;
    final authGeneration = _authGeneration;
    _isRestoringSession = true;
    notifyListeners();
    try {
      final credentials = await _loadSavedCredentialsWithRetry();
      if (credentials == null ||
          authGeneration != _authGeneration ||
          _isLoggingOut) {
        return;
      }
      final outcome = await _login(
        username: credentials.$1,
        password: credentials.$2,
        fromStorage: true,
        persistCredentials: false,
      );
      if (outcome == _LoginOutcome.transientFailure && !_isLoggingOut) {
        _didAttemptRestore = false;
      }
    } catch (_) {
      if (_isCurrentAuthOperation(authGeneration)) {
        _didAttemptRestore = false;
        _error = '本地登录信息读取失败，请稍后重试。';
      }
    } finally {
      _isRestoringSession = false;
      notifyListeners();
    }
  }

  Future<void> refreshRecentCourses() async {
    final session = _session;
    if (session == null) {
      return;
    }
    final authGeneration = _authGeneration;

    _isLoadingRecentCourses = true;
    _error = null;
    notifyListeners();

    try {
      final courses = await _withSessionRetry((liveSession) {
        return _apiClient.fetchRecentCourses(
          token: liveSession.token,
          userId: liveSession.userId,
        );
      });
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _recentCourses = courses;
      notifyListeners();
    } on MoodleApiException catch (error) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _error = error.message;
      notifyListeners();
    } catch (_) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _error = '最近访问课程加载失败，请稍后重试。';
      notifyListeners();
    } finally {
      if (authGeneration == _authGeneration) {
        _isLoadingRecentCourses = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshTimeline() async {
    final session = _session;
    if (session == null) {
      _error = '请先登录 iSpace 账号。';
      notifyListeners();
      return;
    }
    final authGeneration = _authGeneration;

    _isLoadingTimeline = true;
    _error = null;
    notifyListeners();

    try {
      final items = await _withSessionRetry((liveSession) {
        return _apiClient.fetchAllTimeline(token: liveSession.token);
      });
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _timelineItems = items;
      notifyListeners();
      unawaited(_syncDeadlineReminders(items));
    } on MoodleApiException catch (error) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _error = error.message;
      notifyListeners();
    } catch (_) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _error = 'Timeline 拉取失败，请稍后重试。';
      notifyListeners();
    } finally {
      if (authGeneration == _authGeneration) {
        _isLoadingTimeline = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshCourses() async {
    final session = _session;
    if (session == null) {
      return;
    }
    final authGeneration = _authGeneration;

    _isLoadingCourses = true;
    _error = null;
    notifyListeners();

    try {
      final courses = await _withSessionRetry((liveSession) {
        return _apiClient.fetchMyCourses(
          token: liveSession.token,
          userId: liveSession.userId,
        );
      });
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _courses = courses;
      notifyListeners();
    } on MoodleApiException catch (error) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _error = error.message;
      notifyListeners();
    } catch (_) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _error = '课程列表加载失败，请稍后重试。';
      notifyListeners();
    } finally {
      if (authGeneration == _authGeneration) {
        _isLoadingCourses = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshTimetable() async {
    final authGeneration = _authGeneration;
    final credentials = await _currentCredentials();
    if (credentials == null || !_isCurrentAuthOperation(authGeneration)) {
      if (_isCurrentAuthOperation(authGeneration)) {
        _timetableError = '请先登录后加载课表。';
        notifyListeners();
      }
      return;
    }

    _isLoadingTimetable = true;
    _timetableError = null;
    notifyListeners();

    try {
      final timetable = await _misClient.fetchTimetable(
        username: credentials.$1,
        password: credentials.$2,
      );
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _timetable = timetable;
      notifyListeners();
    } on BnbuMisException catch (error) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _timetableError = error.message;
      notifyListeners();
    } catch (_) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _timetableError = '课表加载失败，请稍后重试。';
      notifyListeners();
    } finally {
      if (authGeneration == _authGeneration) {
        _isLoadingTimetable = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshPortalProfile() async {
    final authGeneration = _authGeneration;
    final credentials = await _currentCredentials();
    if (credentials == null || !_isCurrentAuthOperation(authGeneration)) {
      if (_isCurrentAuthOperation(authGeneration)) {
        _portalProfile = null;
        _portalProfileError = '请先登录后同步统一门户资料。';
        notifyListeners();
      }
      return;
    }

    _isLoadingPortalProfile = true;
    _portalProfileError = null;
    notifyListeners();

    try {
      final profile = await _misClient.fetchPortalAccountProfile(
        username: credentials.$1,
        password: credentials.$2,
      );
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _portalProfile = profile;
      notifyListeners();
    } on BnbuMisException catch (error) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _portalProfileError = error.message;
      notifyListeners();
    } catch (_) {
      if (!_isCurrentAuthOperation(authGeneration)) {
        return;
      }
      _portalProfileError = '统一门户用户信息加载失败，请稍后重试。';
      notifyListeners();
    } finally {
      if (authGeneration == _authGeneration) {
        _isLoadingPortalProfile = false;
        notifyListeners();
      }
    }
  }

  Future<List<CourseContentSection>> loadCourseContents(int courseId) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后查看课程内容。');
    }
    return _withSessionRetry((liveSession) {
      return _apiClient.fetchCourseContents(
        token: liveSession.token,
        courseId: courseId,
      );
    });
  }

  Future<TimelineDetailData> loadTimelineDetail(TimelineItem item) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后查看详情。');
    }
    return _withSessionRetry((liveSession) {
      return _apiClient.fetchTimelineDetail(
        token: liveSession.token,
        item: item,
      );
    });
  }

  Future<List<ForumPost>> loadForumDiscussionPosts(int discussionId) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后查看讨论内容。');
    }
    return _withSessionRetry((liveSession) {
      return _apiClient.fetchForumDiscussionPosts(
        token: liveSession.token,
        discussionId: discussionId,
      );
    });
  }

  Future<WebSessionSnapshot> prepareWebSession() async {
    final authGeneration = _authGeneration;
    if (_isLoggingOut) {
      throw MoodleApiException('退出登录处理中，请稍后重试。');
    }
    if (_session == null) {
      await _refreshSessionFromSavedCredentials();
    }
    final credentials = await _currentCredentials();
    if (credentials == null ||
        authGeneration != _authGeneration ||
        _isLoggingOut) {
      throw MoodleApiException('请先登录后再加载官网页面。');
    }
    final snapshot = await _apiClient.prepareWebSession(
      username: credentials.$1,
      password: credentials.$2,
    );
    if (authGeneration != _authGeneration || _isLoggingOut) {
      _apiClient.clearWebSession();
      throw MoodleApiException('登录状态已变化，请重新打开页面。');
    }
    return snapshot;
  }

  Future<TimelineDetailData> loadAssignmentDetailByCourseModule({
    required int courseId,
    required int courseModuleId,
    required String title,
    required String courseName,
    required String url,
  }) async {
    final pseudoItem = TimelineItem(
      id: -courseModuleId,
      title: title,
      activityState: 'Assignment is due',
      activityType: 'assign',
      moduleName: 'assign',
      description: '',
      courseName: courseName,
      courseId: courseId,
      instanceId: courseModuleId,
      url: url,
      sortTime: null,
      formattedTime: '',
      isOverdue: false,
    );
    return loadTimelineDetail(pseudoItem);
  }

  Future<void> submitAssignmentOnlineText({
    required int assignmentId,
    required String text,
  }) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后提交作业。');
    }
    await _withSessionRetry((liveSession) {
      return _apiClient.submitAssignmentOnlineText(
        token: liveSession.token,
        assignmentId: assignmentId,
        text: text,
      );
    });
  }

  Future<void> submitAssignmentFiles({
    required int assignmentId,
    required List<UploadFilePayload> files,
  }) async {
    if (_session == null) {
      throw MoodleApiException('请先登录后提交作业。');
    }
    await _withSessionRetry((liveSession) {
      return _apiClient.submitAssignmentFiles(
        token: liveSession.token,
        assignmentId: assignmentId,
        files: files,
      );
    });
  }

  void clearError() {
    if (_error == null) {
      return;
    }
    _error = null;
    notifyListeners();
  }

  Future<void> logout() {
    final activeLogout = _logoutFuture;
    if (activeLogout != null) {
      return activeLogout;
    }

    final completer = Completer<void>();
    final logoutFuture = completer.future;
    _logoutFuture = logoutFuture;
    unawaited(() async {
      try {
        await _performLogout();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (identical(_logoutFuture, logoutFuture)) {
          _logoutFuture = null;
        }
      }
    }());
    return logoutFuture;
  }

  Future<void> _performLogout() async {
    _authGeneration++;
    _isLoggingOut = true;
    _isLoggingIn = false;
    _isRestoringSession = false;
    _error = null;
    _clearSessionState();
    notifyListeners();

    final credentialsCleared = await _clearSavedCredentials();
    var localSessionCleared = true;
    try {
      await Future.wait([
        _deadlineReminderService.disable(),
        _nativeActions.clearWebSession(),
      ]);
    } on MissingPluginException {
      localSessionCleared = false;
    } catch (_) {
      localSessionCleared = false;
    }
    _apiClient.clearWebSession();
    _misClient.clearSession();

    _isLoggingOut = false;
    if (!credentialsCleared || !localSessionCleared) {
      _error = '已退出登录，但部分本地登录数据清理失败；请在错误消失前保持应用打开并再次退出。';
    } else {
      _error = null;
    }
    notifyListeners();
  }

  Future<String?> setDeadlineReminderEnabled(bool enabled) async {
    if (_isUpdatingDeadlineReminder) {
      return 'DDL 提醒设置处理中，请稍后再试。';
    }

    _isUpdatingDeadlineReminder = true;
    notifyListeners();

    try {
      if (!enabled) {
        await _deadlineReminderService.disable();
        _isDeadlineReminderEnabled = false;
        return null;
      }

      final permissionError = await _deadlineReminderService.enable();
      if (permissionError != null) {
        _isDeadlineReminderEnabled = false;
        return permissionError;
      }

      _isDeadlineReminderEnabled = true;
      notifyListeners();

      if (_timelineItems.isEmpty) {
        await refreshTimeline();
      } else {
        await _syncDeadlineReminders(_timelineItems);
      }
      return null;
    } catch (_) {
      return enabled ? 'DDL 提醒开启失败，请稍后重试。' : 'DDL 提醒关闭失败，请稍后重试。';
    } finally {
      _isUpdatingDeadlineReminder = false;
      notifyListeners();
    }
  }

  Future<T> _withSessionRetry<T>(
    Future<T> Function(AuthSession session) request,
  ) async {
    final authGeneration = _authGeneration;
    final session = _session;
    if (session == null) {
      throw MoodleApiException('请先登录 iSpace 账号。');
    }
    try {
      final result = await request(session);
      if (!_isCurrentAuthOperation(authGeneration)) {
        throw MoodleApiException('登录状态已变化，请重试。');
      }
      return result;
    } on MoodleApiException catch (error) {
      if (!_isCurrentAuthOperation(authGeneration) ||
          !_looksLikeTokenExpired(error.message)) {
        rethrow;
      }
      final refreshed = await _refreshSessionFromSavedCredentials();
      if (refreshed == null || !_isCurrentAuthOperation(authGeneration)) {
        rethrow;
      }
      final result = await request(refreshed);
      if (!_isCurrentAuthOperation(authGeneration)) {
        throw MoodleApiException('登录状态已变化，请重试。');
      }
      return result;
    }
  }

  bool _looksLikeTokenExpired(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('invalidtoken') ||
        normalized.contains('invalid token') ||
        normalized.contains('token is invalid') ||
        normalized.contains('accessexception');
  }

  Future<AuthSession?> _refreshSessionFromSavedCredentials() async {
    if (_isLoggingOut) {
      return null;
    }
    if (_reloginFuture != null) {
      return _reloginFuture!;
    }
    _reloginFuture = _doRefreshSession();
    try {
      return await _reloginFuture;
    } finally {
      _reloginFuture = null;
    }
  }

  Future<AuthSession?> _doRefreshSession() async {
    final authGeneration = _authGeneration;
    final credentials = await _currentCredentials();
    if (credentials == null || !_isCurrentAuthOperation(authGeneration)) {
      return null;
    }
    try {
      final session = await _apiClient.loginWithPassword(
        username: credentials.$1,
        password: credentials.$2,
      );
      if (!_isCurrentAuthOperation(authGeneration) || _session == null) {
        return null;
      }
      _persistSession(
        session: session,
        username: credentials.$1,
        password: credentials.$2,
      );
      await _saveCredentials(
        username: credentials.$1,
        password: credentials.$2,
        expectedAuthGeneration: authGeneration,
      );
      if (!_isCurrentAuthOperation(authGeneration)) {
        return null;
      }
      notifyListeners();
      return session;
    } on MoodleAuthenticationException catch (error) {
      final cleared = await _clearSavedCredentials(
        expectedAuthGeneration: authGeneration,
      );
      if (_isCurrentAuthOperation(authGeneration)) {
        _authGeneration++;
        _error = cleared
            ? error.message
            : '${error.message}；本地登录信息清理失败，请再次退出登录。';
        _clearSessionState();
        notifyListeners();
      }
      return null;
    } on MoodleApiException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _restoreDeadlineReminderPreference() async {
    try {
      _isDeadlineReminderEnabled = await _deadlineReminderService.loadEnabled();
    } finally {
      _isLoadingDeadlineReminderPreference = false;
      notifyListeners();
    }
  }

  Future<void> _syncDeadlineReminders(List<TimelineItem> items) async {
    if (!_isDeadlineReminderEnabled) {
      return;
    }
    try {
      await _deadlineReminderService.synchronize(items);
    } catch (_) {
      // Keep timeline refresh independent from reminder scheduling failures.
    }
  }

  Future<(String, String)?> _currentCredentials() async {
    if (_isLoggingOut) {
      return null;
    }
    final authGeneration = _authGeneration;
    final username = (_username ?? '').trim();
    final password = _password ?? '';
    if (username.isNotEmpty && password.isNotEmpty) {
      return (username, password);
    }
    final (String, String)? saved;
    try {
      saved = await _loadSavedCredentials();
    } catch (_) {
      return null;
    }
    if (saved == null || authGeneration != _authGeneration || _isLoggingOut) {
      return null;
    }
    _username = saved.$1;
    _password = saved.$2;
    return saved;
  }

  void _persistSession({
    required AuthSession session,
    required String username,
    required String password,
  }) {
    _session = session;
    _username = username;
    _password = password;
  }

  void _clearSessionState() {
    _session = null;
    _username = null;
    _password = null;
    _timelineItems = const [];
    _courses = const [];
    _recentCourses = const [];
    _isLoadingTimeline = false;
    _isLoadingCourses = false;
    _isLoadingRecentCourses = false;
    _isLoadingTimetable = false;
    _isLoadingPortalProfile = false;
    _portalProfile = null;
    _timetable = null;
    _portalProfileError = null;
    _timetableError = null;
    _isDeadlineReminderEnabled = false;
  }

  bool _isCurrentAuthOperation(int authGeneration) {
    return authGeneration == _authGeneration && !_isLoggingOut;
  }

  Future<bool> _saveCredentials({
    required String username,
    required String password,
    int? expectedAuthGeneration,
  }) async {
    try {
      return await _withCredentialMutation(() async {
        if (expectedAuthGeneration != null &&
            expectedAuthGeneration != _authGeneration) {
          return true;
        }
        await _credentialStore.save(
          StoredCredentials(username: username, password: password),
        );
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  Future<(String, String)?> _loadSavedCredentialsWithRetry() async {
    try {
      return await _loadSavedCredentials();
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return _loadSavedCredentials();
    }
  }

  Future<(String, String)?> _loadSavedCredentials() async {
    final credentials = await _withCredentialMutation(_credentialStore.load);
    if (credentials == null) {
      return null;
    }
    return (credentials.username, credentials.password);
  }

  Future<bool> _clearSavedCredentials({int? expectedAuthGeneration}) async {
    try {
      return await _withCredentialMutation(() async {
        if (expectedAuthGeneration != null &&
            expectedAuthGeneration != _authGeneration) {
          return true;
        }
        await _credentialStore.clear();
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  Future<T> _withCredentialMutation<T>(Future<T> Function() operation) async {
    final previous = _credentialMutation;
    final completer = Completer<void>();
    _credentialMutation = completer.future;
    await previous;
    try {
      return await operation();
    } finally {
      completer.complete();
    }
  }

  @override
  void dispose() {
    _apiClient.dispose();
    _misClient.dispose();
    super.dispose();
  }
}
