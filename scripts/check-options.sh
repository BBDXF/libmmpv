#!/usr/bin/env bash
# Verify that every -Dname used in our option files exists in the given mpv /
# libplacebo checkout. Usage: check-options.sh [MPV_SRC] [LIBPLACEBO_SRC]
. "$(dirname "$0")/lib.sh"
MPV="${1:-$SRC_DIR/mpv}"; PL="${2:-$SRC_DIR/libplacebo}"
rc=0
check() { # file srcfile optionsfile
  local names; names=$(grep -oE "^option\('[^']+'" "$2" | cut -d"'" -f2)
  while read -r o; do
    n=${o#-D}; n=${n%%=*}
    grep -qxF "$n" <<<"$names" || { echo "UNKNOWN option '$n' ($1 not in $2)"; rc=1; }
  done < <(read_opts "$3")
}
mpvopts="$MPV/meson.options"; [ -f "$mpvopts" ] || mpvopts="$MPV/meson_options.txt"
for f in common/mpv-common.options common/mpv-linux.options common/mpv-windows.options \
         music/mpv-music.options video/mpv-video.options video/mpv-hwdec-windows.options; do
  check "$f" "$mpvopts" "$ROOT/$f"
done
[ -f "$PL/meson_options.txt" ] && check common/libplacebo.options "$PL/meson_options.txt" "$ROOT/common/libplacebo.options"
[ $rc = 0 ] && echo "all option names exist"
exit $rc
