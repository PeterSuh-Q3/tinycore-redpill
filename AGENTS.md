# Repository workflow notes

## `my.sh.gz` distribution policy

- Keep `my.sh.gz` tracked in the branch and available at its existing raw GitHub URL.
- Do not add `my.sh.gz` to `.gitignore` or remove it from Git tracking. Older deployed `menu.sh` versions depend on that URL and removing it can permanently prevent self-update.
- The build workflow may regenerate and commit `my.sh.gz`. Those automated commits can make the local branch fall behind and cause a non-fast-forward push or rebase requirement.
- Before committing or pushing changes, fetch the target branch and integrate any workflow-generated commits first (for example, `git fetch origin <branch>` followed by rebase or another explicitly safe integration).

## Paired functions files

- Any implementation or bug fix added to `functions.sh` must also be applied to `functions_t.sh` in the same change. Keep the production and test-track helper behavior synchronized; do not leave a functions-only fix in one file.
