#!/usr/bin/env bash
# apply.sh <profile>  - apply common/patches/<proj>/*.patch then <profile>/patches/<proj>/*.patch
# Idempotent: patches that are already applied are skipped.
. "$(dirname "$0")/lib.sh"
PROFILE=${1:?profile}; check_profile "$PROFILE"
for proj in mpv ffmpeg libplacebo dav1d; do
  tree="$SRC_DIR/$proj"; [ -d "$tree/.git" ] || continue
  # start from pristine upstream so patch changes never conflict with a cached, older-patched tree
  git -C "$tree" checkout -q -- . && git -C "$tree" clean -fdq
  for dir in "$ROOT/common/patches/$proj" "$ROOT/$PROFILE/patches/$proj"; do
    [ -d "$dir" ] || continue
    for p in "$dir"/*.patch; do
      [ -e "$p" ] || continue
      if git -C "$tree" apply --reverse --check "$p" 2>/dev/null; then
        echo "already applied: $proj/$(basename "$p")"
      else
        log "apply $proj/$(basename "$p")"
        git -C "$tree" apply --check "$p" || die "patch does not apply: $p"
        git -C "$tree" apply "$p"
      fi
    done
  done
done
