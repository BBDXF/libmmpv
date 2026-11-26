#!/usr/bin/env bash
# rebase.sh <mpv-ref> [ffmpeg-ref]
# Dry-run: do our patches still apply to another mpv / FFmpeg ref (e.g. master or a new tag)?
# Also re-validates option and component names. Does not compile anything.
. "$(dirname "$0")/lib.sh"
MREF=${1:?mpv ref}; FREF=${2:-}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
rc=0
git clone -q --depth 1 --branch "$MREF" "$MPV_URL" "$T/mpv" 2>/dev/null || git clone -q --depth 1 "$MPV_URL" "$T/mpv"
for p in "$ROOT"/common/patches/mpv/*.patch "$ROOT"/{music,video}/patches/mpv/*.patch; do
  [ -e "$p" ] || continue
  if git -C "$T/mpv" apply --check "$p" 2>/tmp/rebase.err; then echo "OK    $(basename "$p")"
  else echo "FAIL  $(basename "$p")"; sed 's/^/      /' /tmp/rebase.err; rc=1; fi
done
SRC_DIR="$T" bash "$ROOT/scripts/check-options.sh" "$T/mpv" "$SRC_DIR/libplacebo" || rc=1
if [ -n "$FREF" ]; then
  git clone -q --depth 1 --branch "$FREF" "$FFMPEG_URL" "$T/ffmpeg"
  bash "$ROOT/scripts/check-ffmpeg.sh" "$T/ffmpeg" || rc=1
fi
echo "mpv ref: $(git -C "$T/mpv" describe --tags --always 2>/dev/null || echo "$MREF") rc=$rc"
exit $rc
