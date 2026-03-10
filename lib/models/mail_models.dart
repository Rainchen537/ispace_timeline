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

class MailMessageSummary {
  const MailMessageSummary({
    required this.uid,
    required this.subject,
    required this.sender,
    required this.preview,
    required this.hasHtmlBody,
    required this.date,
    required this.isSeen,
  });

  final int uid;
  final String subject;
  final String sender;
  final String preview;
  final bool hasHtmlBody;
  final DateTime? date;
  final bool isSeen;

  MailMessageSummary copyWith({
    int? uid,
    String? subject,
    String? sender,
    String? preview,
    bool? hasHtmlBody,
    DateTime? date,
    bool? isSeen,
  }) {
    return MailMessageSummary(
      uid: uid ?? this.uid,
      subject: subject ?? this.subject,
      sender: sender ?? this.sender,
      preview: preview ?? this.preview,
      hasHtmlBody: hasHtmlBody ?? this.hasHtmlBody,
      date: date ?? this.date,
      isSeen: isSeen ?? this.isSeen,
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
}

class MailInboxSnapshot {
  const MailInboxSnapshot({
    required this.emailAddress,
    required this.incomingServer,
    required this.outgoingServer,
    required this.messages,
    required this.fetchedAt,
  });

  final String emailAddress;
  final String incomingServer;
  final String outgoingServer;
  final List<MailMessageSummary> messages;
  final DateTime fetchedAt;

  int get unreadCount => messages.where((message) => !message.isSeen).length;

  MailInboxSnapshot copyWith({
    String? emailAddress,
    String? incomingServer,
    String? outgoingServer,
    List<MailMessageSummary>? messages,
    DateTime? fetchedAt,
  }) {
    return MailInboxSnapshot(
      emailAddress: emailAddress ?? this.emailAddress,
      incomingServer: incomingServer ?? this.incomingServer,
      outgoingServer: outgoingServer ?? this.outgoingServer,
      messages: messages ?? this.messages,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }
}
