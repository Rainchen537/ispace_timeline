import '../models/mail_models.dart';

abstract class MailService {
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
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
