import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ispace_timeline/services/bnbu_mis_client.dart';

void main() {
  group('MIS redirect credential isolation', () {
    late BnbuMisClient client;

    setUp(() {
      client = BnbuMisClient();
    });

    tearDown(() {
      client.dispose();
    });

    test('rejects cross-origin redirects that preserve a request body', () {
      expect(
        () => client.redirectRequestForTesting(
          method: 'POST',
          currentUri: Uri.parse('https://sso.example.edu/auth/login'),
          targetUri: Uri.parse('https://attacker.example/collect'),
          statusCode: HttpStatus.temporaryRedirect,
          body: '{"password":"secret"}',
          headers: const <String, String>{
            HttpHeaders.contentTypeHeader: 'application/json',
          },
        ),
        throwsA(isA<BnbuMisException>()),
      );
    });

    test('rejects cross-origin 308 redirects that preserve a body', () {
      expect(
        () => client.redirectRequestForTesting(
          method: 'POST',
          currentUri: Uri.parse('https://sso.example.edu/auth/login'),
          targetUri: Uri.parse('https://attacker.example/collect'),
          statusCode: HttpStatus.permanentRedirect,
          body: '{"password":"secret"}',
        ),
        throwsA(isA<BnbuMisException>()),
      );
    });

    test('keeps request bodies on same-origin 307 redirects', () {
      final redirect = client.redirectRequestForTesting(
        method: 'POST',
        currentUri: Uri.parse('https://sso.example.edu/auth/login'),
        targetUri: Uri.parse('https://sso.example.edu/auth/continue'),
        statusCode: HttpStatus.temporaryRedirect,
        body: '{"step":1}',
        headers: const <String, String>{
          HttpHeaders.contentTypeHeader: 'application/json',
        },
      );

      expect(redirect.method, 'POST');
      expect(redirect.body, '{"step":1}');
      expect(
        redirect.headers[HttpHeaders.contentTypeHeader],
        'application/json',
      );
    });

    test('drops sensitive headers after a safe cross-origin POST redirect', () {
      final redirect = client.redirectRequestForTesting(
        method: 'POST',
        currentUri: Uri.parse('https://sso.example.edu/auth/login'),
        targetUri: Uri.parse('https://mis.example.edu/home'),
        statusCode: HttpStatus.found,
        body: 'ticket=temporary',
        headers: const <String, String>{
          HttpHeaders.authorizationHeader: 'Bearer secret',
          HttpHeaders.cookieHeader: 'session=secret',
          HttpHeaders.refererHeader: 'https://sso.example.edu/auth/login',
          HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
          HttpHeaders.acceptHeader: 'text/html',
          'Origin': 'https://sso.example.edu',
        },
      );

      expect(redirect.method, 'GET');
      expect(redirect.body, isNull);
      expect(
        redirect.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains(HttpHeaders.authorizationHeader)),
      );
      expect(
        redirect.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains(HttpHeaders.cookieHeader)),
      );
      expect(
        redirect.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains(HttpHeaders.refererHeader)),
      );
      expect(
        redirect.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains(HttpHeaders.contentTypeHeader)),
      );
      expect(
        redirect.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('origin')),
      );
      expect(redirect.headers[HttpHeaders.acceptHeader], 'text/html');
    });
  });

  group('MIS cookie isolation', () {
    late BnbuMisClient client;

    setUp(() {
      client = BnbuMisClient();
    });

    tearDown(() {
      client.dispose();
    });

    test('honors host-only, path, and secure cookie scope', () {
      final cookie = Cookie('session', 'secret')
        ..path = '/auth'
        ..secure = true;
      client.storeCookieForTesting(
        cookie,
        Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
      );

      expect(
        client.cookieHeaderForTesting(
          Uri.parse('https://sso.bnbu.edu.cn/auth/continue'),
        ),
        'session=secret',
      );
      expect(
        client.cookieHeaderForTesting(
          Uri.parse('https://sso.bnbu.edu.cn/profile'),
        ),
        isEmpty,
      );
      expect(
        client.cookieHeaderForTesting(
          Uri.parse('https://sub.sso.bnbu.edu.cn/auth/continue'),
        ),
        isEmpty,
      );
      expect(
        client.cookieHeaderForTesting(
          Uri.parse('http://sso.bnbu.edu.cn/auth/continue'),
        ),
        isEmpty,
      );
    });

    test('rejects a cookie scoped to an unrelated domain', () {
      final cookie = Cookie('session', 'secret')
        ..domain = 'attacker.example'
        ..path = '/';
      client.storeCookieForTesting(
        cookie,
        Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
      );

      expect(
        client.cookieHeaderForTesting(
          Uri.parse('https://attacker.example/collect'),
        ),
        isEmpty,
      );
    });

    test('allows the trusted parent domain and rejects public suffixes', () {
      final parentCookie = Cookie('parent', 'allowed')
        ..domain = 'bnbu.edu.cn'
        ..path = '/';
      client.storeCookieForTesting(
        parentCookie,
        Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
      );
      final publicSuffixCookie = Cookie('suffix', 'secret')
        ..domain = 'cn'
        ..path = '/';
      client.storeCookieForTesting(
        publicSuffixCookie,
        Uri.parse('https://sso.bnbu.edu.cn/auth/login'),
      );

      expect(
        client.cookieHeaderForTesting(
          Uri.parse('https://sso.bnbu.edu.cn/auth/continue'),
        ),
        'parent=allowed',
      );
      expect(
        client.cookieHeaderForTesting(Uri.parse('https://portal.bnbu.edu.cn/')),
        'parent=allowed',
      );
    });
  });
}
