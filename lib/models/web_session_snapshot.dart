class WebSessionCookie {
  WebSessionCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.hostOnly,
    required this.secure,
    this.expiresAt,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool hostOnly;
  final bool secure;
  final DateTime? expiresAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'name': name,
      'value': value,
      'domain': domain,
      'path': path,
      'hostOnly': hostOnly,
      'secure': secure,
      'expiresAt': expiresAt?.millisecondsSinceEpoch,
    };
  }
}

class WebSessionSnapshot {
  WebSessionSnapshot({required this.baseUrl, required this.cookies});

  final String baseUrl;
  final List<WebSessionCookie> cookies;
}
