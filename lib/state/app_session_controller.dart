import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/course_content.dart';
import '../models/course_summary.dart';
import '../models/recent_course.dart';
import '../models/timetable_data.dart';
import '../models/timeline_detail_data.dart';
import '../models/timeline_item.dart';
import '../models/upload_file_payload.dart';
import '../models/web_session_snapshot.dart';
import '../services/bnbu_mis_client.dart';
import '../services/moodle_api_client.dart';

class AppSessionController extends ChangeNotifier {
  AppSessionController({
    MoodleApiClient? apiClient,
    BnbuMisClient? misClient,
  }) : _apiClient = apiClient ?? MoodleApiClient(),
       _misClient = misClient ?? BnbuMisClient();

  static const MethodChannel _credentialStoreChannel = MethodChannel(
    'ispace/credential_store',
  );

  final MoodleApiClient _apiClient;
  final BnbuMisClient _misClient;

  AuthSession? _session;
  List<TimelineItem> _timelineItems = const [];
  List<CourseSummary> _courses = const [];
  List<RecentCourse> _recentCourses = const [];
  TimetableData? _timetable;
  bool _isLoggingIn = false;
  bool _isLoadingTimeline = false;
  bool _isLoadingCourses = false;
  bool _isLoadingRecentCourses = false;
  bool _isLoadingTimetable = false;
  String? _error;
  String? _timetableError;
  String? _username;
  String? _password;
  bool _isRestoringSession = false;
  bool _didAttemptRestore = false;
  Future<AuthSession?>? _reloginFuture;

  AuthSession? get session => _session;
  List<TimelineItem> get timelineItems => _timelineItems;
  List<CourseSummary> get courses => _courses;
  List<RecentCourse> get recentCourses => _recentCourses;
  TimetableData? get timetable => _timetable;
  bool get isLoggingIn => _isLoggingIn;
  bool get isLoadingTimeline => _isLoadingTimeline;
  bool get isLoadingCourses => _isLoadingCourses;
  bool get isLoadingRecentCourses => _isLoadingRecentCourses;
  bool get isLoadingTimetable => _isLoadingTimetable;
  bool get isRestoringSession => _isRestoringSession;
  bool get isBusy =>
      _isLoggingIn ||
      _isLoadingTimeline ||
      _isLoadingCourses ||
      _isLoadingRecentCourses ||
      _isLoadingTimetable ||
      _isRestoringSession;
  bool get isLoggedIn => _session != null;
  String? get error => _error;
  String? get timetableError => _timetableError;
  String get baseUrl => _apiClient.baseUrl;

  Future<void> login({
    required String username,
    required String password,
    bool fromStorage = false,
    bool persistCredentials = true,
  }) async {
    _didAttemptRestore = true;
    _isLoggingIn = true;
    _error = null;
    notifyListeners();

    try {
      final session = await _apiClient.loginWithPassword(
        username: username,
        password: password,
      );
      _persistSession(session: session, username: username, password: password);
      if (persistCredentials) {
        await _saveCredentials(username: username, password: password);
      }
      notifyListeners();
      await Future.wait([
        refreshTimeline(),
        refreshCourses(),
        refreshRecentCourses(),
      ]);
    } on MoodleApiException catch (error) {
      _error = error.message;
      _session = null;
      _username = null;
      _password = null;
      _timelineItems = const [];
      _courses = const [];
      _recentCourses = const [];
      _timetable = null;
      _timetableError = null;
      if (fromStorage) {
        await _clearSavedCredentials();
      }
      notifyListeners();
    } catch (_) {
      _error = '登录失败，请检查网络后重试。';
      _session = null;
      _username = null;
      _password = null;
      _timelineItems = const [];
      _courses = const [];
      _recentCourses = const [];
      _timetable = null;
      _timetableError = null;
      if (fromStorage) {
        await _clearSavedCredentials();
      }
      notifyListeners();
    } finally {
      _isLoggingIn = false;
      notifyListeners();
    }
  }

  Future<void> restoreSessionIfPossible() async {
    if (_didAttemptRestore || _session != null) {
      return;
    }
    _didAttemptRestore = true;
    _isRestoringSession = true;
    notifyListeners();
    try {
      final credentials = await _loadSavedCredentials();
      if (credentials == null) {
        return;
      }
      await login(
        username: credentials.$1,
        password: credentials.$2,
        fromStorage: true,
        persistCredentials: false,
      );
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
      _recentCourses = courses;
      notifyListeners();
    } on MoodleApiException catch (error) {
      _error = error.message;
      notifyListeners();
    } catch (_) {
      _error = '最近访问课程加载失败，请稍后重试。';
      notifyListeners();
    } finally {
      _isLoadingRecentCourses = false;
      notifyListeners();
    }
  }

  Future<void> refreshTimeline() async {
    final session = _session;
    if (session == null) {
      _error = '请先登录 iSpace 账号。';
      notifyListeners();
      return;
    }

    _isLoadingTimeline = true;
    _error = null;
    notifyListeners();

    try {
      final items = await _withSessionRetry((liveSession) {
        return _apiClient.fetchAllTimeline(token: liveSession.token);
      });
      _timelineItems = items;
      notifyListeners();
    } on MoodleApiException catch (error) {
      _error = error.message;
      notifyListeners();
    } catch (_) {
      _error = 'Timeline 拉取失败，请稍后重试。';
      notifyListeners();
    } finally {
      _isLoadingTimeline = false;
      notifyListeners();
    }
  }

  Future<void> refreshCourses() async {
    final session = _session;
    if (session == null) {
      return;
    }

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
      _courses = courses;
      notifyListeners();
    } on MoodleApiException catch (error) {
      _error = error.message;
      notifyListeners();
    } catch (_) {
      _error = '课程列表加载失败，请稍后重试。';
      notifyListeners();
    } finally {
      _isLoadingCourses = false;
      notifyListeners();
    }
  }

  Future<void> refreshTimetable() async {
    final credentials = await _currentCredentials();
    if (credentials == null) {
      _timetableError = '请先登录后加载课表。';
      notifyListeners();
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
      _timetable = timetable;
      notifyListeners();
    } on BnbuMisException catch (error) {
      _timetableError = error.message;
      notifyListeners();
    } catch (_) {
      _timetableError = '课表加载失败，请稍后重试。';
      notifyListeners();
    } finally {
      _isLoadingTimetable = false;
      notifyListeners();
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
    if (_session == null) {
      await _refreshSessionFromSavedCredentials();
    }
    final credentials = await _currentCredentials();
    if (credentials == null) {
      throw MoodleApiException('请先登录后再加载官网页面。');
    }
    return _apiClient.prepareWebSession(
      username: credentials.$1,
      password: credentials.$2,
    );
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

  void logout() {
    _session = null;
    _username = null;
    _password = null;
    _timelineItems = const [];
    _courses = const [];
    _recentCourses = const [];
    _timetable = null;
    _error = null;
    _timetableError = null;
    _clearSavedCredentials();
    notifyListeners();
  }

  Future<T> _withSessionRetry<T>(
    Future<T> Function(AuthSession session) request,
  ) async {
    final session = _session;
    if (session == null) {
      throw MoodleApiException('请先登录 iSpace 账号。');
    }
    try {
      return await request(session);
    } on MoodleApiException catch (error) {
      if (!_looksLikeTokenExpired(error.message)) {
        rethrow;
      }
      final refreshed = await _refreshSessionFromSavedCredentials();
      if (refreshed == null) {
        rethrow;
      }
      return request(refreshed);
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
    final credentials = await _currentCredentials();
    if (credentials == null) {
      return null;
    }
    try {
      final session = await _apiClient.loginWithPassword(
        username: credentials.$1,
        password: credentials.$2,
      );
      _persistSession(
        session: session,
        username: credentials.$1,
        password: credentials.$2,
      );
      await _saveCredentials(
        username: credentials.$1,
        password: credentials.$2,
      );
      notifyListeners();
      return session;
    } on MoodleApiException {
      await _clearSavedCredentials();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<(String, String)?> _currentCredentials() async {
    final username = (_username ?? '').trim();
    final password = _password ?? '';
    if (username.isNotEmpty && password.isNotEmpty) {
      return (username, password);
    }
    final saved = await _loadSavedCredentials();
    if (saved == null) {
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

  Future<void> _saveCredentials({
    required String username,
    required String password,
  }) async {
    try {
      await _credentialStoreChannel.invokeMethod('saveCredentials', {
        'username': username,
        'password': password,
      });
    } on PlatformException {
      // Best-effort only.
    }
  }

  Future<(String, String)?> _loadSavedCredentials() async {
    try {
      final raw = await _credentialStoreChannel.invokeMethod<dynamic>(
        'loadCredentials',
      );
      if (raw is! Map) {
        return null;
      }
      final data = raw.cast<dynamic, dynamic>();
      final username = (data['username'] as String?)?.trim() ?? '';
      final password = (data['password'] as String?) ?? '';
      if (username.isEmpty || password.isEmpty) {
        return null;
      }
      return (username, password);
    } on PlatformException {
      return null;
    }
  }

  Future<void> _clearSavedCredentials() async {
    try {
      await _credentialStoreChannel.invokeMethod('clearCredentials');
    } on PlatformException {
      // Best-effort only.
    }
  }

  @override
  void dispose() {
    _apiClient.dispose();
    _misClient.dispose();
    super.dispose();
  }
}
