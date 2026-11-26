#!/usr/bin/env bash
# package.sh <profile> <target>  - strip, collect headers/licences, write SIZES.md + SHA256SUMS, archive.
. "$(dirname "$0")/lib.sh"
PROFILE=${1:?}; TARGET=${2:?}; parse_target "$TARGET"
WITH_NETWORK=${WITH_NETWORK:-0}
ID="$PROFILE-$TARGET"; [ "$WITH_NETWORK" = 1 ] && ID="$ID-net"
STAGE="$ROOT/build/$ID/stage"; OUT="$ROOT/dist/$ID"
rm -rf "$OUT"; mkdir -p "$OUT/include/mpv" "$OUT/LICENSES"
STRIP=strip; NM=nm
[ "$OS" = windows ] && { STRIP=llvm-strip; NM=llvm-nm; }

if [ "$OS" = linux ]; then
  mkdir -p "$OUT/lib"
  find "$STAGE" -name 'libmpv.so*' \( -type f -o -type l \) -exec cp -a {} "$OUT/lib/" \;
  LIB=$(find "$OUT/lib" -name 'libmpv.so.*.*.*' -type f | head -1)
  [ -n "$LIB" ] || LIB=$(find "$OUT/lib" -name 'libmpv.so*' -type f | head -1)
else
  mkdir -p "$OUT/bin" "$OUT/lib"
  cp "$(find "$STAGE" -name 'libmpv-2.dll' | head -1)" "$OUT/bin/"
  find "$STAGE" -name 'libmpv.dll.a' -exec cp {} "$OUT/lib/" \;
  LIB="$OUT/bin/libmpv-2.dll"
fi
[ -f "$LIB" ] || die "libmpv not found in $STAGE"
cp "$LIB" "$OUT/libmpv.unstripped"
"$STRIP" --strip-unneeded "$LIB"

# headers: client API always; render API only where a video output exists
INC=$(find "$STAGE" -type d -path '*/include/mpv' | head -1)
HDRS=(client.h stream_cb.h)
[ "$PROFILE" = video ] && HDRS+=(render.h render_gl.h)
for h in "${HDRS[@]}"; do cp "$INC/$h" "$OUT/include/mpv/"; done

# licences
S="$ROOT/build/src"
for f in mpv/LICENSE.LGPL ffmpeg/COPYING.LGPLv2.1 ffmpeg/COPYING.LGPLv3 libplacebo/LICENSE dav1d/COPYING mbedtls/LICENSE; do
  [ -f "$S/$f" ] && cp "$S/$f" "$OUT/LICENSES/$(echo "$f" | tr / _)"
done
cp "$ROOT/common/patches/mpv/0001-libass-stub.patch" "$OUT/LICENSES/" 2>/dev/null || true
echo "libass is replaced by a no-op stub (ISC headers from libass 0.17.4); see docs/design.md" > "$OUT/LICENSES/NOTICE-libass-stub.txt"
cp "$ROOT/upstream.lock" "$OUT/upstream.lock"

# ---- size report -------------------------------------------------------
raw=$(stat -c %s "$LIB"); gz=$(gzip -9 -c "$LIB" | wc -c); rawu=$(stat -c %s "$OUT/libmpv.unstripped")
{
  echo "# libmmpv $ID"
  echo
  echo "| file | stripped (bytes) | gzip -9 (bytes) | unstripped (bytes) |"
  echo "|---|---|---|---|"
  echo "| $(basename "$LIB") | $raw | $gz | $rawu |"
  echo
  echo "Human readable: stripped $(numfmt --to=iec "$raw"), gzip $(numfmt --to=iec "$gz")"
  echo
  echo '## Dependencies'; echo '```'
  if [ "$OS" = linux ]; then
    readelf -d "$LIB" | grep NEEDED || true
    if [ "$TARGET" = linux-x86_64 ] || [ "$TARGET" = linux-arm64 ]; then echo; ldd "$LIB" 2>&1 || true; fi
  else
    llvm-objdump -p "$LIB" 2>/dev/null | grep 'DLL Name' || true
  fi
  echo '```'
  echo; echo '## Exported symbols (not prefixed mpv_)'; echo '```'
  if [ "$OS" = linux ]; then
    "$NM" -D --defined-only "$LIB" | awk '{print $3}' | grep -v '^mpv_' | grep -vE '^(_init|_fini|_edata|_end|__bss_start)$' || echo "(none)"
  else
    llvm-readobj --coff-exports "$LIB" 2>/dev/null | awk '/Name:/{print $2}' | grep -v '^mpv_' || echo "(none)"
  fi
  echo '```'
  echo
  if [ "$OS" = linux ]; then
    echo "Exported mpv_ symbols: $("$NM" -D --defined-only "$LIB" 2>/dev/null | grep -c ' mpv_' || true)"
  else
    echo "Exported mpv_ symbols: $(llvm-readobj --coff-exports "$LIB" 2>/dev/null | grep -c 'Name: mpv_' || true)"
    echo "Total exported symbols: $(llvm-readobj --coff-exports "$LIB" 2>/dev/null | grep -c 'Name: ' || true)"
  fi
  echo; echo '## Size breakdown of the unstripped library (heuristic: grouped by symbol-name prefix)'; echo '```'
  "$NM" -S --defined-only -t d "$OUT/libmpv.unstripped" 2>/dev/null | awk '
    NF>=4 { sz=$2+0; n=$4; g="other";
      if (n ~ /^_?(ff_|av_|avcodec|avformat|avfilter|avutil|swr_|sws_|swscale|swresample|aac_|ac3_|h264|hevc|vp[89]|mpeg|flac|opus|vorbis|mp3|celt|silk|ogg|mov_|matroska|ebml)/) g="FFmpeg-like";
      else if (n ~ /^_?(pl_|PL_)/) g="libplacebo";
      else if (n ~ /^_?(dav1d|dav1d_)/) g="dav1d";
      else if (n ~ /^_?(mbedtls|psa_|mbedtls_)/) g="mbedtls";
      else if (n ~ /^_?(mp_|mpv_|m_|ao_|vo_|demux|stream_|sub_|osd_|sd_|ra_|gl_|cmd_|mpctx|talloc|ta_)/) g="mpv";
      tot[g]+=sz; all+=sz }
    END { for (g in tot) printf "%-14s %10d bytes  %5.1f%%\n", g, tot[g], 100*tot[g]/all; printf "%-14s %10d bytes (sum of sized symbols)\n","TOTAL",all }' | sort -k2 -nr
  echo '```'
  echo; echo '## Largest 15 symbols'; echo '```'
  "$NM" -S --defined-only -t d "$OUT/libmpv.unstripped" 2>/dev/null | awk 'NF>=4{print $2+0, $4}' | sort -nr | sed -n 1,15p
  echo '```'
  echo; echo '## Sections'; echo '```'
  if [ "$OS" = linux ]; then size -A "$OUT/libmpv.unstripped" | awk '$2>20000'; else llvm-size -A "$OUT/libmpv.unstripped" 2>/dev/null | awk '$2>20000'; fi
  echo '```'

} > "$OUT/SIZES.md"
rm -f "$OUT/libmpv.unstripped"
( cd "$OUT" && find . -type f ! -name SHA256SUMS | sort | xargs sha256sum > SHA256SUMS )
cat "$OUT/SIZES.md"

# ---- archive -----------------------------------------------------------
mkdir -p "$ROOT/dist"
if [ "$OS" = windows ]; then
  ( cd "$ROOT/dist" && rm -f "libmmpv-$ID.zip" && zip -qr "libmmpv-$ID.zip" "$ID" )
  ARCH_FILE="$ROOT/dist/libmmpv-$ID.zip"
else
  tar -C "$ROOT/dist" -czf "$ROOT/dist/libmmpv-$ID.tar.gz" "$ID"
  ARCH_FILE="$ROOT/dist/libmmpv-$ID.tar.gz"
fi
sha256sum "$ARCH_FILE" | tee "$ARCH_FILE.sha256"
echo "archive: $ARCH_FILE ($(stat -c %s "$ARCH_FILE") bytes)"
