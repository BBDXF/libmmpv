# libmmpv

精简的 **libmpv**：只暴露标准 C client API（`mpv/client.h`，视频 profile 额外有 `render.h` / `render_gl.h`），没有语言绑定。
同一套脚本和补丁产出两个 profile：

| profile | 用途 | 内容 |
|---|---|---|
| **music** | 音乐播放器 | 音频解复用/解码（mp3、flac、ogg/vorbis/opus、wav/pcm、aac、m4a/alac、mka/webm 音频、ape、wavpack…）+ 内嵌封面（mjpeg/png）。**没有视频解码器。** |
| **video** | 视频播放器 | music 的全部 + h264 / hevc / vp8 / vp9 软解 + av1（dav1d）+ libmpv render API（OpenGL，由宿主提供上下文；以及软件渲染 SW） |

共同点：LGPL 构建（`-Dgpl=false`、FFmpeg `--disable-gpl --disable-nonfree`）；一个共享库
（`libmpv.so` / `libmpv-2.dll`），FFmpeg / libplacebo / dav1d / zlib / mbedTLS 静态链入；
无 Lua / JS / cplayer / libcurl / OSC / console / stats；libass 被替换为空桩（见下文）。

**支持平台**：Linux x86_64、Linux arm64、Windows x86_64、Windows arm64（llvm-mingw 交叉编译）、
Android arm64-v8a、Android x86_64、Android armeabi-v7a、Android x86（NDK r28c 交叉编译；音乐 audiotrack AO / 视频 `vo=mediacodec_embed` + `hwdec=mediacodec`，**无** GL render API）。
**不在范围内**：macOS、iOS。

> 本仓库的构建与测试**只在 GitHub Actions 上验证过**；我没有在本地编译过。下面每一条 “已验证” 都注明了 run id。

## 版本（`upstream.lock`）
mpv v0.42.0 · FFmpeg n9.1 · libplacebo v7.387.0 · dav1d 1.5.5 · mbedTLS 3.6.8 · zlib 1.3.1 · llvm-mingw 20261117。
上述 tag 均已用 `git ls-remote` 确认存在。

## 构建

### 用 CI（推荐）
推送到 `main` 或手动触发 `build` workflow，artifact 为 `libmmpv-<profile>-<target>[-net]`（tar.gz / zip + sha256 + `SIZES.md`）。

### 本地 / 自己的机器
```bash
# Linux 依赖: nasm cmake ninja-build pkg-config python3 meson(>=1.3) ccache(可选)
#            libasound2-dev libpulse-dev libpipewire-0.3-dev
scripts/build.sh music linux-x86_64         # → dist/libmmpv-music-linux-x86_64.tar.gz
scripts/build.sh video linux-arm64
WITH_NETWORK=1 scripts/build.sh music linux-x86_64   # 加 http/https/HLS（mbedTLS）
# Windows: PATH 里需要 llvm-mingw
scripts/build.sh video win-x86_64
# Android: 需要 NDK r28c，ANDROID_NDK 指向其目录（见下方 “Android 构建”）
scripts/build.sh video android-arm64
scripts/build.sh music android-x86_64
scripts/build.sh video android-armv7     # 32 位 armeabi-v7a
scripts/build.sh music android-x86       # 32 位 x86
```
`scripts/build.sh <music|video> <linux-x86_64|linux-arm64|win-x86_64|win-arm64|android-arm64|android-x86_64|android-armv7|android-x86>`；脚本依次 fetch → apply 补丁 →
构建 zlib / dav1d(video) / mbedTLS(网络) / libplacebo / FFmpeg / mpv → strip → 打包。

## 使用产物
```
dist/<profile>-<target>/
  lib/libmpv.so(.2, .2.6.0)         或  bin/libmpv-2.dll + lib/libmpv.dll.a
  include/mpv/client.h stream_cb.h   (video 另有 render.h render_gl.h)
  SIZES.md  SHA256SUMS  LICENSES/  upstream.lock
```
```bash
gcc app.c -I dist/include -L dist/lib -lmpv -Wl,-rpath,'$ORIGIN/lib'     # Linux
x86_64-w64-mingw32-clang app.c -I include -L lib -lmpv                   # Windows（import lib）
```
- 只有 C ABI：库只导出 `mpv_*` 符号（Linux/Windows 各 54 个，见 `SIZES.md`；run 45812728213）。
- 运行时依赖：Linux 动态依赖 `libasound` / `libpipewire-0.3` / `libpulse`（音频输出）、libm、libgcc_s、libc；C++ 运行时已静态链入。
  Windows 只导入系统 DLL，不再需要 `libc++.dll`（run 45812728213 的 x64 Windows 实机加载通过）。
- 音频输出：Linux 为 ALSA / PulseAudio / PipeWire，Windows 为 WASAPI。
- 例：`examples/play_with_headers.c`（只用 `mpv/client.h`）。

## 在线流与自定义 HTTP header
需要 `WITH_NETWORK=1`（http / https / tcp / tls / crypto / HLS / mpegts + mbedTLS）。详见 [docs/header-streaming.md](docs/header-streaming.md)。

推荐：把 header 作为 **node 字符串数组**设置，每个 header 一个元素，值里的逗号不用转义：
```c
mpv_node_list list = { .num = n, .values = items };   // items[i].format = MPV_FORMAT_STRING; .u.string = "X-Token: abc"
mpv_node arr = { .format = MPV_FORMAT_NODE_ARRAY, .u.list = &list };
mpv_set_option(h, "http-header-fields", MPV_FORMAT_NODE, &arr);   // 在 loadfile 之前
mpv_set_option_string(h, "user-agent", "MyApp/1.0");              // referrer / cookies / cookies-file 同理
```
- **已验证（CI，run 45812728213，music linux-x86_64 net job）**：本地 HTTP 服务器记录请求头；普通 mp3、HLS 播放列表、HLS 分片、
  AES-128 的 key 请求、加密分片，全部带上了 `X-Test-Token`、`X-Second: a,b`（含逗号）、自定义 `User-Agent` 和 `Referer`。
  单个 URL 的 `loadfile … replace -1 http-header-fields-append=X-Per-File: yes` 在 HLS 播放列表和分片上也带上了该头
  （key 请求未在该测试里检查）。
- **只读源码、未测试**：HTTPS 自定义 CA。mbedTLS 只有设置了 `ca_file` 才会加载 CA，没有系统证书回退
  （`libavformat/tls_mbedtls.c:553`）；FFmpeg 的 HLS 子请求不复制 `ca_file` / `tls_verify`
  （`libavformat/aviobuf.c` 的 `ffio_copy_url_options`），所以 HTTPS+HLS 需要额外设置
  `tls-ca-file`，并用 `demuxer-lavf-o=ca_file=/path/ca.pem` 让 mpv 的嵌套请求带上（`demux/demux_lavf.c` 的 `nested_io_open`，
  `demuxer-lavf-propagate-opts` 默认 yes）。**CI 没有 HTTPS 测试，这条未经验证。**
- **music 构建只有音频**：在线视频流只会播放音轨（CI 里 music 播放 h264 mp4 只播音频，并报 `Failed to initialize a decoder for codec 'h264'`；run 45809092040 日志）。

## 上游跟踪
- 版本只在 `upstream.lock` 里改；补丁在 `common/patches/<项目>/`（两个 profile 共用）和 `<profile>/patches/<项目>/`。
- `scripts/rebase.sh <mpv-ref> [ffmpeg-ref]`：只做干跑（补丁能否 apply、选项/组件名是否仍存在），不编译。
- `scripts/check-options.sh` / `check-ffmpeg.sh` 校验我们用到的每个 meson 选项和 FFmpeg 组件名都存在于固定版本源码里。
- `.github/workflows/upstream-watch.yml` 每周一跑一次 `rebase.sh master master`，失败则自动开 issue。
  手动触发的一次（run 45807674933）通过：补丁 `0001-libass-stub.patch` 能 apply 到 mpv master（`1eab28e`），选项名与 FFmpeg 组件名都存在。
  这只说明 **apply 成功，不说明 master 能编译**。
- `release.yml`：在 `v*` tag 上调用 build 并发布产物。**从未运行过**（没有打过 tag）。
- 详见 [docs/upstream-tracking.md](docs/upstream-tracking.md)。

## libass 桩及其后果
mpv 0.42 的 `meson.build` 无条件依赖 libass、libplacebo、libswscale、libavfilter，且没有相应开关（已读源码）。因此：
- libass 用 `common/patches/mpv/0001-libass-stub.patch` 替换成一个很小的桩（libass 0.17.4 的 ISC 头文件 + 空实现）。
  **后果：文本字幕（srt/ass/vtt）和 OSD 文字不会被渲染。** 位图字幕未测试。
- libplacebo 保留，但构建为没有任何 GPU 后端的静态库（`common/libplacebo.options`）。
- 不带 zlib 时 FFmpeg 的 png 解码器不可用（嵌入 PNG 封面无法解码），所以 build.sh 自己编译了一个 zlib（CI run 45809092040 暴露、45810046253 起通过）。
- “无滤镜”只是运行时约束：mpv 没有构建开关，内部自动滤镜仍在，`af`/`vf` 选项也仍然存在，由使用方不去设置。

## 硬件解码（video profile）
只做 mpv 原生支持的 `-copy`（硬解后拷回内存）路径，**不做零拷贝**：后者需要 ANGLE/EGL 等，与本项目精简目标冲突。配置改动之外只有 6 行 mpv `meson.build` 补丁
（`common/patches/mpv/0002-d3d-hwaccel-without-d3d11.patch`：在不开 `d3d11` 时让 `d3d-hwaccel` 能编译），无其他 mpv 源码改动。

由 `HWDEC=1`（默认，video 有效；`HWDEC=0` 关闭）控制，LGPL 不变。CI run **45829808951** 已验证下面这些 hwaccel 出现在 `hwdec=help` 列出的可用方法里（h264/hevc/vp9/av1 基本都有，DXVA2 无 av1）：

| 平台 | 方式 | 加载 | 备注 |
|---|---|---|---|
| Windows x86_64 / arm64 | `d3d11va-copy`、`dxva2-copy` | 运行时 `LoadLibrary`（导入表无 d3d/dxgi/dxva2） | 用 mpv `-Dd3d-hwaccel=enabled -Dd3d9-hwaccel=enabled`，不引入 shaderc/spirv-cross |
| Windows x86_64 / Linux x86_64 | `nvdec-copy` | 运行时 dlopen `libcuda`/`libnvcuvid` | 仅需 nv-codec-headers 头文件；CI 日志出现 `Cannot load libcuda.so.1` 且回退正常 |
| Linux x86_64 / arm64 | `vaapi-copy` | **链接时依赖** `libva.so.2`、`libva-drm.so.2` | 未做 Implib.so 运行时加载；没有 libva 的系统上库无法加载 |

- **默认行为**：libmpv 默认 `hwdec=no`，需要宿主显式设置 `hwdec=auto-copy`；`auto-copy` 只选安全的拷回方式。更广的覆盖可看 `hwdec-codecs`。
- **CI 能证明的**：带 hwaccel 的库能构建/加载；`hwdec=auto-copy` 及显式 `*-copy` 下 h264/hevc/vp9/av1 测试片段都靠软解回退播完，`hwdec-current` 为 `no`（runner 没有 GPU）。日志里能看到 `Could not create device` 后回退。
- **CI 不能证明的**：真实硬件上是否真的硬解、性能/画质。`hwdec-current` 变为具体方法名才算启用。请在真机上这样验证：
  `mpv --hwdec=auto-copy --msg-level=vd=v <视频>`，播放中读 `hwdec-current` 属性，或用 API `mpv_get_property(..., "hwdec-current", ...)`。
- AV1 硬解需要 FFmpeg 原生 `av1` 解码器（仅 hwaccel 用）；它排在 libdav1d 之后，**软解 AV1 仍走 dav1d**（读源码结论，run 45829808951 的软解测试通过）。

## 体积（CI 实测，run 45829808951；详见 [docs/size-budget.md](docs/size-budget.md)）
| profile | linux-x86_64 | linux-arm64 | win-x86_64 | win-arm64 |
|---|---|---|---|---|
| music（strip / gzip，字节） | 6,307,376 / 2,623,274 | 5,597,376 / 2,461,279 | 6,221,312 / 2,742,720 | 5,223,936 / 2,531,469 |
| video + HWDEC（strip / gzip，字节） | 17,440,656 / 6,984,591 | 11,889,616 / 5,396,506 | 15,229,952 / 5,886,489 | 10,301,440 / 4,817,515 |

`WITH_NETWORK=1` 的 music linux-x86_64：7,086,064 / 2,999,019（+778,688 / +375,745）。
video 开启硬解后的增量（相对 run 45812728213，未开硬解）：linux-x86_64 +242,080 B stripped，linux-arm64 +131,552 B，win-x86_64 +163,328 B，win-arm64 +84,992 B。
这些都**大于**项目最初估算（music 3–6 MB、video 10–18 MB 的上沿或之上）；原因分析见 size-budget，其中未归因的部分已标明。

## CI 覆盖：已验证 / 未验证
除另注外，来自 run **45829808951**（最新全绿 run；硬解已开启）。

| 项目 | 状态 |
|---|---|
| 21 个构建 job：{music, video} × {linux-x86_64, linux-arm64, win-x86_64, win-arm64, android-arm64, android-x86_64, android-armv7, android-x86} + music 网络构建 | ✅ 全部成功 |
| Linux x86_64 / arm64 冒烟测试（music、video）：用 ao=null 解码 mp3 / flac / ogg / opus / wav / m4a / alac / aac / mka；内嵌 PNG/JPEG 封面；音频文件不应有视频轨 | ✅ 0 hard / 0 soft failure |
| video 解码 h264 / hevc / vp9 / av1，并用软件渲染 API 渲染出 50 帧非黑画面 | ✅ Windows x64 / arm64 实机（run 45812728213 日志）；Linux x86_64、arm64 的 50 帧输出见 run 45804606058 日志，之后各 run（含 45829808951）的 Linux 冒烟步骤均成功但我没有逐条重读 |
| **Windows x86_64 实机（Windows Server 2025）**：加载 `libmpv-2.dll`、`mpv_create`/`mpv_initialize`、解码测试、video 的 SW 渲染 | ✅ music、video 均通过（早先的失败是因为 DLL 导入了 `libc++.dll`，已改为静态链接） |
| **Windows arm64 实机（Windows 11 ARM）**：同上 | ✅ music、video 均通过（该 job 配置为 soft，但实际通过） |
| 自定义 header（全局 node 数组）→ 普通文件 / HLS 播放列表 / 分片 / AES key | ✅ |
| 单 URL `loadfile … http-header-fields-append` | ✅（HLS 播放列表和分片；key 未检查） |
| 导出符号只有 `mpv_*`（54 个） | ✅ Linux 与 Windows |
| **Android** 交叉编译（music/video × arm64-v8a/x86_64/armeabi-v7a/x86）：ELF ABI、NEEDED 白名单、16 KB `PT_LOAD` 对齐、`GNU_RELRO`、`JNI_OnLoad` 导出 | ✅ 见 `build` workflow 的 “Verify Android ELF” 步骤 |
| **Android 真机播放**（audiotrack 出音、mediacodec_embed 渲 Surface、`wid` 传 Surface） | ❌ **未测试**（CI 无模拟器/真机，须使用者在设备上验证） || upstream-watch（手动一次，run 45807674933） | ✅ 补丁可 apply 到 mpv master；**未验证能编译** |
| **HTTPS / 自定义 CA / mbedTLS 握手** | ❌ **未测试** |
| 硬解 hwaccel **编译进去**（`hwdec=help` 列出 d3d11va-copy/dxva2-copy/nvdec-copy/vaapi-copy 及对应直通方式） | ✅ 各平台 video 构建（run 45829808951 日志） |
| 无 GPU 机器上 `hwdec=auto-copy` 与显式 `*-copy` 的回退播放（4 种编码播完、`hwdec-current=no`、`Could not create device`） | ✅ Linux 与 Windows（run 45829808951 日志） |
| Windows DLL / Linux .so 导入表无 d3d/dxgi/dxva2/nvcuda/libcuda/GL/X11/Wayland；Linux video 新增 `libva.so.2`、`libva-drm.so.2` | ✅ run 45829808951 的 `check-deps.sh` |
| **真实 GPU 上实际硬解、`hwdec-current` 为具体方法、性能与画质** | ❌ **未测试**（CI runner 无 GPU，须真机验证） |
| 文本字幕 / OSD 文字 | ❌ 不支持（libass 为桩） |
| 位图字幕（PGS/DVD） | ❌ 未测试 |
| `release.yml` | ❌ 从未运行 |
| 真实声卡输出（ALSA/Pulse/PipeWire/WASAPI） | ❌ 测试只用 `ao=null` |
| 真实窗口 / OpenGL 渲染 | ❌ 只测了软件渲染 API；OpenGL render API 没有在 CI 里运行 |
| FFmpeg n9.1 与 mpv 0.42 的长期兼容性 | 仅限编译通过与上述测试；不代表其它场景 |

说明：`windows-latest` 的 x64 runner 上，`api-ms-win-*` DLL 在 System32 里不是真实文件（API set），诊断输出里显示 False 是正常的。
linux-arm64 job 在私有仓库也跑起来了（仓库现已公开）。

## Android 构建与使用
Android 目标（`android-arm64` / `android-x86_64` / `android-armv7` / `android-x86`）由 CI 交叉编译并校验 ELF，但**不做运行时测试**（CI 无模拟器/真机；真机验证是使用者的工作）。

### 构建
需要 **NDK r28c**（`28.2.13676358`），`ANDROID_NDK` 指向解包后的目录：
```bash
export ANDROID_NDK=/path/to/android-ndk-r28c
scripts/build.sh music android-arm64
scripts/build.sh video android-x86_64
scripts/build.sh video android-armv7     # 32 位 armeabi-v7a
scripts/build.sh music android-x86       # 32 位 x86
```
产物与桌面相同：`dist/libmmpv-<profile>-android-<abi>[-net].tar.gz`，内含 `lib/libmpv.so*`、`include/mpv/client.h`（Android video 无 `render.h`）、`SIZES.md`、`LICENSES/`。
ABI：arm64-v8a、x86_64、armeabi-v7a、x86（全部以 NDK `NDK_DEFAULT_API=24` 为 minSdk）。NDK r28+ 默认按 **16 KB 页** 链接共享库，满足 Google Play 2027 年起的 16 KB 对齐要求；CI 校验每个 `PT_LOAD` 的 `Align == 0x4000`。

### 音乐（audiotrack）
JavaVM 由 `JNI_OnLoad` 注册（补丁 `common/patches/mpv/0003-jni-onload.patch`：调用 `av_jni_set_java_vm`）。宿主 App `System.loadLibrary("mpv")`
后，Android 运行时会回调 `JNI_OnLoad`，audiotrack AO 即能取到 JavaVM。
```java
System.loadLibrary("mpv");            // 触发 JNI_OnLoad 注册 JavaVM
mpv_create();
mpv_set_option(h, "ao", "audiotrack");
mpv_initialize();
mpv_command(h, new String[]{"loadfile", url, null});
```

### 视频（mediacodec_embed，无 GL render API）
Android video 不构建 `render.h` / OpenGL；视频直接渲到宿主传入的 `android.view.Surface`。把 Surface 对象按其地址（`intptr_t`）传给 `--wid`，
配合 `--vo=mediacodec_embed --hwdec=mediacodec`：
```java
System.loadLibrary("mpv");
mpv_create();
mpv_set_option(h, "vo",    "mediacodec_embed");
mpv_set_option(h, "hwdec", "mediacodec");
mpv_set_option(h, "wid",   "<Surface 的 intptr_t 地址，见下方说明>");
mpv_initialize();
mpv_command(h, new String[]{"loadfile", url, null});
```
把 `android.view.Surface` 对象的地址按 `intptr_t` 传给 `--wid`（在你的 JNI 桥接层里从 C 侧拿
`env->NewGlobalRef(surface)` 的句柄换算成地址；`ANativeWindow_fromSurface` 用同一个句柄取原生窗口）。
> 真机验证由使用者完成：CI 只校验 ABI、NEEDED、16 KB 对齐、RELRO、`JNI_OnLoad` 导出。

## 已知限制
- music 不能解码视频；video 的硬解只支持拷回内存的 `-copy` 方式、未在真 GPU 上验证；两者都没有文本字幕/OSD 文字。
- Linux 的 VAAPI 是链接时依赖：没有 `libva`/`libva-drm` 的系统上 video 库无法加载（未做运行时加载）。Windows 的 D3D11VA/DXVA2 与 NVDEC 为运行时加载，不受此限。
- 没有 zlib 之外的压缩库：bzip2 / lzma 等 MKV/MOV 的少见封装可能不可用（`--disable-autodetect`）。
- 网络构建没有系统证书回退（见上）。
- 体积比最初预期大（见 size-budget）。
- 构建依赖 GitHub runner 上的 apt；个别时候镜像 404 会导致 job 失败，重跑即可（本项目遇到过一次，run 45812728213 重跑后通过）。

## 许可证
- mpv（`-Dgpl=false`）：LGPL-2.1+；FFmpeg（`--disable-gpl --disable-nonfree`）：LGPL-2.1+；libplacebo：LGPL-2.1+；dav1d：BSD-2-Clause；zlib：zlib license；
  libass 头文件（桩）：ISC。各自的许可证文本会放进产物的 `LICENSES/`。
- `WITH_NETWORK=1`：mbedTLS 是 Apache-2.0（或 GPL-2.0+）。按惯例 Apache-2.0 只与 (L)GPLv3 兼容，所以该构建给 FFmpeg 加了 `--enable-version3`，
  整体应按 **LGPL-3.0+** 对待（这是我的判断，FFmpeg 是否强制要求未单独核实）。
- 因为 FFmpeg 等是**静态链入**共享库，应用必须以动态链接方式使用 libmpv，并保证用户可以替换这个库，才符合 LGPL 的惯常要求。
- **这不是法律意见**：分发前请自行核对每个组件的许可证和你的使用方式。
