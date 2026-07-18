#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

pubspec_lock_snapshot="$(mktemp -t ispace-pubspec-lock.XXXXXX)"
pod_lock_snapshot="$(mktemp -t ispace-pod-lock.XXXXXX)"
release_gate_log=""
cp pubspec.lock "$pubspec_lock_snapshot"
cp ios/Podfile.lock "$pod_lock_snapshot"

finish() {
  local status=$?
  trap - EXIT
  if ! cmp -s pubspec.lock "$pubspec_lock_snapshot" ||
    ! cmp -s ios/Podfile.lock "$pod_lock_snapshot"; then
    git diff -- pubspec.lock ios/Podfile.lock >&2
    printf '%s\n' "Dependency resolution changed a lockfile during verification." >&2
    status=1
  fi
  rm -f "$pubspec_lock_snapshot" "$pod_lock_snapshot"
  if [[ -n "$release_gate_log" ]]; then
    rm -f "$release_gate_log"
  fi
  exit "$status"
}
trap finish EXIT

flutter_cmd=(flutter)
dart_cmd=(dart)
if command -v fvm >/dev/null 2>&1; then
  flutter_cmd=(fvm flutter)
  dart_cmd=(fvm dart)
elif ! flutter --version | grep -Fq "Flutter 3.32.6"; then
  printf '%s\n' "Flutter 3.32.6 is required; install FVM or select the pinned global SDK." >&2
  exit 1
fi

"${flutter_cmd[@]}" pub get --enforce-lockfile
"${dart_cmd[@]}" format --output=none --set-exit-if-changed lib test
"${flutter_cmd[@]}" analyze
"${flutter_cmd[@]}" test
"${flutter_cmd[@]}" build apk --debug

if [[ ! -f android/key.properties ]]; then
  release_gate_log="$(mktemp -t ispace-release-gate.XXXXXX)"
  if "${flutter_cmd[@]}" build apk --release >"$release_gate_log" 2>&1; then
    printf '%s\n' "Unsigned Android release build unexpectedly succeeded." >&2
    exit 1
  fi
  if ! grep -Fq "Release signing is not configured" "$release_gate_log"; then
    cat "$release_gate_log" >&2
    printf '%s\n' "Android release build failed before exercising the signing gate." >&2
    exit 1
  fi
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  if [[ "$(pod --version 2>/dev/null || true)" != "1.16.2" ]]; then
    printf '%s\n' "CocoaPods 1.16.2 is required." >&2
    exit 1
  fi
  "${flutter_cmd[@]}" build ios --debug --no-codesign
fi
