import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/timeline_detail_data.dart';
import '../models/timeline_item.dart';
import '../models/upload_file_payload.dart';
import '../services/moodle_api_client.dart';
import '../state/app_session_controller.dart';
import 'web_mirror_page.dart';

class TimelineDetailPage extends StatefulWidget {
  const TimelineDetailPage({
    super.key,
    required this.controller,
    required this.item,
  });

  final AppSessionController controller;
  final TimelineItem item;

  @override
  State<TimelineDetailPage> createState() => _TimelineDetailPageState();
}

class _TimelineDetailPageState extends State<TimelineDetailPage> {
  final _timeFormatter = DateFormat('yyyy-MM-dd HH:mm');

  TimelineDetailData? _detail;
  bool _loading = true;
  bool _submittingText = false;
  bool _submittingFiles = false;
  String? _error;
  List<UploadFilePayload> _pickedFiles = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _pickedFiles = const [];
    });
    try {
      final detail = await widget.controller.loadTimelineDetail(widget.item);
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail;
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
        _error = '详情加载失败，请稍后重试。';
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
    final detail = _detail;
    final useMirrorLayout = detail != null && _shouldRenderMirror(detail);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: Text(_pageTitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        minimum: useMirrorLayout ? EdgeInsets.zero : const EdgeInsets.all(16),
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
    final detail = _detail!;
    if (_shouldRenderMirror(detail)) {
      return MirrorWebViewPanel(
        controller: widget.controller,
        pathOrUrl: detail.item.url,
      );
    }

    return ListView(
      children: [
        if (detail.type == TimelineDetailType.assignment)
          _buildAssignmentCard(context, detail)
        else if (detail.type == TimelineDetailType.forum)
          _buildForumCard(context, detail)
        else if (detail.type == TimelineDetailType.mediasite)
          _buildMediaSiteCard(context, detail)
        else
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '暂不支持原生详情',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('该事件当前没有可用的原生详情数据。'),
                if (detail.hints.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final hint in detail.hints) Text('• $hint'),
                ],
              ],
            ),
          ),
      ],
    );
  }

  bool _shouldRenderMirror(TimelineDetailData detail) {
    return detail.type == TimelineDetailType.generic &&
        detail.item.url.trim().isNotEmpty;
  }

  String _pageTitle() {
    final preferred = _detail?.item.title.trim() ?? '';
    final fallback = widget.item.title.trim();
    final resolved = preferred.isEmpty ? fallback : preferred;
    if (resolved.isEmpty) {
      return 'Timeline';
    }
    return '$resolved · Timeline';
  }

  Widget _buildAssignmentCard(BuildContext context, TimelineDetailData detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assignment',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              _kv('作业 ID', '${detail.assignmentId}'),
              _kv(
                '作业名',
                detail.assignmentName.isEmpty
                    ? detail.item.title
                    : detail.assignmentName,
              ),
              _kv(
                'Opened',
                detail.openDate == null
                    ? '未提供'
                    : _timeFormatter.format(detail.openDate!.toLocal()),
              ),
              _kv(
                'Due',
                detail.dueDate == null
                    ? '未提供'
                    : _timeFormatter.format(detail.dueDate!.toLocal()),
              ),
              _kv(
                'Cut-off',
                detail.cutoffDate == null
                    ? '未提供'
                    : _timeFormatter.format(detail.cutoffDate!.toLocal()),
              ),
              _kv(
                'Grading due',
                detail.gradingDueDate == null
                    ? '未提供'
                    : _timeFormatter.format(detail.gradingDueDate!.toLocal()),
              ),
              if (detail.assignmentIntroHtml.isNotEmpty ||
                  detail.assignmentIntro.isNotEmpty ||
                  detail.assignmentIntroFiles.isNotEmpty) ...[
                const SizedBox(height: 10),
                _assignmentInstructionBox(detail),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusGrid(detail),
              if (detail.hints.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final hint in detail.hints)
                  Text(
                    '• $hint',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
              ],
              const SizedBox(height: 12),
              if (detail.supportsFileSubmission)
                _buildFileSubmissionBox(context, detail)
              else
                const Text('当前作业未开放文件提交。'),
              const SizedBox(height: 12),
              if (detail.supportsOnlineTextSubmission)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: (_submittingText || detail.assignmentId <= 0)
                        ? null
                        : () => _openSubmissionDialog(detail.assignmentId),
                    child: _submittingText
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('在线文本提交'),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                detail.canEditSubmission ? '当前作业允许编辑提交' : '当前作业可能不允许编辑提交',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildForumCard(BuildContext context, TimelineDetailData detail) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Forum',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _kv('Forum ID', '${detail.forumId}'),
          _kv(
            'Forum 名称',
            detail.forumName.isEmpty ? detail.item.title : detail.forumName,
          ),
          if (detail.forumDescription.isNotEmpty)
            _kv('简介', detail.forumDescription),
          _kv('讨论权限', detail.canStartDiscussion ? '可发起讨论' : '当前不可发起讨论'),
          if (detail.forumDiscussions.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              '最新讨论',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 6),
            for (final discussion in detail.forumDiscussions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _forumDiscussionTile(context, discussion),
              ),
          ] else ...[
            const SizedBox(height: 6),
            const Text('暂无可见讨论帖子。'),
          ],
          if (detail.hints.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final hint in detail.hints)
              Text('• $hint', style: const TextStyle(color: Color(0xFF64748B))),
          ],
        ],
      ),
    );
  }

  Widget _forumDiscussionTile(
    BuildContext context,
    ForumDiscussion discussion,
  ) {
    final badges = <String>[
      if (discussion.pinned) 'Pinned',
      if (discussion.locked) 'Locked',
      '回复 ${discussion.replyCount}',
    ];
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openForumDiscussion(context, discussion),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  discussion.subject,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${discussion.author} · ${discussion.timeModifiedAt == null ? '未知时间' : _timeFormatter.format(discussion.timeModifiedAt!.toLocal())}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                if (discussion.messagePreview.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    discussion.messagePreview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF334155),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        badges.join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1D4E89),
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaSiteCard(BuildContext context, TimelineDetailData detail) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mediasite',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _kv('活动名', detail.item.title),
          _kv(
            '模块类型',
            detail.item.moduleName.isEmpty
                ? 'mediasite'
                : detail.item.moduleName,
          ),
          if (detail.mediasiteLaunchUrl.isNotEmpty)
            _kv('入口 URL', detail.mediasiteLaunchUrl),
          if (detail.item.activityState.isNotEmpty)
            _kv('状态', detail.item.activityState),
          if (detail.mediasiteLaunchUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _copyText(
                detail.mediasiteLaunchUrl,
                successMessage: 'Mediasite 链接已复制',
              ),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('复制 Mediasite 链接'),
            ),
          ],
          if (detail.hints.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final hint in detail.hints)
              Text('• $hint', style: const TextStyle(color: Color(0xFF64748B))),
          ],
        ],
      ),
    );
  }

  Widget _statusGrid(TimelineDetailData detail) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD7DEE7)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _statusLine(
            '提交状态',
            _displaySubmissionStatus(detail.submissionStatus),
          ),
          _statusLine('评分状态', _displayGradingStatus(detail.gradingStatus)),
          _statusLine(
            '反馈',
            detail.feedbackSummary.isEmpty ? '暂无' : detail.feedbackSummary,
          ),
        ],
      ),
    );
  }

  Widget _assignmentInstructionBox(TimelineDetailData detail) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD7DEE7)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.assignmentIntroHtml.isNotEmpty)
            _assignmentIntroHtmlPanel(detail.assignmentIntroHtml)
          else if (detail.assignmentIntro.isNotEmpty)
            Text(
              detail.assignmentIntro,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                height: 1.35,
                fontSize: 14,
              ),
            ),
          if (detail.assignmentIntroFiles.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              '说明附件',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF334155),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final file in detail.assignmentIntroFiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: file.fileUrl.trim().isEmpty
                        ? null
                        : () => _openWebResource(
                            title: file.fileName,
                            pathOrUrl: file.fileUrl,
                          ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          const Icon(Icons.attach_file_rounded, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              file.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (file.fileSize > 0)
                            Text(
                              _formatBytes(file.fileSize),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _assignmentIntroHtmlPanel(String introHtml) {
    final html = _buildIntroHtmlDocument(introHtml);
    final dataUrl = 'data:text/html;charset=utf-8,${Uri.encodeComponent(html)}';
    return SizedBox(
      height: 300,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: MirrorWebViewPanel(
          controller: widget.controller,
          pathOrUrl: dataUrl,
        ),
      ),
    );
  }

  String _buildIntroHtmlDocument(String rawHtml) {
    final baseUri = Uri.tryParse(widget.controller.baseUrl);
    final trustedOrigin =
        baseUri?.hasScheme == true && baseUri?.host.isNotEmpty == true
        ? baseUri!.origin
        : '';
    final mediaSources = trustedOrigin.isEmpty
        ? 'data:'
        : 'data: $trustedOrigin';
    return '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta
      http-equiv="Content-Security-Policy"
      content="default-src 'none'; img-src $mediaSources; media-src $mediaSources; style-src 'unsafe-inline'; font-src data:; connect-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'"
    >
    <style>
      body {
        margin: 0;
        padding: 10px;
        color: #1E293B;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
        font-size: 14px;
        line-height: 1.45;
        background: #FFFFFF;
      }
      img, video, iframe {
        max-width: 100%;
        height: auto;
      }
      table {
        width: 100%;
        max-width: 100%;
        border-collapse: collapse;
      }
      a {
        color: #1D4E89;
      }
      pre, code {
        white-space: pre-wrap;
      }
    </style>
  </head>
  <body>$rawHtml</body>
</html>
''';
  }

  Widget _statusLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _displaySubmissionStatus(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case '':
        return '未知';
      case 'new':
      case 'notsubmitted':
      case 'noattempt':
        return '未提交';
      case 'submitted':
        return '已提交';
      case 'draft':
        return '草稿';
      case 'reopened':
        return '已重新开启';
      default:
        return value.trim();
    }
  }

  String _displayGradingStatus(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case '':
        return '未知';
      case 'notgraded':
        return '未评分';
      case 'graded':
        return '已评分';
      case 'grading':
      case 'inmarking':
        return '评分中';
      default:
        return value.trim();
    }
  }

  Widget _buildFileSubmissionBox(
    BuildContext context,
    TimelineDetailData detail,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD7DEE7)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'File submissions',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF1D4E89),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '最大文件数：${detail.maxFileSubmissions <= 0 ? '未限制' : detail.maxFileSubmissions}，单文件大小：${_formatBytes(detail.maxSubmissionSizeBytes)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _submittingFiles ? null : _pickFiles,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: const Text('选择文件'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed:
                      _submittingFiles ||
                          detail.assignmentId <= 0 ||
                          _pickedFiles.isEmpty ||
                          !detail.canEditSubmission
                      ? null
                      : () => _submitFiles(detail.assignmentId),
                  child: _submittingFiles
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('提交文件'),
                ),
              ),
            ],
          ),
          if (_pickedFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final file in _pickedFiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• ${file.fileName}'),
              ),
          ],
          if (detail.submissionFiles.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('已提交文件', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final file in detail.submissionFiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${file.fileName} (${_formatBytes(file.fileSize)})',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      type: FileType.any,
    );
    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final files = <UploadFilePayload>[];
    for (final file in result.files) {
      final path = file.path?.trim() ?? '';
      if (path.isNotEmpty) {
        files.add(UploadFilePayload(fileName: file.name, filePath: path));
        continue;
      }
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        files.add(UploadFilePayload(fileName: file.name, bytes: file.bytes));
      }
    }

    if (files.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('选择的文件不可读取，请重试。')));
      return;
    }

    setState(() {
      _pickedFiles = files;
    });
  }

  Future<void> _submitFiles(int assignmentId) async {
    setState(() {
      _submittingFiles = true;
    });
    try {
      await widget.controller.submitAssignmentFiles(
        assignmentId: assignmentId,
        files: _pickedFiles,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('文件提交请求已发送，请稍后刷新查看状态。')));
      await _load();
    } on MoodleApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('提交失败：${error.message}')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('提交失败，请稍后重试。')));
    } finally {
      if (mounted) {
        setState(() {
          _submittingFiles = false;
        });
      }
    }
  }

  Future<void> _openSubmissionDialog(int assignmentId) async {
    final controller = TextEditingController();
    String? result;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('在线文本提交'),
          content: TextField(
            controller: controller,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: '输入你的作业文本内容',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                result = controller.text;
                Navigator.of(context).pop();
              },
              child: const Text('提交'),
            ),
          ],
        );
      },
    );

    final text = result?.trim() ?? '';
    if (text.isEmpty) {
      return;
    }

    setState(() {
      _submittingText = true;
    });
    try {
      await widget.controller.submitAssignmentOnlineText(
        assignmentId: assignmentId,
        text: text,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('提交请求已发送，请稍后刷新查看状态。')));
      await _load();
    } on MoodleApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('提交失败：${error.message}')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('提交失败，请稍后重试。')));
    } finally {
      if (mounted) {
        setState(() {
          _submittingText = false;
        });
      }
    }
  }

  Future<void> _openForumDiscussion(
    BuildContext context,
    ForumDiscussion discussion,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ForumDiscussionPage(
          controller: widget.controller,
          discussion: discussion,
        ),
      ),
    );
  }

  Future<void> _copyText(String value, {required String successMessage}) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
  }

  Future<void> _openWebResource({
    required String title,
    required String pathOrUrl,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebMirrorPage(
          controller: widget.controller,
          title: title.trim().isEmpty ? '资源详情' : title,
          pathOrUrl: pathOrUrl,
          showFileActions: true,
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '未限制';
    }
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size = size / 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(size < 10 && unitIndex > 0 ? 1 : 0)} ${units[unitIndex]}';
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Color(0xFF334155), fontSize: 14),
          children: [
            TextSpan(
              text: '$key：',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _ForumDiscussionPage extends StatefulWidget {
  const _ForumDiscussionPage({
    required this.controller,
    required this.discussion,
  });

  final AppSessionController controller;
  final ForumDiscussion discussion;

  @override
  State<_ForumDiscussionPage> createState() => _ForumDiscussionPageState();
}

class _ForumDiscussionPageState extends State<_ForumDiscussionPage> {
  final _timeFormatter = DateFormat('yyyy-MM-dd HH:mm');

  bool _loading = true;
  String? _error;
  List<ForumPost> _posts = const [];

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
      final posts = await widget.controller.loadForumDiscussionPosts(
        widget.discussion.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = posts;
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
        _error = '讨论内容加载失败，请稍后重试。';
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
        title: Text(
          widget.discussion.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              )
            : _posts.isEmpty
            ? const Center(child: Text('暂无帖子内容'))
            : ListView.separated(
                itemCount: _posts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final post = _posts[index];
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.subject.isEmpty
                              ? widget.discussion.subject
                              : post.subject,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${post.author} · ${post.timeCreatedAt == null ? '未知时间' : _timeFormatter.format(post.timeCreatedAt!.toLocal())}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        if (post.isPrivateReply)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Private reply',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          post.message.isEmpty ? '（无正文）' : post.message,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
