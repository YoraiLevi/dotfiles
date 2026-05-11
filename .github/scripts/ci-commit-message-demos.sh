#!/usr/bin/env bash
# Run after timer install + unit tests. Exercises auto-commit message shapes; prints subject/body to CI logs.
set -euo pipefail

G="${HOME}/.dotfiles"
WT="${HOME}"
AC="${G}/.auto-commit.sh"

dump_msg() {
  local title="$1"
  echo "::group::${title}"
  echo "--- subject (git log -1 --pretty=%s) ---"
  git --git-dir="$G" --work-tree="$WT" log -1 --pretty=%s
  echo "--- body (git log -1 --pretty=%b) ---"
  git --git-dir="$G" --work-tree="$WT" log -1 --pretty=%b
  echo "::endgroup::"
}

echo "ci-commit-message-demos.sh: auto-commit script=${AC}"

# --- modified only ---
echo "patch-demo" >> "${WT}/README.md"
bash "$AC"
dump_msg "Sample A: modified tracked file (mod)"

# --- new tracked file (manual git add required before commit; auto-commit uses git add -u) ---
echo "ci-demo-added" > "${WT}/.ci-demo-added.txt"
git --git-dir="$G" --work-tree="$WT" add "${WT}/.ci-demo-added.txt"
bash "$AC"
dump_msg "Sample B: new tracked file (add)"

# --- deletion ---
rm -f "${WT}/.ci-demo-added.txt"
bash "$AC"
dump_msg "Sample C: deleted file (del)"

# --- rename ---
cd "${WT}"
git --git-dir="$G" --work-tree="$WT" mv README.md README.ci-demo-renamed.md
bash "$AC"
dump_msg "Sample D: rename (ren)"

# --- many paths → long / truncated subject ---
for i in $(seq -f '%02g' 1 35); do
  echo "long-${i}" > "${WT}/.ci-long-${i}.txt"
done
git --git-dir="$G" --work-tree="$WT" add "${WT}"/.ci-long-*.txt
bash "$AC"
dump_msg "Sample E: many adds (truncated subject when >160 chars)"

# --- combined add + mod + del in one commit ---
echo "combo-edit" >> "${WT}/README.ci-demo-renamed.md"
echo "combo-new" > "${WT}/.ci-combo-new.txt"
git --git-dir="$G" --work-tree="$WT" add "${WT}/.ci-combo-new.txt"
rm -f "${WT}/.ci-long-01.txt"
bash "$AC"
dump_msg "Sample F: add + mod + del together"

echo "ci-commit-message-demos.sh: finished"
