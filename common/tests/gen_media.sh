#!/usr/bin/env bash
# gen_media.sh OUTDIR [video]  - generate tiny test media with the system ffmpeg (test tooling only).
set -euo pipefail
O=${1:?outdir}; mkdir -p "$O"; cd "$O"
F() { ffmpeg -hide_banner -loglevel error -y "$@"; }
S=(-f lavfi -i "sine=frequency=440:duration=2" -ar 48000 -ac 2)
F "${S[@]}" -c:a libmp3lame a.mp3
F "${S[@]}" -c:a flac a.flac
F "${S[@]}" -c:a libvorbis a.ogg
F "${S[@]}" -c:a libopus a.opus
F "${S[@]}" -c:a pcm_s16le a.wav
F "${S[@]}" -c:a aac a.m4a
F "${S[@]}" -c:a alac alac.m4a
F "${S[@]}" -c:a aac -f adts a.aac
F "${S[@]}" -c:a libopus a.mka
# NOTE: images live in src/ - mpv's cover-art-auto would otherwise pick up cover.* next to the audio files
mkdir -p src
F -f lavfi -i "color=c=red:s=128x128" -frames:v 1 src/cover.png
F -f lavfi -i "color=c=blue:s=128x128" -frames:v 1 src/cover.jpg
F -i a.mp3  -i src/cover.png -map 0:a -map 1 -c copy -id3v2_version 3 -disposition:v:0 attached_pic cover-png.mp3
F -i a.flac -i src/cover.jpg -map 0:a -map 1 -c copy -disposition:v:0 attached_pic cover-jpg.flac
if [ "${2:-}" = video ]; then
  V=(-f lavfi -i "testsrc=size=320x240:rate=25:duration=2" "${S[@]}")
  F "${V[@]}" -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac v_h264.mp4
  F "${V[@]}" -c:v libx265 -preset ultrafast -pix_fmt yuv420p -x265-params log-level=error -c:a aac v_hevc.mp4
  F "${V[@]}" -c:v libvpx-vp9 -b:v 300k -deadline realtime -cpu-used 8 -c:a libopus v_vp9.webm
  F "${V[@]}" -c:v libaom-av1 -cpu-used 8 -crf 45 -b:v 0 -c:a libopus v_av1.mkv
fi
ls -l
