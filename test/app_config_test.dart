import 'package:flutter_test/flutter_test.dart';
import 'package:ispace_timeline/config/app_config.dart';

void main() {
  test(
    'production endpoints default to HTTPS URLs without trailing slashes',
    () {
      final baseUrls = [
        AppConfig.ispaceBaseUrl,
        AppConfig.bnbuSsoBaseUrl,
        AppConfig.bnbuMisBaseUrl,
        AppConfig.bnbuPortalBaseUrl,
        AppConfig.mailWebBaseUrl,
      ];

      for (final value in baseUrls) {
        expect(Uri.parse(value).scheme, 'https');
        expect(value.endsWith('/'), isFalse);
      }
    },
  );

  test('normalizedBaseUrl trims whitespace and trailing slashes', () {
    expect(
      AppConfig.normalizedBaseUrl('  https://example.com///  '),
      'https://example.com',
    );
  });

  test('HTTPS base URLs reject credential-bearing or ambiguous values', () {
    expect(
      AppConfig.normalizedHttpsBaseUrl(
        ' https://example.com/// ',
        settingName: 'TEST_BASE_URL',
      ),
      'https://example.com',
    );

    for (final value in [
      'http://example.com',
      'https://user:pass@example.com',
      'https://@example.com',
      'https://example.com/path?next=other',
      'https://example.com?',
      'https://example.com/#fragment',
      'https://example.com#',
      'example.com',
    ]) {
      expect(
        () => AppConfig.normalizedHttpsBaseUrl(
          value,
          settingName: 'TEST_BASE_URL',
        ),
        throwsFormatException,
      );
    }
  });

  test('mail hosts reject schemes, ports, and paths', () {
    expect(
      AppConfig.normalizedMailHost(
        ' IMAP.EXAMPLE.COM ',
        settingName: 'TEST_MAIL_HOST',
      ),
      'imap.example.com',
    );

    for (final value in [
      'https://imap.example.com',
      'imap.example.com:993',
      'imap.example.com/path',
      '',
    ]) {
      expect(
        () =>
            AppConfig.normalizedMailHost(value, settingName: 'TEST_MAIL_HOST'),
        throwsFormatException,
      );
    }
  });

  test('cookie trust boundaries are normalized school domains', () {
    expect(AppConfig.ispaceCookieDomain, 'uic.edu.cn');
    expect(AppConfig.bnbuCookieDomain, 'bnbu.edu.cn');
    expect(
      AppConfig.normalizedCookieDomain('  .School.Example.  '),
      'school.example',
    );
  });
}
