#!/usr/bin/env bash
# run_smoke.sh PROFILE DISTDIR   (Linux, native arch). Needs gcc + ffmpeg (test media generator).
set -uo pipefail
P=${1:?profile}; D=$(cd "${2:?dist dir}" && pwd); HERE=$(cd "$(dirname "$0")" && pwd)
W=${WORK:-$(mktemp -d)}; mkdir -p "$W"
EXTRA=(); [ "$P" = video ] && EXTRA=(-DMMPV_SW_RENDER)
if [ -n "${SMOKE_BIN:-}" ]; then S="$SMOKE_BIN"; else
  gcc -O1 -Wall "${EXTRA[@]}" -I"$D/include" -o "$W/mmpv_smoke" "$HERE/smoke.c" \
      -L"$D/lib" -lmpv -Wl,-rpath,"$D/lib" || { echo "smoke build failed"; exit 1; }
  S="$W/mmpv_smoke"
fi
if [ -n "${MEDIA_DIR:-}" ]; then M="$MEDIA_DIR"; else
  "$HERE/gen_media.sh" "$W/media" video >/dev/null || { echo "media generation failed"; exit 1; }
  M="$W/media"
fi
BASE=(-o ao=null -o ao-null-untimed=yes -o vo=null -o hwdec=no)
hard=0; soft=0
run()  { echo "--- $*"; "$S" "$@" "${BASE[@]}" || { echo "^^^ HARD FAIL"; hard=$((hard+1)); }; }
soft() { echo "--- (soft) $*"; "$S" "$@" "${BASE[@]}" || { echo "^^^ soft fail"; soft=$((soft+1)); }; }

"$S" --probe || { echo "probe failed"; hard=$((hard+1)); }
run "$M/a.mp3"   -A mp3 -N
run "$M/a.flac"  -A flac -N
run "$M/a.ogg"   -A vorbis -N
run "$M/a.opus"  -A opus -N
run "$M/a.wav"   -A pcm_s16le -N
run "$M/a.m4a"   -A aac -N
run "$M/alac.m4a" -A alac -N
run "$M/a.aac"   -A aac -N
run "$M/a.mka"   -A opus -N
# embedded cover art must not break playback (with and without a video track selected)
run "$M/cover-png.mp3"  -A mp3 -C png
run "$M/cover-jpg.flac" -A flac -C mjpeg
run "$M/cover-png.mp3"  -A mp3 -o vid=no -N
if [ "$P" = video ]; then
  run "$M/v_h264.mp4" -V h264 -A aac
  run "$M/v_hevc.mp4" -V hevc -A aac
  run "$M/v_vp9.webm" -V vp9  -A opus
  run "$M/v_av1.mkv"  -V av1  -A opus
  run "$M/v_h264.mp4" -V h264 --sw
  run "$M/v_av1.mkv"  -V av1  --sw
else
  # documented caveat: audio-only build plays only the audio track of a video file
  run "$M/v_h264.mp4" -A aac    # video file: only the audio track is played (no video decoder built)
fi
echo "== smoke summary: hard failures=$hard soft failures=$soft"
[ $hard = 0 ]
