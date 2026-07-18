import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ta_course_entry.dart';
import '../models/timetable_data.dart';
import '../models/timeline_item.dart';
import '../state/app_session_controller.dart';
import 'ta_course_manager_page.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key, required this.controller});

  final AppSessionController controller;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  static const String _legacyShowDeadlinesPreferenceKey =
      'schedule.show_deadlines';
  static const String _legacyTaCoursesPreferenceKey = 'schedule.ta_courses';
  static const String _showDeadlinesPreferenceKeyPrefix =
      'schedule.show_deadlines.v2';
  static const String _taCoursesPreferenceKeyPrefix = 'schedule.ta_courses.v2';
  static const List<Color> _coursePalette = <Color>[
    Color(0xFF0F766E),
    Color(0xFF2563EB),
    Color(0xFFDC2626),
    Color(0xFF7C3AED),
    Color(0xFFEA580C),
    Color(0xFF059669),
    Color(0xFF4F46E5),
    Color(0xFFC026D3),
    Color(0xFF0284C7),
    Color(0xFF65A30D),
    Color(0xFFB45309),
    Color(0xFFBE123C),
    Color(0xFF0891B2),
    Color(0xFF7C2D12),
    Color(0xFF16A34A),
    Color(0xFF4338CA),
    Color(0xFFA21CAF),
    Color(0xFF0D9488),
    Color(0xFF1D4ED8),
    Color(0xFFD97706),
    Color(0xFFB91C1C),
    Color(0xFF0369A1),
    Color(0xFF4D7C0F),
    Color(0xFF7E22CE),
    Color(0xFFB83280),
    Color(0xFF9A3412),
    Color(0xFF15803D),
    Color(0xFF5B21B6),
    Color(0xFFE11D48),
    Color(0xFF0EA5E9),
    Color(0xFFA16207),
    Color(0xFF334155),
  ];
  static const Color _nowPinColor = Color(0xFF2563EB);
  static const double _regularTimeColumnWidth = 48;
  static const double _compactTimeColumnWidth = 38;
  static const double _regularRowHeight = 72;
  static const double _compactRowHeight = 64;
  static const double _regularHeaderBaseHeight = 62;
  static const double _compactHeaderBaseHeight = 54;
  static const double _regularDeadlineGap = 4;
  static const double _compactDeadlineGap = 3;
  static const double _regularDeadlineEventHeight = 22;
  static const double _compactDeadlineEventHeight = 18;
  static const List<_SlotSpec> _slots = <_SlotSpec>[
    _SlotSpec('8:00 - 8:50', 8 * 60, 8 * 60 + 50),
    _SlotSpec('9:00 - 9:50', 9 * 60, 9 * 60 + 50),
    _SlotSpec('10:00 - 10:50', 10 * 60, 10 * 60 + 50),
    _SlotSpec('11:00 - 11:50', 11 * 60, 11 * 60 + 50),
    _SlotSpec('12:00 - 12:50', 12 * 60, 12 * 60 + 50),
    _SlotSpec('13:00 - 13:50', 13 * 60, 13 * 60 + 50),
    _SlotSpec('14:00 - 14:50', 14 * 60, 14 * 60 + 50),
    _SlotSpec('15:00 - 15:50', 15 * 60, 15 * 60 + 50),
    _SlotSpec('16:00 - 16:50', 16 * 60, 16 * 60 + 50),
    _SlotSpec('17:00 - 17:50', 17 * 60, 17 * 60 + 50),
    _SlotSpec('18:00 - 18:50', 18 * 60, 18 * 60 + 50),
    _SlotSpec('19:00 - 19:50', 19 * 60, 19 * 60 + 50),
    _SlotSpec('20:00 - 20:50', 20 * 60, 20 * 60 + 50),
    _SlotSpec('21:00 - 21:50', 21 * 60, 21 * 60 + 50),
  ];

  final DateFormat _fullDateFormatter = DateFormat('M月d日 HH:mm');
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _weekBoardKey = GlobalKey();
  final GlobalKey _currentTimePinKey = GlobalKey();
  late final Future<SharedPreferences> _preferencesFuture;
  late DateTime _visibleWeekStart;
  late DateTime _currentTime;
  Timer? _currentTimeTicker;
  List<TaCourseEntry> _taCourses = const [];
  bool _showDeadlines = true;
  bool _showDeadlineHint = false;
  bool _shouldLocateCurrentTime = false;
  int _taCoursesVersion = 0;
  int _deadlineVisibilityVersion = 0;
  int _deadlineHintSerial = 0;
  int _weekTransitionDirection = 0;

  String get _preferenceOwner {
    final username = widget.controller.username?.trim().toLowerCase() ?? '';
    if (username.isEmpty) {
      return 'signed-out';
    }
    return base64Url.encode(utf8.encode(username));
  }

  String get _showDeadlinesPreferenceKey =>
      '$_showDeadlinesPreferenceKeyPrefix.$_preferenceOwner';

  String get _taCoursesPreferenceKey =>
      '$_taCoursesPreferenceKeyPrefix.$_preferenceOwner';

  @override
  void initState() {
    super.initState();
    _preferencesFuture = SharedPreferences.getInstance();
    _currentTime = DateTime.now();
    _visibleWeekStart = _startOfWeek(_currentTime);
    _startCurrentTimeTicker();
    unawaited(_restoreDeadlineVisibility());
    unawaited(_restoreTaCourses());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = widget.controller;
      if (controller.timetable == null && !controller.isLoadingTimetable) {
        controller.refreshTimetable();
      }
    });
  }

  @override
  void dispose() {
    _currentTimeTicker?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final timetable = widget.controller.timetable;
        final isLoading = widget.controller.isLoadingTimetable;
        final timetableError = widget.controller.timetableError;

        return Scaffold(
          backgroundColor: const Color(0xFFF3F7FB),
          appBar: AppBar(
            titleSpacing: 12,
            title: _buildWeekTitle(context),
            actions: [
              _buildDeadlineActionButton(context),
              IconButton(
                onPressed: timetable == null
                    ? _goToCurrentWeek
                    : _locateCurrentTime,
                tooltip: '定位到当前时间',
                icon: const Icon(Icons.my_location_rounded),
              ),
              IconButton(
                onPressed: _openTaCourseManager,
                tooltip: '管理TA课',
                icon: const Icon(Icons.edit_calendar_rounded),
              ),
              IconButton(
                onPressed: isLoading ? null : _pickWeek,
                tooltip: '切换周',
                icon: const Icon(Icons.calendar_month_rounded),
              ),
              IconButton(
                onPressed: isLoading ? null : _refreshAll,
                tooltip: '刷新',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refreshAll,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    minimum: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Column(
                      children: [
                        if (isLoading)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        if (timetableError != null) ...[
                          _buildErrorCard(context, timetableError),
                        ],
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
                  sliver: SliverToBoxAdapter(
                    child: timetable == null
                        ? _buildEmptyState(context, isLoading: isLoading)
                        : KeyedSubtree(
                            key: _weekBoardKey,
                            child: _buildWeekBoard(context, timetable),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeekTitle(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F3FB),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          _weekRangeLabel(_visibleWeekStart),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: const Color(0xFF185B89),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  void _startCurrentTimeTicker() {
    _currentTimeTicker?.cancel();
    _currentTimeTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _currentTime = DateTime.now();
      });
    });
  }

  Future<void> _refreshAll() {
    return Future.wait<void>([
      widget.controller.refreshTimeline(),
      widget.controller.refreshTimetable(),
    ]);
  }

  Future<void> _pickWeek() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _visibleWeekStart,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      helpText: '选择所在周',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (!mounted || pickedDate == null) {
      return;
    }
    _setVisibleWeek(_startOfWeek(pickedDate));
  }

  void _shiftWeek(int deltaWeeks) {
    if (deltaWeeks == 0) {
      return;
    }
    _setVisibleWeek(
      _visibleWeekStart.add(Duration(days: 7 * deltaWeeks)),
      fallbackDirection: deltaWeeks.isNegative ? -1 : 1,
    );
  }

  void _goToCurrentWeek() {
    _setVisibleWeek(_startOfWeek(DateTime.now()));
  }

  void _locateCurrentTime() {
    setState(() {
      _shouldLocateCurrentTime = true;
    });
    _goToCurrentWeek();
  }

  void _setVisibleWeek(DateTime nextWeekStart, {int fallbackDirection = 0}) {
    final normalized = _startOfWeek(nextWeekStart);
    if (_isSameDate(normalized, _visibleWeekStart)) {
      return;
    }
    final direction = normalized.isAfter(_visibleWeekStart)
        ? 1
        : normalized.isBefore(_visibleWeekStart)
        ? -1
        : fallbackDirection;
    setState(() {
      _visibleWeekStart = normalized;
      _weekTransitionDirection = direction;
    });
  }

  void _toggleDeadlineVisibility() {
    final nextValue = !_showDeadlines;
    final nextSerial = _deadlineHintSerial + 1;
    _deadlineVisibilityVersion += 1;
    setState(() {
      _showDeadlines = nextValue;
      _showDeadlineHint = true;
      _deadlineHintSerial = nextSerial;
    });
    unawaited(_persistDeadlineVisibility(nextValue));
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 1100), () {
        if (!mounted || _deadlineHintSerial != nextSerial) {
          return;
        }
        setState(() {
          _showDeadlineHint = false;
        });
      }),
    );
  }

  Future<void> _openTaCourseManager() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaCourseManagerPage(
          initialEntries: _taCourses,
          onChanged: _updateTaCourses,
        ),
      ),
    );
  }

  Future<void> _restoreDeadlineVisibility() async {
    final restoreVersion = _deadlineVisibilityVersion;
    try {
      final preferences = await _preferencesFuture;
      final persistedValue = preferences.getBool(_showDeadlinesPreferenceKey);
      await preferences.remove(_legacyShowDeadlinesPreferenceKey);
      if (!mounted ||
          _deadlineVisibilityVersion != restoreVersion ||
          persistedValue == null ||
          persistedValue == _showDeadlines) {
        return;
      }
      setState(() {
        _showDeadlines = persistedValue;
      });
    } catch (_) {}
  }

  Future<void> _persistDeadlineVisibility(bool value) async {
    try {
      final preferences = await _preferencesFuture;
      await preferences.setBool(_showDeadlinesPreferenceKey, value);
    } catch (_) {}
  }

  Future<void> _restoreTaCourses() async {
    final restoreVersion = _taCoursesVersion;
    try {
      final preferences = await _preferencesFuture;
      final rawJson = preferences.getString(_taCoursesPreferenceKey);
      await preferences.remove(_legacyTaCoursesPreferenceKey);
      if (!mounted ||
          _taCoursesVersion != restoreVersion ||
          rawJson == null ||
          rawJson.isEmpty) {
        return;
      }
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) {
        return;
      }
      final restoredEntries = decoded
          .map(
            (item) =>
                TaCourseEntry.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false);
      setState(() {
        _taCourses = restoredEntries;
      });
    } catch (_) {}
  }

  Future<void> _persistTaCourses(List<TaCourseEntry> entries) async {
    try {
      final preferences = await _preferencesFuture;
      final payload = jsonEncode(
        entries.map((entry) => entry.toJson()).toList(),
      );
      await preferences.setString(_taCoursesPreferenceKey, payload);
    } catch (_) {}
  }

  void _updateTaCourses(List<TaCourseEntry> entries) {
    _taCoursesVersion += 1;
    setState(() {
      _taCourses = List<TaCourseEntry>.unmodifiable(entries);
    });
    unawaited(_persistTaCourses(entries));
  }

  Widget _buildDeadlineActionButton(BuildContext context) {
    const accentColor = Color(0xFFB42318);
    final hintText = 'DDL显示：${_showDeadlines ? '开' : '关'}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Tooltip(
        message: _showDeadlines ? 'DDL已显示' : 'DDL已隐藏',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: _toggleDeadlineVisibility,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: _showDeadlineHint ? 132 : 34,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: _showDeadlines ? accentColor : Colors.white,
                border: Border.all(
                  color: _showDeadlines
                      ? accentColor.withValues(alpha: 0.92)
                      : accentColor.withValues(alpha: 0.28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: _showDeadlines ? 0.14 : 0.06,
                    ),
                    blurRadius: _showDeadlines ? 12 : 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 36),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 140),
                            opacity: _showDeadlineHint ? 1 : 0,
                            child: Text(
                              hintText,
                              maxLines: 1,
                              overflow: TextOverflow.visible,
                              softWrap: false,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: _showDeadlines
                                        ? Colors.white
                                        : accentColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 34,
                        height: 34,
                        child: Icon(
                          Icons.assignment_late_rounded,
                          size: 18,
                          color: _showDeadlines ? Colors.white : accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F7),
        border: const Border(
          left: BorderSide(color: Color(0xFFDC2626), width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF991B1B),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, {required bool isLoading}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 48, 0, 0),
      child: Column(
        children: [
          const Icon(
            Icons.calendar_month_rounded,
            size: 44,
            color: Color(0xFF235789),
          ),
          const SizedBox(height: 14),
          Text(
            isLoading ? '正在同步课表…' : '还没有加载到课表',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '下拉刷新或点击右上角刷新后，会自动从 MIS 拉取当前学期课表。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5B6472)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildWeekBoard(BuildContext context, TimetableData timetable) {
    final weekDates = _weekDatesForStart(_visibleWeekStart);
    final weekDeadlines = _deadlinesForWeek(_visibleWeekStart);
    final visibleSlots = _buildVisibleSlots(
      weekDeadlines,
      taCourses: _taCourses.where(
        (entry) => entry.appliesToWeek(_visibleWeekStart),
      ),
    );
    final courseColors = _buildCourseColorMap(timetable, _taCourses);
    final meetingBlocks = _buildMeetingBlocks(
      timetable,
      visibleSlots,
      courseColors,
      visibleWeekStart: _visibleWeekStart,
    );
    final deadlinesByWeekday = <int, List<TimelineItem>>{
      for (final day in weekDates)
        day.weekday: _deadlinesOnDate(weekDeadlines, day),
    };
    final meetingsByWeekday = <int, List<_MeetingBlock>>{
      for (var weekday = 1; weekday <= 7; weekday++) weekday: <_MeetingBlock>[],
    };
    for (final block in meetingBlocks) {
      meetingsByWeekday[block.meeting.weekday]!.add(block);
    }
    final visibleDays = _resolveVisibleDays(
      weekDates,
      meetingsByWeekday: meetingsByWeekday,
      deadlinesByWeekday: deadlinesByWeekday,
    );
    final dayIndexByWeekday = <int, int>{
      for (var index = 0; index < visibleDays.length; index++)
        visibleDays[index].weekday: index,
    };
    _scheduleLocateCurrentTimeIfNeeded();

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 180) {
          return;
        }
        if (velocity < 0) {
          _shiftWeek(1);
        } else {
          _shiftWeek(-1);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 480;
          final timeColumnWidth = compact
              ? _compactTimeColumnWidth
              : _regularTimeColumnWidth;
          final rowHeight = compact ? _compactRowHeight : _regularRowHeight;
          final headerBaseHeight = compact
              ? _compactHeaderBaseHeight
              : _regularHeaderBaseHeight;
          final deadlineGap = compact
              ? _compactDeadlineGap
              : _regularDeadlineGap;
          final deadlineEventHeight = compact
              ? _compactDeadlineEventHeight
              : _regularDeadlineEventHeight;
          final nowPinSize = compact ? 16.0 : 18.0;
          final headerHeight = headerBaseHeight;
          final dayColumnWidth =
              (constraints.maxWidth - timeColumnWidth).clamp(
                0.0,
                double.infinity,
              ) /
              visibleDays.length;
          final totalHeight = visibleSlots.length * rowHeight;
          final nowMarker = _buildCurrentTimeMarker(
            visibleDays,
            dayIndexByWeekday: dayIndexByWeekday,
            visibleSlots: visibleSlots,
            rowHeight: rowHeight,
            markerSize: nowPinSize,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TweenAnimationBuilder<double>(
                key: ValueKey<String>(
                  '${_visibleWeekStart.toIso8601String()}-${visibleSlots.length}',
                ),
                tween: Tween<double>(
                  begin: _weekTransitionDirection * 0.08,
                  end: 0,
                ),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, offsetFactor, child) {
                  final opacity = (1 - offsetFactor.abs() * 4).clamp(0.0, 1.0);
                  return Transform.translate(
                    offset: Offset(constraints.maxWidth * offsetFactor, 0),
                    child: Opacity(opacity: opacity, child: child),
                  );
                },
                child: Column(
                  children: [
                    SizedBox(
                      height: headerHeight,
                      child: Row(
                        children: [
                          SizedBox(width: timeColumnWidth),
                          for (final day in visibleDays)
                            _buildDayHeader(
                              context,
                              day,
                              width: dayColumnWidth,
                              compact: compact,
                              hasCourses:
                                  (meetingsByWeekday[day.weekday]?.isNotEmpty ??
                                  false),
                              hasDeadlines:
                                  _showDeadlines &&
                                  (deadlinesByWeekday[day.weekday]
                                          ?.isNotEmpty ??
                                      false),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: totalHeight,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Row(
                              children: [
                                SizedBox(width: timeColumnWidth),
                                for (
                                  var day = 0;
                                  day < visibleDays.length;
                                  day++
                                )
                                  Container(
                                    width: dayColumnWidth,
                                    decoration: BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: Colors.black.withValues(
                                            alpha: 0.06,
                                          ),
                                        ),
                                        right: day == visibleDays.length - 1
                                            ? BorderSide(
                                                color: Colors.black.withValues(
                                                  alpha: 0.06,
                                                ),
                                              )
                                            : BorderSide.none,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          for (
                            var index = 0;
                            index < visibleSlots.length;
                            index++
                          )
                            if (index.isOdd)
                              Positioned(
                                left: timeColumnWidth,
                                right: 0,
                                top: index * rowHeight,
                                height: rowHeight,
                                child: Container(
                                  color: const Color(
                                    0xFF0F4C75,
                                  ).withValues(alpha: 0.028),
                                ),
                              ),
                          for (
                            var index = 0;
                            index <= visibleSlots.length;
                            index++
                          )
                            Positioned(
                              left: 0,
                              right: 0,
                              top: index * rowHeight,
                              child: Divider(
                                height: 1,
                                color: Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                          for (
                            var index = 0;
                            index < visibleSlots.length;
                            index++
                          )
                            Positioned(
                              left: 0,
                              top: index * rowHeight,
                              width: timeColumnWidth,
                              height: rowHeight,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: compact ? 4 : 6,
                                  top: 6,
                                  bottom: 6,
                                ),
                                child: _buildTimeAxisLabel(
                                  context,
                                  visibleSlots[index],
                                  compact: compact,
                                ),
                              ),
                            ),
                          for (final block in meetingBlocks)
                            if (dayIndexByWeekday[block.meeting.weekday]
                                case final dayIndex?)
                              _buildMeetingBlock(
                                context,
                                block,
                                dayIndex: dayIndex,
                                timeColumnWidth: timeColumnWidth,
                                dayColumnWidth: dayColumnWidth,
                                visibleSlots: visibleSlots,
                                rowHeight: rowHeight,
                                compact: compact,
                              ),
                          if (_showDeadlines)
                            for (final block in _buildDeadlineBlocks(
                              visibleDays,
                              deadlinesByWeekday,
                              visibleSlots: visibleSlots,
                              totalHeight: totalHeight,
                              height: deadlineEventHeight,
                              minGap: deadlineGap,
                            ))
                              _buildDeadlineBlock(
                                context,
                                block,
                                timeColumnWidth: timeColumnWidth,
                                dayColumnWidth: dayColumnWidth,
                                compact: compact,
                              ),
                          if (nowMarker != null)
                            _buildCurrentTimePin(
                              context,
                              nowMarker,
                              timeColumnWidth: timeColumnWidth,
                              dayColumnWidth: dayColumnWidth,
                              compact: compact,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDayHeader(
    BuildContext context,
    DateTime day, {
    required double width,
    required bool compact,
    required bool hasCourses,
    required bool hasDeadlines,
  }) {
    final headerTone = _headerTone(
      hasCourses: hasCourses,
      hasDeadlines: hasDeadlines,
    );
    final titleStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: headerTone.titleColor,
      fontWeight: FontWeight.w800,
      fontSize: compact ? 11 : 13,
    );
    final dateStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: headerTone.subtitleColor,
      fontSize: compact ? 10 : 11,
    );

    return SizedBox(
      width: width,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: compact ? 1.5 : 3),
        padding: EdgeInsets.fromLTRB(
          compact ? 4 : 8,
          compact ? 6 : 8,
          compact ? 4 : 8,
          compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: headerTone.background,
          border: Border.all(color: headerTone.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_weekdayLabel(day), style: titleStyle),
            const SizedBox(height: 2),
            Text(_dateLabel(day), style: dateStyle),
          ],
        ),
      ),
    );
  }

  void _scheduleLocateCurrentTimeIfNeeded() {
    if (!_shouldLocateCurrentTime) {
      return;
    }
    _shouldLocateCurrentTime = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final targetContext =
          _currentTimePinKey.currentContext ?? _weekBoardKey.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.32,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Widget _buildDeadlineBlock(
    BuildContext context,
    _DeadlineBlock block, {
    required double timeColumnWidth,
    required double dayColumnWidth,
    required bool compact,
  }) {
    final markerSize = block.height;
    return Positioned(
      left:
          timeColumnWidth +
          block.dayIndex * dayColumnWidth +
          (dayColumnWidth - markerSize) / 2,
      top: block.top,
      width: markerSize,
      height: markerSize,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDeadlineDetail(block.item),
          child: _buildDeadlineCard(
            context,
            block.item,
            compact: compact,
            height: block.height,
          ),
        ),
      ),
    );
  }

  Widget _buildDeadlineCard(
    BuildContext context,
    TimelineItem item, {
    required bool compact,
    required double height,
  }) {
    final accentColor = _deadlineAccentColor(item);
    return Tooltip(
      message: '${item.title}\n${_deadlineLabel(item)}',
      child: Container(
        width: height,
        height: height,
        decoration: BoxDecoration(
          color: accentColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.28),
              blurRadius: compact ? 6 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.assignment_late_rounded,
          size: compact ? 10 : 12,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTimeAxisLabel(
    BuildContext context,
    _SlotSpec slot, {
    required bool compact,
  }) {
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: const Color(0xFF778092),
      height: 1.05,
      fontSize: compact ? 9.5 : 10.5,
      fontWeight: FontWeight.w700,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(slot.startLabel, textAlign: TextAlign.right, style: textStyle),
        const Spacer(),
        Text(slot.endLabel, textAlign: TextAlign.right, style: textStyle),
      ],
    );
  }

  Widget _buildMeetingBlock(
    BuildContext context,
    _MeetingBlock block, {
    required int dayIndex,
    required double timeColumnWidth,
    required double dayColumnWidth,
    required List<_SlotSpec> visibleSlots,
    required double rowHeight,
    required bool compact,
  }) {
    final color = block.color;
    final secondaryText = block.meeting.room.isEmpty
        ? block.course.teacher
        : block.meeting.room;
    final horizontalInset = compact ? 2.0 : 4.0;
    final verticalInset = compact ? 3.0 : 5.0;
    final top =
        _verticalOffsetForScheduleMinutes(
          block.meeting.startMinutes.toDouble(),
          visibleSlots: visibleSlots,
          rowHeight: rowHeight,
        ) +
        verticalInset;
    final bottom =
        _verticalOffsetForScheduleMinutes(
          block.meeting.endMinutes.toDouble(),
          visibleSlots: visibleSlots,
          rowHeight: rowHeight,
        ) -
        verticalInset;
    final blockHeight = (bottom - top).clamp(compact ? 26.0 : 30.0, 9999.0);

    return Positioned(
      left: timeColumnWidth + dayIndex * dayColumnWidth + horizontalInset,
      top: top,
      width: dayColumnWidth - horizontalInset * 2,
      height: blockHeight,
      child: Material(
        color: color.withValues(alpha: 0.18),
        child: InkWell(
          onTap: () => _showCourseDetail(block),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: color, width: 3),
                top: BorderSide(color: color.withValues(alpha: 0.55)),
                right: BorderSide(color: color.withValues(alpha: 0.55)),
                bottom: BorderSide(color: color.withValues(alpha: 0.55)),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              compact ? 4 : 7,
              compact ? 5 : 7,
              compact ? 4 : 7,
              compact ? 4 : 7,
            ),
            child: _buildMeetingTextContent(
              context,
              title: block.course.name,
              secondaryText: secondaryText,
              compact: compact,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTimePin(
    BuildContext context,
    _CurrentTimeMarker marker, {
    required double timeColumnWidth,
    required double dayColumnWidth,
    required bool compact,
  }) {
    final markerSize = marker.size;
    return Positioned(
      left:
          timeColumnWidth +
          marker.dayIndex * dayColumnWidth +
          (dayColumnWidth - markerSize) / 2,
      top: marker.top,
      width: markerSize,
      height: markerSize,
      child: Tooltip(
        message: '当前时间 ${TaCourseEntry.formatMinutes(marker.minutes)}',
        child: Container(
          key: _currentTimePinKey,
          width: markerSize,
          height: markerSize,
          decoration: BoxDecoration(
            color: _nowPinColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _nowPinColor.withValues(alpha: 0.28),
                blurRadius: compact ? 6 : 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.push_pin_rounded,
            size: compact ? 10 : 12,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildMeetingTextContent(
    BuildContext context, {
    required String title,
    required String secondaryText,
    required bool compact,
  }) {
    final titleStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: const Color(0xFF102A43),
      fontWeight: FontWeight.w800,
      fontSize: compact ? 7.8 : 9.8,
      height: compact ? 1.1 : 1.15,
    );
    final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: const Color(0xFF0B6FA4),
      fontSize: compact ? 6.8 : 8.8,
      height: 1.15,
      fontWeight: FontWeight.w700,
    );

    if (secondaryText.isEmpty) {
      return Text(
        title,
        maxLines: compact ? 8 : 8,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final gap = compact ? 2.0 : 4.0;

        final titlePainter = _textPainter(
          context: context,
          text: title,
          style: titleStyle,
          maxWidth: width,
        );
        final titleLineHeight = titlePainter.preferredLineHeight;
        final secondaryPainter = _textPainter(
          context: context,
          text: secondaryText,
          style: secondaryStyle,
          maxWidth: width,
        );
        final secondaryLineHeight = secondaryPainter.preferredLineHeight;
        final secondaryLineCount = secondaryPainter.computeLineMetrics().length;
        final secondaryMaxLines =
            ((height - gap - titleLineHeight) / secondaryLineHeight)
                .floor()
                .clamp(1, 99);
        final displayedSecondaryLines = secondaryLineCount.clamp(
          1,
          secondaryMaxLines,
        );
        final displayedSecondaryHeight =
            displayedSecondaryLines * secondaryLineHeight;
        final remainingTitleHeight = (height - displayedSecondaryHeight - gap)
            .clamp(titleLineHeight, height);
        final titleMaxLines = (remainingTitleHeight / titleLineHeight)
            .floor()
            .clamp(1, 99);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  title,
                  maxLines: titleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
            ),
            SizedBox(height: gap),
            Text(
              secondaryText,
              maxLines: displayedSecondaryLines,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: secondaryStyle,
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCourseDetail(_MeetingBlock block) async {
    final course = block.course;
    final meeting = block.meeting;
    final accent = block.color;
    final taCourse = block.taCourse;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    border: Border(
                      left: BorderSide(color: accent, width: 4),
                      top: BorderSide(color: accent.withValues(alpha: 0.4)),
                      right: BorderSide(color: accent.withValues(alpha: 0.4)),
                      bottom: BorderSide(color: accent.withValues(alpha: 0.4)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meeting.room.isEmpty ? '未提供教室' : meeting.room,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        course.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        taCourse != null
                            ? 'TA课 · ${_taCourseRepeatLabel(taCourse)}'
                            : '${course.code.isEmpty ? '未提供课程代码' : course.code} · ${course.teacher}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF475467),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoRow(
                  '本次时间',
                  '${_weekdayLabelFromWeekday(meeting.weekday)} ${meeting.startLabel}-${meeting.endLabel}',
                ),
                if (taCourse != null)
                  _buildInfoRow('重复方式', _taCourseRepeatLabel(taCourse)),
                _buildInfoRow(
                  '课程类型',
                  taCourse != null
                      ? 'TA课'
                      : (course.category.isEmpty ? '未提供' : course.category),
                ),
                if (taCourse == null)
                  _buildInfoRow(
                    '学分',
                    course.units.isEmpty ? '未提供' : course.units,
                  ),
                if (taCourse == null)
                  _buildInfoRow(
                    '节次',
                    course.section.isEmpty ? '未提供' : course.section,
                  ),
                _buildInfoRow(
                  '本周全部上课时间',
                  taCourse != null
                      ? meeting.timeLabel
                      : course.meetings
                            .map((item) => item.timeLabel)
                            .join('  /  '),
                ),
                if (course.remark.isNotEmpty)
                  _buildInfoRow('备注', course.remark),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDeadlineDetail(TimelineItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFECE8),
                    border: Border(
                      left: BorderSide(color: Color(0xFFDC2626), width: 4),
                      top: BorderSide(color: Color(0x66DC2626)),
                      right: BorderSide(color: Color(0x66DC2626)),
                      bottom: BorderSide(color: Color(0x66DC2626)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.courseName.isEmpty ? '未提供课程信息' : item.courseName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFB42318),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoRow('截止时间', _deadlineLabel(item)),
                _buildInfoRow(
                  '状态',
                  item.isOverdue ? '已逾期' : item.activityState,
                ),
                if (item.description.isNotEmpty)
                  _buildInfoRow('说明', item.description),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  List<_MeetingBlock> _buildMeetingBlocks(
    TimetableData timetable,
    List<_SlotSpec> visibleSlots,
    Map<String, Color> courseColors, {
    required DateTime visibleWeekStart,
  }) {
    final blocks = <_MeetingBlock>[];
    for (final course in timetable.courses) {
      final seed = _courseSeed(course);
      final color = courseColors[seed] ?? _fallbackCourseColor(seed);
      for (final meeting in course.meetings) {
        if (meeting.endMinutes <= visibleSlots.first.startMinutes) {
          continue;
        }
        blocks.add(
          _MeetingBlock(
            color: color,
            course: course,
            meeting: meeting,
            taCourse: null,
          ),
        );
      }
    }
    for (final taCourse in _taCourses) {
      if (!taCourse.appliesToWeek(visibleWeekStart)) {
        continue;
      }
      final seed = _taCourseSeed(taCourse);
      final color = courseColors[seed] ?? _fallbackCourseColor(seed);
      final meeting = TimetableMeeting(
        weekday: taCourse.weekday,
        dayLabel: _weekdayShortLabelFromWeekday(taCourse.weekday),
        startLabel: TaCourseEntry.formatMinutes(taCourse.startMinutes),
        endLabel: TaCourseEntry.formatMinutes(taCourse.endMinutes),
        startMinutes: taCourse.startMinutes,
        endMinutes: taCourse.endMinutes,
        room: taCourse.displayLocation,
      );
      blocks.add(
        _MeetingBlock(
          color: color,
          course: TimetableCourse(
            section: 'TA',
            category: 'TA课',
            code: 'TA',
            name: taCourse.displayTitle,
            teacher: 'TA课',
            meetings: <TimetableMeeting>[meeting],
            rooms: taCourse.displayLocation.isEmpty
                ? const <String>[]
                : <String>[taCourse.displayLocation],
            units: '',
            remark: '',
          ),
          meeting: meeting,
          taCourse: taCourse,
        ),
      );
    }
    blocks.sort((left, right) {
      final weekdayCompare = left.meeting.weekday.compareTo(
        right.meeting.weekday,
      );
      if (weekdayCompare != 0) {
        return weekdayCompare;
      }
      return left.meeting.startMinutes.compareTo(right.meeting.startMinutes);
    });
    return blocks;
  }

  List<_DeadlineBlock> _buildDeadlineBlocks(
    List<DateTime> visibleDays,
    Map<int, List<TimelineItem>> deadlinesByWeekday, {
    required List<_SlotSpec> visibleSlots,
    required double totalHeight,
    required double height,
    required double minGap,
  }) {
    final blocks = <_DeadlineBlock>[];
    if (!_showDeadlines) {
      return blocks;
    }

    final maxTop = (totalHeight - height)
        .clamp(0.0, double.infinity)
        .toDouble();
    for (var dayIndex = 0; dayIndex < visibleDays.length; dayIndex++) {
      final items =
          deadlinesByWeekday[visibleDays[dayIndex].weekday] ?? const [];
      double lastBottom = -minGap;
      for (final item in items) {
        final due = item.sortTime?.toLocal();
        final dueMinutes = due == null
            ? visibleSlots.first.startMinutes.toDouble()
            : (due.hour * 60 + due.minute).toDouble();
        final desiredTop = _verticalOffsetForMinutes(
          dueMinutes,
          visibleSlots: visibleSlots,
          totalHeight: maxTop,
        );
        final top = desiredTop < lastBottom + minGap
            ? (lastBottom + minGap).clamp(0.0, maxTop).toDouble()
            : desiredTop;
        blocks.add(
          _DeadlineBlock(
            item: item,
            dayIndex: dayIndex,
            top: top,
            height: height,
          ),
        );
        lastBottom = top + height;
      }
    }
    return blocks;
  }

  List<TimelineItem> _deadlinesForWeek(DateTime weekStart) {
    final start = _startOfWeek(weekStart);
    final end = start.add(const Duration(days: 7));
    final items = widget.controller.timelineItems.where((item) {
      final due = item.sortTime?.toLocal();
      return due != null && !due.isBefore(start) && due.isBefore(end);
    }).toList();
    items.sort((left, right) {
      final leftTime = left.sortTime ?? start;
      final rightTime = right.sortTime ?? start;
      return leftTime.compareTo(rightTime);
    });
    return items;
  }

  List<TimelineItem> _deadlinesOnDate(List<TimelineItem> items, DateTime day) {
    return items
        .where(
          (item) =>
              item.sortTime != null &&
              _isSameDate(item.sortTime!.toLocal(), day),
        )
        .toList();
  }

  List<DateTime> _weekDatesForStart(DateTime weekStart) {
    final start = _startOfWeek(weekStart);
    return List<DateTime>.generate(
      7,
      (index) => start.add(Duration(days: index)),
    );
  }

  List<DateTime> _resolveVisibleDays(
    List<DateTime> weekDates, {
    required Map<int, List<_MeetingBlock>> meetingsByWeekday,
    required Map<int, List<TimelineItem>> deadlinesByWeekday,
  }) {
    bool hasVisibleEvents(int weekday) {
      final hasCourses = meetingsByWeekday[weekday]?.isNotEmpty ?? false;
      final hasDeadlines =
          _showDeadlines && (deadlinesByWeekday[weekday]?.isNotEmpty ?? false);
      return hasCourses || hasDeadlines;
    }

    final hasSaturdayEvents = hasVisibleEvents(DateTime.saturday);
    final hasSundayEvents = hasVisibleEvents(DateTime.sunday);

    return weekDates.where((day) {
      if (day.weekday <= DateTime.friday) {
        return true;
      }
      if (day.weekday == DateTime.saturday) {
        return hasSaturdayEvents || hasSundayEvents;
      }
      return hasSundayEvents;
    }).toList();
  }

  DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _weekRangeLabel(DateTime weekStart) {
    final end = weekStart.add(const Duration(days: 6));
    return '${weekStart.month}/${weekStart.day} - ${end.month}/${end.day}';
  }

  String _weekdayLabel(DateTime day) {
    return _weekdayLabelFromWeekday(day.weekday);
  }

  String _weekdayLabelFromWeekday(int weekday) {
    const labels = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return labels[weekday - 1];
  }

  String _weekdayShortLabelFromWeekday(int weekday) {
    const labels = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[weekday - 1];
  }

  String _dateLabel(DateTime day) {
    return '${day.month}/${day.day}';
  }

  List<_SlotSpec> _buildVisibleSlots(
    List<TimelineItem> weekDeadlines, {
    required Iterable<TaCourseEntry> taCourses,
  }) {
    final latestDeadlineMinutes = weekDeadlines.fold<int>(
      _slots.last.endMinutes,
      (currentLatest, item) {
        final due = item.sortTime?.toLocal();
        if (due == null) {
          return currentLatest;
        }
        return due.hour * 60 + due.minute > currentLatest
            ? due.hour * 60 + due.minute
            : currentLatest;
      },
    );
    final latestTaCourseMinutes = taCourses.fold<int>(
      _slots.last.endMinutes,
      (currentLatest, entry) =>
          entry.endMinutes > currentLatest ? entry.endMinutes : currentLatest,
    );
    final latestVisibleMinutes = latestDeadlineMinutes > latestTaCourseMinutes
        ? latestDeadlineMinutes
        : latestTaCourseMinutes;

    final visibleSlots = List<_SlotSpec>.from(_slots);
    var nextStart = _slots.last.startMinutes + 60;
    while (nextStart <= latestVisibleMinutes) {
      var nextEnd = nextStart + 50;
      if (nextStart + 60 > latestVisibleMinutes &&
          latestVisibleMinutes > nextEnd) {
        nextEnd = latestVisibleMinutes;
      }
      visibleSlots.add(
        _SlotSpec(
          '${_formatMinutes(nextStart)} - ${_formatMinutes(nextEnd)}',
          nextStart,
          nextEnd,
        ),
      );
      nextStart += 60;
    }
    return visibleSlots;
  }

  _HeaderTone _headerTone({
    required bool hasCourses,
    required bool hasDeadlines,
  }) {
    if (hasCourses && hasDeadlines) {
      return const _HeaderTone(
        background: Color(0xFFF1EBFF),
        border: Color(0xFFD9C8FF),
        titleColor: Color(0xFF5B2DA3),
        subtitleColor: Color(0xFF7C5AC3),
      );
    }
    if (hasDeadlines) {
      return const _HeaderTone(
        background: Color(0xFFFFECE8),
        border: Color(0xFFF8C4BA),
        titleColor: Color(0xFFB33927),
        subtitleColor: Color(0xFFCC5B4B),
      );
    }
    if (hasCourses) {
      return const _HeaderTone(
        background: Color(0xFFEAF4FF),
        border: Color(0xFFC7DCF6),
        titleColor: Color(0xFF215A9A),
        subtitleColor: Color(0xFF4E7DB5),
      );
    }
    return const _HeaderTone(
      background: Colors.transparent,
      border: Color(0x14000000),
      titleColor: Color(0xFF1F2937),
      subtitleColor: Color(0xFF6B7280),
    );
  }

  double _verticalOffsetForMinutes(
    double minutes, {
    required List<_SlotSpec> visibleSlots,
    required double totalHeight,
  }) {
    final earliest = visibleSlots.first.startMinutes.toDouble();
    final latest = visibleSlots.last.endMinutes.toDouble();
    final clampedMinutes = minutes.clamp(earliest, latest).toDouble();
    final range = latest - earliest;
    if (range <= 0 || totalHeight <= 0) {
      return 0;
    }
    return ((clampedMinutes - earliest) / range) * totalHeight;
  }

  double _verticalOffsetForScheduleMinutes(
    double minutes, {
    required List<_SlotSpec> visibleSlots,
    required double rowHeight,
  }) {
    if (visibleSlots.isEmpty) {
      return 0;
    }
    for (var index = 0; index < visibleSlots.length; index++) {
      final slot = visibleSlots[index];
      if (minutes <= slot.startMinutes) {
        return index * rowHeight;
      }
      if (minutes < slot.endMinutes) {
        final span = slot.endMinutes - slot.startMinutes;
        if (span <= 0) {
          return index * rowHeight;
        }
        final progress = (minutes - slot.startMinutes) / span;
        return index * rowHeight + progress * rowHeight;
      }
    }
    return visibleSlots.length * rowHeight;
  }

  _CurrentTimeMarker? _buildCurrentTimeMarker(
    List<DateTime> visibleDays, {
    required Map<int, int> dayIndexByWeekday,
    required List<_SlotSpec> visibleSlots,
    required double rowHeight,
    required double markerSize,
  }) {
    if (!_isSameDate(_visibleWeekStart, _startOfWeek(_currentTime))) {
      return null;
    }
    final dayIndex = dayIndexByWeekday[_currentTime.weekday];
    if (dayIndex == null || visibleDays.isEmpty) {
      return null;
    }
    final minutes = _currentTime.hour * 60 + _currentTime.minute;
    final top =
        _verticalOffsetForScheduleMinutes(
          minutes.toDouble(),
          visibleSlots: visibleSlots,
          rowHeight: rowHeight,
        ) -
        markerSize / 2;
    final maxTop = visibleSlots.length * rowHeight - markerSize;
    return _CurrentTimeMarker(
      dayIndex: dayIndex,
      top: top.clamp(0.0, maxTop).toDouble(),
      size: markerSize,
      minutes: minutes,
    );
  }

  TextPainter _textPainter({
    required BuildContext context,
    required String text,
    required TextStyle? style,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    return painter;
  }

  String _formatMinutes(int minutes) {
    final safeMinutes = minutes < 0 ? 0 : minutes;
    final hour = safeMinutes ~/ 60;
    final minute = safeMinutes % 60;
    final minuteLabel = minute.toString().padLeft(2, '0');
    return '$hour:$minuteLabel';
  }

  String _deadlineLabel(TimelineItem item) {
    if (item.sortTime != null) {
      return _fullDateFormatter.format(item.sortTime!.toLocal());
    }
    if (item.formattedTime.isNotEmpty) {
      return item.formattedTime;
    }
    return item.courseName.isEmpty ? '无时间信息' : item.courseName;
  }

  String _taCourseRepeatLabel(TaCourseEntry entry) {
    if (entry.repeatType == TaCourseRepeatType.weekly) {
      return '每周重复';
    }
    final weekStart = entry.weekStart;
    if (weekStart == null) {
      return '单独一周';
    }
    return '${weekStart.month}/${weekStart.day} 所在周';
  }

  Map<String, Color> _buildCourseColorMap(
    TimetableData timetable,
    Iterable<TaCourseEntry> taCourses,
  ) {
    final seeds = <String>{
      ...timetable.courses.map(_courseSeed),
      ...taCourses.map(_taCourseSeed),
    }.toList()..sort();
    final colorMap = <String, Color>{};
    final usedPaletteIndexes = <int>{};
    var overflowCount = 0;
    for (final seed in seeds) {
      final seedHash = seed.hashCode.abs();
      var paletteIndex = seedHash % _coursePalette.length;
      var probeSteps = 0;
      while (usedPaletteIndexes.contains(paletteIndex) &&
          probeSteps < _coursePalette.length) {
        paletteIndex = (paletteIndex + 1) % _coursePalette.length;
        probeSteps++;
      }
      if (probeSteps < _coursePalette.length) {
        usedPaletteIndexes.add(paletteIndex);
        colorMap[seed] = _coursePalette[paletteIndex];
        continue;
      }
      overflowCount++;
      final fallbackColor = _coursePalette[seedHash % _coursePalette.length];
      colorMap[seed] = _shiftCoursePaletteColor(fallbackColor, overflowCount);
    }
    return colorMap;
  }

  String _courseSeed(TimetableCourse course) {
    return course.code.isNotEmpty ? course.code : course.name;
  }

  String _taCourseSeed(TaCourseEntry entry) {
    return 'ta:${entry.id}';
  }

  Color _fallbackCourseColor(String seed) {
    return _coursePalette[seed.hashCode.abs() % _coursePalette.length];
  }

  Color _shiftCoursePaletteColor(Color baseColor, int variant) {
    final hsl = HSLColor.fromColor(baseColor);
    final adjustedLightness = (hsl.lightness + variant * 0.08).clamp(
      0.35,
      0.72,
    );
    final adjustedSaturation = (hsl.saturation - variant * 0.03).clamp(
      0.42,
      0.75,
    );
    return hsl
        .withLightness(adjustedLightness.toDouble())
        .withSaturation(adjustedSaturation.toDouble())
        .toColor();
  }

  Color _deadlineAccentColor(TimelineItem item) {
    return item.isOverdue ? const Color(0xFFB42318) : const Color(0xFFDC2626);
  }
}

class _SlotSpec {
  const _SlotSpec(this.label, this.startMinutes, this.endMinutes);

  final String label;
  final int startMinutes;
  final int endMinutes;

  String get startLabel => _format(startMinutes);

  String get endLabel => _format(endMinutes);

  static String _format(int minutes) {
    final safeMinutes = minutes < 0 ? 0 : minutes;
    final hour = safeMinutes ~/ 60;
    final minute = safeMinutes % 60;
    return '$hour:${minute.toString().padLeft(2, '0')}';
  }
}

class _MeetingBlock {
  const _MeetingBlock({
    required this.color,
    required this.course,
    required this.meeting,
    required this.taCourse,
  });

  final Color color;
  final TimetableCourse course;
  final TimetableMeeting meeting;
  final TaCourseEntry? taCourse;
}

class _CurrentTimeMarker {
  const _CurrentTimeMarker({
    required this.dayIndex,
    required this.top,
    required this.size,
    required this.minutes,
  });

  final int dayIndex;
  final double top;
  final double size;
  final int minutes;
}

class _DeadlineBlock {
  const _DeadlineBlock({
    required this.item,
    required this.dayIndex,
    required this.top,
    required this.height,
  });

  final TimelineItem item;
  final int dayIndex;
  final double top;
  final double height;
}

class _HeaderTone {
  const _HeaderTone({
    required this.background,
    required this.border,
    required this.titleColor,
    required this.subtitleColor,
  });

  final Color background;
  final Color border;
  final Color titleColor;
  final Color subtitleColor;
}
