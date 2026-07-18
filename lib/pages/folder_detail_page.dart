import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/course_content.dart';
import '../models/course_summary.dart';
import '../services/native_actions.dart';
import '../state/app_session_controller.dart';
import 'web_mirror_page.dart';

class FolderDetailPage extends StatefulWidget {
  const FolderDetailPage({
    super.key,
    required this.controller,
    required this.course,
    required this.module,
  });

  final AppSessionController controller;
  final CourseSummary course;
  final CourseModule module;

  @override
  State<FolderDetailPage> createState() => _FolderDetailPageState();
}

class _FolderDetailPageState extends State<FolderDetailPage> {
  static const MethodChannel _nativeActionsChannel = MethodChannel(
    'ispace/native_actions',
  );
  final DateFormat _timeFormatter = DateFormat('yyyy-MM-dd HH:mm');

  List<CourseModuleContent> _files = const [];
  String _descriptionHtml = '';
  bool _loading = false;
  String? _error;

  String get _downloadFolderUrl {
    final raw = widget.module.url.trim();
    final parsed = Uri.tryParse(raw);
    final idFromQuery = parsed?.queryParameters['id']?.trim() ?? '';
    final cmid = int.tryParse(idFromQuery) ?? widget.module.id;
    if (cmid <= 0) {
      return '';
    }
    return '${widget.controller.baseUrl}/mod/folder/download_folder.php?id=$cmid';
  }

  @override
  void initState() {
    super.initState();
    _descriptionHtml = widget.module.descriptionHtml.trim();
    _files = _normalizeFiles(widget.module.contents);
    if (_files.isEmpty || _descriptionHtml.isEmpty) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sections = await widget.controller.loadCourseContents(
        widget.course.id,
      );
      final latest = _resolveFolderModule(sections);
      if (!mounted) {
        return;
      }
      if (latest == null) {
        setState(() {
          _error = 'Folder 内容加载失败，请稍后重试。';
        });
      } else {
        setState(() {
          _descriptionHtml = latest.descriptionHtml.trim();
          _files = _normalizeFiles(latest.contents);
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Folder 内容加载失败，请稍后重试。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  CourseModule? _resolveFolderModule(List<CourseContentSection> sections) {
    final targetModuleId = widget.module.id;
    final targetInstanceId = widget.module.instance;
    final targetUrl = widget.module.url.trim();

    for (final section in sections) {
      for (final module in section.modules) {
        final modName = module.modName.toLowerCase();
        if (!modName.contains('folder')) {
          continue;
        }
        if (targetModuleId > 0 && module.id == targetModuleId) {
          return module;
        }
        if (targetInstanceId > 0 && module.instance == targetInstanceId) {
          return module;
        }
        if (targetUrl.isNotEmpty &&
            module.url.trim().isNotEmpty &&
            module.url.trim() == targetUrl) {
          return module;
        }
      }
    }
    return null;
  }

  List<CourseModuleContent> _normalizeFiles(List<CourseModuleContent> source) {
    final files = source
        .where((item) => item.fileName.trim().isNotEmpty)
        .toList(growable: false);
    files.sort((a, b) {
      final orderCompare = a.sortOrder.compareTo(b.sortOrder);
      if (orderCompare != 0) {
        return orderCompare;
      }
      return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
    });
    return files;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: Text(widget.module.name),
        actions: [
          if (_downloadFolderUrl.isNotEmpty)
            IconButton(
              onPressed: _downloadFolder,
              tooltip: 'Download folder',
              icon: const Icon(Icons.download_rounded),
            ),
          IconButton(
            onPressed: _loading ? null : _refresh,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: ListView(
          children: [
            _summaryCard(context),
            if (_loading) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              _errorBox(context, _error!),
            ],
            if (_descriptionHtml.isNotEmpty) ...[
              const SizedBox(height: 12),
              _descriptionPanel(_descriptionHtml),
            ],
            const SizedBox(height: 12),
            _filesCard(context),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.course.fullName,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF475569)),
          ),
          const SizedBox(height: 6),
          Text(
            '${_files.length} files',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _downloadFolderUrl.isEmpty ? null : _downloadFolder,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Download folder'),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(BuildContext context, String message) {
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

  Widget _descriptionPanel(String descriptionHtml) {
    final html = _buildHtmlDocument(descriptionHtml);
    final dataUrl = 'data:text/html;charset=utf-8,${Uri.encodeComponent(html)}';
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD5DEEA)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 260,
          child: MirrorWebViewPanel(
            controller: widget.controller,
            pathOrUrl: dataUrl,
          ),
        ),
      ),
    );
  }

  Widget _filesCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: _files.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: Text('当前 Folder 暂无可展示文件。'),
            )
          : Column(
              children: [
                for (var i = 0; i < _files.length; i++) ...[
                  _fileTile(context, _files[i]),
                  if (i != _files.length - 1)
                    const Divider(height: 1, indent: 14, endIndent: 14),
                ],
              ],
            ),
    );
  }

  Widget _fileTile(BuildContext context, CourseModuleContent file) {
    final fileUrl = file.fileUrl.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: fileUrl.isEmpty ? null : () => _openFilePreview(file),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  _fileIcon(file),
                  size: 18,
                  color: const Color(0xFF1D4E89),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fileMeta(file),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
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

  IconData _fileIcon(CourseModuleContent file) {
    final name = file.fileName.toLowerCase();
    final mime = file.mimeType.toLowerCase();
    if (mime.startsWith('image/') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    if (name.endsWith('.pdf') || mime.contains('pdf')) {
      return Icons.picture_as_pdf_outlined;
    }
    if (name.endsWith('.ppt') || name.endsWith('.pptx')) {
      return Icons.slideshow_outlined;
    }
    if (name.endsWith('.doc') ||
        name.endsWith('.docx') ||
        mime.contains('word')) {
      return Icons.description_outlined;
    }
    if (name.endsWith('.xls') ||
        name.endsWith('.xlsx') ||
        mime.contains('excel') ||
        mime.contains('spreadsheet')) {
      return Icons.table_chart_outlined;
    }
    if (name.endsWith('.zip') ||
        name.endsWith('.rar') ||
        mime.contains('zip')) {
      return Icons.archive_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _fileMeta(CourseModuleContent file) {
    final parts = <String>[];
    if (file.fileSize > 0) {
      parts.add(_formatBytes(file.fileSize));
    }
    if (file.timeModifiedAt != null) {
      parts.add(_timeFormatter.format(file.timeModifiedAt!.toLocal()));
    }
    if (file.mimeType.trim().isNotEmpty) {
      parts.add(file.mimeType.trim());
    }
    return parts.isEmpty ? '点击预览' : parts.join(' · ');
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
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

  Future<void> _openFilePreview(CourseModuleContent file) async {
    final previewUrl = _toPreviewUrl(file.fileUrl);
    if (previewUrl.isEmpty) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebMirrorPage(
          controller: widget.controller,
          title: file.fileName,
          pathOrUrl: previewUrl,
          showFileActions: true,
        ),
      ),
    );
  }

  String _toPreviewUrl(String sourceUrl) {
    final absolute = _resolveAbsoluteUrl(sourceUrl);
    if (absolute.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(absolute);
    if (uri == null) {
      return absolute;
    }
    final normalizedPath = uri.path.replaceFirst(
      '/webservice/pluginfile.php',
      '/pluginfile.php',
    );
    final query = Map<String, String>.from(uri.queryParameters);
    query.remove('token');
    final normalized = uri.replace(
      path: normalizedPath,
      queryParameters: query.isEmpty ? null : query,
    );
    return normalized.toString();
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

  Future<void> _downloadFolder() async {
    if (_downloadFolderUrl.isEmpty) {
      return;
    }
    final fileName = '${_safeFileName(widget.module.name)}.zip';
    String cookieHeader = '';
    String cookieOrigin = '';
    try {
      final snapshot = await widget.controller.prepareWebSession();
      if (urlsHaveSameOrigin(_downloadFolderUrl, snapshot.baseUrl)) {
        cookieHeader = snapshot.cookies
            .where((cookie) => cookie.name.trim().isNotEmpty)
            .map((cookie) => '${cookie.name}=${cookie.value}')
            .join('; ');
        cookieOrigin = snapshot.baseUrl;
      }
    } catch (_) {
      cookieHeader = '';
      cookieOrigin = '';
    }
    try {
      await _nativeActionsChannel.invokeMethod('downloadFile', {
        'url': _downloadFolderUrl,
        'filename': fileName,
        'title': widget.module.name,
        if (cookieHeader.isNotEmpty) 'cookieHeader': cookieHeader,
        if (cookieOrigin.isNotEmpty) 'cookieOrigin': cookieOrigin,
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已开始下载：$fileName')));
    } on PlatformException {
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WebMirrorPage(
            controller: widget.controller,
            title: 'Download folder',
            pathOrUrl: _downloadFolderUrl,
            showFileActions: true,
          ),
        ),
      );
    }
  }

  String _safeFileName(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return 'folder';
    }
    return normalized.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _buildHtmlDocument(String rawHtml) {
    return '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
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
}
