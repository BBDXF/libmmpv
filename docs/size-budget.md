# 体积（CI 实测）

来源：GitHub Actions run **45829808951**（最新全绿 run，video 开启硬解；2026-11-26）。数字取自各 artifact 里的 `SIZES.md`；
“stripped” 是 `strip --strip-unneeded` 后的库文件字节数，“gzip” 是 `gzip -9` 后的字节数。发布包大小仅在 run 45812728213 读过，未随硬解改动重测。

| profile | 目标 | stripped (B) | gzip -9 (B) |
|---|---|---|---|
| music | linux-x86_64 | 6,307,376 | 2,623,274 |
| music | linux-arm64 | 5,597,376 | 2,461,279 |
| music | win-x86_64 | 6,221,312 | 2,742,720 |
| music | win-arm64 | 5,223,936 | 2,531,469 |
| music + `WITH_NETWORK=1` | linux-x86_64 | 7,086,064 | 2,999,019 |
| video + HWDEC | linux-x86_64 | 17,440,656 | 6,984,591 |
| video + HWDEC | linux-arm64 | 11,889,616 | 5,396,506 |
| video + HWDEC | win-x86_64 | 15,229,952 | 5,886,489 |
| video + HWDEC | win-arm64 | 10,301,440 | 4,817,515 |

硬解增量（video，run 45829808951 相对 45812728213 未开硬解，均为 stripped）：
linux-x86_64 +242,080 B；linux-arm64 +131,552 B；win-x86_64 +163,328 B；win-arm64 +84,992 B。
music 不受 HWDEC 影响，数值未变。

- 网络构建增量（music linux-x86_64）：+778,688 B stripped，+375,745 B gzip（mbedTLS + http/https/tls/hls/mpegts/crypto）。
- video 相对 music（linux-x86_64）：+10.9 MB stripped（软解 h264/hevc/vp8/vp9 + dav1d + 视频滤镜 + OpenGL/SW render 代码）。
- 注意：music 的 arm64 库比 x86_64 小约 0.7 MB，**原因没有单独验证**（可能与指令编码/汇编优化有关，仅为猜测）。
- 注意：早期 run 45803313523 的构建不含 zlib（PNG 封面解码需要它）；加入后 music linux-x86_64 增加约 45 KB（6,262,320 → 6,307,376，跨 run 比较，仅作参考）。

## 为什么比最初的估算（music 3–6 MB / video 10–18 MB）大
最初的估算是按旧版 media-kit 构建（mpv 0.35/0.36）类推的。下面只列 CI 数据能支持的事实
（music linux-x86_64 的未 strip 库，`SIZES.md` 的 section 表和符号前缀统计，**前缀归类是启发式的**）：

- 段大小：`.text` 3.89 MB、`.rodata` 0.83 MB、`.data.rel.ro` 0.61 MB、`.eh_frame`+`.eh_frame_hdr` 0.47 MB、`.rela.dyn` 0.43 MB（`.bss` 1.57 MB 不占文件体积）。
  即体积主要是代码；`.rela.dyn`/`.data.rel.ro` 来自位置无关的共享库。
- 按符号名前缀粗分（已定大小的符号合计 6.04 MB）：FFmpeg 相关 39%、mpv 12%、libplacebo 3.4%、无法按前缀归类 45%。
  libplacebo（无 GPU 后端）只占约 205 KB。
- 没有查明的部分：“其它 45%” 里具体是什么（mpv 之外的静态库、C++ 运行时、表数据等）未归因；
  也没有做过 `--enable-small` / LTO / 更窄的 mpv 功能裁剪对体积影响的对比实验。
- 与 `--enable-small` 无关的事实：music 已经使用 `--enable-small`，video 没有（`video/ffmpeg-video.sh`）。

## 继续缩小的方向（**未验证**，仅作线索）
LTO、`-Os`、进一步关掉 mpv 里不用的输入/选项代码、裁剪 FFmpeg 滤镜/解码器白名单。每项都需要单独跑 CI 量一次。
