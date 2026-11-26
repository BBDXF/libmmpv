# 上游跟踪
- 版本固定在 `upstream.lock`；改版本只改这一个文件。
- `scripts/rebase.sh <mpv-ref> [ffmpeg-ref]`：只做"补丁还能否 apply + 选项名/组件名是否仍存在"的干跑，不编译。
- `.github/workflows/upstream-watch.yml` 每周对 mpv master 跑一遍 rebase.sh，失败则自动开 issue。
- 补丁只放在 `common/patches/<proj>/`（两个 profile 共享）或 `<profile>/patches/<proj>/`（专属）。
- 升级 mpv 小版本时的步骤：改 `upstream.lock` → 运行 rebase.sh → 若补丁失败，在 mpv 源码树里手改后 `git diff` 重新导出补丁。
