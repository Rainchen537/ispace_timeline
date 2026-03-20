import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dart_sm/dart_sm.dart';

import '../models/portal_account_profile.dart';
import '../models/timetable_data.dart';

class BnbuMisException implements Exception {
  BnbuMisException(this.message);

  final String message;

  @override
  String toString() => 'BnbuMisException($message)';
}

class BnbuMisClient {
  BnbuMisClient() {
    _httpClient.userAgent =
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/145.0.0.0 Safari/537.36 Edg/145.0.0.0';
  }

  static const String _ssoBaseUrl = 'https://sso.bnbu.edu.cn';
  static const String _misBaseUrl = 'https://mis.bnbu.edu.cn';
  static const String _portalBaseUrl = 'https://portal.bnbu.edu.cn';
  static const String _misServiceId = '3bvkl8pks1ki04nirus0g';
  static const String _portalServiceId = 'na3j8azrv30vamqac8yg';
  static const String _misLaunchUrl =
      '$_ssoBaseUrl/auth/sso/ssoLogin?service=$_misServiceId';
  static const String _portalLaunchUrl =
      '$_ssoBaseUrl/auth/sso/ssoLogin?service=$_portalServiceId';
  static const String _htmlAcceptHeader = 'text/html,application/xhtml+xml,*/*';

  final HttpClient _httpClient = HttpClient();
  final List<_StoredCookie> _cookieJar = <_StoredCookie>[];
  final Random _random = Random();

  void dispose() {
    _httpClient.close(force: true);
  }

  Future<TimetableData> fetchTimetable({
    required String username,
    required String password,
  }) async {
    await _loginToSso(username: username, password: password);
    await _openMisSession(username: username);
    final timetableHtml = await _requestText(
      'GET',
      Uri.parse('$_misBaseUrl/mis/student/tts/timetable_min.do'),
      headers: const <String, String>{
        'X-Requested-With': 'XMLHttpRequest',
        HttpHeaders.refererHeader: '$_misBaseUrl/mis/usr/index.do',
        HttpHeaders.acceptHeader: '*/*',
      },
    );
    final data = TimetableData.fromHtml(timetableHtml);
    if (data.courses.isEmpty) {
      throw BnbuMisException('MIS 课表解析失败，请稍后重试。');
    }
    return data;
  }

  Future<PortalAccountProfile> fetchPortalAccountProfile({
    required String username,
    required String password,
  }) async {
    await _loginToSso(username: username, password: password);
    await _openPortalSession(username: username);

    final response = await _requestJson(
      'GET',
      Uri.parse(
        '$_portalBaseUrl/api/hrm/login/getAccountList'
        '?__random__=${DateTime.now().millisecondsSinceEpoch}',
      ),
      headers: const <String, String>{
        HttpHeaders.acceptHeader: '*/*',
        'X-Requested-With': 'XMLHttpRequest',
        HttpHeaders.refererHeader: '$_portalBaseUrl/wui/index.html',
      },
    );
    if (_stringOf(response['status']) != '1') {
      throw BnbuMisException('统一门户用户信息加载失败。');
    }

    final profile = PortalAccountProfile.fromPortalJson(
      _mapOf(response['data']),
    );
    if (profile.isEmpty) {
      throw BnbuMisException('未获取到统一门户账号信息。');
    }
    return profile;
  }

  Future<void> _loginToSso({
    required String username,
    required String password,
  }) async {
    _cookieJar.clear();
    await _request(
      'GET',
      Uri.parse('$_ssoBaseUrl/'),
      headers: const <String, String>{
        HttpHeaders.acceptHeader: _htmlAcceptHeader,
      },
    );

    final publicKey = await _loadSm2PublicKey();
    final loginResponse = await _requestJson(
      'POST',
      Uri.parse('$_ssoBaseUrl/auth/pwd/tencent/login'),
      body: <String, dynamic>{
        'userName': username,
        'password': _encryptPassword(password, publicKey),
        'randomP': _randomPayload(),
      },
    );
    final loginData = _mapOf(loginResponse['data']);
    final message = _stringOf(loginData['message']);
    if (_boolOf(loginData['success']) != true) {
      if (_boolOf(loginData['needVerifyCode']) == true) {
        throw BnbuMisException(
          message.isNotEmpty ? message : '统一认证要求验证码，当前版本暂不支持。',
        );
      }
      throw BnbuMisException(message.isNotEmpty ? message : '统一认证登录失败。');
    }
  }

  Future<String> _loadSm2PublicKey() async {
    final response = await _requestJson(
      'GET',
      Uri.parse('$_ssoBaseUrl/auth/flow/login/getSm2PubK'),
    );
    final key = _stringOf(response['data']);
    if (key.isEmpty) {
      throw BnbuMisException('未获取到统一认证公钥。');
    }
    return key;
  }

  Future<void> _openMisSession({required String username}) async {
    final launchCandidates = <Uri>[
      Uri.parse(
        '$_ssoBaseUrl/auth/sso/login/$_misServiceId'
        '?service=$_misServiceId&accountName=${Uri.encodeQueryComponent(username)}',
      ),
      Uri.parse(_misLaunchUrl),
    ];

    _Response? launch;
    for (final candidate in launchCandidates) {
      final response = await _request(
        'GET',
        candidate,
        headers: const <String, String>{
          HttpHeaders.acceptHeader: _htmlAcceptHeader,
        },
      );
      final settled = await _followHtmlRedirectPages(response);
      if (_looksLikeMisUri(settled.uri)) {
        launch = settled;
        break;
      }
    }

    if (launch == null) {
      throw BnbuMisException('未能打开 MIS 单点登录入口。');
    }

    final indexResponse = await _request(
      'GET',
      Uri.parse('$_misBaseUrl/mis/usr/index.do'),
      headers: const <String, String>{
        HttpHeaders.acceptHeader: _htmlAcceptHeader,
      },
    );
    if (!_looksLikeMisUri(indexResponse.uri) ||
        !indexResponse.body.contains('BNBU MIS')) {
      throw BnbuMisException('MIS 会话建立失败，请重新登录后重试。');
    }
  }

  Future<void> _openPortalSession({required String username}) async {
    final launchCandidates = <Uri>[
      Uri.parse(
        '$_ssoBaseUrl/auth/sso/login/$_portalServiceId'
        '?service=$_portalServiceId&accountName=${Uri.encodeQueryComponent(username)}',
      ),
      Uri.parse(_portalLaunchUrl),
      Uri.parse(_portalBaseUrl),
      Uri.parse('$_portalBaseUrl/wui/index.html'),
    ];

    _Response? launch;
    for (final candidate in launchCandidates) {
      final response = await _request(
        'GET',
        candidate,
        headers: const <String, String>{
          HttpHeaders.acceptHeader: _htmlAcceptHeader,
        },
      );
      final settled = await _followHtmlRedirectPages(response);
      if (_looksLikePortalUri(settled.uri)) {
        launch = settled;
        break;
      }
    }

    if (launch == null) {
      throw BnbuMisException('未能打开统一门户入口。');
    }

    final indexResponse = await _request(
      'GET',
      Uri.parse('$_portalBaseUrl/wui/index.html'),
      headers: const <String, String>{
        HttpHeaders.acceptHeader: _htmlAcceptHeader,
      },
    );
    if (!_looksLikePortalUri(indexResponse.uri)) {
      throw BnbuMisException('统一门户会话建立失败，请重新登录后重试。');
    }
  }

  String _encryptPassword(String password, String rawPublicKey) {
    final encrypted = SM2.encrypt(password, '04$rawPublicKey');
    return encrypted.startsWith('04') ? encrypted : '04$encrypted';
  }

  String _randomPayload() {
    final left = (_random.nextDouble()).toStringAsFixed(5);
    final right = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return '$left$right';
  }

  bool _looksLikeMisUri(Uri uri) {
    return uri.host == Uri.parse(_misBaseUrl).host;
  }

  bool _looksLikePortalUri(Uri uri) {
    return uri.host == Uri.parse(_portalBaseUrl).host;
  }

  Future<_Response> _followHtmlRedirectPages(
    _Response response, {
    int limit = 6,
  }) async {
    var current = response;
    for (var index = 0; index < limit; index++) {
      if (_looksLikeMisUri(current.uri)) {
        return current;
      }
      final redirectPath = _extractHtmlRedirectPath(current.body);
      if (redirectPath == null) {
        return current;
      }
      current = await _request(
        'GET',
        current.uri.resolve(redirectPath),
        headers: const <String, String>{
          HttpHeaders.acceptHeader: _htmlAcceptHeader,
        },
      );
    }
    return current;
  }

  String? _extractHtmlRedirectPath(String body) {
    if (body.isEmpty) {
      return null;
    }

    final patterns = <RegExp>[
      RegExp(r'''redirect\(['"]([^'"]+)['"]\)''', caseSensitive: false),
      RegExp(
        r'''location\.replace\(['"]([^'"]+)['"]\)''',
        caseSensitive: false,
      ),
      RegExp(
        r'''<meta[^>]+http-equiv=['"]refresh['"][^>]+url=([^'"> ]+)''',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      final path = match?.group(1)?.trim();
      if (path != null && path.isNotEmpty) {
        return path;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final response = await _request(
      method,
      uri,
      headers: <String, String>{
        HttpHeaders.contentTypeHeader: 'application/json',
        if (headers != null) ...headers,
      },
      body: body == null ? null : jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BnbuMisException('请求失败（HTTP ${response.statusCode}）。');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw BnbuMisException('接口返回格式异常。');
    }
    return decoded;
  }

  Future<String> _requestText(
    String method,
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final response = await _request(method, uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BnbuMisException('请求失败（HTTP ${response.statusCode}）。');
    }
    return response.body;
  }

  Future<_Response> _request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
    int redirectLimit = 8,
  }) async {
    var currentMethod = method.toUpperCase();
    var currentUri = uri;
    var currentBody = body;

    for (
      var redirectCount = 0;
      redirectCount <= redirectLimit;
      redirectCount++
    ) {
      final request = await _httpClient.openUrl(currentMethod, currentUri);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptLanguageHeader,
        'zh-CN,zh;q=0.9,en;q=0.8',
      );
      if (headers != null) {
        headers.forEach(request.headers.set);
      }
      for (final cookie in _matchingCookies(currentUri)) {
        request.cookies.add(cookie.toCookie());
      }
      if (currentBody != null) {
        request.write(currentBody);
      }

      final response = await request.close();
      _storeCookies(response.cookies, currentUri);
      final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
        buffer.addAll(chunk);
        return buffer;
      });

      if (_isRedirect(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || location.isEmpty) {
          return _Response(
            uri: currentUri,
            statusCode: response.statusCode,
            body: utf8.decode(bytes, allowMalformed: true),
          );
        }
        currentUri = currentUri.resolve(location);
        if (response.statusCode == HttpStatus.seeOther ||
            ((response.statusCode == HttpStatus.movedTemporarily ||
                    response.statusCode == HttpStatus.found) &&
                currentMethod == 'POST')) {
          currentMethod = 'GET';
          currentBody = null;
        }
        continue;
      }

      return _Response(
        uri: currentUri,
        statusCode: response.statusCode,
        body: utf8.decode(bytes, allowMalformed: true),
      );
    }

    throw BnbuMisException('请求跳转过多，请稍后重试。');
  }

  Iterable<_StoredCookie> _matchingCookies(Uri uri) sync* {
    final now = DateTime.now();
    for (final cookie in _cookieJar) {
      if (cookie.isExpired(now)) {
        continue;
      }
      if (cookie.matches(uri)) {
        yield cookie;
      }
    }
  }

  void _storeCookies(List<Cookie> cookies, Uri uri) {
    final now = DateTime.now();
    for (final cookie in cookies) {
      final stored = _StoredCookie.fromCookie(cookie, uri);
      _cookieJar.removeWhere(
        (existing) =>
            existing.name == stored.name &&
            existing.domain == stored.domain &&
            existing.path == stored.path,
      );
      if (!stored.isExpired(now)) {
        _cookieJar.add(stored);
      }
    }
  }

  bool _isRedirect(int statusCode) {
    return statusCode == HttpStatus.movedPermanently ||
        statusCode == HttpStatus.found ||
        statusCode == HttpStatus.seeOther ||
        statusCode == HttpStatus.temporaryRedirect ||
        statusCode == HttpStatus.permanentRedirect;
  }

  Map<String, dynamic> _mapOf(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  String _stringOf(dynamic value) {
    if (value is String) {
      return value.trim();
    }
    return '';
  }

  bool? _boolOf(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    return null;
  }
}

class _Response {
  const _Response({
    required this.uri,
    required this.statusCode,
    required this.body,
  });

  final Uri uri;
  final int statusCode;
  final String body;
}

class _StoredCookie {
  _StoredCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.secure,
    this.expires,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final DateTime? expires;

  factory _StoredCookie.fromCookie(Cookie cookie, Uri uri) {
    final domain = (cookie.domain ?? '').trim().replaceFirst(
      RegExp(r'^\.+'),
      '',
    );
    final path = (cookie.path ?? '').trim();
    return _StoredCookie(
      name: cookie.name,
      value: cookie.value,
      domain: domain.isEmpty ? uri.host : domain,
      path: path.isEmpty ? '/' : path,
      secure: cookie.secure,
      expires: cookie.expires,
    );
  }

  Cookie toCookie() {
    final cookie = Cookie(name, value);
    cookie.domain = domain;
    cookie.path = path;
    cookie.secure = secure;
    if (expires != null) {
      cookie.expires = expires;
    }
    return cookie;
  }

  bool matches(Uri uri) {
    final host = uri.host.toLowerCase();
    final domainMatch =
        host == domain.toLowerCase() ||
        host.endsWith('.${domain.toLowerCase()}');
    final pathMatch = uri.path.isEmpty
        ? path == '/'
        : uri.path.startsWith(path.isEmpty ? '/' : path);
    final secureMatch = !secure || uri.scheme == 'https';
    return domainMatch && pathMatch && secureMatch;
  }

  bool isExpired(DateTime now) {
    return expires != null && expires!.isBefore(now);
  }
}
