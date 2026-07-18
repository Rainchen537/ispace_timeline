import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ispace_timeline/services/credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/credential_store');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('native Android store saves and loads one combined record', () async {
    String? primaryRecord;
    var logoutBlocked = true;

    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'writeSecureCredentials':
          primaryRecord = (call.arguments as Map)['value'] as String;
          return true;
        case 'readSecureCredentials':
          return primaryRecord;
        case 'clearLegacySecureCredentials':
        case 'clearLegacyCredentials':
          return true;
        case 'readLogoutTombstone':
          return logoutBlocked;
        case 'setLogoutTombstone':
          logoutBlocked = (call.arguments as Map)['blocked'] as bool;
          return true;
        default:
          throw MissingPluginException(call.method);
      }
    });

    final store = SecureCredentialStore(
      legacyChannel: channel,
      useNativeAndroidStore: true,
    );
    await store.save(
      const StoredCredentials(username: 'student', password: 'secret'),
    );

    expect(logoutBlocked, isFalse);
    final loaded = await store.load();
    expect(loaded?.username, 'student');
    expect(loaded?.password, 'secret');
  });

  test('logout tombstone prevents restore after a failed clear', () async {
    String? primaryRecord = '{"username":"student","password":"secret"}';
    var logoutBlocked = false;
    var failSecureClear = true;

    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'readSecureCredentials':
          return primaryRecord;
        case 'clearSecureCredentials':
          if (failSecureClear) {
            failSecureClear = false;
            throw PlatformException(code: 'clear_failed');
          }
          primaryRecord = null;
          return true;
        case 'clearLegacyCredentials':
          return true;
        case 'readLogoutTombstone':
          return logoutBlocked;
        case 'setLogoutTombstone':
          logoutBlocked = (call.arguments as Map)['blocked'] as bool;
          return true;
        default:
          throw MissingPluginException(call.method);
      }
    });

    final store = SecureCredentialStore(
      legacyChannel: channel,
      useNativeAndroidStore: true,
    );

    await expectLater(store.clear(), throwsA(isA<PlatformException>()));
    expect(logoutBlocked, isTrue);
    expect(primaryRecord, isNotNull);

    expect(await store.load(), isNull);
    expect(primaryRecord, isNull);
    expect(logoutBlocked, isTrue);
  });

  test('legacy cleanup failure does not leave a new login blocked', () async {
    String? primaryRecord;
    var logoutBlocked = true;
    var failLegacyCleanup = true;

    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'writeSecureCredentials':
          primaryRecord = (call.arguments as Map)['value'] as String;
          return true;
        case 'readSecureCredentials':
          return primaryRecord;
        case 'clearLegacySecureCredentials':
          if (failLegacyCleanup) {
            failLegacyCleanup = false;
            throw PlatformException(code: 'cleanup_failed');
          }
          return true;
        case 'clearLegacyCredentials':
          return true;
        case 'readLogoutTombstone':
          return logoutBlocked;
        case 'setLogoutTombstone':
          logoutBlocked = (call.arguments as Map)['blocked'] as bool;
          return true;
        default:
          throw MissingPluginException(call.method);
      }
    });

    final store = SecureCredentialStore(
      legacyChannel: channel,
      useNativeAndroidStore: true,
    );

    await expectLater(
      store.save(
        const StoredCredentials(username: 'student', password: 'secret'),
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(logoutBlocked, isFalse);
    expect(primaryRecord, isNotNull);

    final loaded = await store.load();
    expect(loaded?.username, 'student');
    expect(loaded?.password, 'secret');
  });

  test('present but malformed combined records are not downgraded', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'readLogoutTombstone':
          return false;
        case 'readSecureCredentials':
          return 'not-json';
        default:
          throw MissingPluginException(call.method);
      }
    });

    final store = SecureCredentialStore(
      legacyChannel: channel,
      useNativeAndroidStore: true,
    );

    await expectLater(
      store.load(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'credential_record_corrupt',
        ),
      ),
    );
  });
}
