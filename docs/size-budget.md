# 体积预算（**估算**，未实测）

锚点（已核实，GitHub release API，压缩后）：media-kit Android arm64 audio jar 3.0 MB / video 5.7 MB；
macOS arm64 audio 4.2 MB / video 8.1 MB。这些是旧版 mpv(0.35/0.36)、含 libass(video)。

| profile | 平台 | 预估 strip 后 | 预估 gzip |
|---|---|---|---|
| music | linux/win x86_64, arm64 | 3–6 MB | 1.5–3 MB |
| video | linux/win x86_64, arm64 | 10–18 MB | 4–8 MB |

**真实数字以 CI 产物中的 `SIZES.md` 为准**（每个 artifact 里都有，另见 workflow summary）。
