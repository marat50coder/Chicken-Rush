#!/usr/bin/env bash
# Cross-compile rust_guard for all 4 Android ABIs and drop the stripped
# libraries into android/app/src/main/jniLibs/<abi>/librust_guard.so so the
# Flutter Android build packs them into the APK.
#
# Prereqs (one-time):
#   rustup target add aarch64-linux-android armv7-linux-androideabi \
#                     x86_64-linux-android i686-linux-android
#   Android NDK present at $ANDROID_NDK_HOME or ~/Library/Android/sdk/ndk/<ver>
#
# Usage:  bash tool/build_rust.sh
#         bash tool/build_rust.sh --seed 0xDEADBEEFCAFEBABE   # re-fingerprint
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
RUST_DIR="$ROOT/rust"
JNI_DIR="$ROOT/android/app/src/main/jniLibs"

SEED="${RG_BUILD_SEED:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --seed) SEED="$2"; shift 2;;
    *) echo "unknown arg: $1"; exit 2;;
  esac
done

# Locate NDK.
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  for d in "$HOME/Library/Android/sdk/ndk"/* "$HOME/Android/Sdk/ndk"/*; do
    [[ -d "$d" ]] && ANDROID_NDK_HOME="$d"
  done
fi
if [[ -z "${ANDROID_NDK_HOME:-}" || ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "ERROR: ANDROID_NDK_HOME not set and no NDK found under ~/Library/Android/sdk/ndk or ~/Android/Sdk/ndk" >&2
  exit 1
fi

HOST="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$HOST" in
  darwin) HOST_TAG="darwin-x86_64";;
  linux)  HOST_TAG="linux-x86_64";;
  *) echo "ERROR: unsupported host $HOST (use build_rust.ps1 on Windows)"; exit 1;;
esac
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG"
if [[ ! -d "$TOOLCHAIN/bin" ]]; then
  echo "ERROR: NDK toolchain missing: $TOOLCHAIN/bin" >&2
  exit 1
fi
export PATH="$TOOLCHAIN/bin:$PATH"

export RG_BUILD_SEED="$SEED"

echo "NDK:  $ANDROID_NDK_HOME"
echo "SEED: ${RG_BUILD_SEED:-<default>}"

build_one() {
  local target="$1"
  local abi="$2"
  echo "─── $target → $abi ───"
  (cd "$RUST_DIR" && cargo build --release --target "$target")
  mkdir -p "$JNI_DIR/$abi"
  local src="$RUST_DIR/target/$target/release/librust_guard.so"
  if [[ ! -f "$src" ]]; then
    echo "ERROR: build produced no $src" >&2
    exit 1
  fi
  cp "$src" "$JNI_DIR/$abi/librust_guard.so"
  "$TOOLCHAIN/bin/llvm-strip" --strip-all "$JNI_DIR/$abi/librust_guard.so" || true
}

build_one aarch64-linux-android   arm64-v8a
build_one armv7-linux-androideabi armeabi-v7a
build_one x86_64-linux-android    x86_64
build_one i686-linux-android      x86

echo
echo "✓ librust_guard.so installed into:"
find "$JNI_DIR" -name 'librust_guard.so' -exec ls -lh {} \;
