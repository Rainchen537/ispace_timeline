import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/course_content.dart';
import '../models/course_summary.dart';
import '../models/timeline_item.dart';
import '../services/moodle_api_client.dart';
import '../state/app_session_controller.dart';
import 'folder_detail_page.dart';
import 'timeline_detail_page.dart';
import 'web_mirror_page.dart';

class CourseDetailPage extends StatefulWidget {
  const CourseDetailPage({
    super.key,
    required this.controller,
    required this.course,
  });

  final AppSessionController controller;
  final CourseSummary course;

  @override
  State<CourseDetailPage> createState() => _CourseDetailPageState();
}

class _CourseDetailPageState extends State<CourseDetailPage> {
  final _timeFormatter = DateFormat('yyyy-MM-dd HH:mm');

  bool _loading = true;
  String? _error;
  List<CourseContentSection> _sections = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sections = await widget.controller.loadCourseContents(
        widget.course.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _sections = sections;
      });
    } on MoodleApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '课程内容加载失败，请稍后重试。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: Text(widget.course.fullName),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
        ],
      ),
      body: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _buildError(context)
            : _buildContent(context),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _hero(),
          const SizedBox(height: 12),
          if (_sections.isEmpty)
            _empty()
          else
            for (final section in _sections) ...[
              _sectionCard(context, section),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _hero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF12355B), Color(0xFF2A6F97)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.course.fullName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '章节 ${_sections.length} · 活动 ${_sections.fold<int>(0, (sum, sec) => sum + sec.modules.length)}',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.inbox_outlined, size: 42, color: Color(0xFF64748B)),
          SizedBox(height: 12),
          Text('课程内容为空'),
          SizedBox(height: 6),
          Text('下拉刷新或稍后重试', textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _sectionCard(BuildContext context, CourseContentSection section) {
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
              _moduleTile(context, module),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _moduleTile(BuildContext context, CourseModule module) {
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
        onTap: () => _openModule(context, module),
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
                          'Due: ${_timeFormatter.format(dueDate!.dateTime!.toLocal())}',
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

  Future<void> _openModule(BuildContext context, CourseModule module) async {
    final modName = module.modName.toLowerCase();
    final isResource = modName.contains('resource');
    if (modName.contains('folder')) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FolderDetailPage(
            controller: widget.controller,
            course: widget.course,
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
        courseName: widget.course.fullName,
        courseId: widget.course.id,
        instanceId: resolvedInstanceId,
        url: resolvedUrl,
        sortTime: module.dates.isEmpty ? null : module.dates.first.dateTime,
        formattedTime: '',
        isOverdue: false,
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TimelineDetailPage(
            controller: widget.controller,
            item: pseudoItem,
          ),
        ),
      );
      return;
    }

    if (isResource) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WebMirrorPage(
            controller: widget.controller,
            title: module.name,
            pathOrUrl: _moduleViewUrl(module),
            showFileActions: true,
            actionPathOrUrl: _resourceActionUrl(module),
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CourseModuleDetailPage(
          courseName: widget.course.fullName,
          module: module,
          timeFormatter: _timeFormatter,
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

class CourseModuleDetailPage extends StatelessWidget {
  const CourseModuleDetailPage({
    super.key,
    required this.courseName,
    required this.module,
    required this.timeFormatter,
  });

  final String courseName;
  final CourseModule module;
  final DateFormat timeFormatter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(module.name)),
      body: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                module.name,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text('课程：$courseName'),
              const SizedBox(height: 6),
              Text('类型：${module.modName}'),
              if (module.dates.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final date in module.dates)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${date.label} ${date.dateTime == null ? '-' : timeFormatter.format(date.dateTime!.toLocal())}',
                    ),
                  ),
              ],
              const SizedBox(height: 14),
              const Text('该活动类型的完整原生交互正在搬运中，当前优先支持 Assignment。'),
            ],
          ),
        ),
      ),
    );
  }
}
