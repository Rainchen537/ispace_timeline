import '../models/mail_models.dart';

abstract class MailService {
  Future<MailInboxSnapshot> fetchInbox({
    required MailAccessCredentials credentials,
    int limit = 25,
  });

  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required int uid,
  });

  Future<void> close();
}

class MailServiceException implements Exception {
  const MailServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
