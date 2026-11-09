#!/usr/bin/env bash
set -euo pipefail

plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(mktemp -d "${TMPDIR:-/tmp}/vim-git-changes-smoke.XXXXXX")"
other="$(mktemp -d "${TMPDIR:-/tmp}/vim-git-changes-smoke-other.XXXXXX")"
script="$(mktemp "${TMPDIR:-/tmp}/vim-git-changes-smoke-vim.XXXXXX")"
out="$(mktemp -d "${TMPDIR:-/tmp}/vim-git-changes-smoke-out.XXXXXX")"

cleanup() { rm -rf "$repo" "$other" "$script" "$out"; }
trap cleanup EXIT

if [ -z "${VIM_BIN:-}" ]; then
  if command -v vim >/dev/null 2>&1; then VIM_BIN=vim; else VIM_BIN=nvim; fi
fi

(
  cd "$other"
  git init -q
  git config user.name "other"
  git config user.email "other@example.com"
  printf 'other\n' > other.txt
  git add other.txt
  git commit -qm 'other'
)

cd "$repo"
git init -q
git config user.name "smoke"
git config user.email "smoke@example.com"
printf 'alpha\nbeta\ngamma\n' > a.txt
printf 'one\ntwo\n' > b.txt
git add a.txt b.txt
git commit -qm 'first'
printf 'one\nTWO\n' > b.txt
git commit -qam 'second'
printf 'alpha\nBETA\ngamma\n' > a.txt
printf 'one\nSTAGED\n' > b.txt
git add b.txt

# Create a second branch with a different a.txt without touching the worktree.
tmp_index="$(mktemp "${TMPDIR:-/tmp}/vim-git-changes-smoke-index.XXXXXX")"
blob=$(printf 'alpha\nOTHER\ngamma\n' | git hash-object -w --stdin)
GIT_INDEX_FILE="$tmp_index" git read-tree HEAD
GIT_INDEX_FILE="$tmp_index" git update-index --add --cacheinfo "100644,$blob,a.txt"
tree=$(GIT_INDEX_FILE="$tmp_index" git write-tree)
other_commit=$(printf 'other branch\n' | git commit-tree "$tree" -p HEAD)
git branch other "$other_commit"
cur_branch=$(git rev-parse --abbrev-ref HEAD)
git branch sametip HEAD
rm -f "$tmp_index"

cat > "$script" <<'VIM'
set nocompatible
set noswapfile
let &runtimepath = $GC_PLUGIN . ',' . &runtimepath
runtime plugin/git_changes.vim
execute 'cd ' . fnameescape($GC_REPO)
let g:out = $GC_OUT
let g:repo = $GC_REPO
let g:other = $GC_OTHER
let g:cur_branch = $GC_BRANCH
let g:sametip = $GC_SAMETIP
let g:git_changes_statusline_delay = 0
let g:git_changes_refresh_debounce_ms = 0
let g:git_changes_debounce_ms = 0

function! WaitMain() abort
  let n = 0
  while n < 200
    if exists('t:git_changes') && !empty(t:git_changes)
      let st = t:git_changes
      if !has_key(st, 'job_commits-log') && !has_key(st, 'job_branches')
            \ && !has_key(st, 'job_files') && !has_key(st, 'job_files-body')
        break
      endif
    endif
    sleep 20m
    let n += 1
  endwhile
  sleep 100m
endfunction

function! WaitDiff() abort
  let n = 0
  while n < 200
    if exists('t:git_changes_file_diff') && !empty(t:git_changes_file_diff)
      let st = t:git_changes_file_diff
      if !has_key(st, 'job_diff-old') && !has_key(st, 'job_diff-new')
        break
      endif
    endif
    sleep 20m
    let n += 1
  endwhile
  sleep 100m
endfunction

let result = []
function! Check(name, ok, detail) abort
  call add(g:result, (a:ok ? 'ok  ' : 'FAIL') . ' ' . a:name . (a:ok ? '' : ': ' . a:detail))
endfunction

" --- statusline and blame -------------------------------------------------
edit a.txt
let sl = git_changes#statusline()
call Check('statusline', sl =~# '^\[Git(' , sl)

let sl_marker = ''
for i in range(30)
  sleep 100m
  let sl_marker = git_changes#statusline()
  if sl_marker =~# '\*'
    break
  endif
endfor
call Check('statusline unstaged marker', sl_marker =~# '\*', sl_marker)

let info = git_changes#blame_line_info()
call Check('blame sync author', get(info, 'author', '') ==# 'smoke', string(info))
call Check('blame sync sha', strlen(get(info, 'sha', '')) == 8, string(info))

let a1 = git_changes#blame_line_async()
let a2 = ''
for i in range(40)
  sleep 100m
  let a2 = git_changes#blame_line_async()
  if !empty(a2)
    break
  endif
endfor
call Check('blame async', a2 =~# 'smoke', a2)

" --- scratch buffer updates -----------------------------------------------
let tbuf = bufadd('git_changes_set_lines_test')
call bufload(tbuf)
let r1 = git_changes#core_set_lines(tbuf, ['a', 'b'])
let r2 = git_changes#core_set_lines(tbuf, ['a', 'b'])
let r3 = git_changes#core_set_lines(tbuf, ['a', 'c'])
let r4 = git_changes#core_set_lines(tbuf, ['a'])
call Check('set_lines caching',
      \ [r1, r2, r3, r4] == [1, 0, 1, 1]
      \ && getbufline(tbuf, 1, '$') == ['a'],
      \ string([r1, r2, r3, r4]))
execute 'silent! bwipeout! ' . tbuf

" --- blame pane -----------------------------------------------------------
GitChangesBlame
let bp = get(b:, 'git_changes_blame', {})
call Check('blame pane opened', !empty(bp) && bp.path ==# 'a.txt', string(bp))
for i in range(50)
  if empty(get(get(bp, 'state', {}), 'job_blame_pane', 0))
    break
  endif
  sleep 100m
endfor
let pane_lines = getbufline(bp.buf, 1, '$')
call Check('blame pane content', join(pane_lines, ' ') =~# 'smoke',
      \ join(pane_lines, ' '))
call win_gotoid(bp.win)
normal q
call Check('blame pane closes', empty(getwininfo(bp.win)), 'window still exists')

" --- main view ------------------------------------------------------------
GitChanges
call WaitMain()
let st = t:git_changes
call Check('main commits loaded', len(st.commits) >= 2, len(st.commits))
call Check('main files loaded', len(st.files) == 2,
      \ len(st.files) . ' [' . join(map(copy(st.files), 'v:val.path'), ',') . ']')

let commit_lines = filter(getbufline(st.commits_buf, 1, '$'),
      \ 'v:val =~# "second$"')
call Check('commit list author column',
      \ !empty(commit_lines) && commit_lines[0] =~# '^\s*\S\+\s\+smoke\s\+second$',
      \ join(commit_lines, ' / '))

call win_gotoid(st.files_win)
call Check('files map stage', !empty(maparg('s', 'n')), 's')
call Check('files map refresh', !empty(maparg('r', 'n')), 'r')
call Check('files map diff', !empty(maparg('gd', 'n')), 'gd')
call Check('files ctrl-d unmapped', empty(maparg('<C-d>', 'n')), maparg('<C-d>', 'n'))
call Check('files ctrl-u unmapped', empty(maparg('<C-u>', 'n')), maparg('<C-u>', 'n'))

normal 4
call Check('files key 4 jumps to diff', win_getid() == st.new_win,
      \ string(win_getid()) . ' new=' . st.new_win)
call win_gotoid(st.old_win)
normal 4
call Check('diff key 4 moves to new', win_getid() == st.new_win,
      \ string(win_getid()) . ' new=' . st.new_win)

call win_gotoid(st.new_win)
normal 1
call Check('diff key 1 jumps to files', win_getid() == st.files_win,
      \ string(win_getid()) . ' files=' . st.files_win)
call win_gotoid(st.new_win)
normal 2
call Check('diff key 2 jumps to commits', win_getid() == st.commits_win,
      \ string(win_getid()) . ' commits=' . st.commits_win)
call win_gotoid(st.new_win)
normal 3
call Check('diff key 3 jumps to branches', win_getid() == st.branches_win,
      \ string(win_getid()) . ' branches=' . st.branches_win)
call win_gotoid(st.files_win)

" Exercise the generated stage/unstage mapping arguments.
normal s
let staged = systemlist(['git', '-C', g:repo, 'diff', '--cached', '--name-only'])
call Check('main stage key', index(staged, 'a.txt') >= 0, join(staged, ','))
normal u
let staged = systemlist(['git', '-C', g:repo, 'diff', '--cached', '--name-only'])
call Check('main unstage key', index(staged, 'a.txt') < 0, join(staged, ','))

" Refresh keeps the selected commit and file.
let before_commit = st.commit_index
normal r
sleep 300m
call Check('main refresh key',
      \ st.commit_index == before_commit && len(st.files) == 2,
      \ 'commit=' . st.commit_index . ' files=' . len(st.files))

" The diff panes refresh with r as well.
for win in [st.old_win, st.new_win]
  call win_gotoid(win)
  call Check('diff pane map refresh', !empty(maparg('r', 'n')), maparg('r', 'n'))
  call Check('diff pane map co',
        \ maparg('co', 'n') =~# 'GitChangesBranchCheckout', maparg('co', 'n'))
  call Check('diff pane map M',
        \ maparg('M', 'n') =~# 'GitChangesBranchMerge', maparg('M', 'n'))
endfor
call win_gotoid(st.new_win)
let before_commit = st.commit_index
normal r
sleep 300m
call Check('diff pane refresh key',
      \ st.commit_index == before_commit && len(st.files) == 2,
      \ 'commit=' . st.commit_index . ' files=' . len(st.files))
call win_gotoid(st.files_win)

" co prompts for a branch everywhere except the branch list.
call Check('files map co',
      \ maparg('co', 'n') =~# 'GitChangesBranchCheckout', maparg('co', 'n'))
call win_gotoid(st.commits_win)
call Check('commits map co',
      \ maparg('co', 'n') =~# 'GitChangesBranchCheckout', maparg('co', 'n'))
call win_gotoid(st.branches_win)
call Check('branches co unchanged',
      \ maparg('co', 'n') !~# 'GitChangesBranchCheckout', maparg('co', 'n'))
call win_gotoid(st.files_win)

let g:git_changes_input_override = g:sametip
normal co
call WaitMain()
let head = trim(system('git -C ' . g:repo . ' rev-parse --abbrev-ref HEAD'))
call Check('co switches branch', head ==# g:sametip, head)
let g:git_changes_input_override = g:cur_branch
normal co
call WaitMain()
let head = trim(system('git -C ' . g:repo . ' rev-parse --abbrev-ref HEAD'))
call Check('co switches back', head ==# g:cur_branch, head)

" M merges a typed branch everywhere except the branch list.
call Check('files map M',
      \ maparg('M', 'n') =~# 'GitChangesBranchMerge', maparg('M', 'n'))
call win_gotoid(st.commits_win)
call Check('commits map M',
      \ maparg('M', 'n') =~# 'GitChangesBranchMerge', maparg('M', 'n'))
call win_gotoid(st.branches_win)
call Check('branches M unchanged',
      \ maparg('M', 'n') !~# 'GitChangesBranchMerge', maparg('M', 'n'))
call win_gotoid(st.files_win)

let g:git_changes_input_override = g:sametip
let g:git_changes_confirm_override = 1
normal M
call WaitMain()
call Check('M merges branch', st.status =~# 'Merged branch: ' . g:sametip,
      \ st.status)

" statusline text should be set for the files pane
let pane_sl = getwinvar(st.files_win, '&statusline')
call Check('pane statusline', pane_sl =~# 'Files', pane_sl)

" ]c / [c move the diff cursor without leaving the files pane.
call win_gotoid(st.files_win)
call Check('files map ]c', !empty(maparg(']c', 'n')), maparg(']c', 'n'))
call Check('files map [c', !empty(maparg('[c', 'n')), maparg('[c', 'n'))
for i in range(50)
  if !has_key(st, 'job_diff-old') && !has_key(st, 'job_diff-new')
    break
  endif
  sleep 50m
endfor
call win_execute(st.new_win, 'silent! call cursor(1, 1)')
normal ]c
let hunk_next_line = 0
call win_execute(st.new_win, 'let hunk_next_line = line(".")')
call Check('files ]c jumps to next hunk', hunk_next_line > 1,
      \ string(hunk_next_line))
let hunk_last = len(getbufline(st.new_buf, 1, '$'))
call win_execute(st.new_win, 'silent! normal! G')
normal [c
let hunk_prev_line = 0
call win_execute(st.new_win, 'let hunk_prev_line = line(".")')
call Check('files [c jumps to previous hunk',
      \ hunk_prev_line > 1 && hunk_prev_line < hunk_last,
      \ string(hunk_prev_line) . ' last=' . hunk_last)
call win_gotoid(st.files_win)

let v:errmsg = ''
doautocmd VimResized
call Check('resize main view', empty(v:errmsg), v:errmsg)

" gd must still open the editable file diff after the module split.
call win_gotoid(st.files_win)
call cursor(st.files_header + 1, 1)
normal gd
call WaitDiff()
let gd_state = get(t:, 'git_changes_file_diff', {})
let gd_spec = get(gd_state, 'spec', {})
call Check('main gd opens file diff',
      \ !empty(gd_state) && !empty(get(gd_spec, 'path', '')),
      \ string(gd_spec))
execute 'GitChangesDiffQuit'

GitChangesQuit
call Check('main quit', !exists('t:git_changes'), 'tab still open')

" --- gd on a commit entry ------------------------------------------------
GitChanges
call WaitMain()
let hs = t:git_changes
call win_gotoid(hs.commits_win)
normal j
for i in range(50)
  if hs.commit_index == 1 && !empty(hs.files)
    break
  endif
  sleep 100m
endfor
call Check('commit entry selected', hs.commit_index == 1,
      \ 'index=' . hs.commit_index)
call win_gotoid(hs.files_win)
call cursor(hs.files_header + 1, 1)
normal gd
call WaitDiff()
let hd = get(t:, 'git_changes_file_diff', {})
let hentry = hs.commits[hs.commit_index]
call Check('commit gd ref mode',
      \ get(get(hd, 'spec', {}), 'new_kind', '') ==# 'ref',
      \ string(get(hd, 'spec', {})))
call Check('commit gd refs',
      \ len(get(get(hd, 'spec', {}), 'refs', [])) == 2
      \ && get(get(hd, 'spec', {}), 'refs', [])[1] == hentry.sha,
      \ string(get(get(hd, 'spec', {}), 'refs', [])))
execute 'GitChangesDiffQuit'
GitChangesQuit

" --- gd keeps the ref comparison -----------------------------------------
GitChanges HEAD other
call WaitMain()
let cs = t:git_changes
for i in range(50)
  if !empty(cs.files)
    break
  endif
  sleep 100m
endfor
call Check('compare entry selected',
      \ !empty(cs.commits) && cs.commit_index >= 0
      \ && cs.commits[cs.commit_index].kind ==# 'compare',
      \ 'index=' . cs.commit_index . ' commits=' . len(cs.commits))

call win_gotoid(cs.files_win)
call cursor(cs.files_header + 1, 1)
normal gd
call WaitDiff()
let cd = get(t:, 'git_changes_file_diff', {})
let centry = cs.commits[cs.commit_index]
call Check('compare gd ref mode',
      \ get(get(cd, 'spec', {}), 'new_kind', '') ==# 'ref'
      \ && !get(cd, 'editable', 1),
      \ string(get(cd, 'spec', {})))
call Check('compare gd refs',
      \ get(get(cd, 'spec', {}), 'refs', []) == [centry.old_ref, centry.new_ref],
      \ string(get(get(cd, 'spec', {}), 'refs', [])))
call Check('compare gd content',
      \ getbufline(cd.old_buf, 1, '$') != getbufline(cd.new_buf, 1, '$'),
      \ 'old=' . join(getbufline(cd.old_buf, 1, '$'), '|')
      \ . ' new=' . join(getbufline(cd.new_buf, 1, '$'), '|'))
execute 'GitChangesDiffQuit'
GitChangesQuit

" --- file diff ------------------------------------------------------------
GitChangesDiff
call WaitDiff()
let fd = t:git_changes_file_diff
call Check('filediff old content', len(getbufline(fd.old_buf, 1, '$')) == 3,
      \ len(getbufline(fd.old_buf, 1, '$')))
call Check('filediff new content', len(getbufline(fd.new_buf, 1, '$')) == 3,
      \ len(getbufline(fd.new_buf, 1, '$')))

let v:errmsg = ''
doautocmd VimResized
call Check('resize file diff', empty(v:errmsg), v:errmsg)

call win_gotoid(fd.old_win)
call Check('filediff old q', maparg('q', 'n') =~# 'close_file_diff_tab', maparg('q', 'n'))
call Check('filediff old s', maparg('s', 'n') =~# 'stage_file_diff', maparg('s', 'n'))
call Check('filediff old D', maparg('D', 'n') =~# 'discard_file_diff', maparg('D', 'n'))
call Check('filediff old Tab', maparg('<Tab>', 'n') =~# 'cycle_file_diff', maparg('<Tab>', 'n'))

call win_gotoid(fd.new_win)
call Check('filediff new q', maparg('q', 'n') =~# 'close_file_diff_tab', maparg('q', 'n'))
call Check('filediff new s untouched', empty(maparg('s', 'n')), maparg('s', 'n'))
call Check('filediff new u untouched', empty(maparg('u', 'n')), maparg('u', 'n'))

execute 'GitChangesDiffQuit'
call Check('filediff quit', !exists('t:git_changes_file_diff'), 'tab still open')

" --- repository root follows the buffer, not cwd ---------------------------
execute 'cd ' . fnameescape(g:other)
execute 'edit ' . fnameescape(g:repo . '/a.txt')
call git_changes#stage()
let staged = systemlist(['git', '-C', g:repo, 'diff', '--cached', '--name-only'])
call Check('stage uses buffer repo', index(staged, 'a.txt') >= 0, join(staged, ','))
let other_status = systemlist(['git', '-C', g:other, 'status', '--porcelain'])
call Check('stage leaves cwd repo alone', empty(other_status), join(other_status, ','))

" Unstage again, then exercise the file diff stage key. The explicit path is
" resolved from the repository root when cwd is another repository.
call git_changes#unstage()
GitChangesDiff -- a.txt
call WaitDiff()
let fd = t:git_changes_file_diff
call Check('filediff path from other cwd', fd.spec.path ==# 'a.txt', fd.spec.path)
call win_gotoid(fd.old_win)
let v:errmsg = ''
let map_s = maparg('s', 'n')
normal s
sleep 150m
let staged = systemlist(['git', '-C', g:repo, 'diff', '--cached', '--name-only'])
call Check('filediff stage key', index(staged, 'a.txt') >= 0,
      \ join(staged, ',') . ' map=' . map_s . ' err=' . v:errmsg
      \ . ' msgs=' . join(split(execute('messages'), "\n"), ' / '))
execute 'GitChangesDiffQuit'

call writefile(g:result, g:out . '/result.txt')
let v:errmsg = ''
qa!
VIM

GC_PLUGIN="$plugin_dir" GC_REPO="$repo" GC_OTHER="$other" GC_OUT="$out" \
  GC_BRANCH="$cur_branch" GC_SAMETIP=sametip \
  "$VIM_BIN" -Nu NONE -es -S "$script" >/dev/null 2>&1 || true

cat "$out/result.txt"
if grep -q '^FAIL' "$out/result.txt"; then
  exit 1
fi
echo "ok: smoke tests passed ($VIM_BIN)"
