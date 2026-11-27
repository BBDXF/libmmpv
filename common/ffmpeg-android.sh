# Android FFmpeg platform flags (bash arrays). Sourced by scripts/build.sh when OS=android.
# Verified against FFmpeg n9.1 configure.
#
# --enable-jni is required by BOTH profiles:
#   * mpv's Android AOs (audiotrack/aaudio/opensles) get the JavaVM from
#     av_jni_get_java_vm() (misc/jni.c), which only returns a value after our
#     JNI_OnLoad calls av_jni_set_java_vm(). Those two live under CONFIG_JNI.
#   * the mediacodec decoder (video) additionally requires jni (configure:7434).
#
# ANativeWindow (for vo_android / mediacodec_embed surface) is in libandroid, which mpv links
# on its own (meson.build:499). liblog comes in transitively.
FF_ANDROID_COMMON=(
  --enable-jni
  --enable-pthreads
)

# video profile only: MediaCodec hardware decode.
#   mediacodec_deps="android mediandk pthreads" (configure:3347) -> auto-detected from the NDK sysroot.
#   h264/hevc/vp8/vp9/av1 mediacodec decoders exist in allcodecs.c; --enable-mediacodec pulls them in.
FF_ANDROID_VIDEO=(
  --enable-mediacodec
  --enable-decoder=h264_mediacodec,hevc_mediacodec,vp8_mediacodec,vp9_mediacodec,av1_mediacodec
)