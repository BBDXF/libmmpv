#!/usr/bin/env bash
# build.sh <music|video> <linux-x86_64|linux-arm64|win-x86_64|win-arm64>
# Env: HWDEC=0 (video: disable hardware decode, default 1), WITH_NETWORK=1 (http/https/HLS via mbedTLS), JOBS=n, USE_CCACHE=0, FORCE=1 (rebuild deps)
# Output: dist/<profile>-<target>[-net]/ + dist/libmmpv-<profile>-<target>[-net].{tar.gz,zip}
. "$(dirname "$0")/lib.sh"
PROFILE=${1:?profile}; TARGET=${2:?target}
check_profile "$PROFILE"; parse_target "$TARGET"
WITH_NETWORK=${WITH_NETWORK:-0}; export WITH_NETWORK
HWDEC=${HWDEC:-1}; export HWDEC   # video profile only: hardware decode (copy-back) paths
JOBS=${JOBS:-$(nproc)}
ID="$PROFILE-$TARGET"; [ "$WITH_NETWORK" = 1 ] && ID="$ID-net"
BUILD="$ROOT/build/$ID"; PREFIX="$BUILD/prefix"; STAGE="$BUILD/stage"
mkdir -p "$PREFIX/lib/pkgconfig"
export ID BUILD PREFIX STAGE PROFILE TARGET OS ARCH TRIPLE

"$ROOT/scripts/fetch.sh" "$PROFILE"
"$ROOT/scripts/apply.sh" "$PROFILE"

# ---- toolchain ---------------------------------------------------------
if [ "$OS" = android ]; then
  setup_android_env        # sets CC/CXX/AR/NM/STRIP/RANLIB + ANDROID_CFLAGS/ANDROID_LDFLAGS + PATH
  export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"; unset PKG_CONFIG_PATH || true
  MESON_MACHINE=(--cross-file "$ROOT/cross/$TARGET.ini")
elif [ "$OS" = windows ]; then
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
  # 32-bit x86: dav1d's x86 asm emits non-PIC relocations (same issue as FFmpeg above);
  # disable asm for that ABI only.
  DAV1D_EXTRA=()
  [ "$OS" = android ] && [ "$ARCH" = x86 ] && DAV1D_EXTRA+=(-Denable_asm=false)
  meson setup "$BUILD/dav1d" "$SRC_DIR/dav1d" "${MESON_COMMON[@]}" --default-library=static \
    -Denable_tools=false -Denable_tests=false -Denable_examples=false -Denable_docs=false "${DAV1D_EXTRA[@]}"
  meson install -C "$BUILD/dav1d"; mark dav1d
fi

# ---- nv-codec-headers (video + HWDEC, x86_64; header-only) ---------------
if [ "$PROFILE" = video ] && [ "$HWDEC" = 1 ] && [ "$ARCH" = x86_64 ] && [ "$OS" != android ] && ! stamp nvcodec; then
  log "nv-codec-headers $NVCODEC_TAG"
  make -C "$SRC_DIR/nv-codec-headers" PREFIX="$PREFIX" install
  mark nvcodec
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

# ---- zlib (static; needed by FFmpeg png decoder -> embedded PNG covers) ---
if ! stamp zlib; then
  log "zlib $ZLIB_VERSION"
  rm -rf "$BUILD/zlib"; mkdir -p "$BUILD/zlib"
  curl -fL --retry 3 "$ZLIB_URL" | tar -xz --strip-components=1 -C "$BUILD/zlib"
  ( cd "$BUILD/zlib"
    ZCF="-O2 -fPIC -ffunction-sections -fdata-sections"
    [ "$OS" = linux ] && ZCF="$ZCF -DZ_HAVE_UNISTD_H"
    for f in adler32 compress crc32 deflate infback inffast inflate inftrees trees uncompr zutil; do
      $CC $ZCF -c "$f.c" -o "$f.o"
    done
    ${AR:-ar} rcs libz.a ./*.o
    mkdir -p "$PREFIX/include" "$PREFIX/lib/pkgconfig"
    cp zlib.h zconf.h "$PREFIX/include/"; cp libz.a "$PREFIX/lib/"
    printf 'prefix=%s\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\nName: zlib\nDescription: zlib\nVersion: %s\nLibs: -L${libdir} -lz\nCflags: -I${includedir}\n' "$PREFIX" "$ZLIB_VERSION" > "$PREFIX/lib/pkgconfig/zlib.pc" )
  mark zlib
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
if ! stamp "ffmpeg-hw$HWDEC"; then
  log "FFmpeg $FFMPEG_TAG"
  # shellcheck disable=SC1091
  . "$ROOT/common/ffmpeg-common.sh"; . "$ROOT/$PROFILE/ffmpeg-$PROFILE.sh"
  FF_ARGS=("${FF_COMMON[@]}" "${FF_PROFILE[@]}")
  if [ "$WITH_NETWORK" = 1 ]; then FF_ARGS+=("${FF_NETWORK[@]}"); else FF_ARGS+=(--disable-network); fi
  # Android: no d3d11va/vaapi/nvdec; MediaCodec + JNI (see common/ffmpeg-android.sh).
  if [ "$OS" = android ]; then
    . "$ROOT/common/ffmpeg-android.sh"
    FF_ARGS+=("${FF_ANDROID_COMMON[@]}")
    [ "$PROFILE" = video ] && FF_ARGS+=("${FF_ANDROID_VIDEO[@]}")
    # 32-bit x86: FFmpeg's --enable-pic does not reliably propagate -DPIC to its yasm/nasm
    # inline assembly when cross-compiling with the NDK clang, so the resulting .asm objects
    # emit R_386_32 (non-PIC) relocations that lld rejects when linking libmpv.so. Disable asm
    # for this ABI (negligible cost for our minimal decoder set); it stays on for every other ABI.
    [ "$ARCH" = x86 ] && FF_ARGS+=(--disable-asm)
  elif [ "$PROFILE" = video ] && [ "$HWDEC" = 1 ]; then
    . "$ROOT/video/ffmpeg-hwdec.sh"
    FF_ARGS+=("${FF_HW_COMMON[@]}")
    [ "$OS" = windows ] && FF_ARGS+=("${FF_HW_WINDOWS[@]}")
    [ "$OS" = linux ]   && FF_ARGS+=("${FF_HW_VAAPI[@]}")
    [ "$ARCH" = x86_64 ] && FF_ARGS+=("${FF_HW_NVDEC[@]}")
  fi
  FF_PLAT=()
  if [ "$OS" = android ]; then
    # NOTE: FFmpeg's configure keeps only the LAST --extra-cflags/--extra-ldflags, so fold
    # the PREFIX include/lib dirs into the ANDROID_* flags here instead of the generic line.
    FF_PLAT+=(--enable-cross-compile --target-os=android --arch="$FF_ARCH"
              --cc="$CC" --cxx="$CXX"
              --ar=llvm-ar --nm=llvm-nm --ranlib=llvm-ranlib --strip=llvm-strip
              --extra-cflags="$ANDROID_CFLAGS -I$PREFIX/include"
              --extra-ldflags="$ANDROID_LDFLAGS -L$PREFIX/lib")
    [ "$WITH_NETWORK" = 1 ] && FF_PLAT+=(--extra-libs="-lmbedtls -lmbedx509 -lmbedcrypto")
  elif [ "$OS" = windows ]; then
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
  mark "ffmpeg-hw$HWDEC"
fi

# ---- mpv ---------------------------------------------------------------
log "mpv $MPV_TAG ($PROFILE)"
# Profile options can be OS-specific: prefer <profile>/mpv-<profile>-<os>.options,
# fall back to the generic <profile>/mpv-<profile>.options (e.g. Android video uses no GL).
MPV_PROFILE_OPTS="$ROOT/$PROFILE/mpv-$PROFILE.options"
[ -f "$ROOT/$PROFILE/mpv-$PROFILE-$OS.options" ] && MPV_PROFILE_OPTS="$ROOT/$PROFILE/mpv-$PROFILE-$OS.options"
mapfile -t MPV_OPTS < <(read_opts "$ROOT/common/mpv-common.options"
                        read_opts "$ROOT/common/mpv-$OS.options"
                        read_opts "$MPV_PROFILE_OPTS"
                        if [ "$PROFILE" = video ] && [ "$HWDEC" = 1 ] && [ "$OS" = windows ]; then
                          read_opts "$ROOT/video/mpv-hwdec-windows.options"; fi)
rm -rf "$BUILD/mpv"
meson setup "$BUILD/mpv" "$SRC_DIR/mpv" "${MESON_COMMON[@]}" \
  --default-library=shared --prefer-static -Db_ndebug=true "${MPV_OPTS[@]}"
meson compile -C "$BUILD/mpv" -j "$JOBS"
rm -rf "$STAGE"; DESTDIR="$STAGE" meson install -C "$BUILD/mpv"

"$ROOT/scripts/package.sh" "$PROFILE" "$TARGET"
"$ROOT/scripts/check-deps.sh" "$TARGET" "$ROOT/dist/$ID"
