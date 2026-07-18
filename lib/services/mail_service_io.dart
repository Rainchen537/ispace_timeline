import 'dart:async';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../config/app_config.dart';
import '../models/mail_models.dart';
import 'mail_service.dart';

MailService createPlatformMailService() => _IoMailService();

class _IoMailService implements MailService {
  static final String _incomingServer = AppConfig.normalizedMailHost(
    AppConfig.mailIncomingServer,
    settingName: 'BNBU_MAIL_IMAP_HOST',
  );
  static final String _outgoingServer = AppConfig.normalizedMailHost(
    AppConfig.mailOutgoingServer,
    settingName: 'BNBU_MAIL_SMTP_HOST',
  );
  static const int _downloadSizeLimit = 64 * 1024;

  MailClient? _client;
  MailAccessCredentials? _activeCredentials;
  int _connectionGeneration = 0;
  Future<void> _operationQueue = Future<void>.value();
  final Map<(MailFolder, int?, int), MimeMessage> _messageCache =
      <(MailFolder, int?, int), MimeMessage>{};

  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) {
    return _serialize(() async {
      try {
        final client = await _ensureConnected(credentials);
        final folderPath = _mapFolderToPath(folder);
        final mailFolder = await client.selectMailboxByPath(folderPath);
        final uidValidity = mailFolder.uidValidity;
        _verifyMailboxIdentity(
          folder: folder,
          actualUidValidity: uidValidity,
          expectedUidValidity: expectedMailboxUidValidity,
          requireExpected: page > 1,
        );
        _discardStaleMailboxCache(folder, uidValidity);

        final totalMessages = mailFolder.messagesExists;
        if (totalMessages == 0) {
          return MailFolderSnapshot(
            emailAddress: credentials.emailAddress,
            incomingServer: _incomingServer,
            outgoingServer: _outgoingServer,
            messages: const [],
            fetchedAt: DateTime.now(),
            folder: folder,
            totalMessages: 0,
            currentPage: page,
            pageSize: pageSize,
            mailboxUidValidity: uidValidity,
          );
        }

        // enough_mail's fetchMessages(count:, page:) handles the last-page
        // boundary gracefully — it returns fewer messages when fewer exist.
        final messages = await client.fetchMessages(
          mailbox: mailFolder,
          count: pageSize,
          page: page,
          fetchPreference: FetchPreference.envelope,
        );

        final validMessages =
            messages
                .where((message) => message.uid != null)
                .toList(growable: false)
              ..sort(_sortMessagesDesc);

        _cacheEnvelopeMessages(folder, uidValidity, validMessages);

        return MailFolderSnapshot(
          emailAddress: credentials.emailAddress,
          incomingServer: _incomingServer,
          outgoingServer: _outgoingServer,
          messages: validMessages
              .map(
                (message) => _toSummary(
                  message,
                  folder: folder,
                  mailboxUidValidity: uidValidity,
                ),
              )
              .toList(growable: false),
          fetchedAt: DateTime.now(),
          folder: folder,
          totalMessages: totalMessages,
          currentPage: page,
          pageSize: pageSize,
          mailboxUidValidity: uidValidity,
        );
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  @override
  Future<List<MailMessageSummary>> searchFolder({
    required MailAccessCredentials credentials,
    required String query,
    MailFolder folder = MailFolder.inbox,
    MailSearchScope searchScope = MailSearchScope.allText,
  }) {
    final lowerQuery = query.trim().toLowerCase();
    if (lowerQuery.isEmpty) return Future.value(const []);
    return _serialize(() async {
      try {
        final client = await _ensureConnected(credentials);
        final folderPath = _mapFolderToPath(folder);
        final mailbox = await client.selectMailboxByPath(folderPath);
        final uidValidity = mailbox.uidValidity;
        _discardStaleMailboxCache(folder, uidValidity);

        final total = mailbox.messagesExists;
        if (total == 0) return const <MailMessageSummary>[];

        // Fetch all messages with envelope (from/subject/date/flags only)
        // for fast client-side filtering, since QQ exmail does not support
        // IMAP SEARCH criteria properly.
        final messages = await client.fetchMessages(
          mailbox: mailbox,
          count: total,
          fetchPreference: FetchPreference.envelope,
        );
        final validMessages = messages
            .where((message) => message.uid != null)
            .toList(growable: false);
        _cacheEnvelopeMessages(folder, uidValidity, validMessages);

        final summaries =
            validMessages
                .where(
                  (message) => _messageMatchesSearch(
                    message,
                    lowerQuery,
                    searchScope,
                    folder,
                    uidValidity,
                  ),
                )
                .map(
                  (message) => _toSummary(
                    message,
                    folder: folder,
                    mailboxUidValidity: uidValidity,
                  ),
                )
                .toList(growable: false)
              ..sort(_sortSummariesDesc);

        return summaries;
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  bool _messageMatchesSearch(
    MimeMessage message,
    String lowerQuery,
    MailSearchScope scope,
    MailFolder folder,
    int? mailboxUidValidity,
  ) {
    switch (scope) {
      case MailSearchScope.allText:
        return _subjectContains(message, lowerQuery) ||
            _fromContains(message, lowerQuery) ||
            _toContains(message, lowerQuery) ||
            _bodyContains(message, lowerQuery, folder, mailboxUidValidity);
      case MailSearchScope.subject:
        return _subjectContains(message, lowerQuery);
      case MailSearchScope.from:
        return _fromContains(message, lowerQuery);
      case MailSearchScope.to:
        return _toContains(message, lowerQuery);
    }
  }

  bool _subjectContains(MimeMessage message, String query) =>
      (message.decodeSubject()?.toLowerCase() ?? '').contains(query);

  bool _fromContains(MimeMessage message, String query) =>
      _addressListContains(message.from, query);

  bool _toContains(MimeMessage message, String query) =>
      _addressListContains(message.to, query) ||
      _addressListContains(message.cc, query);

  bool _addressListContains(List<MailAddress>? addresses, String query) {
    if (addresses == null || addresses.isEmpty) return false;
    return addresses.any(
      (addr) =>
          (addr.email.toLowerCase()).contains(query) ||
          (addr.personalName?.toLowerCase() ?? '').contains(query),
    );
  }

  bool _bodyContains(
    MimeMessage message,
    String query,
    MailFolder folder,
    int? mailboxUidValidity,
  ) {
    // Body is only available for fully-fetched cached messages.
    final uid = message.uid;
    if (uid == null) return false;
    final cached = _messageCache[(folder, mailboxUidValidity, uid)];
    if (cached == null) return false;
    final plain = cached.decodeTextPlainPart()?.toLowerCase() ?? '';
    return plain.contains(query);
  }

  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    int? expectedMailboxUidValidity,
  }) {
    return _serialize(() async {
      try {
        final client = await _ensureConnected(credentials);
        final mailbox = await client.selectMailboxByPath(
          _mapFolderToPath(folder),
        );
        final uidValidity = mailbox.uidValidity;
        _verifyMailboxIdentity(
          folder: folder,
          actualUidValidity: uidValidity,
          expectedUidValidity: expectedMailboxUidValidity,
          requireExpected: true,
        );
        _discardStaleMailboxCache(folder, uidValidity);

        final message = await _loadMessageEnvelope(
          client: client,
          mailbox: mailbox,
          folder: folder,
          mailboxUidValidity: uidValidity,
          uid: uid,
        );
        final loadedMessage = await client.fetchMessageContents(
          message,
          markAsSeen: true,
          includedInlineTypes: const [MediaToptype.text, MediaToptype.image],
        );
        loadedMessage.isSeen = true;
        _messageCache[(folder, uidValidity, uid)] = loadedMessage;
        return _toDetail(
          loadedMessage,
          folder: folder,
          mailboxUidValidity: uidValidity,
        );
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  @override
  Future<List<int>> downloadAttachment({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    required String partId,
    int? expectedMailboxUidValidity,
  }) {
    return _serialize(() async {
      try {
        final index = int.tryParse(partId);
        if (index == null || index < 0) {
          throw const MailServiceException('附件参数错误。');
        }

        final client = await _ensureConnected(credentials);
        final mailbox = await client.selectMailboxByPath(
          _mapFolderToPath(folder),
        );
        final uidValidity = mailbox.uidValidity;
        _verifyMailboxIdentity(
          folder: folder,
          actualUidValidity: uidValidity,
          expectedUidValidity: expectedMailboxUidValidity,
          requireExpected: true,
        );
        _discardStaleMailboxCache(folder, uidValidity);

        final message = await _loadMessageEnvelope(
          client: client,
          mailbox: mailbox,
          folder: folder,
          mailboxUidValidity: uidValidity,
          uid: uid,
        );
        final loadedMessage = await client.fetchMessageContents(message);
        _messageCache[(folder, uidValidity, uid)] = loadedMessage;

        final allParts = loadedMessage.allPartsFlat;
        if (index >= allParts.length) {
          throw const MailServiceException('未找到该附件。');
        }
        return allParts[index].decodeContentBinary() ?? const [];
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  @override
  Future<void> sendEmail({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
  }) {
    return _serialize(() async {
      try {
        final client = await _ensureConnected(credentials);

        final MessageBuilder builder;
        if (composeData.htmlBody != null) {
          builder = MessageBuilder.prepareMultipartAlternativeMessage(
            plainText: composeData.body,
            htmlText: composeData.htmlBody!,
          );
        } else {
          builder = MessageBuilder.prepareMultipartMixedMessage();
          builder.addTextPlain(composeData.body);
        }

        builder.from = [MailAddress(null, credentials.emailAddress)];
        builder.to = [MailAddress(null, composeData.to)];
        if (composeData.cc != null && composeData.cc!.isNotEmpty) {
          builder.cc = [MailAddress(null, composeData.cc!)];
        }
        builder.subject = composeData.subject;

        if (composeData.inReplyTo != null) {
          builder.addHeader('In-Reply-To', composeData.inReplyTo!);
        }
        if (composeData.references != null) {
          builder.addHeader('References', composeData.references!);
        }

        final mimeMessage = builder.buildMimeMessage();
        await client.sendMessage(mimeMessage);
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  @override
  Future<void> deleteMessages({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  }) {
    if (uids.isEmpty) return Future.value();
    return _serialize(() async {
      try {
        final client = await _ensureConnected(credentials);
        if (client.mailboxes == null) {
          await client.listMailboxes();
        }
        final mailbox = await client.selectMailboxByPath(
          _mapFolderToPath(folder),
        );
        final uidValidity = mailbox.uidValidity;
        _verifyMailboxIdentity(
          folder: folder,
          actualUidValidity: uidValidity,
          expectedUidValidity: expectedMailboxUidValidity,
          requireExpected: true,
        );
        final sequence = MessageSequence.fromIds(uids, isUid: true);

        // Try the standard path: enough_mail will attempt UID MOVE (or UID COPY+\Deleted).
        bool moved = false;
        try {
          await client.deleteMessages(sequence, expunge: false);
          moved = true;
        } on MailException {
          // QQ exmail returns "100001 Mails not exist!" for UID MOVE even when
          // the message exists. Fall through to the manual UID-based fallback.
        }

        if (!moved) {
          // Fallback: UID COPY to trash + UID STORE \Deleted + EXPUNGE.
          // We access the low-level ImapClient because MailClient.deleteMessages
          // with expunge:true incorrectly calls STORE (sequence-number-based)
          // instead of UID STORE for UID sequences.
          final imapClient = client.lowLevelIncomingMailClient as ImapClient;

          if (folder != MailFolder.trash) {
            // Best-effort copy to trash so the message appears in Deleted Messages.
            try {
              await imapClient.uidCopy(
                sequence,
                targetMailboxPath: _mapFolderToPath(MailFolder.trash),
              );
            } catch (_) {
              // If copy to trash fails, skip it and proceed to permanent delete.
            }
          }

          // Mark as \Deleted using UID STORE (correct UID-based command).
          await imapClient.uidStore(
            sequence,
            [MessageFlags.deleted],
            action: StoreAction.add,
            silent: true,
          );
          // EXPUNGE removes all \Deleted messages from the selected mailbox.
          await imapClient.expunge();
        }

        for (final uid in uids) {
          _messageCache.remove((folder, uidValidity, uid));
        }
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  @override
  Future<MailDraftIdentity?> saveDraft({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
    int? existingDraftUid,
    int? expectedMailboxUidValidity,
  }) {
    return _serialize(() async {
      try {
        final client = await _ensureConnected(credentials);
        final draftsMailbox = await client.selectMailboxByPath(
          _mapFolderToPath(MailFolder.drafts),
        );
        final draftsUidValidity = draftsMailbox.uidValidity;
        _discardStaleMailboxCache(MailFolder.drafts, draftsUidValidity);

        // A UID is only meaningful within the exact Drafts UIDVALIDITY epoch.
        if (existingDraftUid != null) {
          if (expectedMailboxUidValidity == null || draftsUidValidity == null) {
            throw const MailServiceException('草稿箱身份不可用，请刷新草稿箱后重试。');
          }
          _verifyMailboxIdentity(
            folder: MailFolder.drafts,
            actualUidValidity: draftsUidValidity,
            expectedUidValidity: expectedMailboxUidValidity,
          );
          final draftSeq = MessageSequence.fromIds([
            existingDraftUid,
          ], isUid: true);
          // Use UID STORE \Deleted + EXPUNGE directly to avoid enough_mail's
          // deleteMessages(expunge:true) bug which uses STORE (not UID STORE).
          final imapClient = client.lowLevelIncomingMailClient as ImapClient;
          await imapClient.uidStore(
            draftSeq,
            [MessageFlags.deleted],
            action: StoreAction.add,
            silent: true,
          );
          await imapClient.expunge();
          _messageCache.remove((
            MailFolder.drafts,
            draftsUidValidity,
            existingDraftUid,
          ));
        }

        // Build message
        final builder = MessageBuilder.prepareMultipartMixedMessage();
        builder.from = [MailAddress(null, credentials.emailAddress)];
        if (composeData.to.isNotEmpty) {
          builder.to = [MailAddress(null, composeData.to)];
        }
        if (composeData.cc != null && composeData.cc!.isNotEmpty) {
          builder.cc = [MailAddress(null, composeData.cc!)];
        }
        builder.subject = composeData.subject;
        builder.addTextPlain(composeData.body);
        if (composeData.inReplyTo != null) {
          builder.addHeader('In-Reply-To', composeData.inReplyTo!);
        }
        if (composeData.references != null) {
          builder.addHeader('References', composeData.references!);
        }
        final mimeMessage = builder.buildMimeMessage();

        // Append to Drafts. APPENDUID supplies the authoritative mailbox epoch.
        UidResponseCode? uidResponse;
        try {
          uidResponse = await client.appendMessageToFlag(
            mimeMessage,
            MailboxFlag.drafts,
            flags: [MessageFlags.draft, MessageFlags.seen],
          );
        } catch (_) {
          uidResponse = await client.appendMessage(
            mimeMessage,
            draftsMailbox,
            flags: [MessageFlags.draft, MessageFlags.seen],
          );
        }

        final newUid = uidResponse?.targetSequence.toList(null).firstOrNull;
        if (uidResponse == null || newUid == null) return null;
        return MailDraftIdentity(
          uid: newUid,
          mailboxUidValidity: uidResponse.uidValidity,
        );
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  @override
  Future<void> restoreMessages({
    required MailAccessCredentials credentials,
    required List<int> uids,
    required String userEmailAddress,
    int? expectedMailboxUidValidity,
  }) {
    if (uids.isEmpty) return Future.value();
    return _serialize(() async {
      try {
        final client = await _ensureConnected(credentials);
        final imapClient = client.lowLevelIncomingMailClient as ImapClient;

        // Select trash so subsequent IMAP commands operate on it.
        final mailbox = await client.selectMailboxByPath(
          _mapFolderToPath(MailFolder.trash),
        );
        final uidValidity = mailbox.uidValidity;
        _verifyMailboxIdentity(
          folder: MailFolder.trash,
          actualUidValidity: uidValidity,
          expectedUidValidity: expectedMailboxUidValidity,
          requireExpected: true,
        );
        final sequence = MessageSequence.fromIds(uids, isUid: true);

        // Fetch FLAGS + FROM for each UID to determine the restore target folder.
        final fetchResult = await imapClient.uidFetchMessages(
          sequence,
          '(UID FLAGS ENVELOPE)',
        );

        // Group UIDs by their inferred restore target folder.
        final Map<String, List<int>> byFolder = {};
        final Set<int> foundUids = {};
        for (final msg in fetchResult.messages) {
          final uid = msg.uid;
          if (uid == null) continue;
          foundUids.add(uid);
          final targetPath = _inferRestoreFolder(msg, userEmailAddress);
          byFolder.putIfAbsent(targetPath, () => []).add(uid);
        }

        // Any UIDs not returned by the server fall back to INBOX.
        for (final uid in uids) {
          if (!foundUids.contains(uid)) {
            byFolder.putIfAbsent('INBOX', () => []).add(uid);
          }
        }

        // UID COPY each group to its target folder.
        for (final entry in byFolder.entries) {
          if (entry.value.isEmpty) continue;
          final groupSeq = MessageSequence.fromIds(entry.value, isUid: true);
          await imapClient.uidCopy(groupSeq, targetMailboxPath: entry.key);
        }

        // Mark all restored messages as \Deleted in trash, then expunge only
        // those UIDs (UID EXPUNGE via UIDPLUS extension) so we don't accidentally
        // purge other messages that happen to carry \Deleted already.
        await imapClient.uidStore(
          sequence,
          [MessageFlags.deleted],
          action: StoreAction.add,
          silent: true,
        );
        try {
          await imapClient.uidExpunge(sequence);
        } catch (_) {
          // If the server doesn't support UIDPLUS, fall back to plain EXPUNGE.
          await imapClient.expunge();
        }

        for (final uid in uids) {
          _messageCache.remove((MailFolder.trash, uidValidity, uid));
        }
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  /// Infers the folder a trash message originally came from.
  ///
  /// Priority (checked in order):
  ///   1. Message has `\Draft` flag → 'Drafts'
  ///   2. FROM address matches [userEmailAddress] → 'Sent Messages'
  ///   3. Otherwise → 'INBOX'
  String _inferRestoreFolder(MimeMessage message, String userEmailAddress) {
    final flags = message.flags;
    if (flags != null && flags.contains(MessageFlags.draft)) {
      return 'Drafts';
    }
    final from = message.from;
    if (from != null) {
      for (final addr in from) {
        if (addr.email.toLowerCase() == userEmailAddress.toLowerCase()) {
          return 'Sent Messages';
        }
      }
    }
    return 'INBOX';
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _operationQueue.then((_) => operation());
    _operationQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  void _verifyMailboxIdentity({
    required MailFolder folder,
    required int? actualUidValidity,
    required int? expectedUidValidity,
    bool requireExpected = false,
  }) {
    if (expectedUidValidity == null) {
      if (!requireExpected) return;
      throw MailServiceException('${_folderDisplayName(folder)}身份不可用，请刷新后重试。');
    }
    if (actualUidValidity == expectedUidValidity) return;
    throw MailServiceException('${_folderDisplayName(folder)}已更新，请刷新后重试。');
  }

  void _discardStaleMailboxCache(MailFolder folder, int? mailboxUidValidity) {
    _messageCache.removeWhere(
      (key, _) => key.$1 == folder && key.$2 != mailboxUidValidity,
    );
  }

  void _cacheEnvelopeMessages(
    MailFolder folder,
    int? mailboxUidValidity,
    Iterable<MimeMessage> messages,
  ) {
    for (final message in messages) {
      final uid = message.uid;
      if (uid == null) continue;
      _messageCache.putIfAbsent((
        folder,
        mailboxUidValidity,
        uid,
      ), () => message);
    }
  }

  Future<MimeMessage> _loadMessageEnvelope({
    required MailClient client,
    required Mailbox mailbox,
    required MailFolder folder,
    required int? mailboxUidValidity,
    required int uid,
  }) async {
    final key = (folder, mailboxUidValidity, uid);
    final cached = _messageCache[key];
    if (cached != null) return cached;

    final messages = await client.fetchMessageSequence(
      MessageSequence.fromIds([uid], isUid: true),
      mailbox: mailbox,
      fetchPreference: FetchPreference.envelope,
    );
    for (final message in messages) {
      if (message.uid == uid) {
        _messageCache[key] = message;
        return message;
      }
    }
    throw const MailServiceException('未找到这封邮件，请先刷新后重试。');
  }

  @override
  Future<void> close() => _serialize(_closeConnection);

  Future<void> _closeConnection() async {
    _connectionGeneration++;
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

    await _closeConnection();
    final connectionGeneration = ++_connectionGeneration;
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
    try {
      await nextClient.connect(timeout: const Duration(seconds: 20));
      if (connectionGeneration != _connectionGeneration) {
        try {
          await nextClient.disconnect();
        } catch (_) {
          // Ignore teardown failures for a superseded connection.
        }
        throw const MailServiceException('邮箱连接已关闭，请重试。');
      }
      _client = nextClient;
      _activeCredentials = credentials;
      return nextClient;
    } catch (_) {
      try {
        await nextClient.disconnect();
      } catch (_) {
        // Ignore cleanup failures for an incomplete connection.
      }
      if (connectionGeneration == _connectionGeneration) {
        _activeCredentials = null;
      }
      rethrow;
    }
  }

  String _folderDisplayName(MailFolder folder) {
    switch (folder) {
      case MailFolder.inbox:
        return '收件箱';
      case MailFolder.sent:
        return '已发送';
      case MailFolder.drafts:
        return '草稿箱';
      case MailFolder.trash:
        return '已删除';
    }
  }

  String _mapFolderToPath(MailFolder folder) {
    switch (folder) {
      case MailFolder.inbox:
        return 'INBOX';
      case MailFolder.sent:
        return 'Sent Messages';
      case MailFolder.drafts:
        return 'Drafts';
      case MailFolder.trash:
        return 'Deleted Messages';
    }
  }

  MailMessageSummary _toSummary(
    MimeMessage message, {
    required MailFolder folder,
    required int? mailboxUidValidity,
  }) {
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
      hasAttachments: message.hasAttachments(),
      folder: folder,
      mailboxUidValidity: mailboxUidValidity,
    );
  }

  MailMessageDetail _toDetail(
    MimeMessage message, {
    required MailFolder folder,
    required int? mailboxUidValidity,
  }) {
    final recipients = _joinAddresses(message.to);
    final cc = _joinAddresses(message.cc);
    final plainText = _extractPlainText(message);
    final htmlBody = _buildRenderableHtml(message);

    final attachments = <MailAttachment>[];
    final allParts = message.allPartsFlat;
    for (var i = 0; i < allParts.length; i++) {
      final part = allParts[i];
      final contentDisposition =
          part.decodeHeaderValue('Content-Disposition')?.toLowerCase() ?? '';
      if (contentDisposition.contains('attachment')) {
        attachments.add(
          MailAttachment(
            name: part.decodeFileName() ?? '未命名附件',
            size: 0,
            mimeType:
                part.decodeHeaderValue('Content-Type') ??
                'application/octet-stream',
            contentId: part.decodeHeaderValue('Content-ID'),
            partId: i.toString(),
          ),
        );
      }
    }

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
      attachments: attachments,
      messageId: message.getHeaderValue('Message-Id'),
      mailboxUidValidity: mailboxUidValidity,
      folder: folder,
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

  int _sortSummariesDesc(MailMessageSummary left, MailMessageSummary right) {
    final leftDate = left.date;
    final rightDate = right.date;
    if (leftDate != null && rightDate != null) {
      return rightDate.compareTo(leftDate);
    }
    return right.uid.compareTo(left.uid);
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
    return addresses
        .map((address) {
          final personalName = address.personalName?.trim() ?? '';
          if (personalName.isNotEmpty) {
            return '$personalName <${address.email}>';
          }
          return address.email;
        })
        .join('，');
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
    for (final element in parsed.querySelectorAll(
      'script,iframe,object,embed,base,form,meta[http-equiv="refresh"]',
    )) {
      element.remove();
    }
    final headInnerHtml = parsed.head?.innerHtml.trim() ?? '';
    final bodyInnerHtml = parsed.body?.innerHtml.trim().isNotEmpty == true
        ? parsed.body!.innerHtml
        : (parsed.documentElement?.innerHtml ?? '');
    return '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: cid:; style-src 'unsafe-inline'; font-src data:; connect-src 'none'; media-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'">
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
    for (final element in parsed.querySelectorAll(
      'script,style,head,title,meta,link',
    )) {
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
        return const MailServiceException('邮箱登录失败，请确认当前账号已开通邮箱，且邮箱密码与登录密码一致。');
      }
      final readableMessage = error.message?.trim();
      if (readableMessage != null && readableMessage.isNotEmpty) {
        return MailServiceException('邮箱服务返回错误：$readableMessage');
      }
    }
    return const MailServiceException('邮箱加载失败，请稍后重试。');
  }
}
