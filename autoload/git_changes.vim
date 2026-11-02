
let s:sid = expand('<SID>')
let s:instances = []


function! s:err(msg) abort
  echohl ErrorMsg
  echomsg 'GitChanges: ' . a:msg
  echohl None
endfunction

function! s:opt_int(name, default) abort
  let value = get(g:, a:name, a:default)
  return type(value) == type(0) && value > 0 ? value : a:default
endfunction

function! git_changes#complete_refs(arglead, cmdline, cursorpos) abort
  let root = s:repo_root()
  if empty(root)
    return []
  endif

  let refs = ['HEAD']
  call extend(refs, s:git(root,
        \ 'for-each-ref ' . shellescape('--format=%(refname:short)')
        \ . ' refs/heads refs/tags refs/remotes'))

  let result = []
  let seen = {}
  for ref in refs
    if !has_key(seen, ref) && stridx(ref, a:arglead) == 0
      let seen[ref] = 1
      call add(result, ref)
    endif
  endfor
  return result
endfunction

function! s:truncate(text, max) abort
  if a:max < 4 || strchars(a:text) <= a:max
    return a:text
  endif
  return strcharpart(a:text, 0, a:max - 3) . '...'
endfunction

function! s:repo_root() abort
  let out = systemlist('git rev-parse --show-toplevel 2>&1')
  if !v:shell_error && !empty(out)
    return out[0]
  endif

  let file = expand('%:p')
  if !empty(file)
    let dir = fnamemodify(file, ':h')
    let out = systemlist('git -C ' . shellescape(dir)
          \ . ' rev-parse --show-toplevel 2>&1')
    if !v:shell_error && !empty(out)
      return out[0]
    endif
  endif

  return ''
endfunction

function! s:git(root, args) abort
  let cmd = 'git --no-pager -c core.quotePath=false -C '
        \ . shellescape(a:root) . ' ' . a:args
  let out = systemlist(cmd)
  if v:shell_error
    return []
  endif
  return out
endfunction

function! s:git_one(root, args) abort
  let out = s:git(a:root, a:args)
  return empty(out) ? '' : out[0]
endfunction

function! s:buf_linecount(buf) abort
  let info = getbufinfo(a:buf)
  if !empty(info) && has_key(info[0], 'linecount')
    return info[0].linecount
  endif
  return len(getbufline(a:buf, 1, '$'))
endfunction

function! s:cur_state() abort
  return get(b:, 'git_changes', {})
endfunction

function! s:state_alive(state) abort
  return bufexists(a:state.files_buf)
        \ || bufexists(a:state.commits_buf)
        \ || bufexists(a:state.old_buf)
        \ || bufexists(a:state.new_buf)
        \ || bufexists(a:state.branches_buf)
endfunction

function! s:find_state() abort
  let state = s:cur_state()
  if !empty(state) && s:state_alive(state)
    return state
  endif
  for state in reverse(copy(s:instances))
    if s:state_alive(state)
      return state
    endif
  endfor
  return {}
endfunction

function! s:forget(state) abort
  call filter(s:instances, 'v:val isnot a:state')
endfunction


function! s:new_scratch(name, filetype) abort
  enew
  let buf = bufnr('%')
  execute 'silent! file ' . fnameescape(a:name)

  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal nonumber
  setlocal norelativenumber
  setlocal nolist
  setlocal nowrap
  setlocal signcolumn=no
  setlocal foldcolumn=0
  setlocal nospell
  setlocal nomodeline
  setlocal nomodifiable

  execute 'setlocal filetype=' . a:filetype
  return buf
endfunction

function! s:set_lines(buf, lines) abort
  if !bufexists(a:buf)
    return
  endif

  let was_modifiable = getbufvar(a:buf, '&modifiable')
  call setbufvar(a:buf, '&modifiable', 1)
  try
    silent call deletebufline(a:buf, 1, '$')
    if empty(a:lines)
      call setbufline(a:buf, 1, '')
    else
      call setbufline(a:buf, 1, a:lines)
    endif
  finally
    call setbufvar(a:buf, '&modifiable', was_modifiable ? 1 : 0)
  endtry
endfunction

function! s:set_cursor(winid, lnum) abort
  if a:winid <= 0 || win_id2win(a:winid) == 0
    return
  endif

  if exists('*win_execute')
    call win_execute(a:winid, 'call cursor(' . a:lnum . ', 1)')
  else
    let curwin = win_getid()
    call win_gotoid(a:winid)
    call cursor(a:lnum, 1)
    call win_gotoid(curwin)
  endif
endfunction

function! s:scroll_top(winid) abort
  if a:winid <= 0 || win_id2win(a:winid) == 0
    return
  endif
  if exists('*win_execute')
    call win_execute(a:winid, 'silent! normal! gg')
  endif
endfunction

function! s:setup_list_window() abort
  setlocal cursorline
  setlocal scrolloff=2
  setlocal sidescrolloff=0
  setlocal winminwidth=20
endfunction

function! s:setup_diff_window() abort
  setlocal cursorline
  setlocal scrolloff=0
  setlocal sidescrolloff=0
  setlocal nowrap
  setlocal number
  setlocal numberwidth=4
  setlocal scrollbind
  setlocal cursorbind
  setlocal foldenable
  setlocal foldmethod=diff
  setlocal foldlevel=99
  setlocal winminwidth=20
endfunction


function! s:map_quit() abort
  execute 'nnoremap <buffer> <silent> <leader>gq :<C-u>GitChangesQuit<CR>'
endfunction

function! s:init_list_buffer(state, kind) abort
  let b:git_changes = a:state
  let b:gc_kind = a:kind

  call s:setup_list_window()

  execute 'nnoremap <buffer> <silent> j :<C-u>call ' . s:sid . 'move_' . a:kind . '(1)<CR>'
  execute 'nnoremap <buffer> <silent> k :<C-u>call ' . s:sid . 'move_' . a:kind . '(-1)<CR>'
  execute 'nnoremap <buffer> <silent> <Down> :<C-u>call ' . s:sid . 'move_' . a:kind . '(1)<CR>'
  execute 'nnoremap <buffer> <silent> <Up> :<C-u>call ' . s:sid . 'move_' . a:kind . '(-1)<CR>'
  execute 'nnoremap <buffer> <silent> J :<C-u>call ' . s:sid . 'scroll_diff(1)<CR>'
  execute 'nnoremap <buffer> <silent> K :<C-u>call ' . s:sid . 'scroll_diff(-1)<CR>'
  execute 'nnoremap <buffer> <silent> <Tab> :<C-u>call ' . s:sid . 'cycle_left_pane()<CR>'

  if a:kind ==# 'files'
    execute 'nnoremap <buffer> <silent> t :<C-u>call ' . s:sid . 'toggle_tree()<CR>'
    execute 'nnoremap <buffer> <silent> ? :<C-u>call ' . s:sid . 'toggle_help()<CR>'
    execute 'nnoremap <buffer> <silent> r :<C-u>call ' . s:sid . 'refresh_files()<CR>'
    execute 'nnoremap <buffer> <silent> s :<C-u>call ' . s:sid . 'stage_current("stage")<CR>'
    execute 'nnoremap <buffer> <silent> u :<C-u>call ' . s:sid . 'stage_current("unstage")<CR>'
    execute 'nnoremap <buffer> <silent> - :<C-u>call ' . s:sid . 'stage_current("toggle")<CR>'
    execute 'nnoremap <buffer> <silent> d :<C-u>call ' . s:sid . 'discard_current()<CR>'
    execute 'nnoremap <buffer> <silent> yy :<C-u>call ' . s:sid . 'copy_file_path()<CR>'
    execute 'nnoremap <buffer> <silent> c :<C-u>call ' . s:sid . 'commit_current()<CR>'
    execute 'nnoremap <buffer> <silent> p :<C-u>call ' . s:sid . 'pull_current()<CR>'
    execute 'nnoremap <buffer> <silent> P :<C-u>call ' . s:sid . 'push_current()<CR>'
  endif

  call s:map_quit()

  let callback = a:kind ==# 'files' ? 'on_files_cursor_moved' : 'on_commits_cursor_moved'
  augroup git_changes
    autocmd! CursorMoved <buffer>
    execute 'autocmd CursorMoved <buffer> call ' . s:sid . callback . '()'
  augroup END
endfunction

function! s:init_diff_buffer(state, side) abort
  let b:git_changes = a:state
  let b:gc_kind = 'diff'
  let b:gc_side = a:side
  call s:setup_diff_window()
  call s:map_quit()
endfunction

function! s:init_branch_buffer(state) abort
  let b:git_changes = a:state
  let b:gc_kind = 'branches'
  call s:setup_list_window()

  execute 'nnoremap <buffer> <silent> j :<C-u>call ' . s:sid . 'move_branches(1)<CR>'
  execute 'nnoremap <buffer> <silent> k :<C-u>call ' . s:sid . 'move_branches(-1)<CR>'
  execute 'nnoremap <buffer> <silent> <Down> :<C-u>call ' . s:sid . 'move_branches(1)<CR>'
  execute 'nnoremap <buffer> <silent> <Up> :<C-u>call ' . s:sid . 'move_branches(-1)<CR>'
  execute 'nnoremap <buffer> <silent> cc :<C-u>call ' . s:sid . 'checkout_branch()<CR>'
  execute 'nnoremap <buffer> <silent> <CR> :<C-u>call ' . s:sid . 'apply_branch()<CR>'
  execute 'nnoremap <buffer> <silent> <Tab> :<C-u>call ' . s:sid . 'cycle_left_pane()<CR>'
  execute 'nnoremap <buffer> <silent> n :<C-u>call ' . s:sid . 'new_branch()<CR>'
  execute 'nnoremap <buffer> <silent> d :<C-u>call ' . s:sid . 'delete_branch()<CR>'
  execute 'nnoremap <buffer> <silent> yy :<C-u>call ' . s:sid . 'copy_branch_name()<CR>'
  call s:map_quit()

  augroup git_changes
    autocmd! CursorMoved <buffer>
    execute 'autocmd CursorMoved <buffer> call ' . s:sid . 'on_branch_cursor_moved()'
  augroup END
endfunction


function! s:move_files(delta) abort
  let state = s:cur_state()
  if empty(state) || empty(state.display_file_indexes)
    return
  endif

  let indexes = state.display_file_indexes
  let current = s:current_file_index(state)
  if current < 0
    let current = state.file_index
  endif

  let pos = current >= 0 ? index(indexes, current) : -1
  if pos < 0
    let pos = a:delta > 0 ? -1 : len(indexes)
  endif
  let pos = max([0, min([len(indexes) - 1, pos + a:delta])])
  let index = indexes[pos]

  let changed = index != state.file_index
  if changed
    let state.file_index = index
  endif
  call s:goto_file_index(state, index)
  if changed
    call s:show_diff(state, state.files[index])
  endif
endfunction

function! s:move_commits(delta) abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits)
    return
  endif

  let index = state.commit_index
  if index < 0
    let index = 0
  else
    let index += a:delta
  endif
  let index = max([0, min([len(state.commits) - 1, index])])

  call cursor(state.commits_header + 1 + index, 1)
  if index != state.commit_index
    call s:select_commit(state, index)
  endif
endfunction

" Scroll the right-hand diff one line without changing the selected file.
function! s:scroll_diff(delta) abort
  let state = s:cur_state()
  if empty(state)
    return
  endif

  let old_ok = state.old_win > 0 && win_id2win(state.old_win) > 0
  let new_ok = state.new_win > 0 && win_id2win(state.new_win) > 0
  if !old_ok && !new_ok
    return
  endif

  let winid = old_ok ? state.old_win : state.new_win
  if old_ok && new_ok
    let old_lines = s:buf_linecount(state.old_buf)
    let new_lines = s:buf_linecount(state.new_buf)
    if new_lines > old_lines
      let winid = state.new_win
    endif
  endif

  let key = a:delta > 0 ? "\<C-e>" : "\<C-y>"
  if exists('*win_execute')
    call win_execute(winid, 'silent! normal! ' . key)
  else
    let curwin = win_getid()
    call win_gotoid(winid)
    execute 'silent! normal! ' . key
    call win_gotoid(curwin)
  endif
endfunction

function! s:on_files_cursor_moved() abort
  let state = s:cur_state()
  if empty(state) || get(state, 'updating', 0)
    return
  endif

  let offset = line('.') - state.files_header - 1
  let index = get(state.file_line_map, offset, -1)
  if index < 0 || index >= len(state.files) || index == state.file_index
    return
  endif

  let state.file_index = index
  call s:show_diff(state, state.files[index])
endfunction

function! s:on_commits_cursor_moved() abort
  let state = s:cur_state()
  if empty(state) || get(state, 'updating', 0)
    return
  endif

  let index = line('.') - state.commits_header - 1
  if index < 0 || index >= len(state.commits) || index == state.commit_index
    return
  endif

  call s:select_commit(state, index)
endfunction

function! s:cycle_left_pane() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif

  let windows = [state.files_win, state.commits_win, state.branches_win]
  let current = win_getid()
  let target = 0
  for i in range(len(windows))
    if windows[i] == current
      let target = (i + 1) % len(windows)
      break
    endif
  endfor

  for _ in range(len(windows))
    let winid = windows[target]
    if winid > 0 && win_id2win(winid) > 0
      call win_gotoid(winid)
      return
    endif
    let target = (target + 1) % len(windows)
  endfor
endfunction


function! s:empty_message(entry) abort
  if a:entry.kind ==# 'worktree'
    return '(no working tree changes)'
  elseif a:entry.kind ==# 'compare'
    return '(no files changed between refs)'
  endif
  return '(no files changed in this commit)'
endfunction

function! s:rerender_files(state) abort
  if empty(a:state.commits) || a:state.commit_index < 0
    return
  endif

  let a:state.updating = 1
  try
    let entry = a:state.commits[a:state.commit_index]
    call s:render_files(a:state, entry, a:state.files)

    if empty(a:state.files)
      call s:set_cursor(a:state.files_win, 1)
      return
    endif
    if a:state.file_index < 0 || a:state.file_index >= len(a:state.files)
      let a:state.file_index = 0
    endif
    call s:goto_file_index(a:state, a:state.file_index)
  finally
    let a:state.updating = 0
  endtry
endfunction

function! s:toggle_tree() abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif

  let state.file_tree = !state.file_tree
  call s:rerender_files(state)
endfunction

function! s:toggle_help() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif

  let state.show_help = !state.show_help
  if empty(state.commits) || state.commit_index < 0
    call s:show_no_commits(state)
  else
    call s:rerender_files(state)
  endif
endfunction

function! s:git_do(root, args) abort
  let cmd = 'git --no-pager -c core.quotePath=false -c credential.interactive=never -C '
        \ . shellescape(a:root) . ' ' . a:args . ' 2>&1'
  let out = systemlist(cmd)
  if v:shell_error
    call s:err(empty(out) ? 'git command failed' : join(out, ' '))
    return 0
  endif
  return 1
endfunction

function! s:prompt_input(prompt) abort
  if exists('g:git_changes_input_override')
    let value = g:git_changes_input_override
    unlet g:git_changes_input_override
    return value
  endif
  return input(a:prompt)
endfunction

function! s:has_staged_changes(root, paths) abort
  let path_args = join(map(copy(a:paths), 'shellescape(v:val)'), ' ')
  let cmd = 'git --no-pager -c core.quotePath=false -C '
        \ . shellescape(a:root) . ' diff --cached --quiet -- ' . path_args
  call systemlist(cmd)
  return v:shell_error == 1
endfunction

function! s:refresh_file_list(state, keep_path) abort
  if a:state.commit_index < 0 || a:state.commit_index >= len(a:state.commits)
    return
  endif

  let entry = a:state.commits[a:state.commit_index]
  let old_index = a:state.file_index
  let a:state.updating = 1
  try
    call s:load_files(a:state, entry)
    if empty(a:state.files)
      let a:state.file_index = -1
      call s:set_cursor(a:state.files_win, 1)
      call s:show_side_message(a:state, [s:empty_message(entry)])
      return
    endif

    let new_index = -1
    for i in range(len(a:state.files))
      if a:state.files[i].path ==# a:keep_path
        let new_index = i
        break
      endif
    endfor
    if new_index < 0
      let new_index = min([max([old_index, 0]), len(a:state.files) - 1])
    endif

    let a:state.file_index = new_index
    call s:goto_file_index(a:state, new_index)
    call s:show_diff(a:state, a:state.files[new_index])
  finally
    let a:state.updating = 0
  endtry
endfunction

function! s:refresh_files() abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif

  let keep_path = ''
  if state.file_index >= 0 && state.file_index < len(state.files)
    let keep_path = state.files[state.file_index].path
  endif
  call s:refresh_file_list(state, keep_path)
endfunction

function! s:discard_current() abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif

  let entry = state.commits[state.commit_index]
  if entry.kind !=# 'worktree'
    call s:err('discard is only available for working tree changes')
    return
  endif

  let index = s:current_file_index(state)
  if index < 0 || index >= len(state.files)
    call s:err('select a file first')
    return
  endif

  let file = state.files[index]
  let xy = get(file, 'status_text', '')
  let abs = state.root . '/' . file.path

  if xy ==# '??'
    if get(g:, 'git_changes_confirm_discard', 1)
          \ && confirm('Delete untracked file ' . file.path . '?',
          \             "&Yes\n&No", 2) != 1
      return
    endif
    if delete(abs) != 0
      call s:err('failed to delete: ' . file.path)
      return
    endif
    echomsg 'Deleted: ' . file.path
  else
    let worktree_status = strlen(xy) >= 2 ? strpart(xy, 1, 1) : ' '
    if worktree_status ==# ' ' || worktree_status ==# '?'
      echomsg 'No unstaged changes: ' . file.path
      return
    endif

    if get(g:, 'git_changes_confirm_discard', 1)
          \ && confirm('Discard unstaged changes for ' . file.path . '?',
          \             "&Yes\n&No", 2) != 1
      return
    endif

    let oldpath = get(file, 'oldpath', '')
    let index_status = strpart(xy, 0, 1)
    let target = file.path
    if index_status ==# ' ' && !empty(oldpath)
      let target = oldpath
    endif
    if !s:git_do(state.root, 'checkout -- ' . shellescape(target))
      return
    endif

    if index_status ==# ' ' && !empty(oldpath) && oldpath !=# file.path
      let abs_new = state.root . '/' . file.path
      if filereadable(abs_new)
        let tracked = !empty(s:git_one(state.root,
              \ 'ls-files --error-unmatch -- ' . shellescape(file.path)))
        if !tracked
          call delete(abs_new)
        endif
      endif
    endif

    echomsg 'Discarded unstaged changes: ' . file.path
  endif

  call s:refresh_file_list(state, file.path)
endfunction

function! s:copy_to_clipboard(text) abort
  if has('clipboard')
    try
      let @+ = a:text
      return 1
    catch
    endtry
    try
      let @* = a:text
      return 1
    catch
    endtry
  endif

  " Fall back to system clipboard tools when Vim has no clipboard support.
  if executable('pbcopy')
    call system('pbcopy', a:text)
    return v:shell_error == 0
  elseif executable('wl-copy')
    call system('wl-copy', a:text)
    return v:shell_error == 0
  elseif executable('xclip')
    call system('xclip -selection clipboard', a:text)
    return v:shell_error == 0
  endif

  return 0
endfunction

function! s:copy_file_path() abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif

  let index = s:current_file_index(state)
  if index < 0 || index >= len(state.files)
    call s:err('select a file first')
    return
  endif

  let path = state.root . '/' . state.files[index].path
  if s:copy_to_clipboard(path)
    echomsg 'Copied path: ' . path
  else
    call s:err('clipboard not available')
  endif
endfunction

function! s:commit_current() abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif

  let entry = state.commits[state.commit_index]
  if entry.kind !=# 'worktree'
    call s:err('commit is only available for working tree changes')
    return
  endif

  if !s:has_staged_changes(state.root, [])
    echomsg 'No staged changes to commit'
    return
  endif

  let message = trim(s:prompt_input('Commit message: '))
  if empty(message)
    echomsg 'Commit cancelled'
    return
  endif

  if !s:git_do(state.root, 'commit -m ' . shellescape(message))
    return
  endif

  echomsg 'Committed: ' . message
  call s:reload_current_branch(state)
endfunction

function! s:reload_current_branch(state) abort
  let a:state.log_range = ''
  let a:state.log_ref = ''
  let a:state.list_title = 'Branch: ' . s:current_branch(a:state.root)
  let a:state.has_head = !empty(s:resolve_ref(a:state.root, 'HEAD'))
  let a:state.start_entries = []
  if a:state.has_head && get(g:, 'git_changes_show_worktree', 1)
    call add(a:state.start_entries, s:worktree_entry())
  endif

  let a:state.updating = 1
  try
    call s:load_branches(a:state, '')
    call s:load_commits(a:state)
    if empty(a:state.commits)
      call s:show_no_commits(a:state)
    else
      call s:select_commit(a:state, 0)
    endif
  finally
    let a:state.updating = 0
  endtry
endfunction

function! s:pull_current() abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif
  if state.commits[state.commit_index].kind !=# 'worktree'
    call s:err('pull is only available for working tree changes')
    return
  endif

  let ok = s:git_do(state.root, 'pull --no-rebase --no-edit')
  call s:reload_current_branch(state)
  if ok
    echomsg 'Pull complete'
  endif
endfunction

function! s:push_current() abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif
  if state.commits[state.commit_index].kind !=# 'worktree'
    call s:err('push is only available for working tree changes')
    return
  endif

  if s:git_do(state.root, 'push')
    echomsg 'Push complete'
  endif
endfunction

function! s:stage_current(mode) abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif

  let entry = state.commits[state.commit_index]
  if entry.kind !=# 'worktree'
    call s:err('stage/unstage is only available for working tree changes')
    return
  endif

  let index = s:current_file_index(state)
  if index < 0 || index >= len(state.files)
    call s:err('select a file first')
    return
  endif

  let file = state.files[index]
  let paths = s:file_paths(file)[2]
  let path_args = join(map(copy(paths), 'shellescape(v:val)'), ' ')

  let do_stage = a:mode ==# 'stage'
  if a:mode ==# 'unstage'
    if !s:has_staged_changes(state.root, paths)
      echomsg 'Not staged: ' . file.path
      return
    endif
  elseif a:mode ==# 'toggle'
    let do_stage = !s:has_staged_changes(state.root, paths)
  endif

  if do_stage
    if !s:git_do(state.root, 'add -A -- ' . path_args)
      return
    endif
    echomsg 'Staged: ' . file.path
  else
    if !s:git_do(state.root, 'reset -q HEAD -- ' . path_args)
      return
    endif
    echomsg 'Unstaged: ' . file.path
  endif

  call s:refresh_file_list(state, file.path)
endfunction


function! s:load_branches(state, select_name) abort
  let current = s:git_one(a:state.root, 'symbolic-ref --short -q HEAD')
  let names = s:git(a:state.root,
        \ 'for-each-ref --sort=-committerdate '
        \ . shellescape('--format=%(refname:short)')
        \ . ' refs/heads')

  let branches = []
  for name in names
    call add(branches, {
          \ 'name': name,
          \ 'current': name ==# current,
          \ })
  endfor

  let old_name = ''
  if a:state.branch_index >= 0 && a:state.branch_index < len(a:state.branches)
    let old_name = a:state.branches[a:state.branch_index].name
  endif
  let wanted = !empty(a:select_name) ? a:select_name : old_name

  let selected = -1
  for i in range(len(branches))
    if branches[i].name ==# wanted
      let selected = i
      break
    endif
  endfor
  if selected < 0
    for i in range(len(branches))
      if branches[i].current
        let selected = i
        break
      endif
    endfor
  endif
  if selected < 0 && !empty(branches)
    let selected = 0
  endif

  let header = [
        \ '# Branches',
        \ '# j/k:select Enter:show Tab:pane',
        \ '# cc:checkout n:new d:delete yy:copy',
        \ ]
  let a:state.branch_header = len(header)
  let a:state.branches = branches
  let a:state.branch_index = selected

  let lines = copy(header)
  for branch in branches
    call add(lines, (branch.current ? '* ' : '  ') . branch.name)
  endfor
  if empty(branches)
    call add(lines, '  (no branches)')
  endif

  call s:set_lines(a:state.branches_buf, lines)
  if selected >= 0
    call s:set_cursor(a:state.branches_win,
          \ a:state.branch_header + 1 + selected)
  endif
endfunction

function! s:selected_branch(state) abort
  if a:state.branch_index < 0 || a:state.branch_index >= len(a:state.branches)
    return {}
  endif
  return a:state.branches[a:state.branch_index]
endfunction

function! s:show_branch(state, branch) abort
  let a:state.updating = 1
  try
    let a:state.log_ref = a:branch.name
    let a:state.log_range = ''
    let a:state.list_title = 'Branch: ' . a:branch.name
    let a:state.has_head = !empty(s:resolve_ref(a:state.root, 'HEAD'))
    let a:state.start_entries = []

    if a:branch.current
          \ && a:state.has_head
          \ && get(g:, 'git_changes_show_worktree', 1)
      call add(a:state.start_entries, s:worktree_entry())
    endif

    call s:load_commits(a:state)
    if empty(a:state.commits)
      call s:show_no_commits(a:state)
    else
      let target = 0
      if a:state.commits[0].kind ==# 'worktree'
            \ && len(a:state.commits) > 1
        let target = 1
      endif
      call s:select_commit(a:state, target)
    endif
  finally
    let a:state.updating = 0
  endtry
endfunction

function! s:move_branches(delta) abort
  let state = s:cur_state()
  if empty(state) || empty(state.branches)
    return
  endif

  let index = state.branch_index
  if index < 0
    let index = 0
  else
    let index += a:delta
  endif
  let index = max([0, min([len(state.branches) - 1, index])])

  let changed = index != state.branch_index
  if changed
    let state.branch_index = index
  endif
  call cursor(state.branch_header + 1 + index, 1)
endfunction

function! s:on_branch_cursor_moved() abort
  let state = s:cur_state()
  if empty(state) || get(state, 'updating', 0)
    return
  endif

  let index = line('.') - state.branch_header - 1
  if index < 0 || index >= len(state.branches) || index == state.branch_index
    return
  endif

  let state.branch_index = index
endfunction

function! s:apply_branch() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif
  let branch = s:selected_branch(state)
  if empty(branch)
    call s:err('select a branch first')
    return
  endif

  call s:show_branch(state, branch)
endfunction

function! s:checkout_branch() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif
  let branch = s:selected_branch(state)
  if empty(branch)
    call s:err('select a branch first')
    return
  endif
  if branch.current
    echomsg 'Already on branch: ' . branch.name
    return
  endif

  if !s:git_do(state.root, 'checkout ' . shellescape(branch.name))
    return
  endif

  let state.updating = 1
  try
    call s:load_branches(state, branch.name)
    if state.branch_index >= 0
      call s:show_branch(state, state.branches[state.branch_index])
    endif
  finally
    let state.updating = 0
  endtry
  echomsg 'Switched to branch: ' . branch.name
endfunction

function! s:copy_branch_name() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif
  let branch = s:selected_branch(state)
  if empty(branch)
    call s:err('select a branch first')
    return
  endif

  if s:copy_to_clipboard(branch.name)
    echomsg 'Copied branch: ' . branch.name
  else
    call s:err('clipboard not available')
  endif
endfunction

function! s:new_branch() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif
  let branch = s:selected_branch(state)
  if empty(branch)
    call s:err('select a branch first')
    return
  endif

  let name = trim(s:prompt_input('New branch name: '))
  if empty(name)
    echomsg 'Branch creation cancelled'
    return
  endif

  if !s:git_do(state.root,
        \ 'checkout -b ' . shellescape(name) . ' ' . shellescape(branch.name))
    return
  endif

  let state.updating = 1
  try
    call s:load_branches(state, name)
    if state.branch_index >= 0
      call s:show_branch(state, state.branches[state.branch_index])
    endif
  finally
    let state.updating = 0
  endtry
  echomsg 'Created branch: ' . name
endfunction

function! s:delete_branch() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif
  let branch = s:selected_branch(state)
  if empty(branch)
    call s:err('select a branch first')
    return
  endif
  if branch.current
    call s:err('cannot delete the current branch')
    return
  endif

  if get(g:, 'git_changes_confirm_branch_delete', 1)
        \ && confirm('Delete local branch ' . branch.name . '?',
        \             "&Yes\n&No", 2) != 1
    return
  endif

  if !s:git_do(state.root, 'branch -d ' . shellescape(branch.name))
    return
  endif

  let state.updating = 1
  try
    call s:load_branches(state, '')
    if state.branch_index >= 0
      call s:show_branch(state, state.branches[state.branch_index])
    endif
  finally
    let state.updating = 0
  endtry
  echomsg 'Deleted branch: ' . branch.name
endfunction


function! s:current_branch(root) abort
  let branch = s:git_one(a:root, 'symbolic-ref --short -q HEAD')
  if !empty(branch)
    return branch
  endif
  let sha = s:git_one(a:root, 'rev-parse --short HEAD')
  return empty(sha) ? 'HEAD' : 'detached at ' . sha
endfunction

function! s:worktree_entry() abort
  return {
        \ 'kind': 'worktree',
        \ 'short': 'WORK',
        \ 'subject': 'Working tree changes',
        \ 'sha': '',
        \ 'old_ref': '',
        \ 'new_ref': '',
        \ 'old_label': 'HEAD',
        \ 'new_label': 'WORKTREE',
        \ }
endfunction

function! s:resolve_ref(root, ref) abort
  return s:git_one(a:root,
        \ 'rev-parse --verify -q ' . shellescape(a:ref . '^{commit}'))
endfunction

function! s:parse_status_lines(lines) abort
  let files = []
  for line in a:lines
    if empty(line)
      continue
    endif
    let parts = split(line, "\t")
    if empty(parts)
      continue
    endif

    let raw_status = parts[0]
    let status = strpart(raw_status, 0, 1)
    let entry = {
          \ 'status': status,
          \ 'status_text': status . ' ',
          \ 'status_raw': raw_status,
          \ 'worktree': 0,
          \ 'path': '',
          \ 'oldpath': '',
          \ }

    if (status ==# 'R' || status ==# 'C') && len(parts) >= 3
      let entry.oldpath = parts[1]
      let entry.path = parts[2]
    elseif len(parts) >= 2
      let entry.path = parts[1]
    else
      continue
    endif

    call add(files, entry)
  endfor
  return files
endfunction

function! s:parse_worktree_status(lines) abort
  let files = []
  for line in a:lines
    if strlen(line) < 4
      continue
    endif

    let xy = strpart(line, 0, 2)
    if xy ==# '!!'
      continue
    endif

    let rest = strpart(line, 3)
    let oldpath = ''
    if xy =~# '[RC]' && rest =~# ' -> '
      let pieces = split(rest, ' -> ', 1)
      if len(pieces) >= 2
        let oldpath = pieces[0]
        let rest = pieces[-1]
      endif
    endif

    let index_status = strpart(xy, 0, 1)
    let worktree_status = strpart(xy, 1, 1)
    call add(files, {
          \ 'status': index_status !=# ' ' ? index_status : worktree_status,
          \ 'status_text': xy,
          \ 'status_raw': xy,
          \ 'worktree': 1,
          \ 'path': rest,
          \ 'oldpath': oldpath,
          \ })
  endfor
  return files
endfunction

function! s:worktree_summary(files) abort
  let staged = 0
  let unstaged = 0
  let untracked = 0

  for file in a:files
    let xy = get(file, 'status_text', '')
    if xy ==# '??'
      let untracked += 1
      continue
    endif

    if strlen(xy) >= 1
          \ && strpart(xy, 0, 1) !=# ' '
          \ && strpart(xy, 0, 1) !=# '?'
      let staged += 1
    endif
    if strlen(xy) >= 2 && strpart(xy, 1, 1) !=# ' '
      let unstaged += 1
    endif
  endfor

  return [staged, unstaged, untracked]
endfunction

function! s:commit_body_lines(state, entry) abort
  if has_key(a:entry, 'body_lines')
    return a:entry.body_lines
  endif

  let lines = s:git(a:state.root,
        \ 'show -s --format=%b ' . shellescape(a:entry.sha))
  while !empty(lines) && empty(lines[0])
    call remove(lines, 0)
  endwhile
  while !empty(lines) && empty(lines[-1])
    call remove(lines, -1)
  endwhile

  let limit = s:opt_int('git_changes_commit_body_lines', 20)
  if len(lines) > limit
    let lines = lines[0:limit - 1]
    call add(lines, '...')
  endif

  let a:entry.body_lines = lines
  return lines
endfunction

function! s:files_header_lines(state, entry) abort
  let lines = ['# ' . a:entry.short . '  ' . s:truncate(a:entry.subject, 90)]

  if a:entry.kind ==# 'worktree'
    let [staged, unstaged, untracked] = s:worktree_summary(a:state.files)
    if staged + unstaged + untracked == 0
      call add(lines, '# Working tree clean')
    else
      call add(lines, printf('# Staged %d  Unstaged %d  Untracked %d',
            \ staged, unstaged, untracked))
    endif
    if a:state.show_help
      call add(lines, '# s:stage u:unstage -:toggle t:tree')
      call add(lines, '# r:refresh d:discard ?:hide')
      call add(lines, '# yy:path c:commit p:pull P:push')
      call add(lines, '# J/K:scroll Tab:pane <leader>gq:quit')
    endif
  elseif a:entry.kind ==# 'compare'
    call add(lines, '# Range: ' . a:state.list_title)
    if a:state.show_help
      call add(lines, '# t:tree r:refresh ?:hide yy:path')
      call add(lines, '# J/K:scroll Tab:pane <leader>gq:quit')
    endif
  else
    call add(lines, '# Author: ' . s:truncate(a:entry.author, 90))
    call add(lines, '# Date:   ' . a:entry.date)
    for body_line in s:commit_body_lines(a:state, a:entry)
      call add(lines, '# ' . body_line)
    endfor
    if a:state.show_help
      call add(lines, '# t:tree r:refresh ?:hide yy:path')
      call add(lines, '# J/K:scroll Tab:pane <leader>gq:quit')
    endif
  endif

  return lines
endfunction

function! s:file_status_text(file) abort
  let text = get(a:file, 'status_text', '')
  if strlen(text) >= 2
    return text
  endif
  return get(a:file, 'status', '?') . ' '
endfunction

function! s:file_status_display(file) abort
  if get(a:file, 'worktree', 0)
    let text = s:file_status_text(a:file)
    if strlen(text) < 2
      let text .= ' '
    endif
    return substitute(strpart(text, 0, 2), ' ', '·', 'g')
  endif
  return get(a:file, 'status', '?') . ' '
endfunction

function! s:file_path_text(file) abort
  let oldpath = get(a:file, 'oldpath', '')
  if !empty(oldpath) && oldpath !=# a:file.path
    return oldpath . ' -> ' . a:file.path
  endif
  return a:file.path
endfunction

function! s:tree_insert(root, path, index) abort
  let parts = split(a:path, '/')
  if empty(parts)
    return
  endif

  let node = a:root
  let i = 0
  while i < len(parts) - 1
    let name = parts[i]
    if !has_key(node.children, name)
      let node.children[name] = {'type': 'dir', 'name': name, 'children': {}}
    endif
    let node = node.children[name]
    let i += 1
  endwhile

  let name = parts[-1]
  let node.children[name] = {
        \ 'type': 'file',
        \ 'name': name,
        \ 'index': a:index,
        \ }
endfunction

function! s:tree_node_compare(a, b) abort
  if a:a.type ==# a:b.type
    if a:a.name ==# a:b.name
      return 0
    endif
    return a:a.name ># a:b.name ? 1 : -1
  endif
  return a:a.type ==# 'dir' ? -1 : 1
endfunction

function! s:render_tree(node, depth, state, files, body, line_map, file_line_for_index, display_indexes) abort
  let children = []
  for name in keys(a:node.children)
    call add(children, a:node.children[name])
  endfor
  call sort(children, function('s:tree_node_compare'))

  for child in children
    if child.type ==# 'dir'
      call add(a:body, repeat('  ', a:depth) . '▾ ' . child.name . '/')
      call add(a:line_map, -1)
      call s:render_tree(child, a:depth + 1, a:state, a:files,
            \ a:body, a:line_map, a:file_line_for_index, a:display_indexes)
    else
      let file = a:files[child.index]
      call add(a:body, repeat('  ', a:depth)
            \ . s:file_status_display(file) . ' ' . child.name)
      call add(a:line_map, child.index)
      let a:file_line_for_index[child.index] =
            \ a:state.files_header + 1 + len(a:body) - 1
      call add(a:display_indexes, child.index)
    endif
  endfor
endfunction

function! s:render_files(state, entry, files) abort
  let a:state.files = a:files
  let header_lines = s:files_header_lines(a:state, a:entry) + ['']
  let a:state.files_header = len(header_lines)

  let body = []
  let line_map = []
  let file_line_for_index = repeat([0], len(a:files))
  let display_indexes = []

  if a:state.file_tree && !empty(a:files)
    let root = {'type': 'dir', 'name': '', 'children': {}}
    for index in range(len(a:files))
      call s:tree_insert(root, a:files[index].path, index)
    endfor
    call s:render_tree(root, 0, a:state, a:files,
          \ body, line_map, file_line_for_index, display_indexes)
  else
    for index in range(len(a:files))
      call add(body, s:file_status_display(a:files[index])
            \ . ' ' . s:file_path_text(a:files[index]))
      call add(line_map, index)
      let file_line_for_index[index] =
            \ a:state.files_header + 1 + len(body) - 1
      call add(display_indexes, index)
    endfor
  endif

  if empty(a:files)
    call add(body, '   ' . s:empty_message(a:entry))
    call add(line_map, -1)
  endif

  let a:state.file_line_map = line_map
  let a:state.file_line_for_index = file_line_for_index
  let a:state.display_file_indexes = display_indexes

  let lines = header_lines + body
  call s:set_lines(a:state.files_buf, lines)
endfunction

function! s:file_index_line(state, index) abort
  return get(a:state.file_line_for_index, a:index, 0)
endfunction

function! s:goto_file_index(state, index) abort
  let lnum = s:file_index_line(a:state, a:index)
  if lnum <= 0
    return
  endif
  if win_getid() == a:state.files_win
    call cursor(lnum, 1)
  else
    call s:set_cursor(a:state.files_win, lnum)
  endif
endfunction

function! s:current_file_index(state) abort
  if get(b:, 'gc_kind', '') ==# 'files'
    let offset = line('.') - a:state.files_header - 1
    return get(a:state.file_line_map, offset, -1)
  endif
  return a:state.file_index
endfunction

function! s:read_worktree(root, path) abort
  let abs = a:root . '/' . a:path
  if !filereadable(abs)
    return []
  endif
  try
    return readfile(abs)
  catch
    return []
  endtry
endfunction

function! s:load_commits(state) abort
  let limit = s:opt_int('git_changes_max_commits', 200)
  let skip_merges = get(g:, 'git_changes_exclude_merges', 1)
  let no_merges = skip_merges ? '--no-merges ' : ''
  let sep = nr2char(31)
  let format = '--pretty=format:%H%x1f%h%x1f%s%x1f%an%x1f%ad'
  let args = 'log ' . no_merges . '--date=short --max-count=' . limit . ' ' . format
  if !empty(a:state.log_range)
    let args .= ' ' . a:state.log_range
  elseif !empty(a:state.log_ref)
    let args .= ' ' . shellescape(a:state.log_ref)
  endif
  if !a:state.has_head && empty(a:state.log_range) && empty(a:state.log_ref)
    let out = []
  else
    let out = s:git(a:state.root, args)
  endif

  let real_commits = []
  for line in out
    let parts = split(line, sep)
    if len(parts) >= 3
      call add(real_commits, {
            \ 'kind': 'commit',
            \ 'sha': parts[0],
            \ 'short': parts[1],
            \ 'subject': parts[2],
            \ 'author': get(parts, 3, ''),
            \ 'date': get(parts, 4, ''),
            \ })
    endif
  endfor

  let entries = copy(a:state.start_entries)
  call extend(entries, real_commits)
  let a:state.commits = entries

  let lines = ['# ' . a:state.list_title . '  (' . len(real_commits) . ' commits)']
  for entry in entries
    if entry.kind ==# 'worktree'
      call add(lines, entry.short . '  ' . entry.subject)
    elseif entry.kind ==# 'compare'
      call add(lines, entry.short . '  '
            \ . s:truncate(entry.old_label . ' ↔ ' . entry.new_label, 90))
    else
      call add(lines, entry.short . '  ' . s:truncate(entry.subject, 90))
    endif
  endfor
  if empty(real_commits) && !empty(entries)
    call add(lines, '   (no commits in range)')
  elseif empty(entries)
    call add(lines, '   (no commits)')
  endif

  call s:set_lines(a:state.commits_buf, lines)
  if !empty(entries)
    call s:set_cursor(a:state.commits_win, a:state.commits_header + 1)
  endif
endfunction

function! s:load_files(state, entry) abort
  if a:entry.kind ==# 'worktree'
    call s:load_worktree_files(a:state, a:entry)
  elseif a:entry.kind ==# 'compare'
    call s:load_compare_files(a:state, a:entry)
  else
    call s:load_commit_files(a:state, a:entry)
  endif
endfunction

function! s:load_commit_files(state, commit) abort
  let out = s:git(a:state.root,
        \ 'show --name-status --format= --no-color --no-ext-diff --find-renames '
        \ . shellescape(a:commit.sha))
  call s:render_files(a:state, a:commit, s:parse_status_lines(out))
endfunction

function! s:load_compare_files(state, entry) abort
  let out = s:git(a:state.root,
        \ 'diff --name-status -M --no-ext-diff '
        \ . shellescape(a:entry.old_ref) . ' ' . shellescape(a:entry.new_ref))
  call s:render_files(a:state, a:entry, s:parse_status_lines(out))
endfunction

function! s:load_worktree_files(state, entry) abort
  let out = s:git(a:state.root,
        \ 'status --porcelain=v1 --untracked-files=all -M')
  call s:render_files(a:state, a:entry, s:parse_worktree_status(out))
endfunction

function! s:side_win(state, side) abort
  return a:side ==# 'old' ? a:state.old_win : a:state.new_win
endfunction

function! s:side_buf(state, side) abort
  return a:side ==# 'old' ? a:state.old_buf : a:state.new_buf
endfunction

function! s:set_side_filetype(state, side, path) abort
  let winid = s:side_win(a:state, a:side)
  if winid <= 0 || win_id2win(winid) == 0
    return
  endif

  let name = '[GitChanges ' . a:state.id . '] ' . a:side . '/' . a:path
  call win_execute(winid, 'silent! file ' . fnameescape(name))
  call win_execute(winid, 'setlocal filetype=')
  call win_execute(winid, 'silent! unlet! b:current_syntax b:did_ftplugin b:did_indent b:undo_ftplugin')
  call win_execute(winid, 'silent! filetype detect')

  call win_execute(winid, 'setlocal nowrap number numberwidth=4 cursorline '
        \ . 'scrollbind cursorbind foldenable foldmethod=diff foldlevel=99')
endfunction

function! s:load_side_buffer(state, side, path, lines, detect_filetype, label) abort
  let buf = s:side_buf(a:state, a:side)
  let winid = s:side_win(a:state, a:side)
  if buf <= 0 || !bufexists(buf) || winid <= 0 || win_id2win(winid) == 0
    return
  endif

  call s:set_lines(buf, a:lines)

  if a:detect_filetype
    call s:set_side_filetype(a:state, a:side, a:path)
  else
    let name = '[GitChanges ' . a:state.id . '] ' . a:side
    call win_execute(winid, 'silent! file ' . fnameescape(name))
    call win_execute(winid, 'setlocal filetype=')
    call win_execute(winid, 'silent! unlet! b:current_syntax')
  endif

  call win_execute(winid, 'setlocal nowrap number numberwidth=4 cursorline '
        \ . 'scrollbind cursorbind foldenable foldmethod=diff foldlevel=99')
  let label = substitute(a:label, '%', '%%', 'g')
  call win_execute(winid, 'let &l:statusline = ' . string(label))
  call s:set_cursor(winid, 1)
endfunction

function! s:sync_diff(state) abort
  let winid = 0
  if a:state.old_win > 0 && win_id2win(a:state.old_win) > 0
    let winid = a:state.old_win
  elseif a:state.new_win > 0 && win_id2win(a:state.new_win) > 0
    let winid = a:state.new_win
  endif

  if winid > 0
    call win_execute(winid, 'silent! diffupdate')
  endif

  call s:set_cursor(a:state.old_win, 1)
  call s:set_cursor(a:state.new_win, 1)
  call s:scroll_top(a:state.old_win)
  call s:scroll_top(a:state.new_win)
endfunction

function! s:show_side_message(state, lines) abort
  call s:load_side_buffer(a:state, 'old', '', a:lines, 0, 'GitChanges')
  call s:load_side_buffer(a:state, 'new', '', a:lines, 0, 'GitChanges')
  call s:sync_diff(a:state)
endfunction

function! s:is_binary(state, args, paths) abort
  let path_args = join(map(copy(a:paths), 'shellescape(v:val)'), ' ')
  let out = s:git(a:state.root, a:args . ' -- ' . path_args)
  for line in out
    if line =~# '^-\t-\t'
      return 1
    endif
  endfor
  return 0
endfunction

function! s:file_paths(file) abort
  let old_path = empty(get(a:file, 'oldpath', '')) ? a:file.path : a:file.oldpath
  let new_path = a:file.path
  let paths = [old_path]
  if new_path !=# old_path
    call add(paths, new_path)
  endif
  return [old_path, new_path, paths]
endfunction

function! s:show_commit_diff(state, commit, file) abort
  let [old_path, new_path, paths] = s:file_paths(a:file)

  if s:is_binary(a:state,
        \ 'show --numstat --format= ' . shellescape(a:commit.sha), paths)
    call s:show_side_message(a:state,
          \ ['(binary file - no side-by-side diff)'])
    return
  endif

  let old_lines = s:git(a:state.root,
        \ 'show ' . shellescape(a:commit.sha . '^:' . old_path))
  let new_lines = s:git(a:state.root,
        \ 'show ' . shellescape(a:commit.sha . ':' . new_path))

  call s:load_side_buffer(a:state, 'old', old_path, old_lines, 1,
        \ 'PARENT ' . old_path)
  call s:load_side_buffer(a:state, 'new', new_path, new_lines, 1,
        \ a:commit.short . ' ' . new_path)
  call s:sync_diff(a:state)
endfunction

function! s:show_compare_diff(state, entry, file) abort
  let [old_path, new_path, paths] = s:file_paths(a:file)

  if s:is_binary(a:state,
        \ 'diff --numstat ' . shellescape(a:entry.old_ref) . ' '
        \ . shellescape(a:entry.new_ref), paths)
    call s:show_side_message(a:state,
          \ ['(binary file - no side-by-side diff)'])
    return
  endif

  let old_lines = s:git(a:state.root,
        \ 'show ' . shellescape(a:entry.old_ref . ':' . old_path))
  let new_lines = s:git(a:state.root,
        \ 'show ' . shellescape(a:entry.new_ref . ':' . new_path))

  call s:load_side_buffer(a:state, 'old', old_path, old_lines, 1,
        \ a:entry.old_label . ' ' . old_path)
  call s:load_side_buffer(a:state, 'new', new_path, new_lines, 1,
        \ a:entry.new_label . ' ' . new_path)
  call s:sync_diff(a:state)
endfunction

function! s:worktree_file_is_binary(root, path) abort
  let abs = a:root . '/' . a:path
  if !filereadable(abs)
    return 0
  endif
  try
    for line in readfile(abs, '', 20)
      " readfile() represents NUL bytes as NL inside a line.
      if stridx(line, "\n") >= 0
        return 1
      endif
    endfor
  catch
    return 0
  endtry
  return 0
endfunction

function! s:show_worktree_diff(state, file) abort
  let [old_path, new_path, paths] = s:file_paths(a:file)

  let binary = s:is_binary(a:state, 'diff --numstat HEAD', paths)
  if !binary && a:file.status !=# 'D'
    let binary = s:worktree_file_is_binary(a:state.root, new_path)
  endif
  if binary
    call s:show_side_message(a:state,
          \ ['(binary file - no side-by-side diff)'])
    return
  endif

  let old_lines = s:git(a:state.root,
        \ 'show ' . shellescape('HEAD:' . old_path))
  let new_lines = s:read_worktree(a:state.root, new_path)

  call s:load_side_buffer(a:state, 'old', old_path, old_lines, 1,
        \ 'HEAD ' . old_path)
  call s:load_side_buffer(a:state, 'new', new_path, new_lines, 1,
        \ 'WORKTREE ' . new_path)
  call s:sync_diff(a:state)
endfunction

function! s:show_diff(state, file) abort
  if a:state.commit_index < 0 || a:state.commit_index >= len(a:state.commits)
    return
  endif
  let entry = a:state.commits[a:state.commit_index]

  if entry.kind ==# 'worktree'
    call s:show_worktree_diff(a:state, a:file)
  elseif entry.kind ==# 'compare'
    call s:show_compare_diff(a:state, entry, a:file)
  else
    call s:show_commit_diff(a:state, entry, a:file)
  endif
endfunction

function! s:select_commit(state, index) abort
  if a:index < 0 || a:index >= len(a:state.commits)
    return
  endif

  let a:state.updating = 1
  try
    let a:state.commit_index = a:index
    call s:set_cursor(a:state.commits_win,
          \ a:state.commits_header + 1 + a:index)
    let entry = a:state.commits[a:index]
    call s:load_files(a:state, entry)

    if empty(a:state.files)
      let a:state.file_index = -1
      call s:set_cursor(a:state.files_win, 1)
      call s:show_side_message(a:state, [s:empty_message(entry)])
    else
      let a:state.file_index = 0
      call s:goto_file_index(a:state, 0)
      call s:show_diff(a:state, a:state.files[0])
    endif
  catch
    call s:err(v:exception)
  finally
    let a:state.updating = 0
  endtry
endfunction

function! s:show_no_commits(state) abort
  let a:state.commit_index = -1
  let a:state.file_index = -1
  call s:set_lines(a:state.commits_buf,
        \ ['# ' . a:state.list_title, '   (no commits)'])

  let file_header = [
        \ '# ' . a:state.list_title,
        \ '# No commit selected',
        \ ]
  if a:state.show_help
    call add(file_header, '# t:tree r:refresh ?:hide')
    call add(file_header, '# <leader>gq:quit')
  endif
  call add(file_header, '')

  let a:state.files = []
  let a:state.files_header = len(file_header)
  let a:state.file_line_map = []
  let a:state.file_line_for_index = []
  let a:state.display_file_indexes = []
  call s:set_lines(a:state.files_buf, file_header + ['   (no commits)'])

  call s:show_side_message(a:state, ['(no commits)'])
  call s:set_cursor(a:state.commits_win, 1)
  call s:set_cursor(a:state.files_win, 1)
endfunction


function! git_changes#open(...) abort
  let root = s:repo_root()
  if empty(root)
    call s:err('not inside a Git repository')
    return
  endif

  if !empty(s:cur_state())
    call s:err('already in a GitChanges tab; use :GitChangesQuit first')
    return
  endif

  let args = a:000
  if len(args) > 2
    call s:err('usage: :GitChanges [ref1] [ref2]')
    return
  endif

  let start_entries = []
  let log_range = ''
  let has_head = 0

  if empty(args)
    let head = s:resolve_ref(root, 'HEAD')
    let has_head = !empty(head)
    let branch = s:current_branch(root)
    let list_title = 'Branch: ' . branch
    if has_head && get(g:, 'git_changes_show_worktree', 1)
      call add(start_entries, {
            \ 'kind': 'worktree',
            \ 'short': 'WORK',
            \ 'subject': 'Working tree changes',
            \ 'sha': '',
            \ 'old_ref': '',
            \ 'new_ref': '',
            \ 'old_label': 'HEAD',
            \ 'new_label': 'WORKTREE',
            \ })
    endif
  elseif len(args) == 1
    let old_ref = s:resolve_ref(root, args[0])
    if empty(old_ref)
      call s:err('unknown revision: ' . args[0])
      return
    endif
    let new_ref = s:resolve_ref(root, 'HEAD')
    if empty(new_ref)
      call s:err('HEAD has no commits')
      return
    endif
    let old_label = args[0]
    let new_label = 'HEAD'
    call add(start_entries, {
          \ 'kind': 'compare',
          \ 'short': 'CMP',
          \ 'subject': old_label . ' ↔ ' . new_label,
          \ 'sha': '',
          \ 'old_ref': old_ref,
          \ 'new_ref': new_ref,
          \ 'old_label': old_label,
          \ 'new_label': new_label,
          \ })
    let list_title = old_label . '..' . new_label
    let log_range = old_ref . '..' . new_ref
  else
    let old_ref = s:resolve_ref(root, args[0])
    if empty(old_ref)
      call s:err('unknown revision: ' . args[0])
      return
    endif
    let new_ref = s:resolve_ref(root, args[1])
    if empty(new_ref)
      call s:err('unknown revision: ' . args[1])
      return
    endif
    let old_label = args[0]
    let new_label = args[1]
    call add(start_entries, {
          \ 'kind': 'compare',
          \ 'short': 'CMP',
          \ 'subject': old_label . ' ↔ ' . new_label,
          \ 'sha': '',
          \ 'old_ref': old_ref,
          \ 'new_ref': new_ref,
          \ 'old_label': old_label,
          \ 'new_label': new_label,
          \ })
    let list_title = old_label . '..' . new_label
    let log_range = old_ref . '..' . new_ref
  endif

  let next_id = get(s:, 'next_id', 0) + 1
  let s:next_id = next_id
  let state = {
        \ 'id': next_id,
        \ 'root': root,
        \ 'tab': 0,
        \ 'commits': [],
        \ 'files': [],
        \ 'commit_index': -1,
        \ 'file_index': -1,
        \ 'commits_header': 1,
        \ 'files_header': 1,
        \ 'updating': 1,
        \ 'list_title': list_title,
        \ 'log_range': log_range,
        \ 'start_entries': start_entries,
        \ 'has_head': has_head,
        \ 'log_ref': '',
        \ 'show_help': 0,
        \ 'file_tree': get(g:, 'git_changes_tree_view', 0) ? 1 : 0,
        \ 'file_line_map': [],
        \ 'file_line_for_index': [],
        \ 'display_file_indexes': [],
        \ 'branches': [],
        \ 'branch_index': -1,
        \ 'branch_header': 2,
        \ 'files_buf': -1,
        \ 'commits_buf': -1,
        \ 'old_buf': -1,
        \ 'new_buf': -1,
        \ 'branches_buf': -1,
        \ 'files_win': 0,
        \ 'commits_win': 0,
        \ 'old_win': 0,
        \ 'new_win': 0,
        \ 'branches_win': 0,
        \ }

  tabnew
  let initial_buf = bufnr('%')
  let state.tab = tabpagenr()
  let t:git_changes = state
  call add(s:instances, state)

  let top_left_win = win_getid()
  rightbelow vsplit
  let old_win = win_getid()
  rightbelow vsplit
  let new_win = win_getid()
  call win_gotoid(top_left_win)
  belowright split
  let bottom_left_win = win_getid()
  belowright split
  let branch_win = win_getid()

  call win_gotoid(top_left_win)
  let state.files_win = win_getid()
  let state.files_buf = s:new_scratch(
        \ printf('[GitChanges %d] Files', next_id), 'gitchanges')
  call s:init_list_buffer(state, 'files')

  call win_gotoid(bottom_left_win)
  let state.commits_win = win_getid()
  let state.commits_buf = s:new_scratch(
        \ printf('[GitChanges %d] Commits', next_id), 'gitchanges')
  call s:init_list_buffer(state, 'commits')

  call win_gotoid(branch_win)
  let state.branches_win = win_getid()
  let state.branches_buf = s:new_scratch(
        \ printf('[GitChanges %d] Branches', next_id), 'gitchanges')
  call s:init_branch_buffer(state)

  call win_gotoid(old_win)
  let state.old_win = win_getid()
  let state.old_buf = s:new_scratch(
        \ printf('[GitChanges %d] Old', next_id), '')
  call s:init_diff_buffer(state, 'old')

  call win_gotoid(new_win)
  let state.new_win = win_getid()
  let state.new_buf = s:new_scratch(
        \ printf('[GitChanges %d] New', next_id), '')
  call s:init_diff_buffer(state, 'new')

  call win_execute(state.old_win, 'diffthis')
  call win_execute(state.new_win, 'diffthis')

  if initial_buf > 0 && bufexists(initial_buf)
        \ && empty(bufname(initial_buf))
        \ && !getbufvar(initial_buf, '&modified')
    execute 'silent! bwipeout ' . initial_buf
  endif

  let width = s:opt_int('git_changes_width', 40)
  let total_left = max([12, &lines - 4])
  let branch_height = max([4, min([
        \ s:opt_int('git_changes_branches_height', 8), total_left / 4])])
  let commit_height = max([5, min([
        \ s:opt_int('git_changes_commits_height', 12), total_left / 3])])
  if total_left - branch_height - commit_height < 4
    let commit_height = max([4, total_left - branch_height - 4])
  endif

  call win_gotoid(state.files_win)
  silent! execute 'vertical resize ' . width
  let side_total = winwidth(state.old_win) + winwidth(state.new_win) + 1
  let side_width = max([20, side_total / 2])
  call win_gotoid(state.old_win)
  silent! execute 'vertical resize ' . side_width
  call win_gotoid(state.commits_win)
  silent! execute 'resize ' . commit_height
  call win_gotoid(state.branches_win)
  silent! execute 'resize ' . branch_height

  call s:load_branches(state, '')
  call s:load_commits(state)
  if empty(state.commits)
    call s:show_no_commits(state)
  else
    call s:select_commit(state, 0)
  endif

  let state.updating = 0
  call win_gotoid(state.files_win)
endfunction

function! git_changes#quit() abort
  let state = s:find_state()
  if empty(state)
    call s:err('no GitChanges tab found')
    return
  endif

  let wins = win_findbuf(state.files_buf)
  if empty(wins)
    let wins = win_findbuf(state.commits_buf)
  endif
  if empty(wins)
    let wins = win_findbuf(state.old_buf)
  endif
  if empty(wins)
    let wins = win_findbuf(state.new_buf)
  endif
  if empty(wins)
    let wins = win_findbuf(state.branches_buf)
  endif

  if !empty(wins)
    let tabwin = win_id2tabwin(wins[0])
    let tabnr = tabwin[0]
    if tabnr > 0
      execute 'tabclose ' . tabnr
    endif
  endif

  for buf in [state.files_buf, state.commits_buf, state.old_buf,
        \ state.new_buf, state.branches_buf]
    if bufexists(buf)
      execute 'silent! bwipeout! ' . buf
    endif
  endfor

  call s:forget(state)
endfunction
