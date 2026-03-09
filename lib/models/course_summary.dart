class CourseSummary {
  CourseSummary({
    required this.id,
    required this.fullName,
    required this.shortName,
    required this.categoryName,
    required this.progress,
  });

  final int id;
  final String fullName;
  final String shortName;
  final String categoryName;
  final int? progress;

  factory CourseSummary.fromJson(Map<String, dynamic> json) {
    return CourseSummary(
      id: _toInt(json['id']),
      fullName: _pickString(json, const ['fullname', 'displayname'], '未命名课程'),
      shortName: _pickString(json, const ['shortname']),
      categoryName: _pickString(json, const ['categoryname']),
      progress: _toNullableInt(json['progress']),
    );
  }

  static int _toInt(dynamic value) {
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

  static int? _toNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }
    final parsed = _toInt(value);
    return parsed;
  }

  static String _pickString(
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
