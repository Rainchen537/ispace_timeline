import '../models/mail_models.dart';
import 'mail_service.dart';

MailService createPlatformMailService() => MailServiceImpl();

class MailServiceImpl extends MailService {
  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<MailMessageSummary>> searchFolder({
    required MailAccessCredentials credentials,
    required String query,
    MailFolder folder = MailFolder.inbox,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required int uid,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<int>> downloadAttachment({
    required MailAccessCredentials credentials,
    required int uid,
    required String partId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> sendEmail({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> close() async {}
}
