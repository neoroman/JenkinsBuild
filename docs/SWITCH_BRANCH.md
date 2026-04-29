# Develop / release branch switch tool

**Languages:** [한국어 (SWITCH_BRANCH.ko.md)](SWITCH_BRANCH.ko.md)

The entry point is `switch.sh` at the repository root of this submodule. It embeds the Python helper logic (formerly a separate module) via heredoc and `mktemp`, so it runs as a **single script** with no external Python file dependency.

The tool keeps **release vs develop** source differences in a **rules file**, then patches or restores the **current branch working tree** of the same repository. Develop-only changes are meant to stay local and not be committed to the remote.

## Quick start walkthrough

Assume the parent app repository is **REPO_ROOT** and this repo is checked out as the `jenkins/` submodule (as in the main [README](../README.md)). If you work **only** inside a standalone JenkinsBuild clone, your cwd is already the repo root—use `./update.sh` and `./switch.sh` **without** the `jenkins/` prefix.

1. From your working copy, `cd` to **REPO_ROOT** and run `./jenkins/update.sh` to refresh the submodule and ensure you have the latest `switch.sh`.
2. The workflow does not depend on which branch is checked out in the app repo; decide **release** and **develop** branch names up front (e.g. `master`, `develop/main`).
3. Dry-run config generation: `./jenkins/switch.sh --mode generate-config --release-branch master --develop-branch develop/main --dry-run` — fix any errors before continuing.
4. Generate config: `./jenkins/switch.sh --mode generate-config --release-branch master --develop-branch develop/main`
5. Confirm `dev_switch.config` was created (path is relative to where you ran the command—typically under `jenkins/` or the repo root you used).
6. Apply **develop** mode on the current branch: `./jenkins/switch.sh --mode develop` (changes from `dev_switch.config` apply to the current working tree).
7. Before committing to GitHub, apply **release** mode to drop develop-only / test code: `./jenkins/switch.sh --mode release`
8. `dev_switch.config.zip` is produced; develop-mode file changes are reverted.
9. `git add` / `commit` / `push`, including `dev_switch.config.zip`, `.gitignore`, and any other intended files.

## Flow

1. **Once** `--mode generate-config`: by default reads `[repo]` from `dev_switch.config.default` next to `switch.sh` (`push_url`, `release_branch` / `production_branch`, `develop_branch`), clones each branch under `.generate-config/<branch-path>/`, compares trees, and writes `dev_switch.config` at the repo root. To use only two local directories, pass `--release-dir` and `--develop-dir`. Generation appends `/dev_switch.config`, `/dev_switch.config.zip`, and `.generate-config/` to `.gitignore` when needed.
2. On any branch, `--mode develop` applies release→develop substitutions; `--mode release` reverses develop→release.
3. After **`--mode release`**, the root `dev_switch.config` is packed into a **password-protected zip** (`dev_switch.config.zip`; password is `ZIP_PASSWORD` in `switch.sh`), and the plain `dev_switch.config` is removed.
4. **`--mode develop`** unpacks `dev_switch.config.zip` if present, then applies rules.

## Quick usage

```bash
# Summary diff (needs dev_switch.config at repo root, or --config)
./switch.sh --mode compare

# Preview develop patch only
./switch.sh --mode develop --dry-run

# Develop apply + round-trip check
./switch.sh --mode verify-develop --release-branch master --develop-branch develop/main

# Restore release (+ archive config to zip and delete plain file)
./switch.sh --mode release

# One-off config generation (default: clone via dev_switch.config.default → dev_switch.config)
./switch.sh --mode generate-config

# Compare using the sample defaults file
./switch.sh --mode compare --config ./dev_switch.config.default
```

## Config files

- Template: `./dev_switch.config.default` (adjust `[repo]` URL and branches for your app; iOS/Android paths must match for `generate-config` to be meaningful).
- Generated / active config: `./dev_switch.config` (sensitive; do not commit — see `.gitignore`).
- After release: `./dev_switch.config.zip` (kept by the script).

INI format: `rule.*` sections with `file`, `release`, and `develop` keys (`prod` / `dev` aliases supported).

## Python-only invocation (optional)

Normal use is via `switch.sh`. Direct `python3` against an extracted helper is for debugging only.
