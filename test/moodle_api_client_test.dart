import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ispace_timeline/services/moodle_api_client.dart';

void main() {
  group('web cookie isolation', () {
    late MoodleApiClient client;

    setUp(() {
      client = MoodleApiClient(baseUrl: 'https://ispace.example.edu');
    });

    tearDown(() {
      client.dispose();
    });

    test('sends host-only cookies only to the exact host and path', () {
      final cookie = Cookie('MoodleSession', 'session-secret')..path = '/login';
      client.cacheWebCookieForTesting(
        cookie,
        Uri.parse('https://ispace.example.edu/login/index.php'),
      );

      expect(
        client.webCookieHeaderForTesting(
          Uri.parse('https://ispace.example.edu/login/verify.php'),
        ),
        'MoodleSession=session-secret',
      );
      expect(
        client.webCookieHeaderForTesting(
          Uri.parse('https://ispace.example.edu/my/'),
        ),
        isEmpty,
      );
      expect(
        client.webCookieHeaderForTesting(
          Uri.parse('https://cdn.ispace.example.edu/login/verify.php'),
        ),
        isEmpty,
      );
    });

    test('preserves host-only scope and replaces same-identity cookies', () {
      final domainCookie = Cookie('MoodleSession', 'old')
        ..domain = 'ispace.example.edu'
        ..path = '/';
      client.cacheWebCookieForTesting(
        domainCookie,
        Uri.parse('https://ispace.example.edu/login/index.php'),
      );
      final expiresAt = DateTime.utc(2030, 1, 2, 3, 4, 5);
      final hostOnlyCookie = Cookie('MoodleSession', 'new')
        ..path = '/'
        ..secure = true
        ..expires = expiresAt;
      client.cacheWebCookieForTesting(
        hostOnlyCookie,
        Uri.parse('https://ispace.example.edu/login/index.php'),
      );

      expect(
        client.webCookieHeaderForTesting(
          Uri.parse('https://ispace.example.edu/my/'),
        ),
        'MoodleSession=new',
      );
      final cookies = client.webSessionCookiesForTesting(
        Uri.parse('https://ispace.example.edu'),
      );
      expect(cookies, hasLength(1));
      expect(cookies.single.hostOnly, isTrue);
      expect(cookies.single.secure, isTrue);
      expect(cookies.single.expiresAt, expiresAt);
      expect(cookies.single.toMap()['hostOnly'], isTrue);
      expect(cookies.single.toMap()['secure'], isTrue);
      expect(
        cookies.single.toMap()['expiresAt'],
        expiresAt.millisecondsSinceEpoch,
      );
    });

    test('allows trusted parent domains and rejects public suffixes', () {
      final publicSuffixClient = MoodleApiClient(
        baseUrl: 'https://school.example.com',
        cookieDomain: 'example.com',
      );
      addTearDown(publicSuffixClient.dispose);
      final parentCookie = Cookie('parent', 'allowed')
        ..domain = 'example.com'
        ..path = '/';
      publicSuffixClient.cacheWebCookieForTesting(
        parentCookie,
        Uri.parse('https://school.example.com/login/index.php'),
      );
      final publicSuffixCookie = Cookie('session', 'secret')
        ..domain = 'com'
        ..path = '/';
      publicSuffixClient.cacheWebCookieForTesting(
        publicSuffixCookie,
        Uri.parse('https://school.example.com/login/index.php'),
      );

      expect(
        publicSuffixClient.webCookieHeaderForTesting(
          Uri.parse('https://school.example.com/my/'),
        ),
        'parent=allowed',
      );
      final snapshotCookies = publicSuffixClient.webSessionCookiesForTesting(
        Uri.parse('https://school.example.com'),
      );
      expect(snapshotCookies, hasLength(1));
      expect(snapshotCookies.single.domain, 'school.example.com');
      expect(snapshotCookies.single.hostOnly, isTrue);
      expect(
        publicSuffixClient.webCookieHeaderForTesting(
          Uri.parse('https://attacker.com/collect'),
        ),
        isEmpty,
      );
    });

    test('does not send secure or expired cookies ineligible for target', () {
      final secureCookie = Cookie('secure', 'value')
        ..path = '/'
        ..secure = true;
      client.cacheWebCookieForTesting(
        secureCookie,
        Uri.parse('https://ispace.example.edu/login/index.php'),
      );
      final expiredCookie = Cookie('expired', 'value')
        ..path = '/'
        ..maxAge = 0;
      client.cacheWebCookieForTesting(
        expiredCookie,
        Uri.parse('https://ispace.example.edu/login/index.php'),
      );

      expect(
        client.webCookieHeaderForTesting(
          Uri.parse('http://ispace.example.edu/my/'),
        ),
        isEmpty,
      );
      expect(
        client.webCookieHeaderForTesting(
          Uri.parse('https://ispace.example.edu/my/'),
        ),
        'secure=value',
      );
    });

    test('rejects cookies scoped to an unrelated domain', () {
      final cookie = Cookie('session', 'secret')
        ..domain = 'attacker.example'
        ..path = '/';
      client.cacheWebCookieForTesting(
        cookie,
        Uri.parse('https://ispace.example.edu/login/index.php'),
      );

      expect(
        client.webCookieHeaderForTesting(
          Uri.parse('https://attacker.example/collect'),
        ),
        isEmpty,
      );
    });
  });

  group('plugin file token decoration', () {
    late MoodleApiClient client;

    setUp(() {
      client = MoodleApiClient(baseUrl: 'https://ispace.example.edu');
    });

    tearDown(() {
      client.dispose();
    });

    test('adds the token to same-origin plugin files', () {
      expect(
        client.decoratePluginFileUrlWithTokenForTesting(
          'https://ispace.example.edu/pluginfile.php/1/report.pdf',
          token: 'student-token',
        ),
        'https://ispace.example.edu/pluginfile.php/1/report.pdf?token=student-token',
      );
    });

    test('does not leak the token to an external origin', () {
      expect(
        client.decoratePluginFileUrlWithTokenForTesting(
          'https://attacker.example/pluginfile.php/leak',
          token: 'student-token',
        ),
        'https://attacker.example/pluginfile.php/leak',
      );
    });

    test('does not treat a different port as the same origin', () {
      expect(
        client.decoratePluginFileUrlWithTokenForTesting(
          'https://ispace.example.edu:444/pluginfile.php/leak',
          token: 'student-token',
        ),
        'https://ispace.example.edu:444/pluginfile.php/leak',
      );
    });
  });
}
