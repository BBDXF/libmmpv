/*
 * play_with_headers.c - play an online stream with custom HTTP headers.
 * Uses only the public libmpv client API (mpv/client.h).
 *
 * Build (Linux, from a libmmpv dist directory):
 *   gcc play_with_headers.c -I dist/include -L dist/lib -lmpv -Wl,-rpath,dist/lib -o play_with_headers
 * Run:
 *   ./play_with_headers http://host/stream.m3u8 "Authorization: Bearer xyz" "X-Token: abc"
 *
 * NOTE: this file is compiled in CI (see .github/workflows/build.yml, header test).
 * Requires a libmmpv build made with WITH_NETWORK=1.
 */
#include <stdio.h>
#include <stdlib.h>
#include <mpv/client.h>

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "usage: %s URL [\"Header: value\"...]\n", argv[0]); return 2; }
    int nh = argc - 2;

    mpv_handle *h = mpv_create();
    if (!h) return 1;

    /* Recommended: headers as a node array. Each header is one array element, so
     * commas inside a header value need NO escaping (unlike the "a,b" string form).
     * Must be set before loadfile; setting it before mpv_initialize() is fine. */
    mpv_node_list list = { .num = nh, .values = calloc(nh ? nh : 1, sizeof(mpv_node)) };
    for (int i = 0; i < nh; i++) {
        list.values[i].format = MPV_FORMAT_STRING;
        list.values[i].u.string = argv[2 + i];
    }
    mpv_node arr = { .format = MPV_FORMAT_NODE_ARRAY, .u.list = &list };
    if (mpv_set_option(h, "http-header-fields", MPV_FORMAT_NODE, &arr) < 0)
        fprintf(stderr, "warning: could not set http-header-fields\n");
    free(list.values);

    /* Other network options (all plain string options): */
    mpv_set_option_string(h, "user-agent", "MyPlayer/1.0");
    /* mpv_set_option_string(h, "referrer", "https://example.com/"); */
    /* mpv_set_option_string(h, "cookies", "yes"); mpv_set_option_string(h, "cookies-file", "cookies.txt"); */
    /* mpv_set_option_string(h, "tls-ca-file", "/etc/ssl/certs/ca-certificates.crt"); */
    /* For HTTPS + HLS also set (nested requests): "demuxer-lavf-o" = "ca_file=/path/ca.pem" */

    mpv_set_option_string(h, "vid", "no"); /* audio-only build */
    if (mpv_initialize(h) < 0) return 1;

    const char *cmd[] = { "loadfile", argv[1], NULL };
    if (mpv_command(h, cmd) < 0) return 1;

    for (;;) {
        mpv_event *ev = mpv_wait_event(h, 1.0);
        if (ev->event_id == MPV_EVENT_END_FILE) {
            mpv_event_end_file *e = ev->data;
            if (e->reason == MPV_END_FILE_REASON_ERROR)
                fprintf(stderr, "playback error: %s\n", mpv_error_string(e->error));
            break;
        }
        if (ev->event_id == MPV_EVENT_SHUTDOWN) break;
    }
    mpv_terminate_destroy(h);
    return 0;
}
