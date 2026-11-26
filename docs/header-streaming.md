# 在线流 + 自定义 HTTP Header

构建需 `WITH_NETWORK=1`（http/https/tcp/tls/crypto/hls/mpegts + mbedTLS）。默认关闭网络。

## 用法（C）
见 `examples/play_with_headers.c`。

1. **全局 header（推荐）**：`mpv_set_option(h, "http-header-fields", MPV_FORMAT_NODE, &array)`，数组每个元素一个 header。
   - 为什么：字符串形式用 `,` 分隔，header 值里有逗号需要转义；`man mpv` 的 List Options 一节也推荐
     libmpv 使用结构化类型。
   - 必须在 `loadfile` 之前设置；`mpv_initialize` 之前或之后均可。
2. 字符串形式：`http-header-fields=A: 1,B: 2`；追加单个：`http-header-fields-append=X: y`（不解释转义）。
3. 单个 URL：`loadfile <url> replace -1 http-header-fields-append=X-Foo: bar`
   （`loadfile <url> [<flags> [<index> [<options>]]]`，index 为 0.38 新增；选项仅在该文件播放期间生效。）
   **本条的 `-append` 写法在 CI 的 header_test 里作为"软测试"验证，结果见 workflow 日志。**
4. 其他选项：`user-agent`、`referrer`、`cookies` / `cookies-file`、`tls-verify`、`tls-ca-file`、`http-proxy`、`network-timeout`。
   底层选项：`stream-lavf-o`（打开流时）、`demuxer-lavf-o`（解复用/嵌套请求时）。

## 源码依据（mpv v0.42.0 / FFmpeg n9.1）
- `stream/stream_lavf.c:156` `mp_setup_av_network_options`：`referrer` → `Referer: x\r\n`；`http-header-fields` 每项追加 `\r\n`，合并成 FFmpeg 的 `headers` 选项；同时设置 `user_agent`、`cookies`、`tls_verify`、`ca_file`、`http_proxy`。
- `libavformat/aviobuf.c:962` `ffio_copy_url_options` 把 `headers`/`user_agent`/`cookies`/`http_proxy`/`referer`/`rw_timeout`/`icy` 复制给 HLS 的子请求；
  `libavformat/hls.c` 用同一份 `avio_opts` 请求子 playlist（≈1676）、分片（≈1682）、AES key（≈1607）。**所以 header 会传给分片和 key。**
- **限制**：`tls_verify`/`ca_file`/`cert_file` **不**在该复制列表里。HTTPS+HLS 的子请求若依赖自定义 CA，
  用 `demuxer-lavf-o=ca_file=/path/ca.pem`：mpv 的 `nested_io_open`（`demux/demux_lavf.c:992`）默认
  `demuxer-lavf-propagate-opts=yes`，会把 `demuxer-lavf-o` 注入嵌套请求。无需改 FFmpeg。
- mbedTLS 只有设置了 `ca_file` 才会加载 CA（`libavformat/tls_mbedtls.c:553`）；没有系统证书回退。
  所以 HTTPS 必须设置 `tls-ca-file`（Linux: `/etc/ssl/certs/ca-certificates.crt`；Windows：自带 `cacert.pem`）。
- 中途修改：header 在每次打开连接时读取；已建立的连接不会改变。切换 header 请重新 `loadfile`。

## CI 证据
network 构建的 job 会跑 `common/tests/header_test.sh`：本地 HTTP 服务器记录每个请求的 header，
断言 mp3、HLS playlist、HLS 分片、AES-128 key 请求均带 `X-Test-Token`/`User-Agent`/`Referer`。证据文件作为 artifact 上传。

## 重要：music 构建只有音频
在线**视频**流在 music 构建里只会播放音轨。需要画面请用 video profile。
