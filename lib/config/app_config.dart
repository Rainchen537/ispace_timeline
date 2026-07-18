abstract final class AppConfig {
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

  static String normalizedHttpsBaseUrl(
    String value, {
    required String settingName,
  }) {
    final normalized = normalizedBaseUrl(value);
    final uri = Uri.tryParse(normalized);
    final schemeSeparator = normalized.indexOf('://');
    final authorityStart = schemeSeparator < 0
        ? normalized.length
        : schemeSeparator + 3;
    var authorityEnd = normalized.length;
    for (final delimiter in ['/', '?', '#']) {
      final index = normalized.indexOf(delimiter, authorityStart);
      if (index >= 0 && index < authorityEnd) {
        authorityEnd = index;
      }
    }
    final rawAuthority = normalized.substring(authorityStart, authorityEnd);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        rawAuthority.contains('@') ||
        normalized.contains('?') ||
        normalized.contains('#') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw FormatException(
        '$settingName 必须是没有用户信息、查询参数或片段的有效 HTTPS Base URL。',
      );
    }
    return normalized;
  }

  static String normalizedMailHost(
    String value, {
    required String settingName,
  }) {
    final normalized = value.trim().toLowerCase();
    final uri = Uri.tryParse('https://$normalized');
    if (normalized.isEmpty ||
        uri == null ||
        uri.host != normalized ||
        uri.hasPort ||
        uri.path.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw FormatException('$settingName 必须是有效的邮件服务器主机名。');
    }
    return normalized;
  }

  static String normalizedCookieDomain(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^\.+'), '')
        .replaceFirst(RegExp(r'\.+$'), '');
  }
}
