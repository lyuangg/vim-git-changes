#!/usr/bin/env bash
set -euo pipefail

plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v git >/dev/null 2>&1; then
  echo "error: git is required" >&2
  exit 1
fi
if ! command -v vim >/dev/null 2>&1; then
  echo "error: vim is required" >&2
  exit 1
fi

repo="$(mktemp -d "${TMPDIR:-/tmp}/vim-git-changes-demo.XXXXXX")"
vimrc="$(mktemp "${TMPDIR:-/tmp}/vim-git-changes-vimrc.XXXXXX")"

cleanup() {
  rm -rf "$repo"
  rm -f "$vimrc"
}
trap cleanup EXIT

cd "$repo"
git init -q
git config user.name "Git Changes Demo"
git config user.email "demo@example.com"

printf 'alpha\nbeta\n' > a.txt
git add a.txt
git commit -qm 'first: add a.txt'

printf 'alpha\nbeta\ngamma\n' > a.txt
printf 'bee\n' > b.txt
git add a.txt b.txt
git commit -qm 'second: modify a.txt, add b.txt'

git mv a.txt c.txt
git rm -q b.txt
printf 'delta\n' > d.txt
git add d.txt
git commit -qm 'third: rename a.txt, delete b.txt, add d.txt'

for i in $(seq 1 80); do
  printf 'line %s\n' "$i"
done > big.txt
git add big.txt
git commit -qm 'fourth: add big.txt for J/K scrolling'

for i in $(seq 81 120); do
  printf 'line %s\n' "$i"
done >> big.txt
rm -f d.txt
printf 'untracked demo\n' > notes.txt

escaped_plugin_dir="${plugin_dir// /\\ }"
{
  echo 'set nocompatible'
  printf 'set runtimepath^=%s\n' "$escaped_plugin_dir"
  echo 'runtime plugin/git_changes.vim'
  echo 'syntax on'
  echo 'filetype plugin indent on'
} > "$vimrc"

echo "Demo repository: $repo"
echo "The GitChanges tab will open automatically on WORK (working tree changes)."
echo
echo "Try:"
echo "  j / k        move between files"
echo "  ?            show/hide help"
echo "  Esc          back to working tree changes"
echo "  t            toggle tree/list view"
echo "  s / u / -    stage / unstage / toggle stage"
echo "  S / U        stage / unstage all files"
echo "  r            refresh files / commits / branches"
echo "  d            discard unstaged changes / delete untracked file"
echo "  o            open current file in a new tab (also in diff)"
echo "  yy           copy file path"
echo "  c / C        commit with prompt / editor"
echo "  p / P        pull / push (all left panes, remote)"
echo "  J / K        scroll the side-by-side diff (lazygit style)"
echo "  H / L        scroll the diff left / right"
echo "  Ctrl-d/u     scroll the diff by half a page (file list)"
echo "  Ctrl-w j     move to the commit list; another Ctrl-w j to branches"
echo "  Tab / S-Tab  cycle focus through all panes, including diff"
echo "  1 / 2 / 3    jump to files / commits / branches (left panes)"
echo "               branch: j/k select, Enter show, co checkout,"
echo "               n new, d delete, yy copy name"
echo "               commit: e edit message"
echo "  n/p/P/c      work in files, commits, and branches"
echo "  zR / zM      expand / fold unchanged blocks in the diff"
echo "  dS           toggle WORK diff: index<->worktree / HEAD<->index"
echo "  D            discard unstaged changes for the selected file"
echo "  gs           open the main GitChanges view"
echo "  q / :GitChangesQuit  quit the whole tab (q also in diff)"
echo
echo "After quitting, try: :GitChanges HEAD~2 HEAD"
echo
echo "File diff commands (run from a file buffer, e.g. :edit big.txt):"
echo "  :GitChangesDiff          index <-> working tree (plain git diff)"
echo "  :GitChangesDiff --staged HEAD <-> index"
echo "  :GitChangesDiff -b       ignore whitespace amount"
echo "  q / r                    close the diff tab / re-read both sides"
echo "  s / u                    stage / unstage the file, then re-diff"
echo "  o                        open the file at the cursor line"
echo "  cc / C                   commit staged changes (prompt / editor)"
echo "  gs                       open the main GitChanges view"
echo "  dS                       toggle git diff / git diff --staged"
echo "  D                        discard unstaged changes (confirmation)"
echo "  zR / zM                  expand / fold unchanged blocks"
echo

vim -N -u "$vimrc" -c 'GitChanges'
