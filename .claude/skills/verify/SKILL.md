---
name: verify
summary: Launch and observe the Flutter app on an iOS Simulator.
---

# Verify the Flutter app

1. Run `flutter devices` and choose an available iOS Simulator.
2. Launch with `flutter run -d <simulator-id> --debug`.
3. Wait for `Syncing files to device` and the Dart VM Service URL.
4. Capture the visible surface with `xcrun simctl io <simulator-id> screenshot /tmp/ispace-screen.png`.
5. Do not enter or automate real school credentials. Account-dependent Mail, MIS, Portal, attachment, and logout flows require a manually controlled test account.
6. Stop or detach the `flutter run` process after capturing evidence.

For build-only checks, use `tool/check.sh`. If Gradle/JVM TLS fails locally, repository-external cached artifacts may be used, but `/tmp/ispace-*` must never be committed.
