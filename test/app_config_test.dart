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

  test('cookie trust boundaries are normalized school domains', () {
    expect(AppConfig.ispaceCookieDomain, 'uic.edu.cn');
    expect(AppConfig.bnbuCookieDomain, 'bnbu.edu.cn');
    expect(
      AppConfig.normalizedCookieDomain('  .School.Example.  '),
      'school.example',
    );
  });
}
