# Repository workflow notes

## Persistent MSHELL context

- Read `ACTIVE-CONTEXT.md` for the current evidence-based handoff before
  starting a long investigation. Keep it free of credentials, tokens, and
  user-specific private network information.
- Default branch is `alpine-redpill`; work on `main` or `master` only when the
  user explicitly selects it. Treat `tcrpfriend`, `tcrp-addons`,
  `tcrp-modules`, and `redpill-load` as separate worktrees.
- Do not commit, push, publish a release, or trigger a workflow unless the
  user explicitly requests that action.
- Prefer direct evidence from the affected image or device over inference. For
  DSM or TinyCore TTYD access, use `tools/ttyd-run.py`; record confirmed facts,
  source ownership, and unfinished validation in `ACTIVE-CONTEXT.md` before a
  long investigation or handoff.
- For module-load failures, separately verify the requesting addon, declared
  dependencies, live `modules.dep`, and module files included in the loader.
- Kernel-module pilots use the Ubuntu build host's root-owned
  `/root/mshell-modules` checkout as the authoritative build worktree. Do not
  use stale non-Git copies from ordinary user home directories as a source of
  truth.
- For a provider pilot, compile only from an exact matching DSM runtime
  `.config` and `Module.symvers` plus the corresponding Synology GPL source.
  Never resolve an `Unknown symbol` by copying a provider from another
  platform, DSM release, or kernel family.
- Treat a consumer `.ko` file as loadable only when all of its declared
  provider modules are present and compatible. A `modules.dep` entry by itself
  is not sufficient evidence because a partial pack can produce incomplete
  dependency metadata.
- Use `tools/prepare_release.py` for release preparation. Validate `.po`
  content before building `lang.tgz`; do not introduce literal `\\n\\n`
  sequences where gettext requires escaped multiline entries.

## `my.sh.gz` distribution policy

- Keep `my.sh.gz` tracked in the branch and available at its existing raw GitHub URL.
- Do not add `my.sh.gz` to `.gitignore` or remove it from Git tracking. Older deployed `menu.sh` versions depend on that URL and removing it can permanently prevent self-update.
- The build workflow may regenerate and commit `my.sh.gz`. Those automated commits can make the local branch fall behind and cause a non-fast-forward push or rebase requirement.
- Before committing or pushing changes, fetch the target branch and integrate any workflow-generated commits first (for example, `git fetch origin <branch>` followed by rebase or another explicitly safe integration).

## Paired functions files

- Any implementation or bug fix added to `functions.sh` must also be applied to `functions_t.sh` in the same change. Keep the production and test-track helper behavior synchronized; do not leave a functions-only fix in one file.
