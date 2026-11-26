#!/usr/bin/env bash
# header_test.sh DISTDIR   (Linux, WITH_NETWORK=1 build). Proves custom HTTP headers reach the server for
# a plain file, an HLS playlist, HLS segments and an AES-128 key request. Evidence -> $EVIDENCE.
set -uo pipefail
D=$(cd "${1:?dist dir}" && pwd); HERE=$(cd "$(dirname "$0")" && pwd)
W=${WORK:-$(mktemp -d)}; mkdir -p "$W/www/hls" "$W/www/hlsenc"; PORT=${PORT:-18765}
EVIDENCE=${EVIDENCE:-$W/header-evidence.txt}; LOG="$W/requests.jsonl"; : > "$LOG"
gcc -O1 -Wall -I"$D/include" -o "$W/mmpv_smoke" "$HERE/smoke.c" -L"$D/lib" -lmpv -Wl,-rpath,"$D/lib" || exit 1
F() { ffmpeg -hide_banner -loglevel error -y "$@"; }
SIN=(-f lavfi -i "sine=frequency=440:duration=6" -ar 48000 -ac 2)
F "${SIN[@]}" -c:a libmp3lame "$W/www/a.mp3"
F "${SIN[@]}" -c:a aac -f hls -hls_time 2 -hls_playlist_type vod -hls_segment_filename "$W/www/hls/seg%d.ts" "$W/www/hls/index.m3u8"
head -c16 /dev/urandom > "$W/www/hlsenc/enc.key"
printf 'http://127.0.0.1:%s/hlsenc/enc.key\n%s\n' "$PORT" "$W/www/hlsenc/enc.key" > "$W/keyinfo"
F "${SIN[@]}" -c:a aac -f hls -hls_time 2 -hls_playlist_type vod -hls_key_info_file "$W/keyinfo" \
  -hls_segment_filename "$W/www/hlsenc/seg%d.ts" "$W/www/hlsenc/index.m3u8"
python3 "$HERE/header_server.py" "$W/www" "$PORT" "$LOG" & SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT; sleep 1
BASE=(-o ao=null -o ao-null-untimed=yes -o vo=null -o user-agent=MMPVTest/1.0 -o referrer=http://example.test/ref)
HDR=(-H "X-Test-Token: s3cret" -H "X-Second: a,b")
fail=0
for u in a.mp3 hls/index.m3u8 hlsenc/index.m3u8; do
  echo "--- $u"; "$W/mmpv_smoke" "http://127.0.0.1:$PORT/$u" "${BASE[@]}" "${HDR[@]}" -A "" || { echo "play FAILED: $u"; fail=1; }
done
sleep 1
python3 - "$LOG" "$EVIDENCE" <<'PY' || fail=1
import json, sys
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
out=[]; ok=True
need=["/a.mp3","/hls/index.m3u8","/hls/seg0.ts","/hlsenc/index.m3u8","/hlsenc/seg0.ts","/hlsenc/enc.key"]
for r in rows:
    h={k.lower():v for k,v in r["headers"].items()}
    good = h.get("x-test-token")=="s3cret" and h.get("x-second")=="a,b" and h.get("user-agent","").startswith("MMPVTest") and h.get("referer")=="http://example.test/ref"
    out.append(f'{"PASS" if good else "FAIL"} {r["method"]} {r["path"]}  X-Test-Token={h.get("x-test-token")} X-Second={h.get("x-second")} UA={h.get("user-agent")} Referer={h.get("referer")}')
    ok &= good
seen={r["path"] for r in rows}
for n in need:
    if n not in seen: out.append(f"FAIL missing request for {n}"); ok=False
open(sys.argv[2],"w").write("\n".join(out)+"\n"); print("\n".join(out))
sys.exit(0 if ok else 1)
PY
echo "== header test (global http-header-fields via MPV_FORMAT_NODE): $([ $fail = 0 ] && echo PASS || echo FAIL)"
# per-file headers through loadfile options: informational (soft) - syntax unverified until this runs
: > "$LOG"
"$W/mmpv_smoke" "http://127.0.0.1:$PORT/hls/index.m3u8" "${BASE[@]}" -P "X-Per-File: yes" >/dev/null 2>&1
sleep 1
python3 - "$LOG" >> "$EVIDENCE" <<'PY'
import json,sys
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
print("\n[soft] per-file loadfile option http-header-fields-append:")
for r in rows: print(("  has" if any(k.lower()=="x-per-file" for k in r["headers"]) else "  MISSING"), r["path"])
PY
tail -8 "$EVIDENCE"
exit $fail
