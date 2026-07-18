import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/course_content.dart';
import '../models/course_summary.dart';
import '../models/recent_course.dart';
import '../models/timeline_detail_data.dart';
import '../models/timeline_item.dart';
import '../models/upload_file_payload.dart';
import '../models/web_session_snapshot.dart';

class AuthSession {
  AuthSession({
    required this.token,
    required this.fullName,
    required this.userId,
  });

  final String token;
  final String fullName;
  final int userId;
}

class MoodleApiException implements Exception {
  MoodleApiException(this.message);

  final String message;

  @override
  String toString() => 'MoodleApiException($message)';
}

class MoodleAuthenticationException extends MoodleApiException {
  MoodleAuthenticationException(super.message);
}

class MoodleApiClient {
  MoodleApiClient({http.Client? client, String? baseUrl, String? cookieDomain})
    : _httpClient = client ?? http.Client(),
      baseUrl = AppConfig.normalizedHttpsBaseUrl(
        baseUrl ?? AppConfig.ispaceBaseUrl,
        settingName: 'ISPACE_BASE_URL',
      ),
      cookieDomain = AppConfig.normalizedCookieDomain(
        cookieDomain ?? AppConfig.ispaceCookieDomain,
      ) {
    _webHttpClient.userAgent =
        'Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36';
  }

  final http.Client _httpClient;
  final String baseUrl;
  final String cookieDomain;
  final HttpClient _webHttpClient = HttpClient();
  final List<_StoredWebCookie> _webCookies = <_StoredWebCookie>[];
  String? _webSessionUser;

  static const int _timelinePageSize = 50;
  static const int _maxTimelinePages = 50;

  void clearWebSession() {
    _webCookies.clear();
    _webSessionUser = null;
  }

  @visibleForTesting
  String decoratePluginFileUrlWithTokenForTesting(
    String url, {
    required String token,
  }) {
    return _decoratePluginFileUrlWithToken(url, token: token);
  }

  @visibleForTesting
  void cacheWebCookieForTesting(Cookie cookie, Uri origin) {
    _cacheWebCookies(<Cookie>[cookie], origin);
  }

  @visibleForTesting
  String webCookieHeaderForTesting(Uri target) {
    return _buildCookieHeader(target);
  }

  @visibleForTesting
  List<WebSessionCookie> webSessionCookiesForTesting(Uri target) {
    return _webSessionCookiesFor(target);
  }

  void dispose() {
    _httpClient.close();
    _webHttpClient.close(force: true);
  }

  Future<AuthSession> loginWithPassword({
    required String username,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/login/token.php');
    final response = await _httpClient.post(
      uri,
      body: <String, String>{
        'username': username,
        'password': password,
        'service': 'moodle_mobile_app',
      },
    );

    if (response.statusCode != 200) {
      throw MoodleApiException('登录接口失败（HTTP ${response.statusCode}）。');
    }

    final json = _decodeJsonMap(response.body);
    final token = (json['token'] as String?)?.trim();
    if (token == null || token.isEmpty) {
      final message = _extractWsError(json, fallback: '未获取到 token，登录失败。');
      final errorCode = (json['errorcode'] as String?)?.trim().toLowerCase();
      if (errorCode == 'invalidlogin') {
        throw MoodleAuthenticationException(message);
      }
      throw MoodleApiException(message);
    }

    final siteInfoRaw = await _callWebService(
      token: token,
      functionName: 'core_webservice_get_site_info',
      parameters: const {},
    );
    final siteInfo = _asJsonMap(siteInfoRaw);

    return AuthSession(
      token: token,
      fullName: (siteInfo['fullname'] as String?)?.trim().isNotEmpty == true
          ? (siteInfo['fullname'] as String).trim()
          : username,
      userId: _toInt(siteInfo['userid']),
    );
  }

  Future<List<TimelineItem>> fetchAllTimeline({required String token}) async {
    final items = <TimelineItem>[];
    final seenIds = <int>{};
    var afterEventId = 0;

    for (var page = 0; page < _maxTimelinePages; page++) {
      final response = _asJsonMap(
        await _callWebService(
          token: token,
          functionName: 'core_calendar_get_action_events_by_timesort',
          parameters: <String, dynamic>{
            'timesortfrom': 0,
            'timesortto': 4102444800, // UTC 2100-01-01
            'limitnum': _timelinePageSize,
            'aftereventid': afterEventId,
          },
        ),
      );

      final events = _extractEvents(response);
      if (events.isEmpty) {
        break;
      }

      for (final event in events) {
        final item = TimelineItem.fromJson(event);
        if (item.id <= 0 || !seenIds.add(item.id)) {
          continue;
        }
        items.add(item);
      }

      final canLoadMore = _toBool(response['canloadmore']);
      final nextCursor = _extractNextCursor(response, events, afterEventId);
      if (!canLoadMore && events.length < _timelinePageSize) {
        break;
      }
      if (nextCursor <= afterEventId) {
        break;
      }
      afterEventId = nextCursor;
    }

    items.sort((a, b) => _timeSortValue(a).compareTo(_timeSortValue(b)));
    return items;
  }

  Future<WebSessionSnapshot> prepareWebSession({
    required String username,
    required String password,
  }) async {
    await _ensureWebSession(username: username, password: password);
    final baseUri = Uri.parse(baseUrl);
    return WebSessionSnapshot(
      baseUrl: baseUrl,
      cookies: _webSessionCookiesFor(baseUri),
    );
  }

  List<WebSessionCookie> _webSessionCookiesFor(Uri uri) {
    final snapshotHost = uri.host.toLowerCase();
    return _matchingWebCookies(uri)
        .map(
          (cookie) => WebSessionCookie(
            name: cookie.name,
            value: cookie.value,
            domain: snapshotHost,
            path: cookie.path,
            hostOnly: cookie.hostOnly || cookie.domain != snapshotHost,
            secure: cookie.secure,
            expiresAt: cookie.expires,
          ),
        )
        .toList(growable: false);
  }

  Future<List<CourseSummary>> fetchMyCourses({
    required String token,
    required int userId,
  }) async {
    final response = await _callWebService(
      token: token,
      functionName: 'core_enrol_get_users_courses',
      parameters: <String, dynamic>{'userid': userId},
    );

    if (response case {'courses': List<dynamic> courses}) {
      return courses
          .whereType<Map>()
          .map((item) => CourseSummary.fromJson(item.cast<String, dynamic>()))
          .toList();
    }

    if (response is List) {
      return response
          .whereType<Map>()
          .map((item) => CourseSummary.fromJson(item.cast<String, dynamic>()))
          .toList();
    }

    return const [];
  }

  Future<List<RecentCourse>> fetchRecentCourses({
    required String token,
    required int userId,
    int limit = 10,
  }) async {
    final response = await _callWebService(
      token: token,
      functionName: 'core_course_get_recent_courses',
      parameters: <String, dynamic>{'userid': userId, 'limit': limit},
    );

    if (response is List) {
      return response
          .whereType<Map>()
          .map((item) => RecentCourse.fromJson(item.cast<String, dynamic>()))
          .toList();
    }

    if (response case {'courses': List<dynamic> courses}) {
      return courses
          .whereType<Map>()
          .map((item) => RecentCourse.fromJson(item.cast<String, dynamic>()))
          .toList();
    }

    return const [];
  }

  Future<List<CourseContentSection>> fetchCourseContents({
    required String token,
    required int courseId,
  }) async {
    final response = await _callWebService(
      token: token,
      functionName: 'core_course_get_contents',
      parameters: <String, dynamic>{'courseid': courseId},
    );

    if (response is! List) {
      return const [];
    }

    final sections = response
        .whereType<Map>()
        .map(
          (item) => CourseContentSection.fromJson(item.cast<String, dynamic>()),
        )
        .toList();
    sections.sort((a, b) => a.sectionNum.compareTo(b.sectionNum));
    return sections;
  }

  Future<TimelineDetailData> fetchTimelineDetail({
    required String token,
    required TimelineItem item,
  }) async {
    if (_looksLikeAssignment(item)) {
      return _fetchAssignmentDetail(token: token, item: item);
    }
    if (_looksLikeForum(item)) {
      return _fetchForumDetail(token: token, item: item);
    }
    if (_looksLikeMediaSite(item)) {
      return _fetchMediaSiteDetail(token: token, item: item);
    }
    return TimelineDetailData(
      item: item,
      type: TimelineDetailType.generic,
      hints: const ['该事件类型暂未完全原生化，后续会继续搬运。'],
    );
  }

  Future<TimelineDetailData> _fetchAssignmentDetail({
    required String token,
    required TimelineItem item,
  }) async {
    final resolvedAssignId = await _resolveAssignId(token: token, item: item);
    if (resolvedAssignId <= 0) {
      return TimelineDetailData(
        item: item,
        type: TimelineDetailType.assignment,
        hints: const ['未能识别作业实例 ID，暂无法获取提交状态。'],
      );
    }

    try {
      final assignmentSummary = await _fetchAssignmentSummary(
        token: token,
        courseId: item.courseId,
        assignmentId: resolvedAssignId,
      );
      final submissionStatus = await _fetchAssignmentSubmissionStatus(
        token: token,
        assignmentId: resolvedAssignId,
      );
      final introRaw = _pickString(assignmentSummary, const [
        'intro',
        'activity',
      ]);
      final introFiles = _extractAssignmentIntroFiles(
        assignmentSummary,
        token: token,
      );

      final submission = _asJsonMapOrEmpty(submissionStatus['submission']);
      final lastAttempt = _asJsonMapOrEmpty(submissionStatus['lastattempt']);

      return TimelineDetailData(
        item: item,
        type: TimelineDetailType.assignment,
        assignmentId: resolvedAssignId,
        assignmentName: _pickString(assignmentSummary, const [
          'name',
        ], item.title),
        assignmentIntro: _stripHtml(introRaw),
        assignmentIntroHtml: _normalizeAssignmentIntroHtml(
          introRaw,
          introFiles: introFiles,
          token: token,
        ),
        assignmentIntroFiles: introFiles,
        openDateEpoch: _toInt(assignmentSummary['allowsubmissionsfromdate']),
        dueDateEpoch: _toInt(assignmentSummary['duedate']),
        cutoffDateEpoch: _toInt(assignmentSummary['cutoffdate']),
        gradingDueDateEpoch: _toInt(assignmentSummary['gradingduedate']),
        submissionStatus: _pickString(submission, const [
          'status',
          'submissionstatus',
        ]),
        gradingStatus: _pickString(lastAttempt, const ['gradingstatus']),
        canEditSubmission: _toBool(lastAttempt['canedit']),
        feedbackSummary: _extractFeedback(submission),
        supportsFileSubmission:
            _assignmentConfigEnabled(assignmentSummary, 'file', 'enabled') ||
            _submissionPluginExists(submission, 'file'),
        supportsOnlineTextSubmission:
            _assignmentConfigEnabled(
              assignmentSummary,
              'onlinetext',
              'enabled',
            ) ||
            _submissionPluginExists(submission, 'onlinetext'),
        maxFileSubmissions: _assignmentConfigInt(
          assignmentSummary,
          'file',
          'maxfilesubmissions',
        ),
        maxSubmissionSizeBytes: _assignmentConfigInt(
          assignmentSummary,
          'file',
          'maxsubmissionsizebytes',
        ),
        submissionFiles: _extractSubmissionFiles(submission),
        hints: const [],
      );
    } on MoodleApiException catch (error) {
      if (_isAssignRecordError(error.message)) {
        return TimelineDetailData(
          item: item,
          type: TimelineDetailType.assignment,
          assignmentId: 0,
          hints: const ['该 Timeline 事件的作业记录在服务端不可用，已切换为安全降级展示。'],
        );
      }
      rethrow;
    }
  }

  Future<TimelineDetailData> _fetchForumDetail({
    required String token,
    required TimelineItem item,
  }) async {
    final forumId = await _resolveModuleInstanceId(
      token: token,
      item: item,
      moduleName: 'forum',
    );
    if (forumId <= 0) {
      return TimelineDetailData(
        item: item,
        type: TimelineDetailType.forum,
        hints: const ['未能识别论坛实例 ID，已切换为基础展示。'],
      );
    }

    String forumName = item.title;
    String forumDescription = '';
    if (item.courseId > 0) {
      try {
        final forumsRaw = await _callWebService(
          token: token,
          functionName: 'mod_forum_get_forums_by_courses',
          parameters: <String, dynamic>{
            'courseids': <int>[item.courseId],
          },
        );
        final forums = _extractForums(forumsRaw);
        for (final forum in forums) {
          if (_toInt(forum['id']) == forumId) {
            forumName = _pickString(forum, const ['name'], forumName);
            forumDescription = _stripHtml(
              _pickString(forum, const ['intro', 'description']),
            );
            break;
          }
        }
      } on MoodleApiException {
        forumName = item.title;
        forumDescription = '';
      }
    }

    var canStartDiscussion = false;
    try {
      final accessInfo = _asJsonMap(
        await _callWebService(
          token: token,
          functionName: 'mod_forum_get_forum_access_information',
          parameters: <String, dynamic>{'forumid': forumId},
        ),
      );
      canStartDiscussion = _toBool(accessInfo['canstartdiscussion']);
    } on MoodleApiException {
      canStartDiscussion = false;
    }

    List<ForumDiscussion> discussions = const [];
    try {
      final discussionResponse = _asJsonMap(
        await _callWebService(
          token: token,
          functionName: 'mod_forum_get_forum_discussions_paginated',
          parameters: <String, dynamic>{
            'forumid': forumId,
            'sortby': 'timemodified',
            'sortdirection': 'DESC',
            'page': 0,
            'perpage': 10,
          },
        ),
      );
      discussions = _extractForumDiscussions(discussionResponse['discussions']);
    } on MoodleApiException {
      discussions = const [];
    }

    return TimelineDetailData(
      item: item,
      type: TimelineDetailType.forum,
      forumId: forumId,
      forumName: forumName,
      forumDescription: forumDescription,
      forumDiscussions: discussions,
      canStartDiscussion: canStartDiscussion,
      hints: discussions.isEmpty ? const ['当前没有可见讨论，或课程暂未发布讨论帖。'] : const [],
    );
  }

  Future<TimelineDetailData> _fetchMediaSiteDetail({
    required String token,
    required TimelineItem item,
  }) async {
    final mediasiteId = await _resolveModuleInstanceId(
      token: token,
      item: item,
      moduleName: 'mediasite',
    );
    return TimelineDetailData(
      item: item,
      type: TimelineDetailType.mediasite,
      assignmentId: mediasiteId,
      assignmentName: item.title,
      mediasiteLaunchUrl: item.url,
      hints: const ['已支持识别 Mediasite 活动并展示基础信息。', '后续将补齐播放/上传等原生交互能力。'],
    );
  }

  Future<List<ForumPost>> fetchForumDiscussionPosts({
    required String token,
    required int discussionId,
  }) async {
    if (discussionId <= 0) {
      return const [];
    }
    final response = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'mod_forum_get_discussion_posts',
        parameters: <String, dynamic>{'discussionid': discussionId},
      ),
    );
    final postsValue = response['posts'];
    if (postsValue is! List) {
      return const [];
    }
    final posts = <ForumPost>[];
    for (final raw in postsValue.whereType<Map>()) {
      final data = raw.cast<String, dynamic>();
      posts.add(
        ForumPost(
          id: _toInt(data['id']),
          subject: _pickString(data, const ['subject'], '无标题'),
          message: _stripHtml(_pickString(data, const ['message'])),
          author: _pickString(data, const ['userfullname'], '未知用户'),
          timeCreatedEpoch: _toInt(
            data['modified'] ?? data['created'] ?? data['timecreated'],
          ),
          parentId: _toInt(data['parent']),
          isPrivateReply: _toBool(data['isprivatereply']),
        ),
      );
    }
    posts.sort((a, b) => a.timeCreatedEpoch.compareTo(b.timeCreatedEpoch));
    return posts;
  }

  Future<void> submitAssignmentOnlineText({
    required String token,
    required int assignmentId,
    required String text,
  }) async {
    if (text.trim().isEmpty) {
      throw MoodleApiException('提交内容不能为空。');
    }

    await _callWebService(
      token: token,
      functionName: 'mod_assign_save_submission',
      parameters: <String, dynamic>{
        'assignmentid': assignmentId,
        'plugindata': <String, dynamic>{
          'onlinetext_editor': <String, dynamic>{
            'text': text.trim(),
            'format': 1,
            'itemid': 0,
          },
        },
      },
    );
  }

  Future<void> submitAssignmentFiles({
    required String token,
    required int assignmentId,
    required List<UploadFilePayload> files,
  }) async {
    final validFiles = files.where((file) => file.hasUsableContent).toList();
    if (validFiles.isEmpty) {
      throw MoodleApiException('请至少选择一个有效文件再提交。');
    }

    final draftItemId = await _createDraftItemId(token: token);
    for (final file in validFiles) {
      await _uploadDraftFile(
        token: token,
        draftItemId: draftItemId,
        file: file,
      );
    }

    await _callWebService(
      token: token,
      functionName: 'mod_assign_save_submission',
      parameters: <String, dynamic>{
        'assignmentid': assignmentId,
        'plugindata': <String, dynamic>{'files_filemanager': draftItemId},
      },
    );
  }

  Future<int> _createDraftItemId({required String token}) async {
    final response = _asJsonMap(
      await _callWebService(
        token: token,
        functionName: 'core_files_get_unused_draft_itemid',
        parameters: const <String, dynamic>{},
      ),
    );
    final draftItemId = _toInt(response['itemid']);
    if (draftItemId <= 0) {
      throw MoodleApiException('未能创建文件草稿空间，请稍后重试。');
    }
    return draftItemId;
  }

  Future<void> _uploadDraftFile({
    required String token,
    required int draftItemId,
    required UploadFilePayload file,
  }) async {
    final uri = Uri.parse('$baseUrl/webservice/upload.php').replace(
      queryParameters: <String, String>{
        'token': token,
        'itemid': '$draftItemId',
        'filepath': '/',
      },
    );

    final request = http.MultipartRequest('POST', uri);
    request.fields['license'] = 'unknown';

    if (file.filePath != null && file.filePath!.trim().isNotEmpty) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'file_1',
          file.filePath!,
          filename: file.fileName,
        ),
      );
    } else if (file.bytes != null && file.bytes!.isNotEmpty) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'file_1',
          file.bytes!,
          filename: file.fileName,
        ),
      );
    } else {
      throw MoodleApiException('文件 ${file.fileName} 无法读取。');
    }

    final response = await _httpClient.send(request);
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      throw MoodleApiException('文件上传失败（HTTP ${response.statusCode}）。');
    }

    final decoded = _decodeDynamicJson(body);
    if (decoded is Map<String, dynamic>) {
      final exception = decoded['exception'];
      if (exception is String && exception.trim().isNotEmpty) {
        throw MoodleApiException(_extractWsError(decoded));
      }
      throw MoodleApiException('文件上传返回格式异常。');
    }
    if (decoded is! List || decoded.isEmpty) {
      throw MoodleApiException('文件上传返回格式异常。');
    }
  }

  Future<void> _ensureWebSession({
    required String username,
    required String password,
  }) async {
    final sameUser = _webSessionUser != null && _webSessionUser == username;
    final hasCookies = _matchingWebCookies(Uri.parse(baseUrl)).isNotEmpty;
    if (sameUser && hasCookies) {
      try {
        final checkUri = Uri.parse('$baseUrl/my/');
        final probe = await _sendWebRequest(method: 'GET', uri: checkUri);
        final finalProbe = probe.isRedirect
            ? await _followRedirects(probe, origin: checkUri)
            : probe;
        if (!_looksLikeLoginPage(finalProbe.body)) {
          return;
        }
      } catch (_) {
        // 网络抖动时继续走重登，避免把失效 cookie 继续传给 WebView。
      }
    }
    await _loginWebSession(username: username, password: password);
  }

  Future<void> _loginWebSession({
    required String username,
    required String password,
  }) async {
    _webCookies.clear();
    _webSessionUser = null;

    final loginUri = Uri.parse('$baseUrl/login/index.php');
    final loginPage = await _sendWebRequest(method: 'GET', uri: loginUri);
    final logintoken = _extractLoginToken(loginPage.body);
    if (logintoken.isEmpty) {
      throw MoodleApiException('未能获取官网登录令牌（logintoken）。');
    }

    var step = await _sendWebRequest(
      method: 'POST',
      uri: loginUri,
      body: Uri(
        queryParameters: <String, String>{
          'logintoken': logintoken,
          'username': username,
          'password': password,
        },
      ).query,
      contentType: ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      ),
    );

    if (step.isRedirect) {
      step = await _followRedirects(step, origin: loginUri);
    }

    final verify = await _sendWebRequest(
      method: 'GET',
      uri: Uri.parse('$baseUrl/my/'),
    );
    final finalVerify = verify.isRedirect
        ? await _followRedirects(verify, origin: Uri.parse('$baseUrl/my/'))
        : verify;

    if (_looksLikeLoginPage(finalVerify.body)) {
      throw MoodleApiException('官网会话建立失败，请检查账号密码后重试。');
    }

    _webSessionUser = username;
  }

  Future<_WebResponse> _followRedirects(
    _WebResponse firstResponse, {
    required Uri origin,
  }) async {
    var current = firstResponse;
    var currentUri = origin;
    for (var i = 0; i < 8; i++) {
      final location = current.location;
      if (!current.isRedirect || location == null || location.trim().isEmpty) {
        return current;
      }
      currentUri = currentUri.resolve(location);
      current = await _sendWebRequest(method: 'GET', uri: currentUri);
    }
    return current;
  }

  Future<_WebResponse> _sendWebRequest({
    required String method,
    required Uri uri,
    String? body,
    ContentType? contentType,
  }) async {
    final request = await _webHttpClient.openUrl(method, uri);
    request.followRedirects = false;
    request.maxRedirects = 0;
    final cookieHeader = _buildCookieHeader(uri);
    if (cookieHeader.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
    }
    if (contentType != null) {
      request.headers.contentType = contentType;
    }
    if (body != null && body.isNotEmpty) {
      request.add(utf8.encode(body));
    }

    final response = await request.close();
    _cacheWebCookies(response.cookies, uri);
    final responseBody = await utf8.decoder.bind(response).join();
    return _WebResponse(
      statusCode: response.statusCode,
      body: responseBody,
      location: response.headers.value(HttpHeaders.locationHeader),
    );
  }

  List<_StoredWebCookie> _matchingWebCookies(Uri uri) {
    final baseUri = Uri.parse(baseUrl);
    if (!_hasSameOrigin(uri, baseUri)) {
      return const <_StoredWebCookie>[];
    }

    final now = DateTime.now();
    _webCookies.removeWhere((cookie) => cookie.isExpired(now));
    final matches = _webCookies
        .where((cookie) => cookie.matches(uri, now))
        .toList(growable: false);
    matches.sort(
      (left, right) => right.path.length.compareTo(left.path.length),
    );
    return matches;
  }

  String _buildCookieHeader(Uri uri) {
    return _matchingWebCookies(
      uri,
    ).map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  void _cacheWebCookies(List<Cookie> cookies, Uri origin) {
    final baseUri = Uri.parse(baseUrl);
    if (!_hasSameOrigin(origin, baseUri)) {
      return;
    }

    final now = DateTime.now();
    for (final cookie in cookies) {
      final stored = _StoredWebCookie.fromCookie(
        cookie,
        origin,
        trustedDomain: cookieDomain,
        now: now,
      );
      if (stored == null) {
        continue;
      }
      _webCookies.removeWhere((existing) => existing.hasSameIdentity(stored));
      if (!stored.isExpired(now)) {
        _webCookies.add(stored);
      }
    }
  }

  String _extractLoginToken(String html) {
    final matches = RegExp(
      "name=[\"']logintoken[\"']\\s+value=[\"']([^\"']+)[\"']",
      caseSensitive: false,
    ).firstMatch(html);
    if (matches == null || matches.groupCount < 1) {
      return '';
    }
    return matches.group(1)?.trim() ?? '';
  }

  bool _looksLikeLoginPage(String html) {
    final normalized = html.toLowerCase();
    return normalized.contains('name="logintoken"') ||
        normalized.contains("name='logintoken'") ||
        normalized.contains('/login/index.php');
  }

  Future<dynamic> _callWebService({
    required String token,
    required String functionName,
    required Map<String, dynamic> parameters,
  }) async {
    final uri = Uri.parse('$baseUrl/webservice/rest/server.php');
    final formBody = <String, String>{
      'wstoken': token,
      'moodlewsrestformat': 'json',
      'wsfunction': functionName,
    };

    for (final entry in parameters.entries) {
      _appendFormField(formBody, entry.key, entry.value);
    }

    if (kDebugMode) {
      debugPrint('[Moodle] wsfunction=$functionName');
    }

    final response = await _httpClient.post(uri, body: formBody);
    if (response.statusCode != 200) {
      throw MoodleApiException(
        '接口 $functionName 调用失败（HTTP ${response.statusCode}）。',
      );
    }

    final body = _decodeDynamicJson(response.body);
    if (body is Map<String, dynamic>) {
      final exception = body['exception'];
      if (exception is String && exception.isNotEmpty) {
        throw MoodleApiException(_extractWsError(body));
      }
      return body;
    }
    if (body is List) {
      return body;
    }

    throw MoodleApiException('接口 $functionName 返回格式异常。');
  }

  List<Map<String, dynamic>> _extractEvents(Map<String, dynamic> response) {
    final dynamic eventsValue = response['events'];
    if (eventsValue is List) {
      return eventsValue
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }

    final dynamic data = response['data'];
    if (data is Map<String, dynamic>) {
      final nestedEvents = data['events'];
      if (nestedEvents is List) {
        return nestedEvents
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
      }
    }
    return const [];
  }

  int _extractNextCursor(
    Map<String, dynamic> response,
    List<Map<String, dynamic>> events,
    int currentCursor,
  ) {
    final fromResponse = _toInt(response['lastid']) != 0
        ? _toInt(response['lastid'])
        : _toInt(response['lasteventid']);
    if (fromResponse > currentCursor) {
      return fromResponse;
    }
    var maxEventId = currentCursor;
    for (final event in events) {
      final eventId = _toInt(event['id']);
      if (eventId > maxEventId) {
        maxEventId = eventId;
      }
    }
    return maxEventId;
  }

  bool _looksLikeAssignment(TimelineItem item) {
    final module = item.moduleName.toLowerCase();
    final activity = item.activityType.toLowerCase();
    final url = item.url.toLowerCase();
    return module.contains('assign') ||
        activity.contains('assign') ||
        url.contains('/mod/assign/');
  }

  bool _looksLikeForum(TimelineItem item) {
    final module = item.moduleName.toLowerCase();
    final activity = item.activityType.toLowerCase();
    final url = item.url.toLowerCase();
    return module.contains('forum') ||
        activity.contains('forum') ||
        url.contains('/mod/forum/');
  }

  bool _looksLikeMediaSite(TimelineItem item) {
    final module = item.moduleName.toLowerCase();
    final activity = item.activityType.toLowerCase();
    final url = item.url.toLowerCase();
    return module.contains('mediasite') ||
        activity.contains('mediasite') ||
        url.contains('/mod/mediasite/');
  }

  Future<int> _resolveAssignId({
    required String token,
    required TimelineItem item,
  }) async {
    return _resolveModuleInstanceId(
      token: token,
      item: item,
      moduleName: 'assign',
    );
  }

  Future<int> _resolveModuleInstanceId({
    required String token,
    required TimelineItem item,
    required String moduleName,
  }) async {
    final cmid = _extractCourseModuleId(item.url);
    if (cmid > 0) {
      final fromCourseModule = await _resolveModuleInstanceFromCourseModule(
        token: token,
        cmid: cmid,
        moduleName: moduleName,
      );
      if (fromCourseModule > 0) {
        return fromCourseModule;
      }
    }

    if (item.instanceId > 0) {
      final fromMaybeCmid = await _resolveModuleInstanceFromCourseModule(
        token: token,
        cmid: item.instanceId,
        moduleName: moduleName,
      );
      if (fromMaybeCmid > 0) {
        return fromMaybeCmid;
      }

      final fromInstance = await _resolveModuleInstanceByInstance(
        token: token,
        moduleName: moduleName,
        moduleInstanceId: item.instanceId,
      );
      if (fromInstance > 0) {
        return fromInstance;
      }
    }

    return 0;
  }

  Future<int> _resolveModuleInstanceFromCourseModule({
    required String token,
    required int cmid,
    required String moduleName,
  }) async {
    try {
      final raw = await _callWebService(
        token: token,
        functionName: 'core_course_get_course_module',
        parameters: <String, dynamic>{'cmid': cmid},
      );
      final data = _asJsonMap(raw);
      final cm = data['cm'];
      if (cm is Map) {
        final modname = (cm['modname'] as String?)?.toLowerCase() ?? '';
        if (modname != moduleName.toLowerCase()) {
          return 0;
        }
        return _toInt(cm['instance']);
      }
    } on MoodleApiException {
      return 0;
    }
    return 0;
  }

  Future<int> _resolveModuleInstanceByInstance({
    required String token,
    required String moduleName,
    required int moduleInstanceId,
  }) async {
    try {
      final raw = await _callWebService(
        token: token,
        functionName: 'core_course_get_course_module_by_instance',
        parameters: <String, dynamic>{
          'module': moduleName,
          'instance': moduleInstanceId,
        },
      );
      final data = _asJsonMap(raw);
      final cm = data['cm'];
      if (cm is Map) {
        final modname = (cm['modname'] as String?)?.toLowerCase() ?? '';
        if (modname != moduleName.toLowerCase()) {
          return 0;
        }
        return _toInt(cm['instance']);
      }
    } on MoodleApiException {
      return 0;
    }
    return 0;
  }

  Future<Map<String, dynamic>> _fetchAssignmentSummary({
    required String token,
    required int courseId,
    required int assignmentId,
  }) async {
    Map<String, dynamic> searchInResponse(dynamic rawResponse) {
      final response = _asJsonMap(rawResponse);
      final courses = response['courses'];
      if (courses is List) {
        for (final course in courses.whereType<Map>()) {
          final assignments = course['assignments'];
          if (assignments is List) {
            for (final assign in assignments.whereType<Map>()) {
              final candidateId = _toInt(assign['id']);
              if (candidateId == assignmentId) {
                return assign.cast<String, dynamic>();
              }
            }
          }
        }
      }
      return const {};
    }

    final scopedParams = <String, dynamic>{};
    if (courseId > 0) {
      scopedParams['courseids'] = <int>[courseId];
    }

    final scopedRaw = await _callWebService(
      token: token,
      functionName: 'mod_assign_get_assignments',
      parameters: scopedParams,
    );
    final fromScoped = searchInResponse(scopedRaw);
    if (fromScoped.isNotEmpty || courseId <= 0) {
      return fromScoped;
    }

    final globalRaw = await _callWebService(
      token: token,
      functionName: 'mod_assign_get_assignments',
      parameters: const <String, dynamic>{},
    );
    return searchInResponse(globalRaw);
  }

  Future<Map<String, dynamic>> _fetchAssignmentSubmissionStatus({
    required String token,
    required int assignmentId,
  }) async {
    final raw = await _callWebService(
      token: token,
      functionName: 'mod_assign_get_submission_status',
      parameters: <String, dynamic>{'assignid': assignmentId},
    );
    final response = _asJsonMap(raw);
    final lastAttempt = _asJsonMapOrEmpty(response['lastattempt']);
    final submission = _asJsonMapOrEmpty(lastAttempt['submission']);
    return <String, dynamic>{
      'lastattempt': lastAttempt,
      'submission': submission,
    };
  }

  bool _assignmentConfigEnabled(
    Map<String, dynamic> assignment,
    String plugin,
    String name,
  ) {
    final value = _assignmentConfigValue(assignment, plugin, name);
    return _toBool(value);
  }

  int _assignmentConfigInt(
    Map<String, dynamic> assignment,
    String plugin,
    String name,
  ) {
    final value = _assignmentConfigValue(assignment, plugin, name);
    return _toInt(value);
  }

  dynamic _assignmentConfigValue(
    Map<String, dynamic> assignment,
    String plugin,
    String name,
  ) {
    final configs = assignment['configs'];
    if (configs is! List) {
      return null;
    }
    for (final config in configs.whereType<Map>()) {
      final pluginName = (config['plugin'] as String?)?.toLowerCase() ?? '';
      final configName = (config['name'] as String?)?.toLowerCase() ?? '';
      if (pluginName == plugin.toLowerCase() &&
          configName == name.toLowerCase()) {
        return config['value'];
      }
    }
    return null;
  }

  bool _submissionPluginExists(
    Map<String, dynamic> submission,
    String pluginType,
  ) {
    final plugins = submission['plugins'];
    if (plugins is! List) {
      return false;
    }
    for (final plugin in plugins.whereType<Map>()) {
      final type = (plugin['type'] as String?)?.toLowerCase() ?? '';
      if (type == pluginType.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  List<SubmissionFile> _extractSubmissionFiles(
    Map<String, dynamic> submission,
  ) {
    final files = <SubmissionFile>[];
    final plugins = submission['plugins'];
    if (plugins is! List) {
      return files;
    }

    for (final plugin in plugins.whereType<Map>()) {
      final type = (plugin['type'] as String?)?.toLowerCase() ?? '';
      if (!type.contains('file')) {
        continue;
      }

      final fileAreas = plugin['fileareas'];
      if (fileAreas is! List) {
        continue;
      }

      for (final area in fileAreas.whereType<Map>()) {
        final areaFiles = area['files'];
        if (areaFiles is! List) {
          continue;
        }
        for (final file in areaFiles.whereType<Map>()) {
          files.add(
            SubmissionFile(
              fileName: _pickString(file.cast<String, dynamic>(), const [
                'filename',
                'fullname',
              ], '未命名文件'),
              fileUrl: _pickString(file.cast<String, dynamic>(), const [
                'fileurl',
                'url',
              ]),
              fileSize: _toInt(file['filesize'] ?? file['size']),
              mimeType: _pickString(file.cast<String, dynamic>(), const [
                'mimetype',
              ]),
              modifiedEpoch: _toInt(
                file['timemodified'] ?? file['datemodified'],
              ),
            ),
          );
        }
      }
    }

    return files;
  }

  List<SubmissionFile> _extractAssignmentIntroFiles(
    Map<String, dynamic> assignment, {
    required String token,
  }) {
    final files = <SubmissionFile>[];
    final attachments =
        assignment['introattachments'] ?? assignment['introfiles'];
    if (attachments is! List) {
      return files;
    }
    for (final raw in attachments.whereType<Map>()) {
      final data = raw.cast<String, dynamic>();
      files.add(
        SubmissionFile(
          fileName: _pickString(data, const ['filename', 'fullname'], '未命名文件'),
          fileUrl: _decoratePluginFileUrlWithToken(
            _pickString(data, const ['fileurl', 'url']),
            token: token,
          ),
          fileSize: _toInt(data['filesize'] ?? data['size']),
          mimeType: _pickString(data, const ['mimetype']),
          modifiedEpoch: _toInt(data['timemodified'] ?? data['datemodified']),
        ),
      );
    }
    return files;
  }

  List<ForumDiscussion> _extractForumDiscussions(dynamic value) {
    if (value is! List) {
      return const [];
    }
    final discussions = <ForumDiscussion>[];
    for (final raw in value.whereType<Map>()) {
      final data = raw.cast<String, dynamic>();
      final discussionId = _toInt(data['discussion'] ?? data['id']);
      discussions.add(
        ForumDiscussion(
          id: discussionId,
          subject: _pickString(data, const ['subject', 'name'], '无标题讨论'),
          messagePreview: _stripHtml(
            _pickString(data, const ['message', 'intro']),
          ),
          author: _pickString(data, const [
            'userfullname',
            'usermodifiedfullname',
            'usercreatedfullname',
          ], '未知用户'),
          timeModifiedEpoch: _toInt(
            data['timemodified'] ?? data['timecreated'],
          ),
          replyCount: _toInt(data['numreplies']),
          pinned: _toBool(data['pinned']),
          locked: _toBool(data['locked']),
          discussionUrl: discussionId <= 0
              ? ''
              : '$baseUrl/mod/forum/discuss.php?d=$discussionId',
        ),
      );
    }
    return discussions;
  }

  List<Map<String, dynamic>> _extractForums(dynamic response) {
    if (response is List) {
      return response
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }
    if (response is Map<String, dynamic>) {
      final forums = response['forums'];
      if (forums is List) {
        return forums
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
      }
    }
    return const [];
  }

  String _extractFeedback(Map<String, dynamic> submission) {
    final plugins = submission['plugins'];
    if (plugins is! List) {
      return '';
    }
    for (final plugin in plugins.whereType<Map>()) {
      final type = (plugin['type'] as String?)?.toLowerCase() ?? '';
      if (!type.contains('feedback')) {
        continue;
      }
      final editorFields = plugin['editorfields'];
      if (editorFields is List) {
        for (final field in editorFields.whereType<Map>()) {
          final text = field['text'];
          if (text is String && text.trim().isNotEmpty) {
            return text.trim();
          }
        }
      }
    }
    return '';
  }

  int _extractCourseModuleId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return 0;
    }
    return _toInt(uri.queryParameters['id']);
  }

  String _normalizeAssignmentIntroHtml(
    String rawHtml, {
    required List<SubmissionFile> introFiles,
    required String token,
  }) {
    var html = rawHtml.trim();
    if (html.isEmpty) {
      return '';
    }

    for (final file in introFiles) {
      final url = _decoratePluginFileUrlWithToken(file.fileUrl, token: token);
      if (url.isEmpty) {
        continue;
      }
      final fileName = file.fileName.trim();
      if (fileName.isEmpty) {
        continue;
      }
      final encoded = Uri.encodeComponent(fileName);
      html = html.replaceAll('@@PLUGINFILE@@/$fileName', url);
      html = html.replaceAll('@@PLUGINFILE@@/$encoded', url);
    }

    html = html.replaceAllMapped(
      RegExp(
        '(https?://[^"\\s>]*?/pluginfile\\.php[^"\\s>]*)',
        caseSensitive: false,
      ),
      (match) =>
          _decoratePluginFileUrlWithToken(match.group(1) ?? '', token: token),
    );

    html = html.replaceAllMapped(
      RegExp(
        '(https?://[^"\\s>]*?/webservice/pluginfile\\.php[^"\\s>]*)',
        caseSensitive: false,
      ),
      (match) =>
          _decoratePluginFileUrlWithToken(match.group(1) ?? '', token: token),
    );

    html = html.replaceAll('@@PLUGINFILE@@', baseUrl);
    return html;
  }

  String _decoratePluginFileUrlWithToken(String url, {required String token}) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return trimmed;
    }
    if (!uri.path.contains('/pluginfile.php')) {
      return trimmed;
    }
    final configuredBaseUri = Uri.parse(baseUrl);
    if ((uri.isAbsolute || uri.hasAuthority) &&
        !_hasSameOrigin(uri, configuredBaseUri)) {
      return trimmed;
    }
    if (uri.queryParameters['token']?.trim().isNotEmpty ?? false) {
      return trimmed;
    }
    final query = Map<String, String>.from(uri.queryParameters);
    query['token'] = token;
    return uri.replace(queryParameters: query).toString();
  }

  bool _hasSameOrigin(Uri left, Uri right) {
    return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
        left.host.toLowerCase() == right.host.toLowerCase() &&
        _effectivePort(left) == _effectivePort(right);
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort) {
      return uri.port;
    }
    return switch (uri.scheme.toLowerCase()) {
      'http' => 80,
      'https' => 443,
      _ => -1,
    };
  }

  Map<String, dynamic> _asJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    throw MoodleApiException('接口返回格式异常，预期对象。');
  }

  Map<String, dynamic> _asJsonMapOrEmpty(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const {};
  }

  dynamic _decodeDynamicJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw MoodleApiException('服务端返回了不可解析的 JSON。');
    }
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    final decoded = _decodeDynamicJson(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw MoodleApiException('服务端返回结构异常。');
  }

  String _extractWsError(
    Map<String, dynamic> json, {
    String fallback = '接口调用失败。',
  }) {
    final message = json['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
    final errorCode = json['errorcode'];
    if (errorCode is String && errorCode.trim().isNotEmpty) {
      return errorCode.trim();
    }
    final debuginfo = json['debuginfo'];
    if (debuginfo is String && debuginfo.trim().isNotEmpty) {
      return debuginfo.trim();
    }
    return fallback;
  }

  void _appendFormField(Map<String, String> form, String key, dynamic value) {
    if (value == null) {
      return;
    }
    if (value is Map<String, dynamic>) {
      for (final entry in value.entries) {
        _appendFormField(form, '$key[${entry.key}]', entry.value);
      }
      return;
    }
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        _appendFormField(form, '$key[$i]', value[i]);
      }
      return;
    }
    form[key] = value.toString();
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  bool _toBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == '1' || normalized == 'true';
    }
    return false;
  }

  bool _isAssignRecordError(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains(
          "can't find data record in database table assign",
        ) ||
        normalized.contains('invalidrecord');
  }

  int _timeSortValue(TimelineItem item) {
    final millis = item.sortTime?.millisecondsSinceEpoch;
    if (millis == null || millis <= 0) {
      return 253402300799000; // 9999-12-31
    }
    return millis;
  }

  String _stripHtml(String input) {
    if (input.isEmpty) {
      return '';
    }
    return input
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _pickString(
    Map<String, dynamic> json,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return fallback;
  }
}

class _StoredWebCookie {
  const _StoredWebCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.hostOnly,
    required this.secure,
    this.expires,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool hostOnly;
  final bool secure;
  final DateTime? expires;

  static _StoredWebCookie? fromCookie(
    Cookie cookie,
    Uri origin, {
    required String trustedDomain,
    required DateTime now,
  }) {
    final originHost = origin.host.trim().toLowerCase();
    final normalizedTrustedDomain = trustedDomain.trim().toLowerCase();
    if (originHost.isEmpty) {
      return null;
    }
    final rawDomain = (cookie.domain ?? '').trim().toLowerCase();
    final normalizedDomain = rawDomain.replaceFirst(RegExp(r'^\.+'), '');
    final hostOnly = normalizedDomain.isEmpty;
    final domain = hostOnly ? originHost : normalizedDomain;
    final isWithinTrustedDomain =
        normalizedTrustedDomain.isNotEmpty &&
        _domainMatches(originHost, normalizedTrustedDomain) &&
        _domainMatches(domain, normalizedTrustedDomain);
    if (domain.isEmpty ||
        domain.endsWith('.') ||
        (!hostOnly &&
            (!_domainMatches(originHost, domain) ||
                (domain != originHost && !isWithinTrustedDomain)))) {
      return null;
    }

    final rawPath = (cookie.path ?? '').trim();
    final path = rawPath.startsWith('/') ? rawPath : _defaultPath(origin);
    final maxAge = cookie.maxAge;
    final expires = maxAge == null
        ? cookie.expires
        : now.add(Duration(seconds: maxAge));
    return _StoredWebCookie(
      name: cookie.name,
      value: cookie.value,
      domain: domain,
      path: path,
      hostOnly: hostOnly,
      secure: cookie.secure,
      expires: expires,
    );
  }

  bool hasSameIdentity(_StoredWebCookie other) {
    return name == other.name && domain == other.domain && path == other.path;
  }

  bool matches(Uri uri, DateTime now) {
    if (isExpired(now) || (secure && uri.scheme.toLowerCase() != 'https')) {
      return false;
    }
    final host = uri.host.toLowerCase();
    final domainMatches = hostOnly
        ? host == domain
        : _domainMatches(host, domain);
    return domainMatches && _pathMatches(uri.path, path);
  }

  bool isExpired(DateTime now) {
    return expires != null && !expires!.isAfter(now);
  }

  static bool _domainMatches(String host, String domain) {
    return host == domain || host.endsWith('.$domain');
  }

  static bool _pathMatches(String requestPath, String cookiePath) {
    final normalizedRequestPath = requestPath.isEmpty ? '/' : requestPath;
    if (normalizedRequestPath == cookiePath) {
      return true;
    }
    if (!normalizedRequestPath.startsWith(cookiePath)) {
      return false;
    }
    return cookiePath.endsWith('/') ||
        normalizedRequestPath.length > cookiePath.length &&
            normalizedRequestPath[cookiePath.length] == '/';
  }

  static String _defaultPath(Uri origin) {
    final requestPath = origin.path;
    if (!requestPath.startsWith('/') || requestPath == '/') {
      return '/';
    }
    final lastSlash = requestPath.lastIndexOf('/');
    return lastSlash <= 0 ? '/' : requestPath.substring(0, lastSlash);
  }
}

class _WebResponse {
  _WebResponse({
    required this.statusCode,
    required this.body,
    required this.location,
  });

  final int statusCode;
  final String body;
  final String? location;

  bool get isRedirect =>
      statusCode == 301 || statusCode == 302 || statusCode == 303;
}
