#!/usr/bin/env bash
# Shared helpers. Source me; do not execute.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/upstream.lock"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

SRC_DIR="${SRC_DIR:-$ROOT/build/src}"

# read_opts FILE -> one option per line (comments/blank stripped)
read_opts() {
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true
}

# parse_target TARGET -> sets OS (linux|windows|android), ARCH (x86_64|arm64), TRIPLE
# Android: TRIPLE = NDK clang target triple (used for NDK_BIN), ANDROID_ABI = the ABI name.
parse_target() {
  case "$1" in
    linux-x86_64) OS=linux;   ARCH=x86_64; TRIPLE= ;;
    linux-arm64)  OS=linux;   ARCH=arm64;  TRIPLE= ;;
    win-x86_64)   OS=windows; ARCH=x86_64; TRIPLE=x86_64-w64-mingw32 ;;
    win-arm64)    OS=windows; ARCH=arm64;  TRIPLE=aarch64-w64-mingw32 ;;
    android-arm64)  OS=android; ARCH=arm64;  TRIPLE=aarch64-linux-android;   ANDROID_ABI=arm64-v8a ;;
    android-x86_64) OS=android; ARCH=x86_64; TRIPLE=x86_64-linux-android;    ANDROID_ABI=x86_64 ;;
    # 32-bit ABIs: minSdk is pinned to 21 by the NDK for these (anything lower is unsupported).
    android-armv7)  OS=android; ARCH=armv7; TRIPLE=armv7a-linux-androideabi; ANDROID_ABI=armeabi-v7a ;;
    android-x86)    OS=android; ARCH=x86;   TRIPLE=i686-linux-android;       ANDROID_ABI=x86 ;;
    *) die "unknown target '$1' (linux-x86_64|linux-arm64|win-x86_64|win-arm64|android-arm64|android-x86_64|android-armv7|android-x86)" ;;
  esac
  case "$ARCH" in
    arm64) FF_ARCH=aarch64 ;;
    armv7) FF_ARCH=arm ;;
    *)     FF_ARCH=$ARCH ;;
  esac
}

android_clang_target() { # ARCH
  case "$1" in
    arm64)  echo aarch64-linux-android ;;
    armv7)  echo armv7a-linux-androideabi ;;
    x86_64) echo x86_64-linux-android ;;
    x86)    echo i686-linux-android ;;
  esac
}

# setup_android_env: point CC/CXX/binutils at the NDK's per-API clang wrappers and pick the sysroot.
# Leaves CC/CXX/AR/... and ANDROID_* in the environment. Call after parse_target.
setup_android_env() {
  [ "$OS" = android ] || return 0
  : "${ANDROID_NDK:?ANDROID_NDK must point at an NDK $NDK_VERSION directory}"
  : "${ANDROID_API:=$NDK_DEFAULT_API}"
  local tag_dir="toolchains/llvm/prebuilt"
  local tc
  tc=$(ls -d "$ANDROID_NDK/$tag_dir"/*/ 2>/dev/null | head -1)
  [ -n "$tc" ] || die "no llvm toolchain in $ANDROID_NDK (expected $tag_dir/<host>)"
  export ANDROID_TC="${tc%/}"
  export ANDROID_API
  export ANDROID_SYSROOT="$ANDROID_TC/sysroot"
  export ANDROID_TRIPLE="$TRIPLE"
  local bin="$ANDROID_TC/bin"
  export CC="$(android_clang_target "$ARCH")$ANDROID_API-clang"
  export CXX="$(android_clang_target "$ARCH")$ANDROID_API-clang++"
  export AR=llvm-ar NM=llvm-nm RANLIB=llvm-ranlib STRIP=llvm-strip
  export ANDROID_LLVM_BIN="$bin"
  export PATH="$bin:$PATH"
  command -v "$CC" >/dev/null || die "$CC not found under $bin"
  export ANDROID_CFLAGS="--sysroot=$ANDROID_SYSROOT -O2 -fPIC -ffunction-sections -fdata-sections"
  export ANDROID_LDFLAGS="-Wl,--gc-sections -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"
}

check_profile() {
  case "$1" in music|video) ;; *) die "unknown profile '$1' (music|video)";; esac
}
