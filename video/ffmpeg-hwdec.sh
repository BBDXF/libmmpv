# Hardware decode (video profile, HWDEC=1, default). Only the "-copy" style hwdec paths are
# targeted: frames are copied back to system memory, so they work with the SW and GL render APIs.
# All hwaccel names verified against FFmpeg n9.1 libavcodec/hwaccels.h (scripts/check-ffmpeg.sh).
#
# Native AV1 decoder: it is "hwaccel hooks only" (libavcodec/allcodecs.c:858) and is listed AFTER
# libdav1d, so software AV1 keeps using dav1d; the native decoder is only used by the hwaccels.
FF_HW_COMMON=(
  --enable-decoder=av1
)

# Windows (x86_64 + arm64): d3d11va + dxva2. FFmpeg and mpv load d3d11.dll/dxgi.dll/d3d9.dll/dxva2.dll
# at runtime (LoadLibrary), so there is no import-table dependency.
FF_HW_WINDOWS=(
  --enable-d3d11va --enable-dxva2
  --enable-hwaccel=h264_d3d11va,h264_d3d11va2,hevc_d3d11va,hevc_d3d11va2,vp9_d3d11va,vp9_d3d11va2,av1_d3d11va,av1_d3d11va2
  --enable-hwaccel=h264_dxva2,hevc_dxva2,vp9_dxva2
)

# NVDEC (x86_64 Windows + Linux): header-only nv-codec-headers, libcuda/libnvcuvid are dlopen()ed.
# configure would also allow aarch64 Linux/Windows (configure:7779-7787); not enabled (no NVIDIA arm64 target).
FF_HW_NVDEC=(
  --enable-ffnvcodec --enable-nvdec
  --enable-hwaccel=h264_nvdec,hevc_nvdec,vp9_nvdec,av1_nvdec
)

# VAAPI (Linux x86_64 + arm64). libva / libva-drm / libdrm are LINK-TIME dependencies of libmpv.so
# (FFmpeg has no dlopen path for libva). libdrm is used to enumerate /dev/dri/renderD* render nodes.
FF_HW_VAAPI=(
  --enable-vaapi --enable-libdrm
  --enable-hwaccel=h264_vaapi,hevc_vaapi,vp9_vaapi,av1_vaapi
)
