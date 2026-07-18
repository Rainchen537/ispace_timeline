import '../models/mail_models.dart';

abstract class MailService {
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  });

  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    int? expectedMailboxUidValidity,
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
    required MailFolder folder,
    required int uid,
    required String partId,
    int? expectedMailboxUidValidity,
  });

  Future<MailDraftIdentity?> saveDraft({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
    int? existingDraftUid,
    int? expectedMailboxUidValidity,
  });

  Future<void> deleteMessages({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  });

  Future<void> restoreMessages({
    required MailAccessCredentials credentials,
    required List<int> uids,
    required String userEmailAddress,
    int? expectedMailboxUidValidity,
  });

  Future<void> close();
}

class MailServiceException implements Exception {
  const MailServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
