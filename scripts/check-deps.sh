#!/usr/bin/env bash
# check-deps.sh <target> <distdir>
# Guard for "runtime-loaded system libraries": the shipped libmpv must not gain link-time dependencies on
# GPU / windowing libraries. Prints the full dependency list; fails on forbidden entries.
. "$(dirname "$0")/lib.sh"
TARGET=${1:?}; D=${2:?}; parse_target "$TARGET"
if [ "$OS" = linux ] || [ "$OS" = android ]; then
  LIB=$(find "$D/lib" -name 'libmpv.so.*.*.*' -type f | head -1)
  [ -n "$LIB" ] || LIB=$(find "$D/lib" -name 'libmpv.so*' -type f | head -1)
  deps=$(readelf -d "$LIB" | awk '/NEEDED/{gsub(/[\[\]]/,"",$NF); print $NF}')
  if [ "$OS" = linux ]; then
    forbid='libcuda|libnvcuvid|libnvidia|libvulkan|libX11|libxcb|libwayland|libEGL|libGL|libOpenGL'
  else
    # Android: only the NDK system libs mpv is allowed to link (libandroid/liblog/libc/...).
    # Anything GPU / display / desktop-AO must not be a link-time dependency.
    forbid='libEGL|libGLES|libGLESv|libGL\b|libOpenGL|libvulkan|libc\+\+|libunwind|libasound|libpulse|libpipewire|libX11|libxcb|libwayland|libdrm|libgbm'
  fi
else
  LIB="$D/bin/libmpv-2.dll"
  deps=$(llvm-objdump -p "$LIB" | awk '/DLL Name:/{print $3}')
  forbid='d3d|dxgi|dxva|nvcuda|nvcuvid|opengl|vulkan|libc\+\+|libunwind'
fi
echo "== link-time dependencies of $(basename "$LIB") ($TARGET)"; echo "$deps" | sed 's/^/   /'
if echo "$deps" | grep -iE "$forbid"; then die "forbidden link-time dependency found (see above)"; fi
echo "== OK: none of: $forbid"
