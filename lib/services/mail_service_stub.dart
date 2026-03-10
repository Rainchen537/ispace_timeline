import '../models/mail_models.dart';
import 'mail_service.dart';

MailService createPlatformMailService() => _UnsupportedMailService();

class _UnsupportedMailService implements MailService {
  @override
  Future<MailInboxSnapshot> fetchInbox({
    required MailAccessCredentials credentials,
    int limit = 25,
  }) {
    throw const MailServiceException('当前平台暂不支持 IMAP 邮箱访问。');
  }

  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required int uid,
  }) {
    throw const MailServiceException('当前平台暂不支持 IMAP 邮箱访问。');
  }

  @override
  Future<void> close() async {}
}
