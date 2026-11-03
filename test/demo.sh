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
echo "  t            toggle tree/list view"
echo "  s / u / -    stage / unstage / toggle stage"
echo "  r            refresh status"
echo "  d            discard unstaged changes / delete untracked file"
echo "  o            open current file in a new tab (also in diff)"
echo "  yy           copy file path"
echo "  c / p / P    commit / pull / push (all left panes, remote for p/P)"
echo "  J / K        scroll the side-by-side diff (lazygit style)"
echo "  Ctrl-d/u     scroll the diff by half a page (file list)"
echo "  Ctrl-w j     move to the commit list; another Ctrl-w j to branches"
echo "  Tab / S-Tab  cycle focus among the left panes"
echo "  1 / 2 / 3    jump to files / commits / branches (left panes)"
echo "               branch: j/k select, Enter show, co checkout,"
echo "               n new, d delete, yy copy name"
echo "  n/p/P/c      work in files, commits, and branches"
echo "  :GitChangesQuit  quit the whole tab"
echo
echo "After quitting, try: :GitChanges HEAD~2 HEAD"
echo

vim -N -u "$vimrc" -c 'GitChanges'
