import 'dart:convert';

import 'package:crypto/crypto.dart';
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

String downloadedFileDisplayName(Object? result, {required String fallback}) {
  final normalizedFallback = fallback.trim();
  if (result is! String || result.trim().isEmpty) {
    return normalizedFallback;
  }
  final raw = result.trim();
  final parsed = Uri.tryParse(raw);
  if (parsed?.scheme.toLowerCase() == 'content') {
    return normalizedFallback;
  }
  final normalizedPath = raw.replaceAll('\\', '/');
  final lastSegment = normalizedPath.split('/').last.trim();
  if (lastSegment.isEmpty) {
    return normalizedFallback;
  }
  return Uri.decodeComponent(lastSegment);
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
  required String accountId,
  required String mailbox,
  required int messageUid,
  required String partId,
  required String originalName,
  String? messageId,
  int? mailboxUidValidity,
}) {
  final scope = jsonEncode(<String>[
    accountId.trim().toLowerCase(),
    mailbox.trim().toLowerCase(),
    mailboxUidValidity?.toString() ?? '',
    messageId?.trim() ?? '',
    messageUid.toString(),
    partId,
  ]);
  final digest = sha256.convert(utf8.encode(scope)).toString().substring(0, 24);
  final prefix = '${digest}_';
  final availableBytes = 240 - utf8.encode(prefix).length;
  final displayName = _truncateFileNameToUtf8Bytes(
    safeAttachmentFileName(originalName),
    availableBytes,
  );
  return '$prefix$displayName';
}

String _truncateFileNameToUtf8Bytes(String fileName, int maxBytes) {
  if (utf8.encode(fileName).length <= maxBytes) {
    return fileName;
  }

  final dotIndex = fileName.lastIndexOf('.');
  final hasExtension = dotIndex > 0 && dotIndex < fileName.length - 1;
  final extension = hasExtension ? fileName.substring(dotIndex) : '';
  final extensionBytes = utf8.encode(extension).length;
  if (extensionBytes >= maxBytes) {
    return _truncateUtf8(fileName, maxBytes);
  }

  final baseName = hasExtension ? fileName.substring(0, dotIndex) : fileName;
  final truncatedBase = _truncateUtf8(baseName, maxBytes - extensionBytes);
  return '$truncatedBase$extension';
}

String _truncateUtf8(String value, int maxBytes) {
  if (maxBytes <= 0) {
    return '';
  }
  final buffer = StringBuffer();
  var byteCount = 0;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final characterBytes = utf8.encode(character).length;
    if (byteCount + characterBytes > maxBytes) {
      break;
    }
    buffer.write(character);
    byteCount += characterBytes;
  }
  return buffer.toString();
}

bool urlsHaveSameOrigin(String first, String second) {
  final left = Uri.tryParse(first.trim());
  final right = Uri.tryParse(second.trim());
  if (!_isHttpUri(left) || !_isHttpUri(right)) {
    return false;
  }
  return left!.scheme.toLowerCase() == right!.scheme.toLowerCase() &&
      left.host.toLowerCase() == right.host.toLowerCase() &&
      _effectiveUriPort(left) == _effectiveUriPort(right);
}

bool _isHttpUri(Uri? uri) {
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
    return false;
  }
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
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
