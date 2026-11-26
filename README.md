# libmmpv

精简的 **libmpv**（只暴露标准 C client API），两个 profile：

- **music**：纯音频，给音乐播放器用。
- **video**：常见视频软解（h264/hevc/vp8/vp9/av1）+ libmpv render API（OpenGL / 软件渲染），给视频播放器用。

共同点：LGPL、单个共享库（FFmpeg/libplacebo/dav1d/mbedTLS 静态链入）、无 Lua/JS/cplayer/OSC/console/stats、无 libass（桩）。
目标：Linux x86_64 / arm64，Windows x86_64 / arm64（llvm-mingw 交叉编译）。**Android、macOS 暂不在范围内。**

> ⚠️ **状态**：所有文件都是在**没有本地编译**的前提下写的，是否能编译、体积多大**只以 GitHub Actions 结果为准**。
> 下表的体积是占位，见 CI 产物里的 `SIZES.md`。

## 使用

```bash
# 依赖(Linux): nasm cmake ninja pkg-config meson>=1.3 libasound2-dev libpulse-dev libpipewire-0.3-dev
scripts/build.sh music linux-x86_64          # → dist/music-linux-x86_64/ 和 dist/libmmpv-*.tar.gz
scripts/build.sh video linux-x86_64
WITH_NETWORK=1 scripts/build.sh music linux-x86_64   # 加 http/https/HLS（mbedTLS）
# Windows（需要 PATH 里有 llvm-mingw）
scripts/build.sh music win-x86_64
```

产物：`lib/libmpv.so*`（或 `bin/libmpv-2.dll` + `lib/libmpv.dll.a`）、`include/mpv/*.h`、`SIZES.md`（原始/gzip 体积、依赖、导出符号）、`SHA256SUMS`、`LICENSES/`。

## 目录
| 路径 | 作用 |
|---|---|
| `upstream.lock` | 固定 mpv v0.42.0 / FFmpeg n9.1 / libplacebo v7.387.0 / dav1d / mbedTLS 版本 |
| `common/` | 共享 FFmpeg 开关、mpv meson 选项、libplacebo 选项、补丁、测试 |
| `music/` `video/` | profile 专属 overlay |
| `cross/` | meson 交叉/本机文件 |
| `scripts/` | fetch / apply / build / package / rebase / check-* |
| `examples/` | `play_with_headers.c`（带自定义 header 的在线流） |
| `docs/` | 设计、上游跟踪、体积预算、header 流媒体说明 |

## 在线流与自定义 header
需 `WITH_NETWORK=1`。详见 [docs/header-streaming.md](docs/header-streaming.md)。
推荐用 `mpv_set_option(h, "http-header-fields", MPV_FORMAT_NODE, 字符串数组)`；header 会传给 HLS 子 playlist、分片和 AES key 请求（源码核实 + CI 测试）。
**music 构建是纯音频：在线视频流只会播放音轨。**

## 体积（占位 — 以 CI 为准）
| profile | linux x86_64 | linux arm64 | win x86_64 | win arm64 |
|---|---|---|---|---|
| music (strip / gzip) | _TBD_ | _TBD_ | _TBD_ | _TBD_ |
| video (strip / gzip) | _TBD_ | _TBD_ | _TBD_ | _TBD_ |

## CI
`.github/workflows/build.yml`：{music,video} × 4 目标 + 1 个 network job；Linux 跑冒烟测试，network job 跑 header/HLS 测试；Windows 做链接检查（x86_64 尝试 wine 加载）。
私有仓库没有免费 arm64 runner，linux-arm64 job 会自动跳过（公开仓库或设置变量 `ENABLE_ARM64=1` 后启用）。
`upstream-watch.yml` 每周检查补丁能否应用到 mpv/FFmpeg master；`release.yml` 在 `v*` tag 上发布产物。

## 许可证
- mpv（`-Dgpl=false`）：LGPL-2.1+；FFmpeg（`--disable-gpl --disable-nonfree`）：LGPL-2.1+；libplacebo：LGPL-2.1+；dav1d：BSD-2。
- **WITH_NETWORK=1**：mbedTLS（Apache-2.0）要求 FFmpeg 以 `--enable-version3`（LGPL-3.0+）构建，整体按 LGPL-3.0+ 对待。
- 因为是**静态链入共享库**，分发时需满足 LGPL（允许用户替换库）；本项目只提供动态库，应用以动态链接方式使用即可。
- `third_party/libass-stub` 的头文件取自 libass 0.17.4（ISC）。
- 这里的说明不是法律意见。
