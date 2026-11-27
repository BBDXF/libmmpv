# Video profile = common + audio + software video decoders. Speed over size.
# AV1 goes through dav1d (FFmpeg's native av1 decoder is hwaccel-only).
# Hardware decode flags live in ffmpeg-hwdec.sh (HWDEC=1 by default).
FF_PROFILE=(
  "${FF_AUDIO[@]}"
  --enable-libdav1d
  --enable-decoder=h264,hevc,vp8,vp9,libdav1d
  --enable-demuxer=mpegts,avi
  --enable-parser=h264,hevc,vp8,vp9,av1
  --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,vp9_superframe,vp9_superframe_split,av1_frame_split,av1_frame_merge
  --enable-filter=scale,transpose,hflip,vflip,bwdif
)
