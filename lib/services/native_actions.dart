import 'dart:convert';

import 'package:flutter/services.dart';

class NativeActions {
  const NativeActions({
    MethodChannel channel = const MethodChannel('ispace/native_actions'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<String> getMailAttachmentCacheDirectory() async {
    final path = await _channel.invokeMethod<String>(
      'getMailAttachmentCacheDir',
    );
    if (path == null || path.trim().isEmpty) {
      throw PlatformException(
        code: 'cache_directory_unavailable',
        message: '邮件附件缓存目录不可用。',
      );
    }
    return path;
  }

  Future<void> openFile({required String path, required String mimeType}) {
    return _channel.invokeMethod<void>('openFile', {
      'path': path,
      'mimeType': mimeType,
    });
  }

  Future<void> clearWebSession() {
    return _channel.invokeMethod<void>('clearWebSession');
  }
}

String safeAttachmentFileName(String rawName) {
  final trimmed = rawName.trim();
  final withoutPath = trimmed.split(RegExp(r'[/\\]')).last;
  final sanitized = withoutPath.replaceAll(RegExp(r'[:*?"<>|\x00-\x1F]'), '_');
  if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
    return 'attachment.bin';
  }
  return sanitized;
}

String mailAttachmentCacheFileName({
  required int messageUid,
  required String partId,
  required String originalName,
}) {
  final encodedPartId = base64Url.encode(utf8.encode(partId));
  return '${messageUid}_${encodedPartId}_${safeAttachmentFileName(originalName)}';
}

bool urlsHaveSameOrigin(String first, String second) {
  final left = Uri.tryParse(first.trim());
  final right = Uri.tryParse(second.trim());
  if (left == null || right == null || !left.hasScheme || !right.hasScheme) {
    return false;
  }
  return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
      left.host.toLowerCase() == right.host.toLowerCase() &&
      _effectiveUriPort(left) == _effectiveUriPort(right);
}

int _effectiveUriPort(Uri uri) {
  if (uri.hasPort) {
    return uri.port;
  }
  return switch (uri.scheme.toLowerCase()) {
    'http' => 80,
    'https' => 443,
    _ => -1,
  };
}
