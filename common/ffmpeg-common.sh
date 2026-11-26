# Shared FFmpeg configure flags (bash arrays). Sourced by scripts/build.sh.
# Every component name below was checked against FFmpeg n9.1 sources
# (libavcodec/allcodecs.c, libavformat/allformats.c, parsers.c, protocols.c,
#  bitstream_filters.c, libavfilter/allfilters.c) - see scripts/check-ffmpeg.sh.

# Licence / linkage / things we never want.
FF_COMMON=(
  --disable-gpl --disable-nonfree
  --enable-static --disable-shared --enable-pic
  --disable-autodetect          # no accidental system libs (zlib, lzma, iconv, vaapi, ...)
  --disable-programs --disable-doc --disable-debug --disable-stripping
  --disable-avdevice
  --enable-zlib                 # png decoder (embedded PNG covers) needs it; zlib is built by build.sh
  --disable-hwaccels
  --disable-everything          # whitelist below
  --enable-avutil --enable-avcodec --enable-avformat --enable-avfilter
  --enable-swresample --enable-swscale   # hard dependencies of mpv 0.42 (meson.build)
)

# Audio components used by BOTH profiles. (ape is optional but tiny.)
FF_AUDIO=(
  --enable-decoder=mp1,mp2,mp2float,mp3,mp3float,flac,vorbis,opus,aac,aac_latm,alac,ape,wavpack
  --enable-decoder='pcm_*'
  --enable-demuxer=mp3,flac,ogg,wav,aac,mov,matroska,ape,aiff,w64,wv
  --enable-parser=mpegaudio,aac,aac_latm,flac,vorbis,opus
  --enable-bsf=aac_adtstoasc,extract_extradata,null
  --enable-protocol=file
  # filters: mpv needs abuffer/abuffersink (always built into avfilter);
  # aresample/aformat/anull/atempo are used by mpv's audio chain.
  --enable-filter=aresample,aformat,anull,atempo,null,format
  # embedded cover art (attached_pic streams) must not break demuxing
  --enable-decoder=mjpeg,png
  --enable-parser=mjpeg,png
)

# Added when WITH_NETWORK=1 (http/https/HLS). mbedTLS is Apache-2.0, which is only
# compatible with (L)GPLv3, hence --enable-version3 in that configuration.
FF_NETWORK=(
  --enable-network --enable-version3 --enable-mbedtls
  --enable-protocol=http,https,tcp,tls,crypto,data,httpproxy
  --enable-demuxer=hls,mpegts
  --enable-parser=ac3
)
