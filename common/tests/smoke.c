/*
 * mmpv_smoke - small libmpv harness used by CI. Only uses mpv/client.h
 * (and mpv/render.h when built with -DMMPV_SW_RENDER).
 *
 *   mmpv_smoke --probe
 *   mmpv_smoke FILE_OR_URL [-o key=val]... [-H "Header: v"]... [-P "Header: v"]
 *              [-A audio-codec-substring] [-V video-format] [--sw]
 *
 * -H  global header list, set as MPV_FORMAT_NODE string array (before init)
 * -P  per-file header, passed via loadfile's options argument
 * --sw  render frames with the software render API (needs -DMMPV_SW_RENDER)
 * Exit codes: 0 ok, 1 expectation failed, 2 mpv error, 3 timeout.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <mpv/client.h>
#ifdef MMPV_SW_RENDER
#include <mpv/render.h>
#endif

static void fail_mpv(const char *what, int err)
{
    fprintf(stderr, "FAIL: %s: %s\n", what, mpv_error_string(err));
    exit(2);
}

static char *prop(mpv_handle *h, const char *name)
{
    return mpv_get_property_string(h, name);
}

int main(int argc, char **argv)
{
    const char *file = NULL, *exp_a = NULL, *exp_v = NULL, *perfile = NULL;
    int probe = 0, sw = 0, nopts = 0, nh = 0;
    const char *opts[64];
    char *hdrs[32];

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--probe")) probe = 1;
        else if (!strcmp(argv[i], "--sw")) sw = 1;
        else if (!strcmp(argv[i], "-o") && i + 1 < argc && nopts < 64) opts[nopts++] = argv[++i];
        else if (!strcmp(argv[i], "-H") && i + 1 < argc && nh < 32) hdrs[nh++] = argv[++i];
        else if (!strcmp(argv[i], "-P") && i + 1 < argc) perfile = argv[++i];
        else if (!strcmp(argv[i], "-A") && i + 1 < argc) exp_a = argv[++i];
        else if (!strcmp(argv[i], "-V") && i + 1 < argc) exp_v = argv[++i];
        else if (argv[i][0] != '-' && !file) file = argv[i];
        else { fprintf(stderr, "bad argument: %s\n", argv[i]); return 2; }
    }
    if (!file && !probe) { fprintf(stderr, "usage: see source header\n"); return 2; }

    mpv_handle *h = mpv_create();
    if (!h) { fprintf(stderr, "FAIL: mpv_create\n"); return 2; }

    for (int i = 0; i < nopts; i++) {
        char *eq = strchr(opts[i], '=');
        if (!eq) { fprintf(stderr, "bad -o %s\n", opts[i]); return 2; }
        char key[128];
        size_t kl = (size_t)(eq - opts[i]);
        if (kl >= sizeof key) return 2;
        memcpy(key, opts[i], kl); key[kl] = 0;
        int r = mpv_set_option_string(h, key, eq + 1);
        if (r < 0) fail_mpv(opts[i], r);
    }
    if (sw) {
        int r = mpv_set_option_string(h, "vo", "libmpv");
        if (r < 0) fail_mpv("vo=libmpv", r);
    }
    if (nh) {
        mpv_node_list list = { .num = nh, .values = calloc((size_t)nh, sizeof(mpv_node)) };
        for (int i = 0; i < nh; i++) {
            list.values[i].format = MPV_FORMAT_STRING;
            list.values[i].u.string = hdrs[i];
        }
        mpv_node arr = { .format = MPV_FORMAT_NODE_ARRAY, .u.list = &list };
        int r = mpv_set_option(h, "http-header-fields", MPV_FORMAT_NODE, &arr);
        if (r < 0) fail_mpv("http-header-fields", r);
        free(list.values);
    }

    int r = mpv_initialize(h);
    if (r < 0) fail_mpv("mpv_initialize", r);
    printf("client-api-version: %lu\n", mpv_client_api_version());
    mpv_request_log_messages(h, "warn");
    if (probe) { mpv_terminate_destroy(h); puts("OK probe"); return 0; }

#ifdef MMPV_SW_RENDER
    mpv_render_context *rc = NULL;
    static unsigned char pix[320 * 240 * 4];
    long frames = 0, nonzero = 0;
    if (sw) {
        mpv_render_param cp[] = {
            { MPV_RENDER_PARAM_API_TYPE, (void *)MPV_RENDER_API_TYPE_SW },
            { MPV_RENDER_PARAM_INVALID, NULL } };
        r = mpv_render_context_create(&rc, h, cp);
        if (r < 0) fail_mpv("mpv_render_context_create(sw)", r);
    }
#else
    if (sw) { fprintf(stderr, "built without MMPV_SW_RENDER\n"); return 2; }
#endif

    char optbuf[1024];
    const char *cmd[8]; int n = 0;
    cmd[n++] = "loadfile"; cmd[n++] = file;
    if (perfile) {
        snprintf(optbuf, sizeof optbuf, "http-header-fields-append=%s", perfile);
        cmd[n++] = "replace"; cmd[n++] = "-1"; cmd[n++] = optbuf;
    }
    cmd[n] = NULL;
    r = mpv_command(h, cmd);
    if (r < 0) fail_mpv("loadfile", r);

    int rc_exit = 0, got_audio = 0, got_video = 0;
    time_t t0 = time(NULL);
    for (;;) {
        mpv_event *ev = mpv_wait_event(h, sw ? 0.01 : 0.5);
        if (time(NULL) - t0 > 90) { fprintf(stderr, "FAIL: timeout\n"); rc_exit = 3; break; }
#ifdef MMPV_SW_RENDER
        if (rc && (mpv_render_context_update(rc) & MPV_RENDER_UPDATE_FRAME)) {
            int size[2] = { 320, 240 };
            size_t stride = 320 * 4;
            mpv_render_param rp[] = {
                { MPV_RENDER_PARAM_SW_SIZE, size },
                { MPV_RENDER_PARAM_SW_FORMAT, (void *)"rgb0" },
                { MPV_RENDER_PARAM_SW_STRIDE, &stride },
                { MPV_RENDER_PARAM_SW_POINTER, pix },
                { MPV_RENDER_PARAM_INVALID, NULL } };
            if (mpv_render_context_render(rc, rp) >= 0) {
                frames++;
                for (size_t i = 0; i < sizeof pix; i++) if (pix[i]) { nonzero++; break; }
            }
        }
#endif
        if (ev->event_id == MPV_EVENT_NONE) continue;
        if (ev->event_id == MPV_EVENT_LOG_MESSAGE) {
            mpv_event_log_message *m = ev->data;
            fprintf(stderr, "[%s] %s", m->prefix, m->text);
        } else if (ev->event_id == MPV_EVENT_FILE_LOADED) {
            char *ac = prop(h, "audio-codec-name"), *vf = prop(h, "video-format"), *d = prop(h, "duration");
            printf("loaded: audio-codec=%s video-format=%s duration=%s\n",
                   ac ? ac : "-", vf ? vf : "-", d ? d : "-");
            if (exp_a && (!ac || !strstr(ac, exp_a))) { fprintf(stderr, "FAIL: expected audio codec '%s'\n", exp_a); rc_exit = 1; }
            if (exp_v && (!vf || strcmp(vf, exp_v)))  { fprintf(stderr, "FAIL: expected video format '%s'\n", exp_v); rc_exit = 1; }
            mpv_free(ac); mpv_free(vf); mpv_free(d);
        } else if (ev->event_id == MPV_EVENT_PLAYBACK_RESTART || ev->event_id == MPV_EVENT_AUDIO_RECONFIG
                   || ev->event_id == MPV_EVENT_VIDEO_RECONFIG) {
            char *w = prop(h, "width"), *sr = prop(h, "audio-params/samplerate");
            if (w && atoi(w) > 0) got_video = 1;
            if (sr && atoi(sr) > 0) got_audio = 1;
            mpv_free(w); mpv_free(sr);
        } else if (ev->event_id == MPV_EVENT_END_FILE) {
            mpv_event_end_file *e = ev->data;
            printf("decoded: audio=%d video=%d\n", got_audio, got_video);
            if (exp_v && !got_video) { fprintf(stderr, "FAIL: no decoded video\n"); rc_exit = 1; }
            if (exp_a && !got_audio) { fprintf(stderr, "FAIL: no decoded audio\n"); rc_exit = 1; }
            if (e->reason != MPV_END_FILE_REASON_EOF) {
                fprintf(stderr, "FAIL: end-file reason=%d error=%s\n", e->reason, mpv_error_string(e->error));
                rc_exit = rc_exit ? rc_exit : 2;
            }
            break;
        } else if (ev->event_id == MPV_EVENT_SHUTDOWN) break;
    }
#ifdef MMPV_SW_RENDER
    if (sw) {
        printf("sw render: frames=%ld nonblack=%ld\n", frames, nonzero);
        if (frames < 1 || nonzero < 1) { fprintf(stderr, "FAIL: sw render produced no picture\n"); rc_exit = 1; }
        mpv_render_context_free(rc);
    }
#endif
    mpv_terminate_destroy(h);
    printf("%s %s\n", rc_exit ? "FAILED" : "OK", file);
    return rc_exit;
}
