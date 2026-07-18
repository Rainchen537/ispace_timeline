import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredCredentials {
  const StoredCredentials({required this.username, required this.password});

  final String username;
  final String password;
}

abstract interface class CredentialStore {
  Future<void> save(StoredCredentials credentials);

  Future<StoredCredentials?> load();

  Future<void> clear();
}

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({
    FlutterSecureStorage? secureStorage,
    MethodChannel? legacyChannel,
  }) : _secureStorage =
           secureStorage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(encryptedSharedPreferences: true),
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.first_unlock_this_device,
             ),
           ),
       _legacyChannel =
           legacyChannel ?? const MethodChannel('ispace/credential_store');

  static const String _credentialsKey = 'bnbu.credentials.v1';
  static const String _legacyUsernameKey = 'bnbu.credentials.username';
  static const String _legacyPasswordKey = 'bnbu.credentials.password';

  final FlutterSecureStorage _secureStorage;
  final MethodChannel _legacyChannel;

  @override
  Future<void> save(StoredCredentials credentials) async {
    final username = credentials.username.trim();
    if (username.isEmpty || credentials.password.isEmpty) {
      throw ArgumentError('Username and password must not be empty.');
    }

    final encoded = jsonEncode(<String, String>{
      'username': username,
      'password': credentials.password,
    });
    await _secureStorage.write(key: _credentialsKey, value: encoded);
    await Future.wait([
      _secureStorage.delete(key: _legacyUsernameKey),
      _secureStorage.delete(key: _legacyPasswordKey),
    ]);
  }

  @override
  Future<StoredCredentials?> load() async {
    final saved = await _loadSecureCredentials();
    if (saved != null) {
      await _clearLegacyCredentials();
      return saved;
    }

    final splitCredentials = await _loadLegacySecureCredentials();
    if (splitCredentials != null) {
      await save(splitCredentials);
      await _clearLegacyCredentials();
      return splitCredentials;
    }

    final legacy = await _readLegacyCredentials();
    if (legacy == null) {
      return null;
    }

    await save(legacy);
    await _clearLegacyCredentials();
    return legacy;
  }

  @override
  Future<void> clear() async {
    var didFail = false;
    for (final key in <String>[
      _credentialsKey,
      _legacyUsernameKey,
      _legacyPasswordKey,
    ]) {
      try {
        await _secureStorage.delete(key: key);
      } catch (_) {
        didFail = true;
      }
    }
    if (!await _clearLegacyCredentials()) {
      didFail = true;
    }
    if (didFail) {
      throw PlatformException(
        code: 'credential_clear_failed',
        message: 'One or more credential records could not be cleared.',
      );
    }
  }

  Future<StoredCredentials?> _loadSecureCredentials() async {
    final raw = await _secureStorage.read(key: _credentialsKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return _credentialsFromMap(decoded.cast<dynamic, dynamic>());
    } on FormatException {
      return null;
    }
  }

  Future<StoredCredentials?> _loadLegacySecureCredentials() async {
    final values = await Future.wait([
      _secureStorage.read(key: _legacyUsernameKey),
      _secureStorage.read(key: _legacyPasswordKey),
    ]);
    return _credentialsFromMap(<String, dynamic>{
      'username': values[0],
      'password': values[1],
    });
  }

  Future<StoredCredentials?> _readLegacyCredentials() async {
    try {
      final raw = await _legacyChannel.invokeMethod<dynamic>(
        'readLegacyCredentials',
      );
      if (raw is! Map) {
        return null;
      }
      return _credentialsFromMap(raw.cast<dynamic, dynamic>());
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  StoredCredentials? _credentialsFromMap(Map<dynamic, dynamic> data) {
    final username = (data['username'] as String?)?.trim() ?? '';
    final password = data['password'] as String? ?? '';
    if (username.isEmpty || password.isEmpty) {
      return null;
    }
    return StoredCredentials(username: username, password: password);
  }

  Future<bool> _clearLegacyCredentials() async {
    try {
      await _legacyChannel.invokeMethod<void>('clearLegacyCredentials');
      return true;
    } on MissingPluginException {
      // Legacy native storage only exists on Android and iOS.
      return true;
    } on PlatformException {
      // A secure copy remains available, so cleanup can be retried later.
      return false;
    }
  }
}
