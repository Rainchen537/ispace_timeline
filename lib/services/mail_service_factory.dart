import 'mail_service.dart';
import 'mail_service_stub.dart'
    if (dart.library.io) 'mail_service_io.dart'
    as platform;

MailService createMailService() => platform.createPlatformMailService();
