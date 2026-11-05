#!/usr/bin/env bash
set -euo pipefail

plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(mktemp -d "${TMPDIR:-/tmp}/vim-git-changes-diff.XXXXXX")"
script="$(mktemp "${TMPDIR:-/tmp}/vim-git-changes-diff-vim.XXXXXX")"
out="$repo/.test-out"

cleanup() {
  rm -rf "$repo"
  rm -f "$script"
}
trap cleanup EXIT

if ! command -v git >/dev/null 2>&1; then
  echo "error: git is required" >&2
  exit 1
fi

if [ -z "${VIM_BIN:-}" ]; then
  if command -v vim >/dev/null 2>&1; then
    VIM_BIN=vim
  elif command -v nvim >/dev/null 2>&1; then
    VIM_BIN=nvim
  else
    echo "error: vim or nvim is required" >&2
    exit 1
  fi
fi

cd "$repo"
git init -q
git config user.name "vim-git-changes test"
git config user.email "test@example.com"

printf 'alpha\nbeta\ngamma\n' > a.txt
printf 'one\ntwo\n' > b.txt
printf 'old\n' > d.txt
printf 'alpha beta\n' > w.txt
printf 'alpha beta\n' > trail.txt
printf 'base\n' > stage.txt
printf 'base\n' > discard.txt
printf '\000\001old\n' > bin.dat
for i in $(seq 1 12); do printf 'line %s\n' "$i"; done > fold.txt
git add a.txt b.txt d.txt w.txt trail.txt stage.txt discard.txt bin.dat fold.txt
git commit -qm 'first'

printf 'alpha\nbeta\n' > a.txt
git add a.txt
git commit -qm 'second'

# Unstaged change
printf 'alpha\nBETA\ngamma\ndelta\n' > a.txt
# Staged change
printf 'one\nTWO\nthree\n' > b.txt
git add b.txt
# Untracked file
printf 'new file\n' > c.txt
# Staged deletion
git rm -q d.txt
# Whitespace-only unstaged change
printf 'alpha  beta\n' > w.txt
# Trailing-space-only unstaged change
printf 'alpha beta \n' > trail.txt
# Staging keys: start with an unstaged change
printf 'staged by key\n' > stage.txt
# Unstaged change for the D (discard) test
printf 'changed\n' > discard.txt
# Binary change
printf '\000\001new\n' > bin.dat
# A long unchanged block followed by one changed line, for fold tests
{
  for i in $(seq 1 11); do printf 'line %s\n' "$i"; done
  printf 'line 12 changed\n'
} > fold.txt

mkdir -p "$out"

cat > "$script" <<'VIM'
set nocompatible
let &runtimepath = $GCDIFF_PLUGIN . ',' . &runtimepath
runtime plugin/git_changes.vim
execute 'cd ' . fnameescape($GCDIFF_REPO)
let g:out = $GCDIFF_OUT
set diffopt+=iwhite
let g:base_diffopt = &g:diffopt

function! Wait() abort
  let n = 0
  while n < 100
    if exists('t:git_changes_file_diff') && !empty(t:git_changes_file_diff)
      let st = t:git_changes_file_diff
      if !has_key(st, 'job_diff-old') && !has_key(st, 'job_diff-new')
        break
      endif
    endif
    sleep 20m
    let n += 1
  endwhile
  " Let the redraw settle so diff_hlID() is meaningful.
  sleep 80m
endfunction

function! MaxDiffHl() abort
  for l in range(1, line('$'))
    let id = diff_hlID(l, 1)
    if id > 0
      return id
    endif
  endfor
  return 0
endfunction

function! Snap(name) abort
  let st = t:git_changes_file_diff
  let cur = win_getid()
  call win_gotoid(st.new_win)
  let hl = MaxDiffHl()
  let foldlevel = &l:foldlevel
  let closed = foldclosed(1)
  let closed_last = foldclosed(line('$'))
  call win_gotoid(cur)
  call writefile([
        \ 'kind=' . st.spec.new_kind,
        \ 'old_label=' . st.spec.old_label,
        \ 'new_label=' . st.spec.new_label,
        \ 'ignore=' . st.spec.ignore,
        \ 'cached=' . st.spec.cached,
        \ 'old=' . join(getbufline(st.old_buf, 1, '$'), '|'),
        \ 'new=' . join(getbufline(st.new_buf, 1, '$'), '|'),
        \ 'hl=' . hl,
        \ 'foldlevel=' . foldlevel,
        \ 'closed=' . closed,
        \ 'closedlast=' . closed_last,
        \ 'diffopt=' . &g:diffopt,
        \ ], g:out . '/' . a:name . '.txt')
  tabclose
endfunction

function! Run(name, cmd) abort
  execute a:cmd
  call Wait()
  call Snap(a:name)
endfunction

function! RunError(name, cmd) abort
  let v:errmsg = ''
  execute a:cmd
  sleep 150m
  let has_tab = exists('t:git_changes_file_diff')
        \ && !empty(t:git_changes_file_diff)
  call writefile([has_tab ? 'TAB' : 'NO_TAB', v:errmsg]
        \ + split(execute('messages'), "\n"),
        \ g:out . '/' . a:name . '.txt')
  if has_tab
    tabclose
  endif
endfunction

function! Press(key) abort
  let st = t:git_changes_file_diff
  call win_gotoid(st.new_win)
  execute 'normal ' . a:key
  call Wait()
endfunction

function! WaitMainDiff() abort
  let n = 0
  while n < 150
    let st = t:git_changes
    if !empty(get(st, 'shown_file', {}))
          \ && !has_key(st, 'job_diff-check')
          \ && !has_key(st, 'job_diff-old')
          \ && !has_key(st, 'job_diff-new')
      break
    endif
    sleep 20m
    let n += 1
  endwhile
  sleep 80m
endfunction

edit a.txt
call Run('default', 'GitChangesDiff')
call Run('ref1', 'GitChangesDiff HEAD~1')
call Run('ref2', 'GitChangesDiff HEAD~1 HEAD')

edit w.txt
call Run('plain-ws', 'GitChangesDiff')
call Run('b-ws', 'GitChangesDiff -b')
call Run('w-ws', 'GitChangesDiff -w')

edit trail.txt
call Run('plain-trail', 'GitChangesDiff')
call Run('b-trail', 'GitChangesDiff -b')

edit b.txt
" b.txt has staged changes; without --staged the command must still
" compare the index with the working tree (no implicit cached).
call Run('default-staged-file', 'GitChangesDiff')
call Run('staged', 'GitChangesDiff --staged')
call Run('cached', 'GitChangesDiff --cached')

edit b.txt
GitChangesDiff
call Wait()
call Press('dS')
call Snap('staged-toggle-on')

GitChangesDiff
call Wait()
call Press('dS')
call Press('dS')
call Snap('staged-toggle-off')

edit c.txt
call Run('untracked', 'GitChangesDiff')

edit d.txt
call Run('deleted-staged', 'GitChangesDiff --staged')

edit stage.txt
GitChangesDiff --staged
call Wait()
call Press('s')
call Snap('stage-key-s')

GitChangesDiff --staged
call Wait()
call Press('u')
call Snap('stage-key-u')

edit! discard.txt
GitChangesDiff
call Wait()
let g:git_changes_confirm_override = 2
call Press('D')
call Snap('discard-cancel')
call writefile(readfile('discard.txt'), g:out . '/discard-cancel-disk.txt')

edit! discard.txt
GitChangesDiff
call Wait()
let g:git_changes_confirm_override = 1
call Press('D')
call Snap('discard-yes')
call writefile(readfile('discard.txt'), g:out . '/discard-yes-disk.txt')
edit! discard.txt

edit fold.txt
call Run('regular-fold', 'GitChangesDiff')

let g:git_changes_fold = 0
edit a.txt
call Run('no-fold', 'GitChangesDiff')
let g:git_changes_fold = 1

edit bin.dat
call Run('binary', 'GitChangesDiff')

" Unsupported options fall back to the normal revision error path.
call RunError('stat', 'GitChangesDiff --stat')

" The save prompt: Skip keeps the disk version, Save writes the buffer.
edit a.txt
call append(line('$'), 'prompt-skip')
let g:git_changes_confirm_override = 2
execute 'GitChangesDiff'
call Wait()
call Snap('skip')
call writefile(readfile('a.txt'), g:out . '/skip-disk.txt')

edit! a.txt
call append(line('$'), 'prompt-save')
let g:git_changes_confirm_override = 1
execute 'GitChangesDiff'
call Wait()
call Snap('save')
call writefile(readfile('a.txt'), g:out . '/save-disk.txt')

" The main GitChanges diff panes follow the same fold option.
let g:git_changes_fold = 1
edit! a.txt
call writefile(['alpha', 'BETA', 'STAGED'], 'a.txt')
call system('git -C ' . shellescape($GCDIFF_REPO) . ' add -- a.txt')
call writefile(['alpha', 'BETA', 'STAGED', 'WORKTREE'], 'a.txt')
edit! a.txt
GitChanges
sleep 300m
let st = t:git_changes
call WaitMainDiff()
let path = st.shown_file.path
let head_lines = systemlist('git -C ' . shellescape($GCDIFF_REPO)
      \ . ' show HEAD:' . shellescape(path))
let index_lines = systemlist('git -C ' . shellescape($GCDIFF_REPO)
      \ . ' show :' . shellescape(path))
let worktree_lines = readfile(path)
let cached0 = get(st, 'diff_cached', 0)
let old0 = join(getbufline(st.old_buf, 1, '$'), '|')
let new0 = join(getbufline(st.new_buf, 1, '$'), '|')

call win_gotoid(st.new_win)
normal dS
sleep 300m
let st = t:git_changes
call WaitMainDiff()
let cached1 = get(st, 'diff_cached', 0)
let old1 = join(getbufline(st.old_buf, 1, '$'), '|')
let new1 = join(getbufline(st.new_buf, 1, '$'), '|')
let status1 = getwinvar(st.new_win, '&statusline')

normal dS
sleep 300m
let st = t:git_changes
call WaitMainDiff()
let cached2 = get(st, 'diff_cached', 0)
let new2 = join(getbufline(st.new_buf, 1, '$'), '|')

let before_discard = readfile(path)
let g:git_changes_confirm_override = 2
normal D
sleep 400m
let after_cancel = readfile(path)
let g:git_changes_confirm_override = 1
normal D
sleep 600m
let after_discard = readfile(path)

call writefile([
      \ 'path=' . path,
      \ 'cached0=' . cached0,
      \ 'cached1=' . cached1,
      \ 'cached2=' . cached2,
      \ 'head=' . join(head_lines, '|'),
      \ 'index=' . join(index_lines, '|'),
      \ 'worktree=' . join(worktree_lines, '|'),
      \ 'old0=' . old0,
      \ 'new0=' . new0,
      \ 'old1=' . old1,
      \ 'new1=' . new1,
      \ 'new2=' . new2,
      \ 'status1=' . status1,
      \ ], g:out . '/main-toggle.txt')
call writefile([
      \ 'path=' . path,
      \ 'worktree=' . join(worktree_lines, '|'),
      \ 'before=' . join(before_discard, '|'),
      \ 'cancel=' . join(after_cancel, '|'),
      \ 'discard=' . join(after_discard, '|'),
      \ 'index=' . join(index_lines, '|'),
      \ ], g:out . '/main-discard.txt')

let st = t:git_changes
let oldlevel = -1
let newlevel = -1
call win_execute(st.old_win, 'let oldlevel = &l:foldlevel')
call win_execute(st.new_win, 'let newlevel = &l:foldlevel')
call writefile(['old=' . oldlevel, 'new=' . newlevel],
      \ g:out . '/main-fold.txt')
GitChangesQuit

let g:git_changes_fold = 0
GitChanges
sleep 600m
let st = t:git_changes
let oldlevel = -1
let newlevel = -1
call win_execute(st.old_win, 'let oldlevel = &l:foldlevel')
call win_execute(st.new_win, 'let newlevel = &l:foldlevel')
call writefile(['old=' . oldlevel, 'new=' . newlevel],
      \ g:out . '/main-nofold.txt')
GitChangesQuit
let g:git_changes_fold = 1

call writefile(['base=' . g:base_diffopt, 'after=' . &g:diffopt],
      \ g:out . '/diffopt.txt')
qa!
VIM

export GCDIFF_PLUGIN="$plugin_dir"
export GCDIFF_REPO="$repo"
export GCDIFF_OUT="$out"

case "$(basename "$VIM_BIN")" in
  nvim|nvim-*)
    "$VIM_BIN" --headless -u NONE -c "source $script"
    ;;
  *)
    "$VIM_BIN" -Nu NONE -es -c "source $script"
    ;;
esac

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

value() {
  sed -n "s/^$2=//p" "$out/$1.txt" 2>/dev/null
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$name: expected [$expected], got [$actual]"
  fi
}

assert_not_zero() {
  local name="$1" actual="$2"
  if [ -z "$actual" ] || [ "$actual" -le 0 ]; then
    fail "$name: expected a positive number, got [$actual]"
  fi
}

assert_contains() {
  local name="$1" needle="$2" file="$3"
  grep -Fq "$needle" "$file" || fail "$name: expected [$needle] in $file"
}

assert_string_contains() {
  local name="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*) ;;
    *) fail "$name: expected [$needle] in [$hay]" ;;
  esac
}

assert_string_not_contains() {
  local name="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*) fail "$name: did not expect [$needle] in [$hay]" ;;
  esac
}

assert_eq "default kind" "worktree" "$(value default kind)"
assert_eq "default old label" "INDEX a.txt" "$(value default old_label)"
assert_eq "default new label" "WORKTREE a.txt" "$(value default new_label)"
assert_eq "default ignore" "" "$(value default ignore)"
assert_eq "default old" "alpha|beta" "$(value default old)"
assert_eq "default new" "alpha|BETA|gamma|delta" "$(value default new)"
assert_not_zero "default diff" "$(value default hl)"

assert_eq "single ref old label" "HEAD~1 a.txt" "$(value ref1 old_label)"
assert_eq "single ref new label" "WORKTREE a.txt" "$(value ref1 new_label)"
assert_eq "single ref old" "alpha|beta|gamma" "$(value ref1 old)"
assert_eq "single ref new" "alpha|BETA|gamma|delta" "$(value ref1 new)"

assert_eq "two refs old" "alpha|beta|gamma" "$(value ref2 old)"
assert_eq "two refs new" "alpha|beta" "$(value ref2 new)"
assert_eq "two refs kind" "ref" "$(value ref2 kind)"
assert_eq "two refs labels" "HEAD~1 a.txt|HEAD a.txt" "$(value ref2 old_label)|$(value ref2 new_label)"

assert_eq "-b whitespace ignore" "iwhite" "$(value b-ws ignore)"
assert_eq "-b whitespace diff" "0" "$(value b-ws hl)"
assert_eq "-w whitespace ignore" "iwhiteall" "$(value w-ws ignore)"
assert_eq "-w whitespace diff" "0" "$(value w-ws hl)"

assert_not_zero "plain whitespace diff" "$(value plain-ws hl)"
assert_string_not_contains "plain whitespace diffopt" "iwhite" "$(value plain-ws diffopt)"
assert_not_zero "plain trailing-space diff" "$(value plain-trail hl)"
assert_string_not_contains "plain trailing-space diffopt" "iwhite" "$(value plain-trail diffopt)"
assert_eq "-b trailing-space diff" "0" "$(value b-trail hl)"
assert_eq "-b trailing-space ignore" "iwhite" "$(value b-trail ignore)"
assert_string_contains "-b trailing-space diffopt" "iwhite" "$(value b-trail diffopt)"

assert_eq "no implicit cached kind" "worktree" "$(value default-staged-file kind)"
assert_eq "no implicit cached flag" "0" "$(value default-staged-file cached)"
assert_eq "no implicit cached old label" "INDEX b.txt" "$(value default-staged-file old_label)"
assert_eq "no implicit cached new label" "WORKTREE b.txt" "$(value default-staged-file new_label)"
assert_eq "no implicit cached old" "one|TWO|three" "$(value default-staged-file old)"
assert_eq "no implicit cached new" "one|TWO|three" "$(value default-staged-file new)"

assert_eq "staged kind" "index" "$(value staged kind)"
assert_eq "staged cached" "1" "$(value staged cached)"
assert_eq "cached kind" "index" "$(value cached kind)"
assert_eq "cached old" "one|two" "$(value cached old)"
assert_eq "cached new" "one|TWO|three" "$(value cached new)"

assert_eq "untracked old" "" "$(value untracked old)"
assert_eq "untracked new" "new file" "$(value untracked new)"
assert_eq "deleted staged old" "old" "$(value deleted-staged old)"
assert_eq "deleted staged new" "" "$(value deleted-staged new)"

assert_eq "stage key kind" "index" "$(value stage-key-s kind)"
assert_eq "stage key cached" "1" "$(value stage-key-s cached)"
assert_eq "stage key new" "staged by key" "$(value stage-key-s new)"
assert_eq "unstage key kind" "index" "$(value stage-key-u kind)"
assert_eq "unstage key cached" "1" "$(value stage-key-u cached)"
assert_eq "unstage key new" "base" "$(value stage-key-u new)"

assert_eq "dS toggle on kind" "index" "$(value staged-toggle-on kind)"
assert_eq "dS toggle on cached" "1" "$(value staged-toggle-on cached)"
assert_eq "dS toggle on old" "one|two" "$(value staged-toggle-on old)"
assert_eq "dS toggle on new" "one|TWO|three" "$(value staged-toggle-on new)"
assert_eq "dS toggle on labels" "HEAD b.txt|INDEX b.txt" "$(value staged-toggle-on old_label)|$(value staged-toggle-on new_label)"
assert_eq "dS toggle off kind" "worktree" "$(value staged-toggle-off kind)"
assert_eq "dS toggle off cached" "0" "$(value staged-toggle-off cached)"
assert_eq "dS toggle off old" "one|TWO|three" "$(value staged-toggle-off old)"
assert_eq "dS toggle off new" "one|TWO|three" "$(value staged-toggle-off new)"
assert_eq "dS toggle off labels" "INDEX b.txt|WORKTREE b.txt" "$(value staged-toggle-off old_label)|$(value staged-toggle-off new_label)"

assert_eq "discard cancel new" "changed" "$(value discard-cancel new)"
assert_contains "discard cancel keeps file" "changed" "$out/discard-cancel-disk.txt"
assert_eq "discard yes old" "base" "$(value discard-yes old)"
assert_eq "discard yes new" "base" "$(value discard-yes new)"
assert_contains "discard yes restores file" "base" "$out/discard-yes-disk.txt"
assert_eq "binary old" "(binary file - no side-by-side diff)" "$(value binary old)"
assert_eq "binary new" "(binary file - no side-by-side diff)" "$(value binary new)"

assert_eq "regular fold level" "0" "$(value default foldlevel)"
assert_eq "regular fold on long file" "0" "$(value regular-fold foldlevel)"
assert_not_zero "regular fold closed" "$(value regular-fold closed)"
assert_eq "regular fold keeps changes visible" "-1" "$(value regular-fold closedlast)"
assert_eq "fold option disabled" "99" "$(value no-fold foldlevel)"

assert_eq "unsupported option" "NO_TAB" "$(head -n 1 "$out/stat.txt")"
assert_contains "unsupported option message" "unknown revision: --stat" "$out/stat.txt"

assert_eq "skip diff" "alpha|BETA|gamma|delta" "$(value skip new)"
if grep -Fq "prompt-skip" "$out/skip-disk.txt"; then
  fail "skip wrote the buffer to disk"
fi
assert_eq "save diff" "alpha|BETA|gamma|delta|prompt-save" "$(value save new)"
assert_contains "save wrote the buffer" "prompt-save" "$out/save-disk.txt"

assert_eq "diffopt restored" "$(value diffopt base)" "$(value diffopt after)"

assert_eq "main fold old" "0" "$(value main-fold old)"
assert_eq "main fold new" "0" "$(value main-fold new)"
assert_eq "main nofold old" "99" "$(value main-nofold old)"
assert_eq "main nofold new" "99" "$(value main-nofold new)"

assert_eq "main toggle path" "a.txt" "$(value main-toggle path)"
assert_eq "main toggle cached off" "0" "$(value main-toggle cached0)"
assert_eq "main toggle cached on" "1" "$(value main-toggle cached1)"
assert_eq "main toggle cached back" "0" "$(value main-toggle cached2)"
assert_eq "main toggle old" "$(value main-toggle index)" "$(value main-toggle old0)"
assert_eq "main toggle old cached" "$(value main-toggle head)" "$(value main-toggle old1)"
if [ "$(value main-toggle head)" = "$(value main-toggle index)" ]; then
  fail "main toggle: HEAD and index should differ for this test"
fi
assert_eq "main toggle worktree" "$(value main-toggle worktree)" "$(value main-toggle new0)"
assert_eq "main toggle index" "$(value main-toggle index)" "$(value main-toggle new1)"
assert_eq "main toggle back" "$(value main-toggle worktree)" "$(value main-toggle new2)"
assert_string_contains "main toggle status" "INDEX a.txt" "$(value main-toggle status1)"

assert_eq "main discard before" "$(value main-discard worktree)" "$(value main-discard before)"
assert_eq "main discard cancel" "$(value main-discard worktree)" "$(value main-discard cancel)"
assert_eq "main discard index" "$(value main-discard index)" "$(value main-discard discard)"
if [ "$(value main-discard before)" = "$(value main-discard index)" ]; then
  fail "main discard: file had no unstaged changes to discard"
fi

echo "ok: GitChangesDiff tests passed"
