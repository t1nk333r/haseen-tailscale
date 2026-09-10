# UPSTREAM — `t1nk33r.tailscale`

- **plugin id**: `t1nk33r.tailscale`
- **plugin version**: `1.0.0`
- **declared upstream id** (`omarchy.clonedFrom`): `omarchy.tailscale`
- **ownership**: cloned into `~/.config/omarchy/plugins/t1nk33r.tailscale` by `omarchy plugin add` (row in `packages/omarchy-plugins.txt`); its own git repo — **fork repo (origin)**: `https://github.com/t1nk333r/omarchy-tailscale.git`
- **upstream**: clone of the first-party `omarchy.tailscale` (no third-party git upstream) — the fork's origin is the owner's own repo, so nothing upstream can be rebased onto
- **tracking branch**: `main` (local HEAD `9bed077a3d8d`) against its own `origin`
- **baseline commit**: `943ad47c5d155a2f4be12003d6e9e93c4f403740` = the `origin/main` tip (plan 119 §3) — there is no third-party upstream to drift from; the real baseline for a first-party clone is the installed `omarchy` package (4.0.3)
- **drift at the last report (plans 119–120)**: ahead 2, behind 0

## Fork / local commits (newest first, `refs/upstream/<branch>..HEAD`)

- `9bed077 Move the settings behind a cog, and stop hover from moving the keyboard cursor`
- `bc7dae7 Port preference switches, login-server rebinding, keyboard model and exit-node discipline`

## Patch records

- none — no unpushed local commit needs recording for this plugin

## Restore / update notes

- Restore: `omarchy plugin add` from the owner's repo restores the current history; `origin main` — 2 commits.
- **Unpushed commits owed** (plan 120's gate, nothing pushed): `origin main` — 2 commits.
- Upstream drift is measured read-only by `~/.local/share/waydots/tools/plugin-upstream-report.sh`; run it before any rebase (plan 119's `plans/notes/119-upstream-status.md` is the pinned baseline).
- Never push a third-party clone; a local rebase of one is a deployment change and belongs in `packages/plugin-patches/`.
- Written by plan 124 (2026-09-11); topology from plan 119, re-verified read-only by plan 124.
