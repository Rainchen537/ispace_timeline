import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ispace_timeline/services/native_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/native_actions');
  const actions = NativeActions(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('requests the attachment cache directory', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getMailAttachmentCacheDir');
      return '/tmp/mail_attachments';
    });

    expect(
      await actions.getMailAttachmentCacheDirectory(),
      '/tmp/mail_attachments',
    );
  });

  test('opens a file with path and MIME type', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });

    await actions.openFile(
      path: '/tmp/mail_attachments/report.pdf',
      mimeType: 'application/pdf',
    );

    expect(received?.method, 'openFile');
    expect(received?.arguments, {
      'path': '/tmp/mail_attachments/report.pdf',
      'mimeType': 'application/pdf',
    });
  });

  test('clears the native web session', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });

    await actions.clearWebSession();

    expect(received?.method, 'clearWebSession');
    expect(received?.arguments, isNull);
  });

  group('safeAttachmentFileName', () {
    test('removes path traversal components', () {
      expect(safeAttachmentFileName('../../secret.txt'), 'secret.txt');
      expect(safeAttachmentFileName(r'..\secret.txt'), 'secret.txt');
    });

    test('replaces invalid file name characters', () {
      expect(safeAttachmentFileName('report:final?.pdf'), 'report_final_.pdf');
    });

    test('uses a fallback for unusable names', () {
      expect(safeAttachmentFileName('..'), 'attachment.bin');
      expect(safeAttachmentFileName(''), 'attachment.bin');
    });
  });

  group('mailAttachmentCacheFileName', () {
    test('includes the message and reversible part identity', () {
      expect(
        mailAttachmentCacheFileName(
          messageUid: 42,
          partId: '2.1',
          originalName: 'report.pdf',
        ),
        '42_Mi4x_report.pdf',
      );
    });

    test('keeps sanitization collisions in separate cache files', () {
      final first = mailAttachmentCacheFileName(
        messageUid: 42,
        partId: '2.1',
        originalName: 'report?.pdf',
      );
      final second = mailAttachmentCacheFileName(
        messageUid: 42,
        partId: '2.2',
        originalName: 'report*.pdf',
      );

      expect(first, isNot(second));
      expect(first, endsWith('report_.pdf'));
      expect(second, endsWith('report_.pdf'));
    });
  });

  group('urlsHaveSameOrigin', () {
    test('accepts equivalent default HTTPS ports', () {
      expect(
        urlsHaveSameOrigin(
          'https://ispace.example.edu/file',
          'https://ispace.example.edu:443',
        ),
        isTrue,
      );
    });

    test('rejects different hosts, schemes, and ports', () {
      expect(
        urlsHaveSameOrigin(
          'https://attacker.example/file',
          'https://ispace.example.edu',
        ),
        isFalse,
      );
      expect(
        urlsHaveSameOrigin(
          'http://ispace.example.edu/file',
          'https://ispace.example.edu',
        ),
        isFalse,
      );
      expect(
        urlsHaveSameOrigin(
          'https://ispace.example.edu:444/file',
          'https://ispace.example.edu',
        ),
        isFalse,
      );
    });
  });
}
