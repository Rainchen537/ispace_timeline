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

  Future<List<MailMessageSummary>> searchFolder({
    required MailAccessCredentials credentials,
    required String query,
    MailFolder folder = MailFolder.inbox,
    MailSearchScope searchScope = MailSearchScope.allText,
  });

  Future<void> sendEmail({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
  });

  Future<List<int>> downloadAttachment({
    required MailAccessCredentials credentials,
    required int uid,
    required String partId,
  });

  Future<int?> saveDraft({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
    int? existingDraftUid,
  });

  Future<void> deleteMessages({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
  });

  Future<void> restoreMessages({
    required MailAccessCredentials credentials,
    required List<int> uids,
    required String userEmailAddress,
  });

  Future<void> close();
}

class MailServiceException implements Exception {
  const MailServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
