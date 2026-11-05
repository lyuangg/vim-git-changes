
let s:sid = expand('<SID>')
let s:instances = []


function! s:err(msg) abort
  echohl ErrorMsg
  echomsg 'GitChanges: ' . a:msg
  echohl None
endfunction

" Statusline groups on purpose set no background color, so the GitChanges
" panes blend with the window instead of drawing a colored bar. Foreground
" colors are copied from the colorscheme when the first statusline is drawn.
let s:statusline_hl_ready = 0

function! s:define_no_bg_group(group, source, attrs) abort
  if hlexists(a:group)
    return
  endif

  let guifg = synIDattr(synIDtrans(hlID(a:source)), 'fg#', 'gui')
  let ctermfg = synIDattr(synIDtrans(hlID(a:source)), 'fg', 'cterm')
  let parts = []
  if !empty(a:attrs)
    call add(parts, 'term=' . a:attrs)
    call add(parts, 'cterm=' . a:attrs)
    call add(parts, 'gui=' . a:attrs)
  endif
  if !empty(guifg)
    call add(parts, 'guifg=' . guifg)
  endif
  if !empty(ctermfg)
    call add(parts, 'ctermfg=' . ctermfg)
  endif
  call add(parts, 'ctermbg=NONE')
  call add(parts, 'guibg=NONE')
  execute 'highlight ' . a:group . ' ' . join(parts, ' ')
endfunction

function! s:init_statusline_highlights() abort
  if s:statusline_hl_ready
    return
  endif
  let s:statusline_hl_ready = 1
  call s:define_no_bg_group('GitChangesPaneStatus', 'Normal', '')
  call s:define_no_bg_group('GitChangesPaneIndex', 'Title', '')
  call s:define_no_bg_group('GitChangesPaneName', 'Title', 'bold')
  call s:define_no_bg_group('GitChangesPaneInfo', 'Comment', '')
endfunction

function! s:output_message(lines) abort
  let lines = filter(copy(a:lines),
        \ '!empty(trim(v:val)) && v:val !~# "^hint:"')
  return empty(lines)
        \ ? 'git command failed'
        \ : s:truncate(join(lines, ' '), 300)
endfunction

function! s:win_in_current_tab(winid) abort
  if !s:win_exists(a:winid)
    return 0
  endif
  let info = getwininfo(a:winid)
  return !empty(info) && info[0].tabnr == tabpagenr()
endfunction

function! s:pane_label(kind) abort
  return a:kind ==# 'files' ? 'Files'
        \ : a:kind ==# 'commits' ? 'Commits'
        \ : 'Branches'
endfunction

function! s:pane_state_text(state, kind) abort
  if a:kind ==# 'files'
    if empty(a:state.commits) || a:state.commit_index < 0
      return 'no commits'
    endif

    let entry = a:state.commits[a:state.commit_index]
    if entry.kind ==# 'worktree'
      let [staged, unstaged, untracked] = s:worktree_summary(a:state.files)
      let parts = []
      if staged > 0
        call add(parts, staged . ' staged')
      endif
      if unstaged > 0
        call add(parts, unstaged . ' unstaged')
      endif
      if untracked > 0
        call add(parts, untracked . ' untracked')
      endif
      return 'worktree ' . (empty(parts) ? 'clean' : join(parts, ', '))
    elseif entry.kind ==# 'compare'
      return s:truncate(a:state.list_title, 48)
    endif
    return entry.short . '  ' . s:truncate(entry.subject, 48)
  elseif a:kind ==# 'commits'
    let commits = len(filter(copy(a:state.commits), 'v:val.kind ==# "commit"'))
    return printf('%s (%d commits)', a:state.list_title, commits)
  endif

  for branch in a:state.branches
    if get(branch, 'current', 0)
      return 'current: ' . branch.name
    endif
  endfor
  return ''
endfunction

" Each left pane shows its own name and a short summary of what it displays.
" Progress messages go to the command line instead of these statuslines.
function! s:update_statusline(state) abort
  if !get(g:, 'git_changes_statusline', 1)
    return
  endif
  call s:init_statusline_highlights()

  let panes = [
        \ ['1', 'files', get(a:state, 'files_win', 0)],
        \ ['2', 'commits', get(a:state, 'commits_win', 0)],
        \ ['3', 'branches', get(a:state, 'branches_win', 0)],
        \ ]
  for [number, kind, winid] in panes
    if !s:win_in_current_tab(winid)
      continue
    endif

    let text = printf('%%#GitChangesPaneIndex#%s%%#GitChangesPaneName# %s',
          \ number, s:pane_label(kind))
    let detail = s:pane_state_text(a:state, kind)
    if !empty(detail)
      let text .= printf('%%#GitChangesPaneInfo# %%<· %s',
            \ substitute(detail, '%', '%%', 'g'))
    endif
    let text .= '%#GitChangesPaneStatus#'
    call win_execute(winid, 'let &l:statusline = ' . string(text))
  endfor
endfunction

function! s:set_status(state, msg, ...) abort
  let kind = a:0 ? a:1 : 'info'
  let a:state.status = a:msg
  let a:state.status_kind = kind

  if kind ==# 'error'
    call s:err(a:msg)
  else
    echomsg 'GitChanges: ' . a:msg
  endif
  redraw
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
    return 0
  endif

  let target = empty(a:lines) ? [''] : a:lines
  let current = getbufline(a:buf, 1, '$')
  if current ==# target
    return 0
  endif

  let was_modifiable = getbufvar(a:buf, '&modifiable')
  call setbufvar(a:buf, '&modifiable', 1)
  try
    call setbufline(a:buf, 1, target)
    if len(current) > len(target)
      silent call deletebufline(a:buf, len(target) + 1, '$')
    endif
  finally
    call setbufvar(a:buf, '&modifiable', was_modifiable ? 1 : 0)
  endtry
  return 1
endfunction

function! s:win_exists(winid) abort
  return a:winid > 0 && !empty(getwininfo(a:winid))
endfunction

function! s:set_cursor(winid, lnum) abort
  if !s:win_exists(a:winid)
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
  if !s:win_exists(a:winid)
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


function! s:default_keymaps() abort
  return {
        \ 'toggle_tree': 't',
        \ 'refresh': 'r',
        \ 'stage': 's',
        \ 'unstage': 'u',
        \ 'stage_all': 'S',
        \ 'unstage_all': 'U',
        \ 'toggle_stage': '-',
        \ 'file_discard': 'd',
        \ 'open_file': 'o',
        \ 'scroll_half_down': '<C-d>',
        \ 'scroll_half_up': '<C-u>',
        \ 'copy_file': 'yy',
        \ 'copy_commit': 'yy',
        \ 'copy_branch': 'yy',
        \ 'edit_message': 'e',
        \ 'commit': 'cc',
        \ 'commit_editor': 'C',
        \ 'pull': 'p',
        \ 'push': 'P',
        \ 'new_branch': 'cb',
        \ 'branch_delete': 'd',
        \ 'checkout_branch': 'co',
        \ 'apply_branch': '<CR>',
        \ 'cycle_next': '<Tab>',
        \ 'cycle_prev': '<S-Tab>',
        \ 'worktree': '<Esc>',
        \ 'pane_files': '1',
        \ 'pane_commits': '2',
        \ 'pane_branches': '3',
        \ 'diff_left': 'H',
        \ 'diff_right': 'L',
        \ 'quit': 'q',
        \ }
endfunction

function! s:keymaps_enabled() abort
  return get(g:, 'git_changes_keymaps_enabled', 1) ? 1 : 0
endfunction

function! s:keymaps() abort
  let maps = s:default_keymaps()
  let user = get(g:, 'git_changes_keymaps', {})
  if type(user) == type({})
    call extend(maps, user, 'force')
  endif
  return maps
endfunction

function! s:map_fixed(key, rhs) abort
  if !s:keymaps_enabled()
    return
  endif
  execute 'silent! nnoremap <buffer> <silent> ' . a:key . ' ' . a:rhs
endfunction

function! s:map_keys(action, rhs) abort
  if !s:keymaps_enabled()
    return
  endif

  let value = get(s:keymaps(), a:action, '')
  if type(value) == type([])
    let keys = value
  elseif type(value) == type('')
    let keys = [value]
  else
    return
  endif

  for key in keys
    if empty(key)
      continue
    endif
    execute 'silent! nnoremap <buffer> <silent> ' . key . ' ' . a:rhs
  endfor
endfunction

function! s:map_quit() abort
  call s:map_keys('quit', ':<C-u>GitChangesQuit<CR>')
endfunction

function! s:map_left_pane_keys() abort
  call s:map_keys('pane_files', ':<C-u>call ' . s:sid . 'goto_left_pane(1)<CR>')
  call s:map_keys('pane_commits', ':<C-u>call ' . s:sid . 'goto_left_pane(2)<CR>')
  call s:map_keys('pane_branches', ':<C-u>call ' . s:sid . 'goto_left_pane(3)<CR>')
endfunction

function! s:map_left_action_keys() abort
  call s:map_keys('commit', ':<C-u>call ' . s:sid . 'commit_current()<CR>')
  call s:map_keys('commit_editor', ':<C-u>call ' . s:sid . 'commit_with_editor()<CR>')
  call s:map_keys('pull', ':<C-u>call ' . s:sid . 'pull_current()<CR>')
  call s:map_keys('push', ':<C-u>call ' . s:sid . 'push_current()<CR>')
  call s:map_keys('new_branch', ':<C-u>call ' . s:sid . 'new_branch()<CR>')
endfunction

function! s:init_list_buffer(state, kind) abort
  let b:git_changes = a:state
  let b:gc_kind = a:kind

  call s:setup_list_window()

  call s:map_fixed('j', ':<C-u>call ' . s:sid . 'move_cursor(1)<CR>')
  call s:map_fixed('k', ':<C-u>call ' . s:sid . 'move_cursor(-1)<CR>')
  call s:map_fixed('<Down>', ':<C-u>call ' . s:sid . 'move_cursor(1)<CR>')
  call s:map_fixed('<Up>', ':<C-u>call ' . s:sid . 'move_cursor(-1)<CR>')
  call s:map_fixed('J', ':<C-u>call ' . s:sid . 'scroll_diff(1)<CR>')
  call s:map_fixed('K', ':<C-u>call ' . s:sid . 'scroll_diff(-1)<CR>')
  call s:map_keys('refresh', ':<C-u>call ' . s:sid . 'refresh_all()<CR>')
  call s:map_keys('cycle_next', ':<C-u>call ' . s:sid . 'cycle_pane(1)<CR>')
  call s:map_keys('cycle_prev', ':<C-u>call ' . s:sid . 'cycle_pane(-1)<CR>')
  call s:map_left_pane_keys()
  call s:map_left_action_keys()
  call s:map_keys('worktree', ':<C-u>call ' . s:sid . 'goto_worktree()<CR>')

  if a:kind ==# 'files'
    call s:map_keys('toggle_tree', ':<C-u>call ' . s:sid . 'toggle_tree()<CR>')
    call s:map_fixed('?', ':<C-u>call ' . s:sid . 'toggle_help()<CR>')
    call s:map_keys('stage', ':<C-u>call ' . s:sid . 'stage_current("stage")<CR>')
    call s:map_keys('unstage', ':<C-u>call ' . s:sid . 'stage_current("unstage")<CR>')
    call s:map_keys('stage_all', ':<C-u>call ' . s:sid . 'stage_all()<CR>')
    call s:map_keys('unstage_all', ':<C-u>call ' . s:sid . 'unstage_all()<CR>')
    call s:map_keys('toggle_stage', ':<C-u>call ' . s:sid . 'stage_current("toggle")<CR>')
    call s:map_keys('file_discard', ':<C-u>call ' . s:sid . 'discard_current()<CR>')
    call s:map_keys('open_file', ':<C-u>call ' . s:sid . 'open_file()<CR>')
    call s:map_keys('scroll_half_down', ':<C-u>call ' . s:sid . 'scroll_diff_half(1)<CR>')
    call s:map_keys('scroll_half_up', ':<C-u>call ' . s:sid . 'scroll_diff_half(-1)<CR>')
    call s:map_keys('copy_file', ':<C-u>call ' . s:sid . 'copy_file_path()<CR>')
    call s:map_keys('diff_left', ':<C-u>call ' . s:sid . 'scroll_diff_horizontal(-1)<CR>')
    call s:map_keys('diff_right', ':<C-u>call ' . s:sid . 'scroll_diff_horizontal(1)<CR>')
  elseif a:kind ==# 'commits'
    call s:map_keys('copy_commit', ':<C-u>call ' . s:sid . 'copy_commit_hash()<CR>')
    call s:map_keys('edit_message', ':<C-u>call ' . s:sid . 'edit_commit_message()<CR>')
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
  call s:map_keys('open_file', ':<C-u>call ' . s:sid . 'open_file()<CR>')
  call s:map_keys('stage', ':<C-u>call ' . s:sid . 'stage_current("stage")<CR>')
  call s:map_keys('unstage', ':<C-u>call ' . s:sid . 'stage_current("unstage")<CR>')
  call s:map_keys('stage_all', ':<C-u>call ' . s:sid . 'stage_all()<CR>')
  call s:map_keys('unstage_all', ':<C-u>call ' . s:sid . 'unstage_all()<CR>')
  call s:map_keys('toggle_stage', ':<C-u>call ' . s:sid . 'stage_current("toggle")<CR>')
  call s:map_keys('commit', ':<C-u>call ' . s:sid . 'commit_current()<CR>')
  call s:map_keys('pull', ':<C-u>call ' . s:sid . 'pull_current()<CR>')
  call s:map_keys('push', ':<C-u>call ' . s:sid . 'push_current()<CR>')
  call s:map_keys('new_branch', ':<C-u>call ' . s:sid . 'new_branch()<CR>')
  call s:map_keys('commit_editor', ':<C-u>call ' . s:sid . 'commit_with_editor()<CR>')
  call s:map_keys('cycle_next', ':<C-u>call ' . s:sid . 'cycle_pane(1)<CR>')
  call s:map_keys('cycle_prev', ':<C-u>call ' . s:sid . 'cycle_pane(-1)<CR>')
  call s:map_quit()
endfunction

function! s:init_branch_buffer(state) abort
  let b:git_changes = a:state
  let b:gc_kind = 'branches'
  call s:setup_list_window()

  call s:map_fixed('j', ':<C-u>call ' . s:sid . 'move_cursor(1)<CR>')
  call s:map_fixed('k', ':<C-u>call ' . s:sid . 'move_cursor(-1)<CR>')
  call s:map_fixed('<Down>', ':<C-u>call ' . s:sid . 'move_cursor(1)<CR>')
  call s:map_fixed('<Up>', ':<C-u>call ' . s:sid . 'move_cursor(-1)<CR>')
  call s:map_keys('refresh', ':<C-u>call ' . s:sid . 'refresh_all()<CR>')
  call s:map_fixed('?', ':<C-u>call ' . s:sid . 'toggle_branch_help()<CR>')
  call s:map_keys('checkout_branch', ':<C-u>call ' . s:sid . 'checkout_branch()<CR>')
  call s:map_keys('apply_branch', ':<C-u>call ' . s:sid . 'apply_branch()<CR>')
  call s:map_keys('cycle_next', ':<C-u>call ' . s:sid . 'cycle_pane(1)<CR>')
  call s:map_keys('cycle_prev', ':<C-u>call ' . s:sid . 'cycle_pane(-1)<CR>')
  call s:map_left_pane_keys()
  call s:map_left_action_keys()
  call s:map_keys('branch_delete', ':<C-u>call ' . s:sid . 'delete_branch()<CR>')
  call s:map_keys('copy_branch', ':<C-u>call ' . s:sid . 'copy_branch_name()<CR>')
  call s:map_quit()

  augroup git_changes
    autocmd! CursorMoved <buffer>
    execute 'autocmd CursorMoved <buffer> call ' . s:sid . 'on_branch_cursor_moved()'
  augroup END

  call s:update_statusline(a:state)
endfunction

function! s:move_cursor(delta) abort
  let target = line('.') + a:delta
  if target < 1 || target > line('$')
    return
  endif

  call cursor(target, 1)

  let kind = get(b:, 'gc_kind', '')
  if kind ==# 'files'
    call s:on_files_cursor_moved()
  elseif kind ==# 'commits'
    call s:on_commits_cursor_moved()
  elseif kind ==# 'branches'
    call s:on_branch_cursor_moved()
  endif
endfunction

" Pick the diff window to scroll: the side with more content.
function! s:diff_scroll_window(state) abort
  let old_ok = a:state.old_win > 0 && win_id2win(a:state.old_win) > 0
  let new_ok = a:state.new_win > 0 && win_id2win(a:state.new_win) > 0
  if !old_ok && !new_ok
    return 0
  endif

  let winid = old_ok ? a:state.old_win : a:state.new_win
  if old_ok && new_ok
    let old_lines = s:buf_linecount(a:state.old_buf)
    let new_lines = s:buf_linecount(a:state.new_buf)
    if new_lines > old_lines
      let winid = a:state.new_win
    endif
  endif
  return winid
endfunction

function! s:scroll_diff_by(winid, delta, count) abort
  let key = a:delta > 0 ? "\<C-e>" : "\<C-y>"
  let keys = (a:count > 1 ? string(a:count) : '') . key
  if exists('*win_execute')
    call win_execute(a:winid, 'silent! normal! ' . keys)
  else
    let curwin = win_getid()
    call win_gotoid(a:winid)
    execute 'silent! normal! ' . keys
    call win_gotoid(curwin)
  endif
endfunction

" Scroll the right-hand diff one line without changing the selected file.
function! s:scroll_diff(delta) abort
  let state = s:cur_state()
  if empty(state)
    return
  endif

  let winid = s:diff_scroll_window(state)
  if winid <= 0
    return
  endif
  call s:scroll_diff_by(winid, a:delta, 1)
endfunction

" Scroll the right-hand diff by half a page.
function! s:scroll_diff_half(delta) abort
  let state = s:cur_state()
  if empty(state)
    return
  endif

  let winid = s:diff_scroll_window(state)
  if winid <= 0
    return
  endif
  let info = getwininfo(winid)
  let lines_to_scroll = empty(info) ? 1 : info[0].height / 2
  if lines_to_scroll < 1
    let lines_to_scroll = 1
  endif
  call s:scroll_diff_by(winid, a:delta, lines_to_scroll)
endfunction

function! s:debounce_delay() abort
  let value = get(g:, 'git_changes_debounce_ms', 300)
  if type(value) != type(0)
    return 300
  endif
  return value > 0 ? value : 0
endfunction

function! s:can_debounce() abort
  return exists('*timer_start') && s:debounce_delay() > 0
endfunction

function! s:cancel_pending(state) abort
  if get(a:state, 'file_timer', -1) != -1
    call timer_stop(a:state.file_timer)
    let a:state.file_timer = -1
  endif
  if get(a:state, 'commit_timer', -1) != -1
    call timer_stop(a:state.commit_timer)
    let a:state.commit_timer = -1
  endif
endfunction

function! s:flush_pending(state) abort
  if get(a:state, 'commit_timer', -1) != -1
    call s:cancel_pending(a:state)
    call s:apply_commit_select(a:state)
  elseif get(a:state, 'file_timer', -1) != -1
    call timer_stop(a:state.file_timer)
    let a:state.file_timer = -1
    call s:apply_file_diff(a:state)
  endif
endfunction

function! s:schedule_file_diff(state) abort
  if get(a:state, 'commit_timer', -1) != -1
    return
  endif
  if !s:can_debounce()
    call s:apply_file_diff(a:state)
    return
  endif
  if get(a:state, 'file_timer', -1) != -1
    call timer_stop(a:state.file_timer)
  endif
  let a:state.file_timer = timer_start(s:debounce_delay(),
        \ {-> s:apply_file_diff(a:state)})
endfunction

function! s:apply_file_diff(state) abort
  let a:state.file_timer = -1
  if !s:state_alive(a:state)
    return
  endif
  if a:state.commit_index < 0 || a:state.commit_index >= len(a:state.commits)
    return
  endif
  if a:state.file_index < 0 || a:state.file_index >= len(a:state.files)
    return
  endif
  call s:show_diff(a:state, a:state.files[a:state.file_index])
endfunction

function! s:schedule_commit_select(state, index) abort
  let a:state.commit_index = a:index
  if get(a:state, 'file_timer', -1) != -1
    call timer_stop(a:state.file_timer)
    let a:state.file_timer = -1
  endif
  if !s:can_debounce()
    call s:apply_commit_select(a:state)
    return
  endif
  if get(a:state, 'commit_timer', -1) != -1
    call timer_stop(a:state.commit_timer)
  endif
  let a:state.commit_timer = timer_start(s:debounce_delay(),
        \ {-> s:apply_commit_select(a:state)})
endfunction

function! s:apply_commit_select(state) abort
  let a:state.commit_timer = -1
  if !s:state_alive(a:state)
    return
  endif
  let index = a:state.commit_index
  if index < 0 || index >= len(a:state.commits)
    return
  endif
  call s:cancel_pending(a:state)
  call s:select_commit(a:state, index)
endfunction

function! s:on_files_cursor_moved() abort
  let state = s:cur_state()
  if empty(state) || get(state, 'updating', 0)
    return
  endif

  let offset = line('.') - state.files_header - 1
  if offset < 0 || offset >= len(state.file_line_map)
    return
  endif
  let index = state.file_line_map[offset]
  if index < 0 || index >= len(state.files) || index == state.file_index
    return
  endif

  let state.file_index = index
  call s:schedule_file_diff(state)
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

  call s:schedule_commit_select(state, index)
endfunction

function! s:cycle_pane(delta) abort
  let state = s:cur_state()
  if empty(state)
    return
  endif

  let windows = [state.files_win, state.commits_win, state.branches_win,
        \ state.old_win, state.new_win]
  let current = win_getid()
  let target = 0
  for i in range(len(windows))
    if windows[i] == current
      let target = (i + a:delta + len(windows)) % len(windows)
      break
    endif
  endfor

  for _ in range(len(windows))
    let winid = windows[target]
    if s:win_exists(winid)
      call win_gotoid(winid)
      return
    endif
    let target = (target + a:delta + len(windows)) % len(windows)
  endfor
endfunction

" Scroll both diff windows horizontally without changing focus.
function! s:scroll_diff_horizontal(delta) abort
  let state = s:cur_state()
  if empty(state)
    return
  endif

  let key = a:delta > 0 ? 'zl' : 'zh'
  for winid in [state.old_win, state.new_win]
    if s:win_exists(winid)
      call win_execute(winid, 'silent! normal! ' . key)
    endif
  endfor
endfunction

function! s:goto_left_pane(index) abort
  let state = s:cur_state()
  if empty(state) || a:index < 1 || a:index > 3
    return
  endif

  let windows = [state.files_win, state.commits_win, state.branches_win]
  let winid = windows[a:index - 1]
  if winid > 0 && win_id2win(winid) > 0
    call win_gotoid(winid)
  endif
endfunction

" Jump back to the working tree changes from any commit or compare view.
function! s:goto_worktree() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif
  call s:flush_pending(state)

  let branch = s:current_branch(state.root)
  if empty(state.log_range) && (empty(state.log_ref) || state.log_ref ==# branch)
    for index in range(len(state.commits))
      if state.commits[index].kind ==# 'worktree'
        if index != state.commit_index
          call s:select_commit(state, index)
        endif
        return
      endif
    endfor
  endif

  " The current view has no working tree entry (another branch, a compare
  " range, or the entry is disabled): reload the current branch.
  call s:reload_current_branch(state)
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

function! s:toggle_branch_help() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif

  let keep_name = ''
  if state.branch_index >= 0 && state.branch_index < len(state.branches)
    let keep_name = state.branches[state.branch_index].name
  endif
  let state.branch_show_help = !get(state, 'branch_show_help', 0)
  call s:load_branches(state, keep_name)
endfunction

function! s:git_run(root, args) abort
  let cmd = 'git --no-pager -c core.quotePath=false -c credential.interactive=never -C '
        \ . shellescape(a:root) . ' ' . a:args . ' 2>&1'
  let out = systemlist(cmd)
  return {'ok': v:shell_error == 0, 'out': out}
endfunction

function! s:git_do(root, args) abort
  let result = s:git_run(a:root, a:args)
  if !result.ok
    call s:err(s:output_message(result.out))
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

function! s:refresh_debounce_delay() abort
  let value = get(g:, 'git_changes_refresh_debounce_ms', 1000)
  if type(value) != type(0)
    return 1000
  endif
  return value > 0 ? value : 0
endfunction

function! s:cancel_refresh(state) abort
  if get(a:state, 'refresh_timer', -1) != -1
    call timer_stop(a:state.refresh_timer)
    let a:state.refresh_timer = -1
  endif
endfunction

function! s:apply_pending_refresh(state) abort
  let a:state.refresh_timer = -1
  call s:do_refresh_all(a:state)
endfunction

function! s:refresh_all() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif

  call s:set_status(state, 'Refreshing...', 'busy')

  let delay = s:refresh_debounce_delay()
  if !exists('*timer_start') || delay <= 0
    call s:do_refresh_all(state)
    return
  endif

  call s:cancel_refresh(state)
  let state.refresh_timer = timer_start(delay,
        \ {-> s:apply_pending_refresh(state)})
endfunction

function! s:do_refresh_all(state) abort
  let state = a:state
  if get(state, 'refreshing', 0) || !s:state_alive(state)
    return
  endif

  call s:flush_pending(state)
  let state.refreshing = 1
  let old_lazy = &lazyredraw
  set lazyredraw
  try
    let keep_kind = ''
    let keep_sha = ''
    let keep_index = state.commit_index
    if state.commit_index >= 0 && state.commit_index < len(state.commits)
      let entry = state.commits[state.commit_index]
      let keep_kind = entry.kind
      let keep_sha = get(entry, 'sha', '')
    endif

    let keep_path = ''
    if state.file_index >= 0 && state.file_index < len(state.files)
      let keep_path = state.files[state.file_index].path
    endif

    let keep_branch = ''
    if state.branch_index >= 0 && state.branch_index < len(state.branches)
      let keep_branch = state.branches[state.branch_index].name
    endif

    let state.updating = 1
    try
      call s:load_branches(state, keep_branch)
      call s:load_commits(state)
    finally
      let state.updating = 0
    endtry

    if empty(state.commits)
      call s:show_no_commits(state)
      return
    endif

    let new_index = -1
    for i in range(len(state.commits))
      let candidate = state.commits[i]
      if !empty(keep_sha)
        if get(candidate, 'sha', '') ==# keep_sha
          let new_index = i
          break
        endif
      elseif candidate.kind ==# keep_kind
        let new_index = i
        break
      endif
    endfor
    if new_index < 0
      let new_index = min([max([keep_index, 0]), len(state.commits) - 1])
    endif

    let state.commit_index = new_index
    call s:set_cursor(state.commits_win, state.commits_header + 1 + new_index)
    call s:refresh_file_list(state, keep_path)
  finally
    let &lazyredraw = old_lazy
    let state.refreshing = 0
    call s:set_status(state, 'Refreshed', 'info')
  endtry
endfunction

function! s:discard_current() abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif
  call s:flush_pending(state)

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

function! s:open_file() abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif
  call s:flush_pending(state)

  let index = s:current_file_index(state)
  if index < 0 || index >= len(state.files)
    call s:err('select a file first')
    return
  endif

  let path = state.root . '/' . state.files[index].path
  if !filereadable(path)
    call s:err('file does not exist: ' . state.files[index].path)
    return
  endif

  execute 'tabnew ' . fnameescape(path)
endfunction

function! s:copy_file_path() abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif
  call s:flush_pending(state)

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

function! s:copy_commit_hash() abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    call s:err('select a commit first')
    return
  endif
  call s:flush_pending(state)

  let entry = state.commits[state.commit_index]
  if entry.kind !=# 'commit'
    call s:err('select a commit first')
    return
  endif

  if s:copy_to_clipboard(entry.sha)
    echomsg 'Copied commit: ' . entry.short
  else
    call s:err('clipboard not available')
  endif
endfunction

function! s:is_ancestor(root, ancestor, descendant) abort
  let cmd = 'git --no-pager -C ' . shellescape(a:root)
        \ . ' merge-base --is-ancestor '
        \ . shellescape(a:ancestor) . ' ' . shellescape(a:descendant)
        \ . ' 2>&1'
  call system(cmd)
  return v:shell_error == 0
endfunction

function! s:git_in_progress(root) abort
  let gitdir = s:git_one(a:root, 'rev-parse --absolute-git-dir')
  if empty(gitdir)
    return ''
  endif

  for marker in ['MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD',
        \ 'BISECT_LOG']
    if filereadable(gitdir . '/' . marker)
      return marker
    endif
  endfor
  for marker in ['rebase-merge', 'rebase-apply', 'sequencer']
    if isdirectory(gitdir . '/' . marker)
      return marker
    endif
  endfor
  return ''
endfunction

function! s:edit_commit_message() abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    call s:err('select a commit first')
    return
  endif
  call s:flush_pending(state)

  let entry = state.commits[state.commit_index]
  if entry.kind !=# 'commit'
    call s:err('select a commit first')
    return
  endif

  let in_progress = s:git_in_progress(state.root)
  if !empty(in_progress)
    call s:err('finish or abort the current Git operation first ('
          \ . in_progress . ')')
    return
  endif

  let branch = s:git_one(state.root, 'symbolic-ref --short -q HEAD')
  if empty(branch)
    call s:err('cannot edit a commit message in detached HEAD')
    return
  endif
  if !empty(state.log_ref) && state.log_ref !=# branch
    call s:err('check out ' . state.log_ref . ' to edit its commits')
    return
  endif
  if !s:is_ancestor(state.root, entry.sha, 'HEAD')
    call s:err('commit is not on the current branch')
    return
  endif

  let head_sha = s:git_one(state.root, 'rev-parse HEAD')
  let is_head = entry.sha ==# head_sha
  let has_remote = !empty(s:git(state.root, 'remote'))
  if has_remote && !get(entry, 'unpushed', 0)
    call s:err('only unpushed commits can be edited')
    return
  endif

  if !is_head
        \ && !empty(s:git(state.root, 'status --porcelain --untracked-files=no'))
    call s:err('commit or stash changes before editing an older commit')
    return
  endif

  if !is_head && get(g:, 'git_changes_confirm_rewrite', 1)
    let rewrite_count = s:git_one(state.root,
          \ 'rev-list --count ' . shellescape(entry.sha . '..' . branch))
    let total = empty(rewrite_count) ? 1 : str2nr(rewrite_count) + 1
    let prompt = printf('Rewrite %d commit(s) on %s? '
          \ . 'Other branches will not be updated. Continue?', total, branch)
    if confirm(prompt, "&Yes\n&No", 2) != 1
      return
    endif
  endif

  let message = s:git(state.root,
        \ 'log -1 --format=%B ' . shellescape(entry.sha))
  while !empty(message) && empty(trim(message[-1]))
    call remove(message, -1)
  endwhile
  if empty(message)
    let message = [entry.subject]
  endif

  let msgfile = tempname()
  tabnew
  execute 'silent! file ' . fnameescape(msgfile)
  setlocal buftype=acwrite
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal filetype=gitcommit
  call setline(1, message)
  setlocal nomodified
  nnoremap <buffer> <silent> q :<C-u>quit<CR>

  let b:git_changes_edit = {
        \ 'state': state,
        \ 'sha': entry.sha,
        \ 'branch': branch,
        \ 'is_head': is_head,
        \ }
  augroup git_changes_edit_message
    autocmd! * <buffer>
    execute 'autocmd BufWriteCmd <buffer> call '
          \ . s:sid . 'apply_edited_message()'
  augroup END

  call cursor(1, 1)
  echomsg 'Edit the message, then :w to save or :q to cancel'
endfunction

function! s:delete_ref_tree(root, prefix) abort
  for ref in s:git(a:root,
        \ 'for-each-ref ' . shellescape('--format=%(refname)') . ' '
        \ . shellescape(a:prefix))
    call s:git(a:root, 'update-ref -d ' . shellescape(ref))
  endfor
endfunction

" Rewrite the target message with filter-branch so merge history is preserved
" without replaying patches (which can cause conflicts).
function! s:reword_commit(info, msgfile) abort
  let root = a:info.state.root
  let sha = a:info.sha
  let branch = a:info.branch
  let unique = a:info.state.id . '-' . localtime()
  let state_ref = 'refs/gitchanges/state-' . unique
  let backup_ns = 'refs/gitchanges/backup-' . unique

  let filter = 'if [ "$GIT_COMMIT" = ' . shellescape(sha) . ' ]; then cat '
        \ . shellescape(a:msgfile) . '; else cat; fi'
  let parent = s:git_one(root,
        \ 'rev-parse --verify -q ' . shellescape(sha . '^'))
  let range = empty(parent)
        \ ? '--root ' . shellescape(branch)
        \ : shellescape(sha . '^..' . branch)
  let args = 'filter-branch -f'
        \ . ' --original ' . shellescape(backup_ns)
        \ . ' --state-branch ' . shellescape(state_ref)
        \ . ' --msg-filter ' . shellescape(filter)
        \ . ' -- ' . range

  let old_head = s:git_one(root, 'rev-parse HEAD')
  let old_tree = s:git_one(root, 'rev-parse HEAD^{tree}')
  let old_count = s:git_one(root, 'rev-list --count HEAD')
  let old_merges = s:git_one(root, 'rev-list --count --merges HEAD')

  let old_squelch = $FILTER_BRANCH_SQUELCH_WARNING
  let $FILTER_BRANCH_SQUELCH_WARNING = '1'
  try
    let ok = s:git_do(root, args)
  finally
    let $FILTER_BRANCH_SQUELCH_WARNING = old_squelch
  endtry

  let new_sha = ''
  let new_head = ''
  if ok
    for line in s:git(root,
          \ 'show ' . shellescape(state_ref . ':filter.map'))
      let parts = split(line, ':')
      if len(parts) >= 2 && parts[0] ==# sha
        let new_sha = parts[1]
        break
      endif
    endfor

    let new_head = s:git_one(root, 'rev-parse HEAD')
    let new_tree = s:git_one(root, 'rev-parse HEAD^{tree}')
    let new_count = s:git_one(root, 'rev-list --count HEAD')
    let new_merges = s:git_one(root, 'rev-list --count --merges HEAD')
    if empty(new_head)
          \ || new_tree !=# old_tree
          \ || str2nr(new_count) != str2nr(old_count)
          \ || str2nr(new_merges) != str2nr(old_merges)
      if !empty(old_head)
        call s:git(root, 'update-ref '
              \ . shellescape('refs/heads/' . branch) . ' '
              \ . shellescape(old_head))
      endif
      call s:err('rewrite verification failed; branch restored')
      let ok = 0
      let new_sha = ''
    endif
  endif

  if ok && empty(new_sha)
    let new_sha = new_head
  endif

  call s:delete_ref_tree(root, state_ref)
  call s:delete_ref_tree(root, backup_ns)
  return new_sha
endfunction

function! s:reload_after_reword(state, sha) abort
  let a:state.updating = 1
  try
    call s:load_commits(a:state)
  finally
    let a:state.updating = 0
  endtry

  let index = -1
  for i in range(len(a:state.commits))
    if get(a:state.commits[i], 'sha', '') ==# a:sha
      let index = i
      break
    endif
  endfor
  if index < 0 && !empty(a:state.commits)
    let index = 0
  endif
  if index >= 0
    call s:select_commit(a:state, index)
  endif
endfunction

function! s:apply_edited_message() abort
  let info = get(b:, 'git_changes_edit', {})
  if empty(info)
    return
  endif

  let message = getline(1, '$')
  while !empty(message) && empty(trim(message[-1]))
    call remove(message, -1)
  endwhile
  if empty(message) || empty(trim(message[0]))
    call s:err('commit message cannot be empty')
    return
  endif

  let msgfile = tempname()
  call writefile(message, msgfile)
  let target_sha = info.sha
  try
    if info.is_head
      if !s:git_do(info.state.root,
            \ 'commit --amend --only -F ' . shellescape(msgfile))
        return
      endif
      let target_sha = s:git_one(info.state.root, 'rev-parse HEAD')
    else
      let target_sha = s:reword_commit(info, msgfile)
      if empty(target_sha)
        return
      endif
    endif
  finally
    call delete(msgfile)
  endtry

  let info.sha = target_sha
  let info.is_head = target_sha ==# s:git_one(info.state.root, 'rev-parse HEAD')
  setlocal nomodified
  echomsg 'Commit message updated'
  call s:reload_after_reword(info.state, target_sha)
endfunction

function! s:commit_current() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif
  call s:flush_pending(state)

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

function! s:commit_template(state) abort
  let lines = [
        \ '',
        \ '# Please enter the commit message for your changes. Lines starting',
        \ '# with ''#'' will be ignored, and an empty message aborts the commit.',
        \ '#',
        \ '# On branch ' . s:current_branch(a:state.root),
        \ '# Changes to be committed:',
        \ ]

  let labels = {
        \ 'M': 'modified',
        \ 'A': 'new file',
        \ 'D': 'deleted',
        \ 'R': 'renamed',
        \ 'C': 'copied',
        \ 'T': 'typechange',
        \ 'U': 'unmerged',
        \ }
  for line in s:git(a:state.root,
        \ 'diff --cached --name-status --find-renames')
    let parts = split(line, "\t", 1)
    if empty(parts)
      continue
    endif
    let code = strpart(parts[0], 0, 1)
    let label = get(labels, code, 'modified')
    let path = get(parts, 1, '')
    if code ==# 'R' || code ==# 'C'
      let path .= ' -> ' . get(parts, 2, '')
    endif
    call add(lines, printf('#%s%-12s%s', "\t", label . ':', path))
  endfor
  call add(lines, '#')
  return lines
endfunction

function! s:commit_with_editor() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif
  call s:flush_pending(state)

  if !s:has_staged_changes(state.root, [])
    echomsg 'No staged changes to commit'
    return
  endif

  let msgfile = tempname()
  tabnew
  execute 'silent! file ' . fnameescape(msgfile)
  setlocal buftype=acwrite
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal filetype=gitcommit
  call setline(1, s:commit_template(state))
  setlocal nomodified
  nnoremap <buffer> <silent> q :<C-u>quit<CR>

  let b:git_changes_commit = {'state': state}
  augroup git_changes_commit_message
    autocmd! * <buffer>
    execute 'autocmd BufWriteCmd <buffer> call '
          \ . s:sid . 'apply_commit_message()'
  augroup END

  call cursor(1, 1)
  echomsg 'Write the commit message, then :w to commit or :q to cancel'
endfunction

function! s:apply_commit_message() abort
  let info = get(b:, 'git_changes_commit', {})
  if empty(info)
    return
  endif

  let message = filter(getline(1, '$'), 'v:val !~# "^#"')
  while !empty(message) && empty(trim(message[-1]))
    call remove(message, -1)
  endwhile
  while !empty(message) && empty(trim(message[0]))
    call remove(message, 0)
  endwhile
  if empty(message) || empty(trim(message[0]))
    call s:err('commit message cannot be empty')
    return
  endif

  let msgfile = tempname()
  call writefile(message, msgfile)
  try
    let ok = s:git_do(info.state.root,
          \ 'commit --cleanup=strip -F ' . shellescape(msgfile))
  finally
    call delete(msgfile)
  endtry
  if !ok
    return
  endif

  setlocal nomodified
  echomsg 'Committed'
  call s:reload_current_branch(info.state)
endfunction

function! s:reload_current_branch(state) abort
  call s:cancel_pending(a:state)
  call s:cancel_refresh(a:state)
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

function! s:upstream_ref(root) abort
  let result = s:git_run(a:root,
        \ 'rev-parse --abbrev-ref --symbolic-full-name @{u}')
  return result.ok && !empty(result.out) ? result.out[0] : ''
endfunction

function! s:has_upstream(root) abort
  return !empty(s:upstream_ref(a:root))
endfunction

function! s:preferred_remote(root, ...) abort
  let branch = a:0 ? a:1 : ''

  let configured = get(g:, 'git_changes_push_remote', '')
  if !empty(configured)
    return configured
  endif

  if !empty(branch)
    let branch_remote = s:git_one(a:root,
          \ 'config --get ' . shellescape('branch.' . branch . '.remote'))
    if !empty(branch_remote)
      return branch_remote
    endif
  endif

  let remotes = s:git(a:root, 'remote')
  if empty(remotes)
    return ''
  endif
  return index(remotes, 'origin') >= 0 ? 'origin' : remotes[0]
endfunction

function! s:push_result(state, out) abort
  if match(a:out, 'Everything up-to-date') >= 0
    return 'Everything up-to-date'
  endif

  let upstream = s:upstream_ref(a:state.root)
  return empty(upstream) ? 'Push complete' : 'Pushed to ' . upstream
endfunction

function! s:pull_current() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif

  call s:set_status(state, 'Pulling...', 'busy')
  let result = s:git_run(state.root, 'pull --no-rebase --no-edit')
  call s:reload_current_branch(state)

  if !result.ok
    let detail = s:output_message(result.out)
    if detail =~? 'no tracking information\|no upstream branch'
      call s:set_status(state, 'Cannot pull: no upstream branch. ' .
            \ 'Press P to push and set the upstream first.', 'error')
    else
      call s:set_status(state, 'Pull failed: ' . detail, 'error')
    endif
    return
  endif

  if match(result.out, 'Already up to date') >= 0
    call s:set_status(state, 'Already up to date', 'info')
  else
    call s:set_status(state, 'Pull complete', 'info')
  endif
endfunction

function! s:refresh_after_push(state) abort
  let index = a:state.commit_index
  let keep_path = ''
  if a:state.file_index >= 0 && a:state.file_index < len(a:state.files)
    let keep_path = a:state.files[a:state.file_index].path
  endif

  let a:state.updating = 1
  try
    call s:load_commits(a:state)
  finally
    let a:state.updating = 0
  endtry

  if empty(a:state.commits)
    call s:show_no_commits(a:state)
    return
  endif

  let index = min([max([index, 0]), len(a:state.commits) - 1])
  let a:state.commit_index = index
  call s:set_cursor(a:state.commits_win,
        \ a:state.commits_header + 1 + index)
  call s:refresh_file_list(a:state, keep_path)
endfunction

function! s:push_current() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif

  if empty(s:resolve_ref(state.root, 'HEAD'))
    call s:set_status(state, 'Cannot push: no commits yet', 'error')
    return
  endif

  call s:set_status(state, 'Pushing...', 'busy')

  if s:has_upstream(state.root)
    let result = s:git_run(state.root, 'push')
    if !result.ok
      call s:set_status(state, 'Push failed: ' . s:output_message(result.out),
            \ 'error')
      return
    endif
    call s:refresh_after_push(state)
    call s:set_status(state, s:push_result(state, result.out), 'info')
    return
  endif

  let branch = s:git_one(state.root, 'symbolic-ref --short -q HEAD')
  if empty(branch)
    call s:set_status(state, 'Cannot push: not on a branch (detached HEAD)',
          \ 'error')
    return
  endif

  let remote = s:preferred_remote(state.root, branch)
  if empty(remote)
    call s:set_status(state, 'Cannot push: no remote configured', 'error')
    return
  endif

  if get(g:, 'git_changes_confirm_push_upstream', 1)
    let question = printf('No upstream for "%s". Push to %s/%s and set upstream?',
          \ branch, remote, branch)
    if confirm(question, "&Yes\n&No", 1) != 1
      call s:set_status(state, 'Push cancelled', 'info')
      return
    endif
  endif

  let result = s:git_run(state.root, 'push --set-upstream '
        \ . shellescape(remote) . ' ' . shellescape(branch))
  if !result.ok
    call s:set_status(state, 'Push failed: ' . s:output_message(result.out),
          \ 'error')
    return
  endif

  call s:refresh_after_push(state)
  call s:set_status(state, s:push_result(state, result.out), 'info')
endfunction

function! s:stage_current(mode) abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif
  call s:flush_pending(state)

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

" Stage every change in the working tree, including untracked files.
function! s:stage_all() abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif
  call s:flush_pending(state)

  let entry = state.commits[state.commit_index]
  if entry.kind !=# 'worktree'
    call s:err('S is only available for working tree changes')
    return
  endif

  let counts = s:worktree_summary(state.files)
  if counts[1] + counts[2] == 0
    echomsg 'Nothing to stage'
    return
  endif

  let keep_path = ''
  if state.file_index >= 0 && state.file_index < len(state.files)
    let keep_path = state.files[state.file_index].path
  endif

  if !s:git_do(state.root, 'add -A -- .')
    return
  endif

  echomsg 'Staged all changes'
  call s:refresh_file_list(state, keep_path)
endfunction

" Unstage every staged change in the working tree.
function! s:unstage_all() abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif
  call s:flush_pending(state)

  let entry = state.commits[state.commit_index]
  if entry.kind !=# 'worktree'
    call s:err('U is only available for working tree changes')
    return
  endif

  let counts = s:worktree_summary(state.files)
  if counts[0] == 0
    echomsg 'Nothing to unstage'
    return
  endif

  let keep_path = ''
  if state.file_index >= 0 && state.file_index < len(state.files)
    let keep_path = state.files[state.file_index].path
  endif

  if !s:git_do(state.root, 'reset -q HEAD -- .')
    return
  endif

  echomsg 'Unstaged all changes'
  call s:refresh_file_list(state, keep_path)
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

  let header = ['# Branches']
  if get(a:state, 'branch_show_help', 0)
    let km = s:keymaps()
    call extend(header, [
          \ '# j/k:select Enter:show 1/2/3 Tab/S-Tab',
          \ '# ' . km.new_branch . ':new ' . km.commit . ':commit '
          \     . km.commit_editor . ':edit',
          \ '# ' . km.pull . ':pull ' . km.push . ':push '
          \     . km.checkout_branch . ':checkout',
          \ '# ' . km.branch_delete . ':delete ' . km.copy_branch
          \     . ':copy ?:hide',
          \ ])
  endif
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
  call s:update_statusline(a:state)
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
  let lines = a:entry.kind ==# 'commit'
        \ ? ['# ' . a:entry.short]
        \ : ['# ' . a:entry.short . '  ' . s:truncate(a:entry.subject, 90)]

  if a:entry.kind ==# 'worktree'
    let [staged, unstaged, untracked] = s:worktree_summary(a:state.files)
    if staged + unstaged + untracked == 0
      call add(lines, '# Working tree clean')
    else
      call add(lines, printf('# Staged %d  Unstaged %d  Untracked %d',
            \ staged, unstaged, untracked))
    endif
    if a:state.show_help
      call add(lines, '# s:stage u:unstage -:toggle S/U:all t:tree')
      call add(lines, '# r:refresh d:discard o:open ?:hide')
      call add(lines, '# Esc:worktree yy:path cc:commit cb:new')
      call add(lines, '# C:edit p:pull P:push')
      call add(lines, '# J/K:scroll C-d/u:half 1/2/3 Tab/S-Tab')
      call add(lines, '# H/L:scroll diff left/right')
    endif
  elseif a:entry.kind ==# 'compare'
    call add(lines, '# Range: ' . a:state.list_title)
    if a:state.show_help
      call add(lines, '# t:tree r:refresh ?:hide yy:path Esc:worktree')
      call add(lines, '# cc:commit cb:new C:edit p:pull P:push')
      call add(lines, '# J/K:scroll C-d/u:half 1/2/3 Tab/S-Tab')
      call add(lines, '# H/L:scroll diff left/right')
    endif
  else
    call add(lines, '# Author: ' . s:truncate(a:entry.author, 90))
    call add(lines, '# Date:   ' . a:entry.date)
    call add(lines, '# ' . s:truncate(a:entry.subject, 90))
    for body_line in s:commit_body_lines(a:state, a:entry)
      call add(lines, '# ' . body_line)
    endfor
    if a:state.show_help
      call add(lines, '# t:tree r:refresh ?:hide yy:path Esc:worktree')
      call add(lines, '# cc:commit cb:new C:edit p:pull P:push')
      call add(lines, '# J/K:scroll C-d/u:half 1/2/3 Tab/S-Tab')
      call add(lines, '# H/L:scroll diff left/right')
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
  call s:update_statusline(a:state)
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
    if offset < 0 || offset >= len(a:state.file_line_map)
      return -1
    endif
    return a:state.file_line_map[offset]
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

" Return the commits in the current view that are not on any remote.
function! s:unpushed_shas(state) abort
  if empty(s:git(a:state.root, 'remote'))
    return {}
  endif

  let args = 'rev-list'
  if !empty(a:state.log_range)
    let args .= ' ' . a:state.log_range
  elseif !empty(a:state.log_ref)
    let args .= ' ' . shellescape(a:state.log_ref)
  elseif a:state.has_head
    let args .= ' HEAD'
  else
    return {}
  endif
  let args .= ' --not --remotes'

  let unpushed = {}
  for sha in s:git(a:state.root, args)
    let unpushed[sha] = 1
  endfor
  return unpushed
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

  let unpushed = s:unpushed_shas(a:state)
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
            \ 'unpushed': has_key(unpushed, parts[0]),
            \ })
    endif
  endfor

  let entries = copy(a:state.start_entries)
  call extend(entries, real_commits)
  let a:state.commits = entries

  let lines = ['# ' . a:state.list_title . '  (' . len(real_commits) . ' commits)']
  for entry in entries
    let prefix = get(entry, 'unpushed', 0) ? '↑ ' : '  '
    if entry.kind ==# 'worktree'
      call add(lines, prefix . entry.short . '  ' . entry.subject)
    elseif entry.kind ==# 'compare'
      call add(lines, prefix . entry.short . '  '
            \ . s:truncate(entry.old_label . ' ↔ ' . entry.new_label, 88))
    else
      call add(lines, prefix . entry.short . '  '
            \ . s:truncate(entry.subject, 88))
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
  call s:update_statusline(a:state)
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
  if !s:win_exists(winid)
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
  if buf <= 0 || !bufexists(buf) || !s:win_exists(winid)
    return 0
  endif

  let content_changed = s:set_lines(buf, a:lines)
  let path_changed = getbufvar(buf, 'git_changes_side_path', '') !=# a:path
  if path_changed
    if a:detect_filetype
      call s:set_side_filetype(a:state, a:side, a:path)
    else
      let name = '[GitChanges ' . a:state.id . '] ' . a:side
      call win_execute(winid, 'silent! file ' . fnameescape(name))
      call win_execute(winid, 'setlocal filetype=')
      call win_execute(winid, 'silent! unlet! b:current_syntax')
    endif
    call setbufvar(buf, 'git_changes_side_path', a:path)
  endif

  call win_execute(winid, 'setlocal nowrap number numberwidth=4 cursorline '
        \ . 'scrollbind cursorbind foldenable foldmethod=diff foldlevel=99')
  call s:init_statusline_highlights()
  let label = substitute(a:label, '%', '%%', 'g')
  call win_execute(winid, 'let &l:statusline = ' . string(
        \ '%#GitChangesPaneInfo#' . label . '%#GitChangesPaneStatus#'))
  if content_changed || path_changed
    call s:set_cursor(winid, 1)
  endif
  return content_changed || path_changed
endfunction

function! s:side_needs_update(state, side, path, lines) abort
  let buf = s:side_buf(a:state, a:side)
  if buf <= 0 || !bufexists(buf)
    return 1
  endif
  let target = empty(a:lines) ? [''] : a:lines
  return getbufline(buf, 1, '$') !=# target
        \ || getbufvar(buf, 'git_changes_side_path', '') !=# a:path
endfunction

function! s:diff_off(state) abort
  for winid in [a:state.old_win, a:state.new_win]
    if s:win_exists(winid)
      call win_execute(winid, 'silent! diffoff')
    endif
  endfor
endfunction

function! s:diff_on(state) abort
  for winid in [a:state.old_win, a:state.new_win]
    if s:win_exists(winid)
      call win_execute(winid, 'silent! diffthis')
    endif
  endfor
  for winid in [a:state.old_win, a:state.new_win]
    if s:win_exists(winid)
      call win_execute(winid,
            \ 'setlocal foldenable foldmethod=diff foldlevel=99')
    endif
  endfor
endfunction

function! s:sync_diff(state) abort
  let winid = 0
  if s:win_exists(a:state.old_win)
    let winid = a:state.old_win
  elseif s:win_exists(a:state.new_win)
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
  let need_diff = s:side_needs_update(a:state, 'old', '', a:lines)
        \ || s:side_needs_update(a:state, 'new', '', a:lines)
  if need_diff
    call s:diff_off(a:state)
  endif
  call s:load_side_buffer(a:state, 'old', '', a:lines, 0,
        \ 'GitChanges')
  call s:load_side_buffer(a:state, 'new', '', a:lines, 0,
        \ 'GitChanges')
  if need_diff
    call s:diff_on(a:state)
    call s:sync_diff(a:state)
  endif
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

  let need_diff = s:side_needs_update(a:state, 'old', old_path, old_lines)
        \ || s:side_needs_update(a:state, 'new', new_path, new_lines)
  if need_diff
    call s:diff_off(a:state)
  endif
  call s:load_side_buffer(a:state, 'old', old_path, old_lines, 1,
        \ 'PARENT ' . old_path)
  call s:load_side_buffer(a:state, 'new', new_path, new_lines, 1,
        \ a:commit.short . ' ' . new_path)
  if need_diff
    call s:diff_on(a:state)
    call s:sync_diff(a:state)
  endif
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

  let need_diff = s:side_needs_update(a:state, 'old', old_path, old_lines)
        \ || s:side_needs_update(a:state, 'new', new_path, new_lines)
  if need_diff
    call s:diff_off(a:state)
  endif
  call s:load_side_buffer(a:state, 'old', old_path, old_lines, 1,
        \ a:entry.old_label . ' ' . old_path)
  call s:load_side_buffer(a:state, 'new', new_path, new_lines, 1,
        \ a:entry.new_label . ' ' . new_path)
  if need_diff
    call s:diff_on(a:state)
    call s:sync_diff(a:state)
  endif
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

  let need_diff = s:side_needs_update(a:state, 'old', old_path, old_lines)
        \ || s:side_needs_update(a:state, 'new', new_path, new_lines)
  if need_diff
    call s:diff_off(a:state)
  endif
  call s:load_side_buffer(a:state, 'old', old_path, old_lines, 1,
        \ 'HEAD ' . old_path)
  call s:load_side_buffer(a:state, 'new', new_path, new_lines, 1,
        \ 'WORKTREE ' . new_path)
  if need_diff
    call s:diff_on(a:state)
    call s:sync_diff(a:state)
  endif
endfunction

function! s:show_diff(state, file) abort
  if a:state.commit_index < 0 || a:state.commit_index >= len(a:state.commits)
    return
  endif
  let entry = a:state.commits[a:state.commit_index]

  let old_lazy = &lazyredraw
  set lazyredraw
  try
    if entry.kind ==# 'worktree'
      call s:show_worktree_diff(a:state, a:file)
    elseif entry.kind ==# 'compare'
      call s:show_compare_diff(a:state, entry, a:file)
    else
      call s:show_commit_diff(a:state, entry, a:file)
    endif
  finally
    let &lazyredraw = old_lazy
  endtry
endfunction

function! s:select_commit(state, index) abort
  if a:index < 0 || a:index >= len(a:state.commits)
    return
  endif

  call s:cancel_pending(a:state)
  let old_lazy = &lazyredraw
  set lazyredraw
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
    let &lazyredraw = old_lazy
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
  call s:update_statusline(a:state)
endfunction


function! git_changes#open(...) abort
  let root = s:repo_root()
  if empty(root)
    call s:err('not inside a Git repository')
    return
  endif

  if len(a:000) > 2
    call s:err('usage: :GitChanges [ref1] [ref2]')
    return
  endif

  let parsed = s:parse_open_args(root, a:000)
  if empty(parsed)
    return
  endif

  let tabnr = 0
  let state = s:cur_state()
  if !empty(state)
    let tabnr = tabpagenr()
    call s:quit_state(state)
  endif

  call s:open_tab(root, parsed, tabnr)
endfunction

function! s:parse_open_args(root, args) abort
  let start_entries = []
  let log_range = ''
  let has_head = 0
  let list_title = ''

  if empty(a:args)
    let head = s:resolve_ref(a:root, 'HEAD')
    let has_head = !empty(head)
    let branch = s:current_branch(a:root)
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
  elseif len(a:args) == 1
    let old_ref = s:resolve_ref(a:root, a:args[0])
    if empty(old_ref)
      call s:err('unknown revision: ' . a:args[0])
      return {}
    endif
    let new_ref = s:resolve_ref(a:root, 'HEAD')
    if empty(new_ref)
      call s:err('HEAD has no commits')
      return {}
    endif
    let old_label = a:args[0]
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
    let old_ref = s:resolve_ref(a:root, a:args[0])
    if empty(old_ref)
      call s:err('unknown revision: ' . a:args[0])
      return {}
    endif
    let new_ref = s:resolve_ref(a:root, a:args[1])
    if empty(new_ref)
      call s:err('unknown revision: ' . a:args[1])
      return {}
    endif
    let old_label = a:args[0]
    let new_label = a:args[1]
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


  return {
        \ 'start_entries': start_entries,
        \ 'log_range': log_range,
        \ 'has_head': has_head,
        \ 'list_title': list_title,
        \ }
endfunction

function! s:open_tab(root, parsed, tabnr) abort
  let root = a:root
  let start_entries = a:parsed.start_entries
  let log_range = a:parsed.log_range
  let has_head = a:parsed.has_head
  let list_title = a:parsed.list_title

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
        \ 'branch_show_help': 0,
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
        \ 'file_timer': -1,
        \ 'commit_timer': -1,
        \ 'refresh_timer': -1,
        \ 'status': '',
        \ 'status_kind': 'info',
        \ }

  tabnew
  if a:tabnr > 0
    execute 'silent! tabmove ' . (a:tabnr - 1)
  endif
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
  let branch_height = max([6, min([
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

function! s:quit_state(state) abort
  let state = a:state
  call s:cancel_pending(state)
  call s:cancel_refresh(state)
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

function! git_changes#quit() abort
  let state = s:find_state()
  if empty(state)
    call s:err('no GitChanges tab found')
    return
  endif
  call s:quit_state(state)
endfunction
