abstract final class AppConfig {
  static const String environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'production',
  );

  static const String ispaceBaseUrl = String.fromEnvironment(
    'ISPACE_BASE_URL',
    defaultValue: 'https://ispace.uic.edu.cn',
  );

  static const String ispaceCookieDomain = String.fromEnvironment(
    'ISPACE_COOKIE_DOMAIN',
    defaultValue: 'uic.edu.cn',
  );

  static const String bnbuSsoBaseUrl = String.fromEnvironment(
    'BNBU_SSO_BASE_URL',
    defaultValue: 'https://sso.bnbu.edu.cn',
  );

  static const String bnbuMisBaseUrl = String.fromEnvironment(
    'BNBU_MIS_BASE_URL',
    defaultValue: 'https://mis.bnbu.edu.cn',
  );

  static const String bnbuPortalBaseUrl = String.fromEnvironment(
    'BNBU_PORTAL_BASE_URL',
    defaultValue: 'https://portal.bnbu.edu.cn',
  );

  static const String bnbuCookieDomain = String.fromEnvironment(
    'BNBU_COOKIE_DOMAIN',
    defaultValue: 'bnbu.edu.cn',
  );

  static const String bnbuMisServiceId = String.fromEnvironment(
    'BNBU_MIS_SERVICE_ID',
    defaultValue: '3bvkl8pks1ki04nirus0g',
  );

  static const String bnbuPortalServiceId = String.fromEnvironment(
    'BNBU_PORTAL_SERVICE_ID',
    defaultValue: 'na3j8azrv30vamqac8yg',
  );

  static const String mailIncomingServer = String.fromEnvironment(
    'BNBU_MAIL_IMAP_HOST',
    defaultValue: 'imap.exmail.qq.com',
  );

  static const String mailOutgoingServer = String.fromEnvironment(
    'BNBU_MAIL_SMTP_HOST',
    defaultValue: 'smtp.exmail.qq.com',
  );

  static const String mailWebBaseUrl = String.fromEnvironment(
    'BNBU_MAIL_WEB_BASE_URL',
    defaultValue: 'https://mail.bnbu.edu.cn',
  );

  static String normalizedBaseUrl(String value) {
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  static String normalizedCookieDomain(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^\.+'), '')
        .replaceFirst(RegExp(r'\.+$'), '');
  }
}
