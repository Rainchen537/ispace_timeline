class MailAccessCredentials {
  const MailAccessCredentials({
    required this.userId,
    required this.emailAddress,
    required this.password,
  });

  factory MailAccessCredentials.fromUserId({
    required String userId,
    required String password,
  }) {
    final normalizedUserId = userId.trim().split('@').first;
    return MailAccessCredentials(
      userId: normalizedUserId,
      emailAddress: '$normalizedUserId@mail.bnbu.edu.cn',
      password: password,
    );
  }

  final String userId;
  final String emailAddress;
  final String password;
}

enum MailFolder { inbox, sent, drafts, trash }

enum MailSearchScope { allText, subject, from, to }

class MailAttachment {
  const MailAttachment({
    required this.name,
    required this.size,
    required this.mimeType,
    this.contentId,
    this.partId,
  });

  final String name;
  final int size;
  final String mimeType;
  final String? contentId;
  final String? partId;
}

class MailMessageSummary {
  const MailMessageSummary({
    required this.uid,
    required this.subject,
    required this.sender,
    required this.preview,
    required this.hasHtmlBody,
    required this.date,
    required this.isSeen,
    this.hasAttachments = false,
  });

  final int uid;
  final String subject;
  final String sender;
  final String preview;
  final bool hasHtmlBody;
  final DateTime? date;
  final bool isSeen;
  final bool hasAttachments;

  MailMessageSummary copyWith({
    int? uid,
    String? subject,
    String? sender,
    String? preview,
    bool? hasHtmlBody,
    DateTime? date,
    bool? isSeen,
    bool? hasAttachments,
  }) {
    return MailMessageSummary(
      uid: uid ?? this.uid,
      subject: subject ?? this.subject,
      sender: sender ?? this.sender,
      preview: preview ?? this.preview,
      hasHtmlBody: hasHtmlBody ?? this.hasHtmlBody,
      date: date ?? this.date,
      isSeen: isSeen ?? this.isSeen,
      hasAttachments: hasAttachments ?? this.hasAttachments,
    );
  }
}

class MailMessageDetail {
  const MailMessageDetail({
    required this.uid,
    required this.subject,
    required this.sender,
    required this.recipients,
    required this.cc,
    required this.date,
    required this.body,
    required this.htmlBody,
    required this.isSeen,
    this.attachments = const [],
    this.messageId,
  });

  final int uid;
  final String subject;
  final String sender;
  final String recipients;
  final String? cc;
  final DateTime? date;
  final String body;
  final String? htmlBody;
  final bool isSeen;
  final List<MailAttachment> attachments;
  final String? messageId;
}

class MailFolderSnapshot {
  const MailFolderSnapshot({
    required this.emailAddress,
    required this.incomingServer,
    required this.outgoingServer,
    required this.messages,
    required this.fetchedAt,
    required this.folder,
    required this.totalMessages,
    required this.currentPage,
    required this.pageSize,
  });

  final String emailAddress;
  final String incomingServer;
  final String outgoingServer;
  final List<MailMessageSummary> messages;
  final DateTime fetchedAt;
  final MailFolder folder;
  final int totalMessages;
  final int currentPage;
  final int pageSize;

  int get unreadCount => messages.where((message) => !message.isSeen).length;

  MailFolderSnapshot copyWith({
    String? emailAddress,
    String? incomingServer,
    String? outgoingServer,
    List<MailMessageSummary>? messages,
    DateTime? fetchedAt,
    MailFolder? folder,
    int? totalMessages,
    int? currentPage,
    int? pageSize,
  }) {
    return MailFolderSnapshot(
      emailAddress: emailAddress ?? this.emailAddress,
      incomingServer: incomingServer ?? this.incomingServer,
      outgoingServer: outgoingServer ?? this.outgoingServer,
      messages: messages ?? this.messages,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      folder: folder ?? this.folder,
      totalMessages: totalMessages ?? this.totalMessages,
      currentPage: currentPage ?? this.currentPage,
      pageSize: pageSize ?? this.pageSize,
    );
  }
}

class MailComposeData {
  const MailComposeData({
    required this.to,
    this.cc,
    required this.subject,
    required this.body,
    this.htmlBody,
    this.inReplyTo,
    this.references,
  });

  final String to;
  final String? cc;
  final String subject;
  final String body;
  final String? htmlBody;
  final String? inReplyTo;
  final String? references;
}
