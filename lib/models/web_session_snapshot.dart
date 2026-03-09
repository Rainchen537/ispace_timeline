class WebSessionCookie {
  WebSessionCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
  });

  final String name;
  final String value;
  final String domain;
  final String path;

  Map<String, String> toMap() {
    return <String, String>{
      'name': name,
      'value': value,
      'domain': domain,
      'path': path,
    };
  }
}

class WebSessionSnapshot {
  WebSessionSnapshot({required this.baseUrl, required this.cookies});

  final String baseUrl;
  final List<WebSessionCookie> cookies;
}
