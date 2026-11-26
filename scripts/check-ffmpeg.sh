#!/usr/bin/env bash
# Verify that every --enable-<kind>=<name> in our FFmpeg config exists in the
# given FFmpeg checkout (wildcards and dependency auto-selection are skipped).
. "$(dirname "$0")/lib.sh"
FF="${1:-$SRC_DIR/ffmpeg}"
. "$ROOT/common/ffmpeg-common.sh"; . "$ROOT/music/ffmpeg-music.sh"; MUSIC=("${FF_PROFILE[@]}")
. "$ROOT/video/ffmpeg-video.sh"
rc=0
for a in "${FF_AUDIO[@]}" "${FF_NETWORK[@]}" "${MUSIC[@]}" "${FF_PROFILE[@]}"; do
  case "$a" in --enable-decoder=*|--enable-demuxer=*|--enable-parser=*|--enable-protocol=*|--enable-bsf=*|--enable-filter=*) ;; *) continue;; esac
  kind=${a#--enable-}; kind=${kind%%=*}; names=${a#*=}; names=${names//\'/}
  case $kind in
    decoder) f=libavcodec/allcodecs.c;; parser) f=libavcodec/parsers.c;;
    bsf) f=libavcodec/bitstream_filters.c;; demuxer) f=libavformat/allformats.c;;
    protocol) f=libavformat/protocols.c;; filter) f=libavfilter/allfilters.c;;
  esac
  IFS=, read -ra arr <<<"$names"
  for n in "${arr[@]}"; do
    case "$n" in *'*'*) continue;; esac
    if [ $kind = filter ]; then pat="ff_(af|vf|asrc|vsrc|asink|vsink)_${n}\b"; else pat="ff_${n}_${kind}\b"; fi
    grep -qE "$pat" "$FF/$f" || { echo "MISSING $kind:$n"; rc=1; }
  done
done
[ $rc = 0 ] && echo "all FFmpeg components exist"
exit $rc
