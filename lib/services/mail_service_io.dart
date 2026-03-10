import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/mail_models.dart';
import 'mail_service.dart';

MailService createPlatformMailService() => _IoMailService();

class _IoMailService implements MailService {
  static const String _incomingServer = 'imap.exmail.qq.com';
  static const String _outgoingServer = 'smtp.exmail.qq.com';
  static const int _downloadSizeLimit = 64 * 1024;

  MailClient? _client;
  MailAccessCredentials? _activeCredentials;
  final Map<int, MimeMessage> _messageCache = <int, MimeMessage>{};

  @override
  Future<MailInboxSnapshot> fetchInbox({
    required MailAccessCredentials credentials,
    int limit = 25,
  }) async {
    try {
      final client = await _ensureConnected(credentials);
      await client.selectInbox();
      final messages = await client.fetchMessages(
        count: limit,
        fetchPreference: FetchPreference.fullWhenWithinSize,
      );
      final validMessages = messages
          .where((message) => message.uid != null)
          .toList(growable: false)
        ..sort(_sortMessagesDesc);
      _messageCache
        ..clear()
        ..addEntries(
          validMessages.map((message) => MapEntry(message.uid!, message)),
        );

      return MailInboxSnapshot(
        emailAddress: credentials.emailAddress,
        incomingServer: _incomingServer,
        outgoingServer: _outgoingServer,
        messages: validMessages.map(_toSummary).toList(growable: false),
        fetchedAt: DateTime.now(),
      );
    } catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required int uid,
  }) async {
    try {
      final client = await _ensureConnected(credentials);
      await client.selectInbox();
      var message = _messageCache[uid];
      if (message == null) {
        await fetchInbox(credentials: credentials);
        message = _messageCache[uid];
      }
      if (message == null) {
        throw const MailServiceException('未找到这封邮件，请先刷新收件箱后重试。');
      }

      final loadedMessage = await client.fetchMessageContents(
        message,
        markAsSeen: true,
        includedInlineTypes: const [MediaToptype.text],
      );
      loadedMessage.isSeen = true;
      _messageCache[uid] = loadedMessage;
      return _toDetail(loadedMessage);
    } catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> close() async {
    _messageCache.clear();
    _activeCredentials = null;
    final client = _client;
    _client = null;
    if (client == null) {
      return;
    }
    try {
      await client.disconnect();
    } catch (_) {
      // Ignore disconnect failures during teardown.
    }
  }

  Future<MailClient> _ensureConnected(MailAccessCredentials credentials) async {
    final activeCredentials = _activeCredentials;
    final client = _client;
    final sameCredentials =
        activeCredentials?.emailAddress == credentials.emailAddress &&
        activeCredentials?.password == credentials.password;
    if (client != null && sameCredentials) {
      return client;
    }

    await close();
    final nextClient = MailClient(
      MailAccount.fromManualSettings(
        name: 'BNBU Mail',
        email: credentials.emailAddress,
        userName: credentials.userId,
        incomingHost: _incomingServer,
        outgoingHost: _outgoingServer,
        password: credentials.password,
        outgoingClientDomain: 'mail.bnbu.edu.cn',
      ),
      downloadSizeLimit: _downloadSizeLimit,
    );
    await nextClient.connect(timeout: const Duration(seconds: 20));
    _client = nextClient;
    _activeCredentials = credentials;
    return nextClient;
  }

  MailMessageSummary _toSummary(MimeMessage message) {
    final plainText = _extractPlainText(message);
    final htmlBody = _extractHtmlSource(message);
    return MailMessageSummary(
      uid: message.uid!,
      subject: _resolvedSubject(message),
      sender: _resolvedSender(message),
      preview: _buildPreview(plainText),
      hasHtmlBody: htmlBody.isNotEmpty,
      date: message.decodeDate(),
      isSeen: message.isSeen,
    );
  }

  MailMessageDetail _toDetail(MimeMessage message) {
    final recipients = _joinAddresses(message.to);
    final cc = _joinAddresses(message.cc);
    final plainText = _extractPlainText(message);
    final htmlBody = _buildRenderableHtml(message);
    return MailMessageDetail(
      uid: message.uid ?? 0,
      subject: _resolvedSubject(message),
      sender: _resolvedSender(message),
      recipients: recipients.isEmpty ? '未解析到收件人' : recipients,
      cc: cc.isEmpty ? null : cc,
      date: message.decodeDate(),
      body: plainText.isNotEmpty
          ? _normalizeReadableText(plainText)
          : _extractReadableText(message),
      htmlBody: htmlBody.isEmpty ? null : htmlBody,
      isSeen: message.isSeen,
    );
  }

  int _sortMessagesDesc(MimeMessage left, MimeMessage right) {
    final leftDate = left.decodeDate();
    final rightDate = right.decodeDate();
    if (leftDate != null && rightDate != null) {
      return rightDate.compareTo(leftDate);
    }
    return (right.uid ?? 0).compareTo(left.uid ?? 0);
  }

  String _resolvedSubject(MimeMessage message) {
    final subject = message.decodeSubject()?.trim() ?? '';
    return subject.isEmpty ? '(无主题)' : subject;
  }

  String _resolvedSender(MimeMessage message) {
    final from = message.from;
    if (from == null || from.isEmpty) {
      return '未知发件人';
    }
    final primary = from.first;
    final personalName = primary.personalName?.trim() ?? '';
    if (personalName.isNotEmpty) {
      return '$personalName <${primary.email}>';
    }
    return primary.email;
  }

  String _joinAddresses(List<MailAddress>? addresses) {
    if (addresses == null || addresses.isEmpty) {
      return '';
    }
    return addresses.map((address) {
      final personalName = address.personalName?.trim() ?? '';
      if (personalName.isNotEmpty) {
        return '$personalName <${address.email}>';
      }
      return address.email;
    }).join('，');
  }

  String _buildPreview(String plainText) {
    final body = _normalizeReadableText(plainText);
    if (body.isEmpty) {
      return '';
    }
    final singleLine = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= 88) {
      return singleLine;
    }
    return '${singleLine.substring(0, 88)}...';
  }

  String _extractReadableText(MimeMessage message) {
    final plainText = _extractPlainText(message);
    if (plainText.isNotEmpty) {
      return _normalizeReadableText(plainText);
    }
    final htmlText = _extractHtmlSource(message);
    if (htmlText.isEmpty) {
      return '';
    }
    return _extractReadableHtml(htmlText);
  }

  String _extractPlainText(MimeMessage message) {
    return message.decodeTextPlainPart()?.trim() ?? '';
  }

  String _extractHtmlSource(MimeMessage message) {
    return message.decodeTextHtmlPart()?.trim() ?? '';
  }

  String _buildRenderableHtml(MimeMessage message) {
    final htmlText = _extractHtmlSource(message);
    if (htmlText.isEmpty) {
      return '';
    }
    final parsed = html_parser.parse(htmlText);
    final headInnerHtml = parsed.head?.innerHtml.trim() ?? '';
    final bodyInnerHtml = parsed.body?.innerHtml.trim().isNotEmpty == true
        ? parsed.body!.innerHtml
        : htmlText;
    return '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
    $headInnerHtml
    <style>
      html, body {
        margin: 0;
        padding: 0;
        background: #ffffff;
      }
      body {
        padding: 12px 14px 18px;
        color: #111827;
        font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
        line-height: 1.55;
        overflow-wrap: break-word;
        word-break: break-word;
      }
      img, video, iframe, table {
        max-width: 100% !important;
      }
      img {
        height: auto !important;
      }
      table {
        width: auto !important;
      }
      pre {
        white-space: pre-wrap;
        word-break: break-word;
      }
      blockquote {
        margin: 0 0 0 12px;
        padding-left: 12px;
        border-left: 3px solid #E5E7EB;
      }
    </style>
  </head>
  <body>$bodyInnerHtml</body>
</html>
''';
  }

  String _extractReadableHtml(String htmlText) {
    final normalizedHtml = htmlText
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(
            r'</(p|div|li|tr|section|article|h[1-6])>',
            caseSensitive: false,
          ),
          '\n',
        );
    final parsed = html_parser.parse(normalizedHtml);
    for (final element
        in parsed.querySelectorAll('script,style,head,title,meta,link')) {
      element.remove();
    }
    final text = _flattenHtmlText(parsed.body ?? parsed.documentElement);
    return _normalizeReadableText(text);
  }

  String _flattenHtmlText(dom.Node? node) {
    if (node == null) {
      return '';
    }
    if (node is dom.Text) {
      return node.text;
    }
    if (node is! dom.Element) {
      return node.text ?? '';
    }
    final buffer = StringBuffer();
    final tag = node.localName?.toLowerCase();
    final isBlock = const {
      'p',
      'div',
      'section',
      'article',
      'header',
      'footer',
      'aside',
      'main',
      'ul',
      'ol',
      'li',
      'table',
      'tr',
      'td',
      'th',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
    }.contains(tag);
    if (tag == 'br') {
      return '\n';
    }
    for (final child in node.nodes) {
      buffer.write(_flattenHtmlText(child));
      if (child is dom.Element && child.localName?.toLowerCase() == 'br') {
        continue;
      }
    }
    if (isBlock) {
      buffer.write('\n');
    }
    return buffer.toString();
  }

  String _normalizeReadableText(String input) {
    return input
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[ \t\f\v]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  MailServiceException _mapError(Object error) {
    if (error is MailServiceException) {
      return error;
    }
    if (error is SocketException) {
      return const MailServiceException('邮箱服务器连接失败，请检查网络后重试。');
    }
    if (error is MailException) {
      final message = (error.message ?? '').toLowerCase();
      if (message.contains('auth') ||
          message.contains('login') ||
          message.contains('password')) {
        return const MailServiceException(
          '邮箱登录失败，请确认当前账号已开通邮箱，且邮箱密码与登录密码一致。',
        );
      }
      final readableMessage = error.message?.trim();
      if (readableMessage != null && readableMessage.isNotEmpty) {
        return MailServiceException('邮箱服务返回错误：$readableMessage');
      }
    }
    return const MailServiceException('邮箱加载失败，请稍后重试。');
  }
}
