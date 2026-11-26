#!/usr/bin/env bash
# fetch.sh <profile>  - shallow-clone the pinned upstream sources into build/src
. "$(dirname "$0")/lib.sh"
PROFILE=${1:?profile}; check_profile "$PROFILE"
WITH_NETWORK=${WITH_NETWORK:-0}
mkdir -p "$SRC_DIR"

clone() { # name url tag [submodules]
  local name=$1 url=$2 tag=$3 sub=${4:-}
  local dest="$SRC_DIR/$name"
  if [ -d "$dest/.git" ]; then log "$name: already present ($(git -C "$dest" describe --tags --always 2>/dev/null))"; return; fi
  log "clone $name $tag"
  if [ -n "$sub" ]; then
    git clone --depth 1 --branch "$tag" --recurse-submodules --shallow-submodules "$url" "$dest"
  else
    git clone --depth 1 --branch "$tag" "$url" "$dest"
  fi
}

clone mpv        "$MPV_URL"        "$MPV_TAG"
clone ffmpeg     "$FFMPEG_URL"     "$FFMPEG_TAG"
clone libplacebo "$LIBPLACEBO_URL" "$LIBPLACEBO_TAG" submodules
[ "$PROFILE" = video ] && clone dav1d "$DAV1D_URL" "$DAV1D_TAG"

if [ "$WITH_NETWORK" = 1 ] && [ ! -d "$SRC_DIR/mbedtls" ]; then
  log "download mbedtls $MBEDTLS_VERSION"
  mkdir -p "$SRC_DIR/mbedtls"
  curl -fL --retry 3 "$MBEDTLS_URL" | tar -xj --strip-components=1 -C "$SRC_DIR/mbedtls"
fi
