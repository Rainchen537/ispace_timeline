enum TaCourseRepeatType { weekly, singleWeek }

class TaCourseEntry {
  const TaCourseEntry({
    required this.id,
    required this.title,
    required this.location,
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
    required this.repeatType,
    this.weekStart,
  });

  final String id;
  final String title;
  final String location;
  final int weekday;
  final int startMinutes;
  final int endMinutes;
  final TaCourseRepeatType repeatType;
  final DateTime? weekStart;

  String get displayTitle => title.trim().isEmpty ? 'TA课' : title.trim();

  String get displayLocation => location.trim();

  String get timeRangeLabel =>
      '${formatMinutes(startMinutes)}-${formatMinutes(endMinutes)}';

  bool appliesToWeek(DateTime targetWeekStart) {
    if (repeatType == TaCourseRepeatType.weekly) {
      return true;
    }
    if (weekStart == null) {
      return false;
    }
    final normalizedTarget = normalizeWeekStart(targetWeekStart);
    final normalizedSelf = normalizeWeekStart(weekStart!);
    return normalizedTarget.year == normalizedSelf.year &&
        normalizedTarget.month == normalizedSelf.month &&
        normalizedTarget.day == normalizedSelf.day;
  }

  TaCourseEntry copyWith({
    String? id,
    String? title,
    String? location,
    int? weekday,
    int? startMinutes,
    int? endMinutes,
    TaCourseRepeatType? repeatType,
    DateTime? weekStart,
    bool clearWeekStart = false,
  }) {
    return TaCourseEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      location: location ?? this.location,
      weekday: weekday ?? this.weekday,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      repeatType: repeatType ?? this.repeatType,
      weekStart: clearWeekStart ? null : weekStart ?? this.weekStart,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'location': location,
      'weekday': weekday,
      'startMinutes': startMinutes,
      'endMinutes': endMinutes,
      'repeatType': repeatType.name,
      'weekStart': weekStart?.toIso8601String(),
    };
  }

  factory TaCourseEntry.fromJson(Map<String, dynamic> json) {
    final repeatTypeName = json['repeatType']?.toString() ?? 'weekly';
    final repeatType = repeatTypeName == TaCourseRepeatType.singleWeek.name
        ? TaCourseRepeatType.singleWeek
        : TaCourseRepeatType.weekly;
    final weekday = (json['weekday'] as num?)?.toInt() ?? 1;
    final startMinutes = (json['startMinutes'] as num?)?.toInt() ?? 8 * 60;
    final endMinutes = (json['endMinutes'] as num?)?.toInt() ?? 8 * 60 + 50;
    if (weekday < 1 || weekday > 7) {
      throw const FormatException('TA课 weekday 超出范围');
    }
    if (endMinutes <= startMinutes) {
      throw const FormatException('TA课结束时间必须晚于开始时间');
    }
    final parsedWeekStart = json['weekStart']?.toString();
    return TaCourseEntry(
      id: json['id']?.toString().trim().isNotEmpty == true
          ? json['id'].toString().trim()
          : DateTime.now().microsecondsSinceEpoch.toString(),
      title: json['title']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      weekday: weekday,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      repeatType: repeatType,
      weekStart: parsedWeekStart == null || parsedWeekStart.isEmpty
          ? null
          : normalizeWeekStart(DateTime.parse(parsedWeekStart)),
    );
  }

  static DateTime normalizeWeekStart(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  static String formatMinutes(int minutes) {
    final safeMinutes = minutes < 0 ? 0 : minutes;
    final hour = safeMinutes ~/ 60;
    final minute = safeMinutes % 60;
    return '$hour:${minute.toString().padLeft(2, '0')}';
  }
}
