#!/usr/bin/env bash
# build.sh <music|video> <linux-x86_64|linux-arm64|win-x86_64|win-arm64>
# Env: WITH_NETWORK=1 (http/https/HLS via mbedTLS), JOBS=n, USE_CCACHE=0, FORCE=1 (rebuild deps)
# Output: dist/<profile>-<target>[-net]/ + dist/libmmpv-<profile>-<target>[-net].{tar.gz,zip}
. "$(dirname "$0")/lib.sh"
PROFILE=${1:?profile}; TARGET=${2:?target}
check_profile "$PROFILE"; parse_target "$TARGET"
WITH_NETWORK=${WITH_NETWORK:-0}; export WITH_NETWORK
JOBS=${JOBS:-$(nproc)}
ID="$PROFILE-$TARGET"; [ "$WITH_NETWORK" = 1 ] && ID="$ID-net"
BUILD="$ROOT/build/$ID"; PREFIX="$BUILD/prefix"; STAGE="$BUILD/stage"
mkdir -p "$PREFIX/lib/pkgconfig"
export ID BUILD PREFIX STAGE PROFILE TARGET OS ARCH TRIPLE

"$ROOT/scripts/fetch.sh" "$PROFILE"
"$ROOT/scripts/apply.sh" "$PROFILE"

# ---- toolchain ---------------------------------------------------------
if [ "$OS" = windows ]; then
  command -v "$TRIPLE-clang" >/dev/null || die "$TRIPLE-clang not in PATH (install llvm-mingw $LLVM_MINGW_VERSION)"
  export CC="$TRIPLE-clang" CXX="$TRIPLE-clang++" AR=llvm-ar RANLIB=llvm-ranlib STRIP=llvm-strip
  export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"; unset PKG_CONFIG_PATH || true
  MESON_MACHINE=(--cross-file "$ROOT/cross/$TARGET.ini")
else
  CC="${CC:-gcc}"; CXX="${CXX:-g++}"
  if [ "${USE_CCACHE:-1}" = 1 ] && command -v ccache >/dev/null; then CC="ccache $CC"; CXX="ccache $CXX"; fi
  export CC CXX
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
  MESON_MACHINE=(--native-file "$ROOT/cross/$TARGET.ini")
fi
MESON_COMMON=(--prefix="$PREFIX" --libdir=lib --buildtype=release "${MESON_MACHINE[@]}"
              -Dpkg_config_path="$PREFIX/lib/pkgconfig")

stamp() { [ -f "$BUILD/.stamp-$1" ] && [ "${FORCE:-0}" != 1 ]; }
mark()  { touch "$BUILD/.stamp-$1"; }

# ---- dav1d (video) -----------------------------------------------------
if [ "$PROFILE" = video ] && ! stamp dav1d; then
  log "dav1d"
  rm -rf "$BUILD/dav1d"
  meson setup "$BUILD/dav1d" "$SRC_DIR/dav1d" "${MESON_COMMON[@]}" --default-library=static \
    -Denable_tools=false -Denable_tests=false -Denable_examples=false -Denable_docs=false
  meson install -C "$BUILD/dav1d"; mark dav1d
fi

# ---- mbedTLS (WITH_NETWORK=1) ------------------------------------------
if [ "$WITH_NETWORK" = 1 ] && ! stamp mbedtls; then
  log "mbedtls $MBEDTLS_VERSION"
  CM=(-G Ninja -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release
      -DENABLE_TESTING=OFF -DENABLE_PROGRAMS=OFF -DGEN_FILES=OFF
      -DUSE_SHARED_MBEDTLS_LIBRARY=OFF -DUSE_STATIC_MBEDTLS_LIBRARY=ON
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
      -DCMAKE_C_FLAGS="-ffunction-sections -fdata-sections")
  if [ "$OS" = windows ]; then
    CM+=(-DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR="${TRIPLE%%-*}"
         -DCMAKE_C_COMPILER="$TRIPLE-clang" -DCMAKE_RC_COMPILER="$TRIPLE-windres")
  else
    command -v ccache >/dev/null && [ "${USE_CCACHE:-1}" = 1 ] && CM+=(-DCMAKE_C_COMPILER_LAUNCHER=ccache)
  fi
  rm -rf "$BUILD/mbedtls"
  cmake -S "$SRC_DIR/mbedtls" -B "$BUILD/mbedtls" "${CM[@]}"
  cmake --build "$BUILD/mbedtls" -j"$JOBS"; cmake --install "$BUILD/mbedtls"; mark mbedtls
fi

# ---- libplacebo (no GPU backends) --------------------------------------
if ! stamp libplacebo; then
  log "libplacebo $LIBPLACEBO_TAG"
  mapfile -t PL_OPTS < <(read_opts "$ROOT/common/libplacebo.options")
  rm -rf "$BUILD/libplacebo"
  meson setup "$BUILD/libplacebo" "$SRC_DIR/libplacebo" "${MESON_COMMON[@]}" \
    --default-library=static "${PL_OPTS[@]}"
  meson install -C "$BUILD/libplacebo"; mark libplacebo
fi

# ---- FFmpeg (static) ---------------------------------------------------
if ! stamp ffmpeg; then
  log "FFmpeg $FFMPEG_TAG"
  # shellcheck disable=SC1091
  . "$ROOT/common/ffmpeg-common.sh"; . "$ROOT/$PROFILE/ffmpeg-$PROFILE.sh"
  FF_ARGS=("${FF_COMMON[@]}" "${FF_PROFILE[@]}")
  if [ "$WITH_NETWORK" = 1 ]; then FF_ARGS+=("${FF_NETWORK[@]}"); else FF_ARGS+=(--disable-network); fi
  FF_PLAT=()
  if [ "$OS" = windows ]; then
    FF_PLAT+=(--enable-cross-compile --target-os=mingw32 --arch="$FF_ARCH"
              --cross-prefix="$TRIPLE-" --cc="$TRIPLE-clang" --cxx="$TRIPLE-clang++"
              --ar=llvm-ar --nm=llvm-nm --ranlib=llvm-ranlib --strip=llvm-strip)
    [ "$WITH_NETWORK" = 1 ] && FF_PLAT+=(--extra-libs="-lbcrypt -ladvapi32")
  else
    FF_PLAT+=(--cc="$CC" --cxx="$CXX")
  fi
  rm -rf "$BUILD/ffmpeg"; mkdir -p "$BUILD/ffmpeg"
  ( cd "$BUILD/ffmpeg"
    "$SRC_DIR/ffmpeg/configure" --prefix="$PREFIX" --libdir="$PREFIX/lib" \
      --pkg-config=pkg-config --pkg-config-flags=--static \
      --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib" \
      "${FF_PLAT[@]}" "${FF_ARGS[@]}" || { tail -50 ffbuild/config.log; exit 1; }
    make -j"$JOBS"; make install )
  mark ffmpeg
fi

# ---- mpv ---------------------------------------------------------------
log "mpv $MPV_TAG ($PROFILE)"
mapfile -t MPV_OPTS < <(read_opts "$ROOT/common/mpv-common.options"
                        read_opts "$ROOT/common/mpv-$OS.options"
                        read_opts "$ROOT/$PROFILE/mpv-$PROFILE.options")
rm -rf "$BUILD/mpv"
meson setup "$BUILD/mpv" "$SRC_DIR/mpv" "${MESON_COMMON[@]}" \
  --default-library=shared --prefer-static -Db_ndebug=true "${MPV_OPTS[@]}"
meson compile -C "$BUILD/mpv" -j "$JOBS"
rm -rf "$STAGE"; DESTDIR="$STAGE" meson install -C "$BUILD/mpv"

"$ROOT/scripts/package.sh" "$PROFILE" "$TARGET"
