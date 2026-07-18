import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/web_session_snapshot.dart';
import '../services/native_actions.dart';
import '../state/app_session_controller.dart';
import '../widgets/native_mirror_webview.dart';

class WebMirrorPage extends StatefulWidget {
  const WebMirrorPage({
    super.key,
    required this.controller,
    required this.title,
    required this.pathOrUrl,
    this.showFileActions = false,
    this.actionPathOrUrl,
  });

  final AppSessionController controller;
  final String title;
  final String pathOrUrl;
  final bool showFileActions;
  final String? actionPathOrUrl;

  @override
  State<WebMirrorPage> createState() => _WebMirrorPageState();
}

class _WebMirrorPageState extends State<WebMirrorPage> {
  static const MethodChannel _nativeActionsChannel = MethodChannel(
    'ispace/native_actions',
  );
  final GlobalKey<_MirrorWebViewPanelState> _panelKey =
      GlobalKey<_MirrorWebViewPanelState>();

  bool get _shouldShowFileActions {
    if (widget.showFileActions) {
      return true;
    }
    final source = '${widget.title} ${_resolvedActionUrl()}'.toLowerCase();
    const fileHints = [
      '.pdf',
      '.ppt',
      '.pptx',
      '.doc',
      '.docx',
      '.xls',
      '.xlsx',
      '/pluginfile.php',
    ];
    return fileHints.any(source.contains);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_shouldShowFileActions) ...[
            IconButton(
              onPressed: _openForDownload,
              tooltip: '下载',
              icon: const Icon(Icons.download_rounded),
            ),
            IconButton(
              onPressed: _shareResource,
              tooltip: '分享',
              icon: const Icon(Icons.share_rounded),
            ),
          ],
          IconButton(
            onPressed: () => _panelKey.currentState?.reload(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: MirrorWebViewPanel(
        key: _panelKey,
        controller: widget.controller,
        pathOrUrl: _resolvedDisplayUrl(),
      ),
    );
  }

  Future<void> _openForDownload() async {
    final url = _downloadUrl(_resolvedActionUrl());
    if (url.isEmpty) {
      return;
    }
    try {
      final fileName = _suggestedFileName(url, widget.title);
      final (cookieHeader, cookieOrigin) = await _loadCookieHeader(url);
      final downloadResult = await _nativeActionsChannel
          .invokeMethod<dynamic>('downloadFile', {
            'url': url,
            'filename': fileName,
            'title': widget.title,
            if (cookieHeader.isNotEmpty) 'cookieHeader': cookieHeader,
            if (cookieOrigin.isNotEmpty) 'cookieOrigin': cookieOrigin,
          });
      if (!mounted) {
        return;
      }
      final completedName = downloadedFileDisplayName(
        downloadResult,
        fallback: fileName,
      );
      final message =
          downloadResult is String && downloadResult.trim().isNotEmpty
          ? completedName.isEmpty
                ? '下载完成。'
                : '下载完成：$completedName'
          : '已加入下载任务。';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on PlatformException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('下载失败，请稍后重试。')));
    }
  }

  Future<void> _shareResource() async {
    final url = _downloadUrl(_resolvedActionUrl());
    if (url.isEmpty) {
      return;
    }
    try {
      final fileName = _suggestedFileName(url, widget.title);
      final (cookieHeader, cookieOrigin) = await _loadCookieHeader(url);
      await _nativeActionsChannel.invokeMethod('shareFile', {
        'url': url,
        'filename': fileName,
        'title': widget.title,
        if (cookieHeader.isNotEmpty) 'cookieHeader': cookieHeader,
        if (cookieOrigin.isNotEmpty) 'cookieOrigin': cookieOrigin,
      });
    } on PlatformException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('分享文件失败，请稍后重试。')));
    }
  }

  Future<(String, String)> _loadCookieHeader(String targetUrl) async {
    try {
      final snapshot = await widget.controller.prepareWebSession();
      if (!urlsHaveSameOrigin(targetUrl, snapshot.baseUrl)) {
        return ('', '');
      }
      final header = snapshot.cookies
          .where((cookie) => cookie.name.trim().isNotEmpty)
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
      return (header, snapshot.baseUrl);
    } catch (_) {
      return ('', '');
    }
  }

  String _resolvedDisplayUrl() {
    return _resolveUrl(widget.pathOrUrl);
  }

  String _resolvedActionUrl() {
    final custom = widget.actionPathOrUrl?.trim() ?? '';
    if (custom.isNotEmpty) {
      return _resolveUrl(custom);
    }
    return _resolvedDisplayUrl();
  }

  String _resolveUrl(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('data:') ||
        trimmed.startsWith('about:')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '${widget.controller.baseUrl}$trimmed';
    }
    return '${widget.controller.baseUrl}/$trimmed';
  }

  String _downloadUrl(String sourceUrl) {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null) {
      return sourceUrl;
    }
    if (!uri.path.contains('/pluginfile.php')) {
      return sourceUrl;
    }
    final query = Map<String, String>.from(uri.queryParameters);
    query.putIfAbsent('forcedownload', () => '1');
    return uri.replace(queryParameters: query).toString();
  }

  String _suggestedFileName(String url, String title) {
    final uri = Uri.tryParse(url);
    final lastSegment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    final normalizedSegment = Uri.decodeComponent(lastSegment).trim();
    if (normalizedSegment.isNotEmpty && normalizedSegment.contains('.')) {
      return normalizedSegment;
    }
    final normalizedTitle = title.trim();
    if (normalizedTitle.isNotEmpty && normalizedTitle.contains('.')) {
      return normalizedTitle;
    }
    return '';
  }
}

class MirrorWebViewPanel extends StatefulWidget {
  const MirrorWebViewPanel({
    super.key,
    required this.controller,
    required this.pathOrUrl,
  });

  final AppSessionController controller;
  final String pathOrUrl;

  @override
  State<MirrorWebViewPanel> createState() => _MirrorWebViewPanelState();
}

class _MirrorWebViewPanelState extends State<MirrorWebViewPanel> {
  Future<WebSessionSnapshot>? _future;
  int _reloadSeed = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<WebSessionSnapshot> _load() {
    return widget.controller.prepareWebSession();
  }

  Future<void> reload() => _reload();

  Future<void> _reload() async {
    final future = _load();
    setState(() {
      _future = future;
      _reloadSeed++;
    });
    try {
      await future;
    } catch (_) {
      // Rendered in UI.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WebSessionSnapshot>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          final message = snapshot.error?.toString() ?? '官网页面加载失败';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  FilledButton(onPressed: _reload, child: const Text('重试加载')),
                ],
              ),
            ),
          );
        }

        final session = snapshot.data!;
        final resolvedUrl = _resolveUrl(session.baseUrl, widget.pathOrUrl);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: NativeMirrorWebView(
              key: ValueKey('$resolvedUrl#$_reloadSeed'),
              initialUrl: resolvedUrl,
              session: session,
            ),
          ),
        );
      },
    );
  }

  String _resolveUrl(String baseUrl, String pathOrUrl) {
    final trimmed = pathOrUrl.trim();
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('data:') ||
        trimmed.startsWith('about:')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '$baseUrl$trimmed';
    }
    return '$baseUrl/$trimmed';
  }
}
