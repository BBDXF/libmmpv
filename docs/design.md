# 设计说明

两个 profile、同一套代码和补丁：

| | music | video |
|---|---|---|
| 目标 | 音乐播放器 | 视频播放器 |
| FFmpeg | 音频解码/解复用 + 封面图(mjpeg/png) | music + h264/hevc/vp8/vp9/av1(dav1d) 软解 |
| mpv 视频输出 | 无 GL | libmpv render API: OpenGL(由宿主提供上下文) + SW |
| 硬件解码 | 无 | v1 关闭（见下） |

## 共同约束
- LGPL：FFmpeg `--disable-gpl --disable-nonfree`，mpv `-Dgpl=false`。网络构建额外 `--enable-version3`（mbedTLS 为 Apache-2.0）。
- 单个共享库 `libmpv.so` / `libmpv-2.dll`，FFmpeg、libplacebo、dav1d、mbedTLS 全部静态链入。
- 只暴露 C client API（`mpv/client.h`；video 额外 `render.h`/`render_gl.h`）。无 Lua/JS/cplayer/libcurl/lcms2/libarchive。
- 配置单一来源：`common/`（共享）+ `music/`、`video/`（overlay）+ `upstream.lock`（版本）。

## 为什么要"补丁 + 桩"
mpv v0.42.0 的 `meson.build:23-33` 无条件依赖 libavfilter、libswscale、libplacebo(>=7.387.0)、libass，
且没有对应的 meson 开关（已读源码确认）。因此：
1. **libplacebo**：保留依赖，但按 `common/libplacebo.options` 编译为无任何 GPU 后端的静态库（仅用其色彩空间等工具代码）。mpv 里调用 `pl_opengl_*`/`pl_d3d11_*` 的代码有 `PL_HAVE_*` 守卫（`video/out/gpu_next/context.c`）。
2. **libass**：`common/patches/mpv/0001-libass-stub.patch` 把依赖替换为 `third_party/libass-stub`（libass 0.17.4 的 ISC 头文件 + 约 150 行空实现）。
   与 media-kit 的 `mpv-remove-libass.patch`（1300~2800 行、需逐版本重做）相比，桩方案只改 `meson.build` 一处，
   源码里的字幕/OSD 代码仍在，但不会渲染任何文字。代价：库里多一点死代码。
3. **libavfilter / libswscale**：mpv 硬依赖，保留；FFmpeg 侧只白名单必要组件。

## 已知限制 / 取舍
- music 构建不能解码视频；视频文件只播放音轨（mpv 会警告缺少视频解码器）。
- 文本字幕和 OSD 文字不会渲染（libass 为桩）。位图字幕未验证。
- 没有 zlib：个别 MKV 头压缩、MOV 压缩 atom、HTTP gzip 不可用（`--disable-autodetect`）。
- 硬件解码在 v1 关闭：d3d11va/vaapi 需要额外的 GL/EGL/DRM 互操作代码或 shaderc，违背"小"的目标。路线：Windows 用 d3d11va-copy，Linux 用 vaapi-copy。
- "无滤镜"：用户不能通过 API 之外设置 `af`/`vf`，但这是**运行时**约束（mpv 无构建开关）。库内部自动滤镜保留。若必须禁止，需要改 `options/options.c`。
- `-Dgl=enabled -Dplain-gl=enabled` 只编译 libmpv 的 OpenGL render API，不带窗口系统。D3D11 render API 需要 shaderc+spirv-cross，未启用。

> 以上全部是读源码得到的结论；**能否编译通过以 GitHub Actions 为准**。
