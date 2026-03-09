import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/course_content.dart';
import '../models/course_summary.dart';
import '../models/timeline_item.dart';
import '../state/app_session_controller.dart';
import 'folder_detail_page.dart';
import 'timeline_detail_page.dart';
import 'web_mirror_page.dart';

enum TimelineDateFilter {
  all,
  overdue,
  next7Days,
  next30Days,
  next3Months,
  next6Months,
}

enum TimelineSortMode { byDates, byCourses }

enum IspaceSection {
  dashboard,
  sitePagesMyCourses,
  sitePagesBlogs,
  sitePagesBadges,
  sitePagesTags,
  sitePagesAnnouncements,
  myCourses,
}

class IspacePage extends StatefulWidget {
  const IspacePage({
    super.key,
    required this.controller,
    required this.onGoToUserTab,
  });

  final AppSessionController controller;
  final VoidCallback onGoToUserTab;

  @override
  State<IspacePage> createState() => _IspacePageState();
}

class _IspacePageState extends State<IspacePage> {
  static const String _dateFilterPreferenceKey = 'ispace.dashboard.date_filter';
  static const String _sortModePreferenceKey = 'ispace.dashboard.sort_mode';
  final _dayFormatter = DateFormat('EEEE, d MMMM yyyy', 'en_US');
  final _hourFormatter = DateFormat('HH:mm');
  final _courseTimeFormatter = DateFormat('yyyy-MM-dd HH:mm');
  late final Future<SharedPreferences> _preferencesFuture;

  IspaceSection _section = IspaceSection.dashboard;
  TimelineDateFilter _dateFilter = TimelineDateFilter.all;
  TimelineSortMode _sortMode = TimelineSortMode.byDates;
  bool _sitePagesExpanded = false;
  bool _myCoursesExpanded = true;
  CourseSummary? _activeCourse;
  bool _isLoadingActiveCourse = false;
  String? _activeCourseError;
  List<CourseContentSection> _activeCourseSections = const [];
  final Map<IspaceSection, int> _webMirrorReloadSeeds = <IspaceSection, int>{};

  @override
  void initState() {
    super.initState();
    _preferencesFuture = SharedPreferences.getInstance();
    unawaited(_restoreDashboardPreferences());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F7FB),
          appBar: AppBar(
            title: Text(_sectionLabel(_section)),
            centerTitle: false,
            actions: [
              IconButton(
                onPressed: widget.controller.isBusy
                    ? null
                    : _refreshCurrentSection,
                tooltip: '刷新',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          drawer: _buildDrawer(context),
          body: widget.controller.isLoggedIn
              ? _buildLoggedInBody(context)
              : _buildNeedLogin(context),
        );
      },
    );
  }

  Widget _buildNeedLogin(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildHeroCard('iSpace Workspace', '请先登录后加载课程与 Timeline 功能'),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 44,
                      color: Color(0xFF235789),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '请先登录 iSpace',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '登录后可在此页面直接查看课程、作业与 Timeline 详情。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: widget.onGoToUserTab,
                      child: const Text('去 User 登录'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoggedInBody(BuildContext context) {
    switch (_section) {
      case IspaceSection.dashboard:
        return _buildDashboardBody(context);
      case IspaceSection.sitePagesMyCourses:
        return _buildSitePagesMyCoursesBody(context);
      case IspaceSection.sitePagesBlogs:
        return _buildSitePagesWebMirrorBody(
          context,
          pathOrUrl: '/blog/index.php',
        );
      case IspaceSection.sitePagesBadges:
        return _buildSitePagesWebMirrorBody(
          context,
          pathOrUrl: '/badges/view.php?type=1',
        );
      case IspaceSection.sitePagesTags:
        return _buildSitePagesWebMirrorBody(
          context,
          pathOrUrl: '/tag/search.php',
        );
      case IspaceSection.sitePagesAnnouncements:
        return _buildSiteAnnouncementsBody(context);
      case IspaceSection.myCourses:
        return _buildCoursesBody(context);
    }
  }

  Widget _buildDashboardBody(BuildContext context) {
    final filtered = _filteredTimeline(widget.controller.timelineItems);
    final entries = _sortMode == TimelineSortMode.byCourses
        ? _buildCourseEntries(filtered)
        : _buildDateEntries(filtered);

    return RefreshIndicator(
      onRefresh: widget.controller.refreshTimeline,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  _buildControlPanel(context),
                  if (widget.controller.error != null) ...[
                    const SizedBox(height: 12),
                    _buildErrorBox(context, widget.controller.error!),
                  ],
                  if (widget.controller.isLoadingTimeline)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            sliver: entries.isEmpty
                ? SliverToBoxAdapter(child: _buildEmptyState(context))
                : SliverList.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      if (entry is _TimelineHeader) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 6),
                          child: Text(
                            entry.title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        );
                      }
                      final item = (entry as _TimelineEvent).item;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildTimelineCard(context, item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoursesBody(
    BuildContext context, {
    String heroTitle = 'My Courses',
    String? heroSubtitle,
  }) {
    final activeCourse = _activeCourse;
    if (activeCourse != null) {
      return _buildActiveCourseBody(
        context,
        course: activeCourse,
        parentTitle: heroTitle,
      );
    }

    final courses = widget.controller.courses;
    return RefreshIndicator(
      onRefresh: widget.controller.refreshCourses,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeroCard(
            heroTitle,
            heroSubtitle ?? '当前共 ${courses.length} 门课程',
          ),
          const SizedBox(height: 12),
          if (widget.controller.isLoadingCourses)
            const LinearProgressIndicator(minHeight: 2),
          if (widget.controller.error != null) ...[
            const SizedBox(height: 12),
            _buildErrorBox(context, widget.controller.error!),
          ],
          const SizedBox(height: 12),
          if (courses.isEmpty)
            _buildEmptyState(context, title: '暂无课程数据', subtitle: '下拉刷新或稍后重试')
          else
            for (final course in courses) ...[
              _buildCourseCard(context, course),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _buildSitePagesMyCoursesBody(BuildContext context) {
    return _buildCoursesBody(
      context,
      heroTitle: 'Site pages · My courses',
      heroSubtitle: '对应官网 Site pages / My courses',
    );
  }

  Widget _buildSitePagesWebMirrorBody(
    BuildContext context, {
    required String pathOrUrl,
  }) {
    final section = _section;
    final reloadSeed = _webMirrorReloadSeeds[section] ?? 0;
    return SafeArea(
      bottom: false,
      child: MirrorWebViewPanel(
        key: ValueKey('$section#$reloadSeed'),
        controller: widget.controller,
        pathOrUrl: pathOrUrl,
      ),
    );
  }

  Widget _buildSiteAnnouncementsBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeroCard(
          'Forum · Site announcements',
          '对应官网 Site pages / Forum Site announcements',
        ),
        const SizedBox(height: 12),
        _buildResourceCard(
          context,
          title: 'Site announcements',
          subtitle: '论坛能力已接入：支持查看讨论列表与帖子内容。',
          status: '已接入',
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => _openSiteAnnouncementForum(context),
          icon: const Icon(Icons.forum_outlined),
          label: const Text('打开 Forum 详情'),
        ),
      ],
    );
  }

  Widget _buildControlPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF102A43).withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: _buildFilterSelector(context)),
          const SizedBox(width: 10),
          Expanded(child: _buildSortSelector(context)),
        ],
      ),
    );
  }

  Widget _buildFilterSelector(BuildContext context) {
    return PopupMenuButton<TimelineDateFilter>(
      onSelected: _updateDateFilter,
      itemBuilder: (context) => TimelineDateFilter.values
          .map(
            (item) => PopupMenuItem<TimelineDateFilter>(
              value: item,
              child: Text(_dateFilterLabel(item)),
            ),
          )
          .toList(),
      child: _selectorChip(
        context: context,
        icon: Icons.filter_alt_outlined,
        text: _dateFilterLabel(_dateFilter),
      ),
    );
  }

  Widget _buildSortSelector(BuildContext context) {
    return PopupMenuButton<TimelineSortMode>(
      onSelected: _updateSortMode,
      itemBuilder: (context) => TimelineSortMode.values
          .map(
            (item) => PopupMenuItem<TimelineSortMode>(
              value: item,
              child: Text(_sortModeLabel(item)),
            ),
          )
          .toList(),
      child: _selectorChip(
        context: context,
        icon: Icons.swap_vert_rounded,
        text: _sortModeLabel(_sortMode),
      ),
    );
  }

  Widget _selectorChip({
    required BuildContext context,
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E2EE)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF2E618A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF334155),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF64748B),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF133B5C), Color(0xFF1F6F8B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildErrorBox(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    String title = 'No in-progress courses',
    String subtitle = '当前筛选条件下没有数据',
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, size: 42, color: Color(0xFF7B8794)),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildCourseCard(BuildContext context, CourseSummary course) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openCourseInline(course),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                course.fullName,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                course.shortName.isEmpty ? '未提供 shortname' : course.shortName,
              ),
              if (course.categoryName.isNotEmpty)
                Text('分类：${course.categoryName}'),
              if (course.progress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (course.progress!.clamp(0, 100)) / 100,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(999),
                ),
                const SizedBox(height: 4),
                Text(
                  '进度：${course.progress}%',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveCourseBody(
    BuildContext context, {
    required CourseSummary course,
    required String parentTitle,
  }) {
    return RefreshIndicator(
      onRefresh: _reloadActiveCourse,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeroCard(
            course.fullName,
            '$parentTitle · 章节 ${_activeCourseSections.length}',
          ),
          const SizedBox(height: 12),
          if (_isLoadingActiveCourse)
            const LinearProgressIndicator(minHeight: 2),
          if (_activeCourseError != null) ...[
            const SizedBox(height: 12),
            _buildErrorBox(context, _activeCourseError!),
          ],
          if (!_isLoadingActiveCourse &&
              _activeCourseError == null &&
              _activeCourseSections.isEmpty) ...[
            const SizedBox(height: 12),
            _buildEmptyState(context, title: '该课程暂无内容', subtitle: '下拉刷新或稍后重试'),
          ],
          if (_activeCourseSections.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final section in _activeCourseSections) ...[
              _buildCourseSectionCard(context, course, section),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCourseSectionCard(
    BuildContext context,
    CourseSummary course,
    CourseContentSection section,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          section.name,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'Section ${section.sectionNum} · ${section.modules.length} activities',
        ),
        initiallyExpanded: section.sectionNum <= 1,
        children: [
          if (section.modules.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6, bottom: 8),
              child: Text('该章节暂无活动'),
            )
          else
            for (final module in section.modules) ...[
              _buildCourseModuleTile(context, course, module),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _buildCourseModuleTile(
    BuildContext context,
    CourseSummary course,
    CourseModule module,
  ) {
    final iconSpec = _activityIconSpec(
      _normalizeActivityTypeKey(module.modName),
    );
    CourseModuleDate? dueDate;
    for (final item in module.dates) {
      if (item.dataId.toLowerCase().contains('due')) {
        dueDate = item;
        break;
      }
    }

    return Material(
      color: const Color(0xFFF7FAFD),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openCourseModule(context, course, module),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconSpec.backgroundColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  iconSpec.icon,
                  color: iconSpec.foregroundColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      module.modName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    if (dueDate?.dateTime != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Due: ${_courseTimeFormatter.format(dueDate!.dateTime!.toLocal())}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFB45309),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResourceCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String status,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(subtitle),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status,
              style: const TextStyle(
                color: Color(0xFF1D4E89),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard(BuildContext context, TimelineItem item) {
    final now = DateTime.now();
    final isOverdue =
        item.isOverdue ||
        (item.sortTime != null && item.sortTime!.isBefore(now));
    final iconData = _activityIconSpec(_timelineTypeKey(item)).icon;
    final timeText = item.sortTime == null
        ? '--:--'
        : _hourFormatter.format(item.sortTime!.toLocal());
    final dueHint = _timelineDueHint(item, now: now);
    final secondaryParts = <String>[
      if (item.activityState.isNotEmpty) item.activityState,
      if (item.courseName.isNotEmpty) item.courseName,
    ];
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openTimelineDetail(context, item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 66,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        timeText,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: isOverdue
                              ? const Color(0xFFD64545)
                              : const Color(0xFF1D4E89),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dueHint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isOverdue
                              ? const Color(0xFFD64545)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(width: 1, height: 56, color: const Color(0xFFE2E8F0)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Row(
                        children: [
                          Icon(
                            iconData,
                            size: 18,
                            color: const Color(0xFF8A94A6),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      secondaryParts.isEmpty
                          ? _activityLabel(item.activityType)
                          : secondaryParts.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF5E6472),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timelineTypeKey(TimelineItem item) {
    final module = item.moduleName.trim().toLowerCase();
    if (module.isNotEmpty) {
      return _normalizeActivityTypeKey(module);
    }
    return _normalizeActivityTypeKey(item.activityType.trim().toLowerCase());
  }

  String _normalizeActivityTypeKey(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.contains('assign')) {
      return 'assign';
    }
    if (value.contains('quiz')) {
      return 'quiz';
    }
    if (value.contains('forum')) {
      return 'forum';
    }
    if (value.contains('resource')) {
      return 'resource';
    }
    if (value.contains('folder')) {
      return 'folder';
    }
    if (value.contains('choice')) {
      return 'choice';
    }
    if (value.contains('mediasite')) {
      return 'mediasite';
    }
    if (value.contains('page')) {
      return 'page';
    }
    if (value.contains('url')) {
      return 'url';
    }
    return value;
  }

  _ActivityIconSpec _activityIconSpec(String key) {
    switch (key) {
      case 'assign':
        return const _ActivityIconSpec(
          icon: Icons.upload_file,
          foregroundColor: Color(0xFFDB2777),
          backgroundColor: Color(0xFFFCE7F3),
        );
      case 'quiz':
        return const _ActivityIconSpec(
          icon: Icons.task_alt,
          foregroundColor: Color(0xFFDB2777),
          backgroundColor: Color(0xFFFCE7F3),
        );
      case 'forum':
        return const _ActivityIconSpec(
          icon: Icons.comment,
          foregroundColor: Color(0xFFEA580C),
          backgroundColor: Color(0xFFFFF3E8),
        );
      case 'resource':
        return const _ActivityIconSpec(
          icon: Icons.description_outlined,
          foregroundColor: Color(0xFF2563EB),
          backgroundColor: Color(0xFFEFF6FF),
        );
      case 'folder':
        return const _ActivityIconSpec(
          icon: Icons.folder_outlined,
          foregroundColor: Color(0xFFB45309),
          backgroundColor: Color(0xFFFFF7ED),
        );
      case 'choice':
        return const _ActivityIconSpec(
          icon: Icons.how_to_vote_outlined,
          foregroundColor: Color(0xFF166534),
          backgroundColor: Color(0xFFF0FDF4),
        );
      case 'mediasite':
        return const _ActivityIconSpec(
          icon: Icons.ondemand_video_outlined,
          foregroundColor: Color(0xFF6D28D9),
          backgroundColor: Color(0xFFF3E8FF),
        );
      case 'url':
        return const _ActivityIconSpec(
          icon: Icons.link_rounded,
          foregroundColor: Color(0xFF0F766E),
          backgroundColor: Color(0xFFF0FDFA),
        );
      case 'page':
        return const _ActivityIconSpec(
          icon: Icons.article_outlined,
          foregroundColor: Color(0xFF334155),
          backgroundColor: Color(0xFFF1F5F9),
        );
      default:
        return const _ActivityIconSpec(
          icon: Icons.widgets_outlined,
          foregroundColor: Color(0xFF166534),
          backgroundColor: Color(0xFFF0FDF4),
        );
    }
  }

  String _activityLabel(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'assign':
        return 'Assignment';
      case 'forum':
        return 'Forum';
      case 'mediasite':
        return 'Mediasite';
      case 'quiz':
        return 'Quiz';
      case 'choice':
        return 'Choice';
      default:
        return value.trim().isEmpty ? 'Activity' : value.trim();
    }
  }

  Drawer _buildDrawer(BuildContext context) {
    final courses = widget.controller.courses;
    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topRight: Radius.circular(28)),
      ),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              color: const Color(0xFF133B5C),
              child: const Text(
                'iSpace Sidebar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _drawerLevel1Tile(
              context,
              title: 'Dashboard',
              icon: Icons.dashboard_rounded,
              selected: _section == IspaceSection.dashboard,
              onTap: () => _setSection(context, IspaceSection.dashboard),
            ),
            const Divider(height: 1),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                initiallyExpanded: _sitePagesExpanded,
                onExpansionChanged: (value) {
                  setState(() {
                    _sitePagesExpanded = value;
                  });
                },
                tilePadding: const EdgeInsets.only(left: 16, right: 12),
                leading: const Icon(Icons.public_rounded, size: 20),
                title: const Text('Site pages'),
                childrenPadding: const EdgeInsets.only(bottom: 4),
                children: [
                  _drawerLeafTile(
                    context,
                    title: 'Site blogs',
                    level: 2,
                    selected: _section == IspaceSection.sitePagesBlogs,
                    onTap: () =>
                        _setSection(context, IspaceSection.sitePagesBlogs),
                  ),
                  _drawerLeafTile(
                    context,
                    title: 'Site badges',
                    level: 2,
                    selected: _section == IspaceSection.sitePagesBadges,
                    onTap: () =>
                        _setSection(context, IspaceSection.sitePagesBadges),
                  ),
                  _drawerLeafTile(
                    context,
                    title: 'Tags',
                    level: 2,
                    selected: _section == IspaceSection.sitePagesTags,
                    onTap: () =>
                        _setSection(context, IspaceSection.sitePagesTags),
                  ),
                  _drawerLeafTile(
                    context,
                    title: 'Forum Site announcements',
                    level: 2,
                    selected: _section == IspaceSection.sitePagesAnnouncements,
                    onTap: () => _setSection(
                      context,
                      IspaceSection.sitePagesAnnouncements,
                    ),
                  ),
                ],
              ),
            ),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                initiallyExpanded: _myCoursesExpanded,
                onExpansionChanged: (value) {
                  setState(() {
                    _myCoursesExpanded = value;
                    if (value) {
                      _section = IspaceSection.myCourses;
                      _activeCourse = null;
                      _activeCourseError = null;
                      _activeCourseSections = const [];
                      _isLoadingActiveCourse = false;
                    }
                  });
                },
                tilePadding: const EdgeInsets.only(left: 16, right: 12),
                leading: const Icon(Icons.menu_book_rounded, size: 20),
                title: const Text('My courses'),
                childrenPadding: const EdgeInsets.only(bottom: 4),
                children: [
                  for (final course in courses)
                    _drawerLeafTile(
                      context,
                      title: course.shortName.isEmpty
                          ? course.fullName
                          : course.shortName,
                      level: 2,
                      selected:
                          _section == IspaceSection.myCourses &&
                          _activeCourse?.id == course.id,
                      onTap: () => _openCourseInline(course, closeDrawer: true),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerLevel1Tile(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, size: 20),
      selected: selected,
      selectedTileColor: const Color(0xFFEAF3FF),
      title: Text(title),
      onTap: onTap,
    );
  }

  Widget _drawerLeafTile(
    BuildContext context, {
    required String title,
    required int level,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final leftPadding = level <= 2 ? 24.0 : 34.0;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: leftPadding, right: 12),
      selected: selected,
      selectedTileColor: const Color(0xFFEAF3FF),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }

  void _setSection(BuildContext context, IspaceSection section) {
    Navigator.of(context).pop();
    if (_section == section) {
      return;
    }
    setState(() {
      _section = section;
    });
  }

  Future<void> _openTimelineDetail(
    BuildContext context,
    TimelineItem item,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TimelineDetailPage(controller: widget.controller, item: item),
      ),
    );
  }

  Future<void> _openCourseModule(
    BuildContext context,
    CourseSummary course,
    CourseModule module,
  ) async {
    final modName = module.modName.toLowerCase();
    final isResource = modName.contains('resource');
    if (modName.contains('folder')) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FolderDetailPage(
            controller: widget.controller,
            course: course,
            module: module,
          ),
        ),
      );
      return;
    }

    final openAsTimelineDetail =
        module.isAssignment ||
        modName.contains('forum') ||
        modName.contains('mediasite');
    if (openAsTimelineDetail) {
      final resolvedInstanceId = module.instance > 0
          ? module.instance
          : module.id;
      final resolvedUrl = module.url.trim().isNotEmpty
          ? module.url
          : '/mod/${module.modName}/view.php?id=${module.id}';
      final pseudoItem = TimelineItem(
        id: -module.id,
        title: module.name,
        activityState: module.isAssignment ? 'Assignment is due' : modName,
        activityType: module.modName,
        moduleName: module.modName,
        description: '',
        courseName: course.fullName,
        courseId: course.id,
        instanceId: resolvedInstanceId,
        url: resolvedUrl,
        sortTime: module.dates.isEmpty ? null : module.dates.first.dateTime,
        formattedTime: '',
        isOverdue: false,
      );
      await _openTimelineDetail(context, pseudoItem);
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebMirrorPage(
          controller: widget.controller,
          title: module.name,
          pathOrUrl: _moduleViewUrl(module),
          showFileActions: isResource,
          actionPathOrUrl: isResource ? _resourceActionUrl(module) : null,
        ),
      ),
    );
  }

  String _moduleViewUrl(CourseModule module) {
    final raw = module.url.trim();
    if (raw.isNotEmpty) {
      return raw;
    }
    return '/mod/${module.modName}/view.php?id=${module.id}';
  }

  String _resourceActionUrl(CourseModule module) {
    for (final content in module.contents) {
      final raw = content.fileUrl.trim();
      if (raw.isEmpty) {
        continue;
      }
      final resolved = _resolveAbsoluteUrl(raw);
      if (resolved.isEmpty) {
        continue;
      }
      final uri = Uri.tryParse(resolved);
      if (uri == null) {
        return resolved;
      }
      final normalizedPath = uri.path.replaceFirst(
        '/webservice/pluginfile.php',
        '/pluginfile.php',
      );
      final query = Map<String, String>.from(uri.queryParameters);
      query.remove('token');
      return uri
          .replace(
            path: normalizedPath,
            queryParameters: query.isEmpty ? null : query,
          )
          .toString();
    }
    return _moduleViewUrl(module);
  }

  String _resolveAbsoluteUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '${widget.controller.baseUrl}$trimmed';
    }
    return '${widget.controller.baseUrl}/$trimmed';
  }

  Future<void> _openSiteAnnouncementForum(BuildContext context) async {
    final pseudoItem = TimelineItem(
      id: -78,
      title: 'Site announcements',
      activityState: 'Forum',
      activityType: 'forum',
      moduleName: 'forum',
      description: 'General news and announcements',
      courseName: 'BNBU Information Space',
      courseId: 1,
      instanceId: 78,
      url: 'https://ispace.uic.edu.cn/mod/forum/view.php?id=78',
      sortTime: null,
      formattedTime: '',
      isOverdue: false,
    );
    await _openTimelineDetail(context, pseudoItem);
  }

  Future<void> _openCourseInline(
    CourseSummary course, {
    bool closeDrawer = false,
  }) async {
    if (closeDrawer) {
      Navigator.of(context).pop();
    }

    setState(() {
      _section = IspaceSection.myCourses;
      _activeCourse = course;
      _isLoadingActiveCourse = true;
      _activeCourseError = null;
      _activeCourseSections = const [];
    });

    await _loadActiveCourseSections(course.id);
  }

  Future<void> _loadActiveCourseSections(int courseId) async {
    try {
      final sections = await widget.controller.loadCourseContents(courseId);
      if (!mounted) {
        return;
      }
      if (_activeCourse == null || _activeCourse!.id != courseId) {
        return;
      }
      setState(() {
        _activeCourseSections = sections;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (_activeCourse == null || _activeCourse!.id != courseId) {
        return;
      }
      setState(() {
        _activeCourseError = '课程内容加载失败，请稍后重试。';
      });
    } finally {
      if (mounted && _activeCourse != null && _activeCourse!.id == courseId) {
        setState(() {
          _isLoadingActiveCourse = false;
        });
      }
    }
  }

  Future<void> _reloadActiveCourse() async {
    final active = _activeCourse;
    if (active == null) {
      await widget.controller.refreshCourses();
      return;
    }
    setState(() {
      _isLoadingActiveCourse = true;
      _activeCourseError = null;
      _activeCourseSections = const [];
    });
    await _loadActiveCourseSections(active.id);
  }

  void _reloadMirrorSection(IspaceSection section) {
    setState(() {
      final current = _webMirrorReloadSeeds[section] ?? 0;
      _webMirrorReloadSeeds[section] = current + 1;
    });
  }

  void _refreshCurrentSection() {
    switch (_section) {
      case IspaceSection.dashboard:
        widget.controller.refreshTimeline();
        return;
      case IspaceSection.sitePagesMyCourses:
        _reloadActiveCourse();
        return;
      case IspaceSection.sitePagesBlogs:
        _reloadMirrorSection(IspaceSection.sitePagesBlogs);
        return;
      case IspaceSection.sitePagesBadges:
        _reloadMirrorSection(IspaceSection.sitePagesBadges);
        return;
      case IspaceSection.sitePagesTags:
        _reloadMirrorSection(IspaceSection.sitePagesTags);
        return;
      case IspaceSection.sitePagesAnnouncements:
        return;
      case IspaceSection.myCourses:
        _reloadActiveCourse();
        return;
    }
  }

  List<TimelineItem> _filteredTimeline(List<TimelineItem> source) {
    final now = DateTime.now();
    final filtered = source
        .where((item) => _matchesDateFilter(item, now))
        .toList();

    if (_sortMode == TimelineSortMode.byCourses) {
      filtered.sort((a, b) {
        final courseCompare = _courseLabel(a).compareTo(_courseLabel(b));
        if (courseCompare != 0) {
          return courseCompare;
        }
        final aTime = a.sortTime?.millisecondsSinceEpoch ?? 0;
        final bTime = b.sortTime?.millisecondsSinceEpoch ?? 0;
        return aTime.compareTo(bTime);
      });
      return filtered;
    }

    filtered.sort((a, b) {
      return _timeSortValue(a).compareTo(_timeSortValue(b));
    });
    return filtered;
  }

  bool _matchesDateFilter(TimelineItem item, DateTime now) {
    final time = item.sortTime;
    switch (_dateFilter) {
      case TimelineDateFilter.all:
        return true;
      case TimelineDateFilter.overdue:
        if (item.isOverdue) {
          return true;
        }
        if (time == null) {
          return false;
        }
        return time.isBefore(now);
      case TimelineDateFilter.next7Days:
        return _isBetween(time, now, now.add(const Duration(days: 7)));
      case TimelineDateFilter.next30Days:
        return _isBetween(time, now, now.add(const Duration(days: 30)));
      case TimelineDateFilter.next3Months:
        return _isBetween(
          time,
          now,
          DateTime(now.year, now.month + 3, now.day),
        );
      case TimelineDateFilter.next6Months:
        return _isBetween(
          time,
          now,
          DateTime(now.year, now.month + 6, now.day),
        );
    }
  }

  bool _isBetween(DateTime? target, DateTime start, DateTime end) {
    if (target == null) {
      return false;
    }
    return !target.isBefore(start) && !target.isAfter(end);
  }

  List<_TimelineEntry> _buildCourseEntries(List<TimelineItem> items) {
    final entries = <_TimelineEntry>[];
    String? currentCourse;
    for (final item in items) {
      final course = _courseLabel(item);
      if (currentCourse != course) {
        entries.add(_TimelineHeader(course));
        currentCourse = course;
      }
      entries.add(_TimelineEvent(item));
    }
    return entries;
  }

  List<_TimelineEntry> _buildDateEntries(List<TimelineItem> items) {
    final entries = <_TimelineEntry>[];
    String? currentDay;
    for (final item in items) {
      final day = _dayLabel(item.sortTime);
      if (currentDay != day) {
        entries.add(_TimelineHeader(day));
        currentDay = day;
      }
      entries.add(_TimelineEvent(item));
    }
    return entries;
  }

  String _courseLabel(TimelineItem item) {
    if (item.courseName.trim().isEmpty) {
      return 'Unknown course';
    }
    return item.courseName.trim();
  }

  String _dayLabel(DateTime? dateTime) {
    if (dateTime == null) {
      return 'No date';
    }
    return _dayFormatter.format(dateTime.toLocal());
  }

  int _timeSortValue(TimelineItem item) {
    final millis = item.sortTime?.millisecondsSinceEpoch;
    if (millis == null || millis <= 0) {
      return 253402300799000; // 9999-12-31
    }
    return millis;
  }

  Future<void> _restoreDashboardPreferences() async {
    final preferences = await _preferencesFuture;
    final dateFilterName = preferences.getString(_dateFilterPreferenceKey);
    final sortModeName = preferences.getString(_sortModePreferenceKey);

    TimelineDateFilter? restoredDateFilter;
    for (final candidate in TimelineDateFilter.values) {
      if (candidate.name == dateFilterName) {
        restoredDateFilter = candidate;
        break;
      }
    }

    TimelineSortMode? restoredSortMode;
    for (final candidate in TimelineSortMode.values) {
      if (candidate.name == sortModeName) {
        restoredSortMode = candidate;
        break;
      }
    }

    if (!mounted ||
        (restoredDateFilter == null && restoredSortMode == null)) {
      return;
    }

    setState(() {
      if (restoredDateFilter != null) {
        _dateFilter = restoredDateFilter;
      }
      if (restoredSortMode != null) {
        _sortMode = restoredSortMode;
      }
    });
  }

  Future<void> _persistDashboardPreferences() async {
    final preferences = await _preferencesFuture;
    await preferences.setString(_dateFilterPreferenceKey, _dateFilter.name);
    await preferences.setString(_sortModePreferenceKey, _sortMode.name);
  }

  void _updateDateFilter(TimelineDateFilter value) {
    if (_dateFilter == value) {
      return;
    }
    setState(() => _dateFilter = value);
    unawaited(_persistDashboardPreferences());
  }

  void _updateSortMode(TimelineSortMode value) {
    if (_sortMode == value) {
      return;
    }
    setState(() => _sortMode = value);
    unawaited(_persistDashboardPreferences());
  }

  String _timelineDueHint(TimelineItem item, {required DateTime now}) {
    final due = item.sortTime;
    if (due == null) {
      return '--';
    }
    if (item.isOverdue || !due.isAfter(now)) {
      return 'Overdue';
    }
    final diff = due.difference(now);
    final totalMinutes = diff.inMinutes;
    if (totalMinutes <= 0) {
      return 'Overdue';
    }
    if (diff > const Duration(days: 2)) {
      final daysLeft = (totalMinutes / (24 * 60)).ceil();
      return '$daysLeft days';
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  String _dateFilterLabel(TimelineDateFilter filter) {
    switch (filter) {
      case TimelineDateFilter.all:
        return 'All';
      case TimelineDateFilter.overdue:
        return 'Overdue';
      case TimelineDateFilter.next7Days:
        return 'Next 7 days';
      case TimelineDateFilter.next30Days:
        return 'Next 30 days';
      case TimelineDateFilter.next3Months:
        return 'Next 3 months';
      case TimelineDateFilter.next6Months:
        return 'Next 6 months';
    }
  }

  String _sortModeLabel(TimelineSortMode mode) {
    switch (mode) {
      case TimelineSortMode.byDates:
        return 'Sort by dates';
      case TimelineSortMode.byCourses:
        return 'Sort by courses';
    }
  }

  String _sectionLabel(IspaceSection section) {
    switch (section) {
      case IspaceSection.dashboard:
        return 'iSpace · Dashboard';
      case IspaceSection.sitePagesMyCourses:
        return 'iSpace · Site pages / My courses';
      case IspaceSection.sitePagesBlogs:
        return 'iSpace · Site pages / Site blogs';
      case IspaceSection.sitePagesBadges:
        return 'iSpace · Site pages / Site badges';
      case IspaceSection.sitePagesTags:
        return 'iSpace · Site pages / Tags';
      case IspaceSection.sitePagesAnnouncements:
        return 'iSpace · Site pages / Forum';
      case IspaceSection.myCourses:
        return 'iSpace · My Courses';
    }
  }
}

sealed class _TimelineEntry {
  const _TimelineEntry();
}

class _TimelineHeader extends _TimelineEntry {
  const _TimelineHeader(this.title);
  final String title;
}

class _TimelineEvent extends _TimelineEntry {
  const _TimelineEvent(this.item);
  final TimelineItem item;
}

class _ActivityIconSpec {
  const _ActivityIconSpec({
    required this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;
}
