
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
    let loaded = get(a:state, 'commit_loaded', -1)
    if loaded < 0
      let loaded = len(filter(copy(a:state.commits), 'v:val.kind ==# "commit"'))
    endif
    let more = get(a:state, 'commit_has_more', 0) ? '+' : ''
    return printf('%s (%d%s commits)', a:state.list_title, loaded, more)
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

" Report progress for a view when there is one, or on the command line when
" the action was run from a normal buffer.
function! s:report(state, msg, kind) abort
  if !empty(a:state)
    call s:set_status(a:state, a:msg, a:kind)
  elseif a:kind ==# 'error'
    call s:err(a:msg)
  else
    echomsg 'GitChanges: ' . a:msg
  endif
endfunction

function! s:noop() abort
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

" Run git in the background. {args} is a List of arguments (no shell escaping
" needed). Output is collected and handed to {callback} from a close callback,
" so it runs after all stdout lines have been received.
function! s:job_stop(state, key) abort
  let name = 'job_' . a:key
  if has_key(a:state, name)
    let job = a:state[name]
    if has('nvim')
      if jobwait([job], 0)[0] == -1
        call jobstop(job)
      endif
    elseif job_status(job) ==# 'run'
      call job_stop(job)
    endif
    unlet a:state[name]
  endif
  if has_key(a:state, 'jobtok_' . a:key)
    unlet a:state['jobtok_' . a:key]
  endif
endfunction

function! s:on_job_out(ctx, channel, msg) abort
  call add(a:ctx.out, a:msg)
endfunction

function! s:on_job_close(state, key, token_key, token, ctx, callback, channel) abort
  if get(a:state, 'jobtok_' . a:key, -1) == a:token
    if has_key(a:state, 'job_' . a:key)
      unlet a:state['job_' . a:key]
    endif
    unlet a:state['jobtok_' . a:key]
  endif
  if get(a:state, a:token_key, -1) != a:token
    return
  endif
  if !s:state_alive(a:state)
    return
  endif
  call a:callback(a:ctx)
endfunction

function! s:nvim_job_out(ctx, id, data, event) abort
  call extend(a:ctx.out, a:data)
endfunction

function! s:nvim_job_err(ctx, id, data, event) abort
  call extend(a:ctx.err, a:data)
endfunction

function! s:nvim_job_exit(state, key, token_key, token, ctx, callback, id, code, event) abort
  " Buffered output ends with an empty string when the final line was
  " newline-terminated; drop it to match the Vim line callbacks.
  if !empty(a:ctx.out) && a:ctx.out[-1] ==# ''
    call remove(a:ctx.out, -1)
  endif
  let a:ctx.status = a:code
  call s:on_job_close(a:state, a:key, a:token_key, a:token, a:ctx, a:callback, 0)
endfunction

function! s:nvim_git_job(state, key, token_key, token, cmd, ctx, callback) abort
  if !has('nvim-0.10')
    " Older Neovim: fall back to a blocking call.
    let a:ctx.out = systemlist(a:cmd)
    if v:shell_error
      let a:ctx.out = []
    endif
    call a:callback(a:ctx)
    return
  endif

  try
    let id = jobstart(a:cmd, {
          \ 'stdout_buffered': v:true,
          \ 'stderr_buffered': v:true,
          \ 'on_stdout': function('s:nvim_job_out', [a:ctx]),
          \ 'on_stderr': function('s:nvim_job_err', [a:ctx]),
          \ 'on_exit': function('s:nvim_job_exit',
          \     [a:state, a:key, a:token_key, a:token, a:ctx, a:callback]),
          \ })
  catch
    call add(a:ctx.err, v:exception)
    call a:callback(a:ctx)
    return
  endtry
  if id <= 0
    call add(a:ctx.err, 'failed to start git')
    call a:callback(a:ctx)
    return
  endif
  let a:state['job_' . a:key] = id
  let a:state['jobtok_' . a:key] = a:token
endfunction

function! s:git_job(state, key, token_key, token, args, callback) abort
  call s:job_stop(a:state, a:key)

  let ctx = {'out': [], 'err': [], 'status': -1}
  let cmd = ['git', '--no-pager', '-c', 'core.quotePath=false',
        \ '-C', a:state.root] + a:args

  if has('nvim')
    call s:nvim_git_job(a:state, a:key, a:token_key, a:token,
          \ cmd, ctx, a:callback)
    return
  endif

  try
    let job = job_start(cmd, {
          \ 'in_io': 'null',
          \ 'err_io': 'null',
          \ 'out_mode': 'nl',
          \ 'out_cb': function('s:on_job_out', [ctx]),
          \ 'close_cb': function('s:on_job_close',
          \     [a:state, a:key, a:token_key, a:token, ctx, a:callback]),
          \ })
  catch
    call add(ctx.err, v:exception)
    call a:callback(ctx)
    return
  endtry
  if job_status(job) ==# 'fail'
    call add(ctx.err, 'failed to start git')
    call a:callback(ctx)
    return
  endif
  let a:state['job_' . a:key] = job
  let a:state['jobtok_' . a:key] = a:token
endfunction

function! s:cancel_jobs(state) abort
  for key in ['branch_req', 'commit_req', 'files_req', 'diff_req']
    let a:state[key] = get(a:state, key, 0) + 1
  endfor
  for key in ['branches', 'commits-log', 'commits-remote', 'commits-unpushed',
        \ 'files', 'files-body', 'diff-check', 'diff-old', 'diff-new']
    call s:job_stop(a:state, key)
  endfor
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
  for key in ['files_buf', 'commits_buf', 'old_buf', 'new_buf', 'branches_buf']
    let buf = get(a:state, key, 0)
    if type(buf) == type(0) && buf > 0 && bufexists(buf)
      return 1
    endif
  endfor
  return 0
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

" Find a live GitChanges view for {root}, so the command can reuse its tab
" instead of opening another one.
function! s:find_state_for_root(root) abort
  for state in reverse(copy(s:instances))
    if s:state_alive(state) && get(state, 'root', '') ==# a:root
      return state
    endif
  endfor
  return {}
endfunction

" Tab holding {state}. Computed from its windows because state.tab goes stale
" when other tabs are opened or closed.
function! s:state_tab(state) abort
  for key in ['files_buf', 'commits_buf', 'branches_buf', 'old_buf', 'new_buf']
    let buf = get(a:state, key, -1)
    if buf > 0 && bufexists(buf)
      let wins = win_findbuf(buf)
      if !empty(wins)
        return win_id2tabwin(wins[0])[0]
      endif
    endif
  endfor
  return 0
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
  silent! setlocal winminwidth=20
endfunction

function! s:fold_level() abort
  return get(g:, 'git_changes_fold', 1) ? 0 : 99
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
  execute 'setlocal foldlevel=' . s:fold_level()
  silent! setlocal winminwidth=20
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
        \ 'file_discard_diff': 'D',
        \ 'staged_view': 'dS',
        \ 'open_file': 'o',
        \ 'diff_file': 'gd',
        \ 'scroll_half_down': '<C-d>',
        \ 'scroll_half_up': '<C-u>',
        \ 'copy_file': 'yy',
        \ 'copy_commit': 'yy',
        \ 'copy_branch': 'yy',
        \ 'edit_message': 'e',
        \ 'load_more': 'L',
        \ 'commit': 'cc',
        \ 'commit_editor': 'C',
        \ 'open_main': 'gs',
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

" Use <Cmd> mappings when available: they do not enter command-line mode, so
" holding a mapped key does not leave characters on the command line.
function! s:cmd_rhs(rhs) abort
  if !(has('nvim') || has('patch-8.2.1978'))
    return a:rhs
  endif
  if a:rhs =~# '^:<C-u>.*<CR>$'
    return '<Cmd>' . strpart(a:rhs, 6, strlen(a:rhs) - 10) . '<CR>'
  endif
  return a:rhs
endfunction

function! s:map_fixed(key, rhs) abort
  if !s:keymaps_enabled()
    return
  endif
  execute 'silent! nnoremap <buffer> <silent> ' . a:key . ' '
        \ . s:cmd_rhs(a:rhs)
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

  let rhs = s:cmd_rhs(a:rhs)
  for key in keys
    if empty(key)
      continue
    endif
    execute 'silent! nnoremap <buffer> <silent> ' . key . ' ' . rhs
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

function! s:map_open_main() abort
  call s:map_keys('open_main', ':<C-u>GitChanges<CR>')
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
  call s:map_open_main()
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
    call s:map_keys('diff_file', ':<C-u>call ' . s:sid . 'open_file_diff_for_current()<CR>')
    call s:map_keys('scroll_half_down', ':<C-u>call ' . s:sid . 'scroll_diff_half(1)<CR>')
    call s:map_keys('scroll_half_up', ':<C-u>call ' . s:sid . 'scroll_diff_half(-1)<CR>')
    call s:map_keys('copy_file', ':<C-u>call ' . s:sid . 'copy_file_path()<CR>')
    call s:map_keys('diff_left', ':<C-u>call ' . s:sid . 'scroll_diff_horizontal(-1)<CR>')
    call s:map_keys('diff_right', ':<C-u>call ' . s:sid . 'scroll_diff_horizontal(1)<CR>')
  elseif a:kind ==# 'commits'
    call s:map_keys('copy_commit', ':<C-u>call ' . s:sid . 'copy_commit_hash()<CR>')
    call s:map_keys('edit_message', ':<C-u>call ' . s:sid . 'edit_commit_message()<CR>')
    call s:map_keys('load_more', ':<C-u>call ' . s:sid . 'load_more_commits()<CR>')
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
  call s:map_keys('diff_file', ':<C-u>call ' . s:sid . 'open_file_diff_for_current()<CR>')
  call s:map_keys('stage', ':<C-u>call ' . s:sid . 'stage_current("stage")<CR>')
  call s:map_keys('unstage', ':<C-u>call ' . s:sid . 'stage_current("unstage")<CR>')
  call s:map_keys('stage_all', ':<C-u>call ' . s:sid . 'stage_all()<CR>')
  call s:map_keys('unstage_all', ':<C-u>call ' . s:sid . 'unstage_all()<CR>')
  call s:map_keys('toggle_stage', ':<C-u>call ' . s:sid . 'stage_current("toggle")<CR>')
  call s:map_keys('staged_view', ':<C-u>call ' . s:sid . 'toggle_main_staged_diff()<CR>')
  call s:map_keys('file_discard_diff', ':<C-u>call ' . s:sid . 'discard_current()<CR>')
  call s:map_keys('commit', ':<C-u>call ' . s:sid . 'commit_current()<CR>')
  call s:map_keys('pull', ':<C-u>call ' . s:sid . 'pull_current()<CR>')
  call s:map_keys('push', ':<C-u>call ' . s:sid . 'push_current()<CR>')
  call s:map_keys('new_branch', ':<C-u>call ' . s:sid . 'new_branch()<CR>')
  call s:map_keys('commit_editor', ':<C-u>call ' . s:sid . 'commit_with_editor()<CR>')
  call s:map_keys('cycle_next', ':<C-u>call ' . s:sid . 'cycle_pane(1)<CR>')
  call s:map_keys('cycle_prev', ':<C-u>call ' . s:sid . 'cycle_pane(-1)<CR>')
  call s:map_open_main()
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
  call s:map_open_main()
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
  let pairs = [[a:state.old_win, a:state.old_buf],
        \ [a:state.new_win, a:state.new_buf]]
  let work_win = get(a:state, 'work_win', 0)
  if work_win > 0
    call add(pairs, [work_win, get(a:state, 'work_buf', -1)])
  endif

  let winid = 0
  let max = -1
  for [candidate, buf] in pairs
    if s:win_exists(candidate) && buf > 0 && bufexists(buf)
      let lines = s:buf_linecount(buf)
      if lines > max
        let max = lines
        let winid = candidate
      endif
    endif
  endfor
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
  let entry = a:state.commits[a:state.commit_index]
  if get(a:state, 'files_entry', '') !=# s:entry_key(entry)
    return
  endif
  call s:show_diff(a:state, a:state.files[a:state.file_index], entry)
endfunction

function! s:clear_files_state(state) abort
  let a:state.files = []
  let a:state.files_entry = ''
  let a:state.file_index = -1
endfunction

function! s:schedule_commit_select(state, index) abort
  let a:state.commit_index = a:index
  call s:clear_files_state(a:state)
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
        \ state.old_win, state.new_win, get(state, 'work_win', 0)]
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
  for winid in s:diff_windows(state)
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

function! s:entry_key(entry) abort
  return get(a:entry, 'kind', '') . nr2char(31) . get(a:entry, 'sha', '')
endfunction

function! s:rerender_files(state) abort
  if empty(a:state.commits) || a:state.commit_index < 0
    return
  endif

  let a:state.updating = 1
  try
    let entry = a:state.commits[a:state.commit_index]
    if get(a:state, 'files_entry', '') !=# s:entry_key(entry)
      return
    endif
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
  return {'ok': v:shell_error == 0, 'out': out, 'code': v:shell_error}
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
  call s:load_files(a:state, entry,
        \ function('s:after_refresh_files',
        \   [a:state, entry, a:keep_path, old_index]))
endfunction

function! s:after_refresh_files(state, entry, keep_path, old_index) abort
  if !s:state_alive(a:state)
    return
  endif
  if empty(a:state.files)
    let a:state.file_index = -1
    call s:set_cursor(a:state.files_win, 1)
    call s:show_side_message(a:state, [s:empty_message(a:entry)])
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
    let new_index = min([max([a:old_index, 0]), len(a:state.files) - 1])
  endif

  let a:state.file_index = new_index
  call s:goto_file_index(a:state, new_index)
  call s:show_diff(a:state, a:state.files[new_index], a:entry)
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
  if !s:state_alive(state)
    return
  endif

  call s:flush_pending(state)

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

  call s:load_branches(state, keep_branch)
  call s:load_commits(state, 'reload',
        \ function('s:after_refresh_all',
        \   [state, keep_kind, keep_sha, keep_index, keep_path]))
endfunction

function! s:after_refresh_all(state, keep_kind, keep_sha, keep_index, keep_path) abort
  if !s:state_alive(a:state)
    return
  endif

  if empty(a:state.commits)
    call s:show_no_commits(a:state)
    call s:set_status(a:state, 'Refreshed', 'info')
    return
  endif

  let new_index = -1
  for i in range(len(a:state.commits))
    let candidate = a:state.commits[i]
    if !empty(a:keep_sha)
      if get(candidate, 'sha', '') ==# a:keep_sha
        let new_index = i
        break
      endif
    elseif candidate.kind ==# a:keep_kind
      let new_index = i
      break
    endif
  endfor
  if new_index < 0
    let new_index = min([max([a:keep_index, 0]), len(a:state.commits) - 1])
  endif

  let a:state.commit_index = new_index
  call s:set_cursor(a:state.commits_win,
        \ a:state.commits_header + 1 + new_index)
  call s:refresh_file_list(a:state, a:keep_path)

  call s:set_status(a:state, 'Refreshed', 'info')
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
  if !s:discard_file(state.root, file)
    return
  endif
  call s:refresh_file_list(state, file.path)
endfunction

" Discard the unstaged changes of {file} (or delete it when untracked).
" Returns 1 when something was discarded.
function! s:discard_file(root, file) abort
  let xy = get(a:file, 'status_text', '')
  let abs = a:root . '/' . a:file.path

  if xy ==# '??'
    if get(g:, 'git_changes_confirm_discard', 1)
          \ && s:prompt_confirm('Delete untracked file ' . a:file.path . '?',
          \             "&Yes\n&No", 2) != 1
      return 0
    endif
    if delete(abs) != 0
      call s:err('failed to delete: ' . a:file.path)
      return 0
    endif
    echomsg 'Deleted: ' . a:file.path
    return 1
  endif

  let worktree_status = strlen(xy) >= 2 ? strpart(xy, 1, 1) : ' '
  if worktree_status ==# ' ' || worktree_status ==# '?'
    echomsg 'No unstaged changes: ' . a:file.path
    return 0
  endif

  if get(g:, 'git_changes_confirm_discard', 1)
        \ && s:prompt_confirm('Discard unstaged changes for ' . a:file.path . '?',
        \             "&Yes\n&No", 2) != 1
    return 0
  endif

  let oldpath = get(a:file, 'oldpath', '')
  let index_status = strpart(xy, 0, 1)
  let target = a:file.path
  if index_status ==# ' ' && !empty(oldpath)
    let target = oldpath
  endif
  if !s:git_do(a:root, 'checkout -- ' . shellescape(target))
    return 0
  endif

  if index_status ==# ' ' && !empty(oldpath) && oldpath !=# a:file.path
    let abs_new = a:root . '/' . a:file.path
    if filereadable(abs_new)
      let tracked = !empty(s:git_one(a:root,
            \ 'ls-files --error-unmatch -- ' . shellescape(a:file.path)))
      if !tracked
        call delete(abs_new)
      endif
    endif
  endif

  echomsg 'Discarded unstaged changes: ' . a:file.path
  return 1
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

" Find a normal (non-plugin) window showing {path}, so opening a file can
" reuse its tab instead of always creating a new one.
function! s:find_file_window(path) abort
  let target = fnamemodify(a:path, ':p')
  for info in getwininfo()
    let buf = info.bufnr
    if !empty(getbufvar(buf, 'gc_kind', ''))
          \ || !empty(getbufvar(buf, '&buftype'))
      continue
    endif
    let name = bufname(buf)
    if !empty(name) && fnamemodify(name, ':p') ==# target
      return info.winid
    endif
  endfor
  return 0
endfunction

function! s:show_file(path, lnum) abort
  let winid = s:find_file_window(a:path)
  if winid > 0
    let tabwin = win_id2tabwin(winid)
    if !empty(tabwin) && tabwin[0] > 0 && tabwin[0] != tabpagenr()
      execute 'tabnext ' . tabwin[0]
    endif
    call win_gotoid(winid)
  else
    execute 'tabnew ' . fnameescape(a:path)
  endif

  if a:lnum > 0
    call cursor(a:lnum, 1)
    normal! zz
  endif
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

  " The side buffers contain the full file, so the cursor line maps directly
  " to a line in the file. Only do this from the diff panes.
  let lnum = 0
  if get(b:, 'gc_kind', '') ==# 'diff'
    let lnum = line('.')
  endif

  call s:show_file(path, lnum)
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
  execute 'nnoremap <buffer> <silent> q ' . s:cmd_rhs(':<C-u>quit<CR>')

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
  call s:load_commits(a:state, 'reload',
        \ function('s:after_reword_reload', [a:state, a:sha]))
endfunction

function! s:after_reword_reload(state, sha) abort
  if !s:state_alive(a:state)
    return
  endif
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

" Prompt for a commit message and commit the index. Returns 1 on success.
function! s:commit_index(root, ...) abort
  if !s:has_staged_changes(a:root, [])
    echomsg 'No staged changes to commit'
    return 0
  endif

  let message = a:0 && !empty(trim(a:1))
        \ ? trim(a:1)
        \ : trim(s:prompt_input('Commit message: '))
  if empty(message)
    echomsg 'Commit cancelled'
    return 0
  endif

  if !s:git_do(a:root, 'commit -m ' . shellescape(message))
    return 0
  endif

  echomsg 'Committed: ' . message
  return 1
endfunction

function! s:commit_current() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif
  call s:flush_pending(state)

  if !s:commit_index(state.root)
    return
  endif
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

  call s:open_commit_editor(state.root,
        \ function('s:reload_current_branch', [state]))
endfunction

function! s:open_commit_editor(root, on_done) abort
  if !s:has_staged_changes(a:root, [])
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
  call setline(1, s:commit_template({'root': a:root}))
  setlocal nomodified
  execute 'nnoremap <buffer> <silent> q ' . s:cmd_rhs(':<C-u>quit<CR>')

  let b:git_changes_commit = {'root': a:root, 'on_done': a:on_done}
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
    let ok = s:git_do(info.root,
          \ 'commit --cleanup=strip -F ' . shellescape(msgfile))
  finally
    call delete(msgfile)
  endtry
  if !ok
    return
  endif

  setlocal nomodified
  echomsg 'Committed'
  call call(info.on_done, [])
endfunction

function! s:reload_current_branch(state) abort
  call s:statusline_clear()
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

  call s:load_branches(a:state, '')
  call s:load_commits(a:state, 'reload',
        \ function('s:after_reload_current', [a:state]))
endfunction

function! s:after_reload_current(state) abort
  if !s:state_alive(a:state)
    return
  endif
  if empty(a:state.commits)
    call s:show_no_commits(a:state)
  else
    call s:select_commit(a:state, 0)
  endif
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

function! s:push_result(root, out) abort
  if match(a:out, 'Everything up-to-date') >= 0
    return 'Everything up-to-date'
  endif

  let upstream = s:upstream_ref(a:root)
  return empty(upstream) ? 'Push complete' : 'Pushed to ' . upstream
endfunction

function! s:pull_current() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif
  call s:pull_root(state.root, state)
endfunction

function! s:pull_root(root, state) abort
  call s:report(a:state, 'Pulling...', 'busy')
  let result = s:git_run(a:root, 'pull --no-rebase --no-edit')
  if !empty(a:state)
    call s:reload_current_branch(a:state)
  endif

  if !result.ok
    let detail = s:output_message(result.out)
    if detail =~? 'no tracking information\|no upstream branch'
      call s:report(a:state,
            \ 'Cannot pull: no upstream branch. Push first to set it.', 'error')
    else
      call s:report(a:state, 'Pull failed: ' . detail, 'error')
    endif
    return
  endif

  if match(result.out, 'Already up to date') >= 0
    call s:report(a:state, 'Already up to date', 'info')
  else
    call s:report(a:state, 'Pull complete', 'info')
  endif
endfunction

function! s:refresh_after_push(state) abort
  let index = a:state.commit_index
  let keep_path = ''
  if a:state.file_index >= 0 && a:state.file_index < len(a:state.files)
    let keep_path = a:state.files[a:state.file_index].path
  endif

  call s:load_commits(a:state, 'reload',
        \ function('s:after_push_reload', [a:state, index, keep_path]))
endfunction

function! s:after_push_reload(state, index, keep_path) abort
  if !s:state_alive(a:state)
    return
  endif
  if empty(a:state.commits)
    call s:show_no_commits(a:state)
    return
  endif

  let index = min([max([a:index, 0]), len(a:state.commits) - 1])
  let a:state.commit_index = index
  call s:set_cursor(a:state.commits_win,
        \ a:state.commits_header + 1 + index)
  call s:refresh_file_list(a:state, a:keep_path)
endfunction

function! s:push_current() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif
  call s:push_root(state.root, state)
endfunction

function! s:push_root(root, state) abort
  if empty(s:resolve_ref(a:root, 'HEAD'))
    call s:report(a:state, 'Cannot push: no commits yet', 'error')
    return
  endif

  call s:report(a:state, 'Pushing...', 'busy')

  if s:has_upstream(a:root)
    let result = s:git_run(a:root, 'push')
    if !result.ok
      call s:report(a:state, 'Push failed: ' . s:output_message(result.out),
            \ 'error')
      return
    endif
    if !empty(a:state)
      call s:refresh_after_push(a:state)
    endif
    call s:report(a:state, s:push_result(a:root, result.out), 'info')
    return
  endif

  let branch = s:git_one(a:root, 'symbolic-ref --short -q HEAD')
  if empty(branch)
    call s:report(a:state, 'Cannot push: not on a branch (detached HEAD)',
          \ 'error')
    return
  endif

  let remote = s:preferred_remote(a:root, branch)
  if empty(remote)
    call s:report(a:state, 'Cannot push: no remote configured', 'error')
    return
  endif

  if get(g:, 'git_changes_confirm_push_upstream', 1)
    let question = printf('No upstream for "%s". Push to %s/%s and set upstream?',
          \ branch, remote, branch)
    if confirm(question, "&Yes\n&No", 1) != 1
      call s:report(a:state, 'Push cancelled', 'info')
      return
    endif
  endif

  let result = s:git_run(a:root, 'push --set-upstream '
        \ . shellescape(remote) . ' ' . shellescape(branch))
  if !result.ok
    call s:report(a:state, 'Push failed: ' . s:output_message(result.out),
          \ 'error')
    return
  endif

  if !empty(a:state)
    call s:refresh_after_push(a:state)
  endif
  call s:report(a:state, s:push_result(a:root, result.out), 'info')
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
    let add_paths = s:addable_paths(state.root, paths)
    if empty(add_paths)
      echomsg 'Nothing to stage: ' . file.path
      return
    endif
    if !s:git_do(state.root,
          \ 'add -A -- ' . s:path_args(add_paths))
      return
    endif
    echomsg 'Staged: ' . file.path
  else
    if !s:git_do(state.root,
          \ 'reset -q HEAD -- ' . s:path_args(paths))
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


function! s:load_branches(state, select_name, ...) abort
  let OnDone = a:0 ? a:1 : 0
  let token = get(a:state, 'branch_req', 0) + 1
  let a:state.branch_req = token
  call s:git_job(a:state, 'branches', 'branch_req', token,
        \ ['for-each-ref', '--sort=-committerdate',
        \  '--format=%(HEAD)%09%(refname:short)', 'refs/heads'],
        \ function('s:apply_branches', [a:state, a:select_name, OnDone]))
endfunction

function! s:apply_branches(state, select_name, on_done, result) abort
  let branches = []
  for line in a:result.out
    let tab = stridx(line, "\t")
    if tab < 0
      continue
    endif
    let name = strpart(line, tab + 1)
    if empty(name)
      continue
    endif
    call add(branches, {
          \ 'name': name,
          \ 'current': strpart(line, 0, tab) ==# '*',
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

  if type(a:on_done) == type(function('tr'))
    call a:on_done()
  endif
endfunction

function! s:selected_branch(state) abort
  if a:state.branch_index < 0 || a:state.branch_index >= len(a:state.branches)
    return {}
  endif
  return a:state.branches[a:state.branch_index]
endfunction

function! s:show_branch(state, branch) abort
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

  call s:load_commits(a:state, 'initial',
        \ function('s:after_show_branch', [a:state]))
endfunction

function! s:after_show_branch(state) abort
  if !s:state_alive(a:state)
    return
  endif
  if empty(a:state.commits)
    call s:show_no_commits(a:state)
    return
  endif
  let target = 0
  if a:state.commits[0].kind ==# 'worktree'
        \ && len(a:state.commits) > 1
    let target = 1
  endif
  call s:select_commit(a:state, target)
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

  call s:load_branches(state, branch.name,
        \ function('s:after_checkout_branch', [state]))
  echomsg 'Switched to branch: ' . branch.name
endfunction

function! s:after_checkout_branch(state) abort
  if !s:state_alive(a:state) || a:state.branch_index < 0
    return
  endif
  call s:show_branch(a:state, a:state.branches[a:state.branch_index])
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

  call s:load_branches(state, name,
        \ function('s:after_checkout_branch', [state]))
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

  call s:load_branches(state, '')
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
  return get(a:entry, 'body_lines', [])
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
      call add(lines, '# r:refresh d:discard o:open gd:diff ?:hide')
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
    let author = a:entry.author
    if !empty(get(a:entry, 'email', ''))
      let author .= ' <' . a:entry.email . '>'
    endif
    call add(lines, '# Author: ' . s:truncate(author, 90))
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
  let a:state.files_entry = s:entry_key(a:entry)
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
  elseif get(b:, 'gc_kind', '') ==# 'diff'
    let shown = get(a:state, 'shown_file', {})
    if empty(shown)
      return -1
    endif
    for i in range(len(a:state.files))
      if a:state.files[i].path ==# shown.path
        return i
      endif
    endfor
    return -1
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

function! s:render_commits(state) abort
  let more = get(a:state, 'commit_has_more', 0)
  let lines = ['# ' . a:state.list_title . '  ('
        \ . get(a:state, 'commit_loaded', 0) . (more ? '+' : '')
        \ . ' commits)' . (more ? '  ' . s:keymaps().load_more . ':more' : '')]
  for entry in a:state.commits
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
  if get(a:state, 'commit_loaded', 0) == 0 && !empty(a:state.commits)
    call add(lines, '   (no commits in range)')
  elseif empty(a:state.commits)
    call add(lines, '   (no commits)')
  endif

  call s:set_lines(a:state.commits_buf, lines)
  call s:update_statusline(a:state)
endfunction

" mode: 'initial' resets to the first page, 'reload' keeps the pages already
" loaded, 'append' fetches the next page after the loaded commits.
function! s:load_commits(state, ...) abort
  let mode = a:0 ? a:1 : 'initial'
  let OnDone = a:0 > 1 ? a:2 : 0
  let page = s:opt_int('git_changes_max_commits', 200)
  let loaded = get(a:state, 'commit_loaded', 0)
  if mode ==# 'append'
    let skip = loaded
    let want = page
  elseif mode ==# 'reload'
    let skip = 0
    let want = max([loaded, page])
  else
    let skip = 0
    let want = page
  endif

  let token = get(a:state, 'commit_req', 0) + 1
  let a:state.commit_req = token

  if !a:state.has_head && empty(a:state.log_range) && empty(a:state.log_ref)
    call s:apply_commits(a:state, mode, want, OnDone,
          \ {'out': [], 'err': [], 'status': 0})
    return
  endif

  let args = ['log']
  if get(g:, 'git_changes_exclude_merges', 1)
    call add(args, '--no-merges')
  endif
  call extend(args, ['--date=short', '--skip=' . skip,
        \ '--max-count=' . (want + 1),
        \ '--pretty=format:%H%x1f%h%x1f%s%x1f%an%x1f%ae%x1f%ad'])
  if !empty(a:state.log_range)
    call add(args, a:state.log_range)
  elseif !empty(a:state.log_ref)
    call add(args, a:state.log_ref)
  endif

  call s:git_job(a:state, 'commits-log', 'commit_req', token, args,
        \ function('s:apply_commits', [a:state, mode, want, OnDone]))
endfunction

function! s:apply_commits(state, mode, want, on_done, result) abort
  let loaded = get(a:state, 'commit_loaded', 0)
  let real_commits = []
  for line in a:result.out
    let parts = split(line, nr2char(31))
    if len(parts) >= 3
      call add(real_commits, {
            \ 'kind': 'commit',
            \ 'sha': parts[0],
            \ 'short': parts[1],
            \ 'subject': parts[2],
            \ 'author': get(parts, 3, ''),
            \ 'email': get(parts, 4, ''),
            \ 'date': get(parts, 5, ''),
            \ 'unpushed': 0,
            \ })
    endif
  endfor

  let has_more = len(real_commits) > a:want
  if has_more
    let real_commits = real_commits[0 : a:want - 1]
  endif

  if a:mode ==# 'append'
    call extend(a:state.commits, real_commits)
    let a:state.commit_loaded = loaded + len(real_commits)
  else
    let entries = copy(a:state.start_entries)
    call extend(entries, real_commits)
    let a:state.commits = entries
    let a:state.commit_loaded = len(real_commits)
  endif
  let a:state.commit_has_more = has_more

  call s:render_commits(a:state)
  if a:mode !=# 'append' && !empty(a:state.commits)
    call s:set_cursor(a:state.commits_win, a:state.commits_header + 1)
  endif

  call s:load_unpushed(a:state, get(a:state, 'commit_req', 0))

  if type(a:on_done) == type(function('tr'))
    call a:on_done()
  endif
endfunction

function! s:load_unpushed(state, token) abort
  if a:token != get(a:state, 'commit_req', 0)
    return
  endif
  call s:job_stop(a:state, 'commits-unpushed')
  call s:git_job(a:state, 'commits-remote', 'commit_req', a:token, ['remote'],
        \ function('s:apply_unpushed_remote', [a:state, a:token]))
endfunction

function! s:apply_unpushed_remote(state, token, result) abort
  if a:token != get(a:state, 'commit_req', 0)
    return
  endif

  let args = ['rev-list']
  if !empty(a:state.log_range)
    call add(args, a:state.log_range)
  elseif !empty(a:state.log_ref)
    call add(args, a:state.log_ref)
  elseif a:state.has_head
    call add(args, 'HEAD')
  else
    return
  endif

  if empty(a:result.out)
    " No remotes: nothing is considered unpushed.
    let changed = 0
    for entry in a:state.commits
      if get(entry, 'unpushed', 0)
        let entry.unpushed = 0
        let changed = 1
      endif
    endfor
    if changed
      call s:render_commits(a:state)
    endif
    return
  endif

  call extend(args, ['--not', '--remotes'])
  call s:git_job(a:state, 'commits-unpushed', 'commit_req', a:token, args,
        \ function('s:apply_unpushed_list', [a:state, a:token]))
endfunction

function! s:apply_unpushed_list(state, token, result) abort
  if a:token != get(a:state, 'commit_req', 0)
    return
  endif

  let shas = {}
  for sha in a:result.out
    let shas[sha] = 1
  endfor

  let changed = 0
  for entry in a:state.commits
    if get(entry, 'kind', '') !=# 'commit'
      continue
    endif
    let unpushed = has_key(shas, entry.sha)
    if get(entry, 'unpushed', 0) != unpushed
      let entry.unpushed = unpushed
      let changed = 1
    endif
  endfor
  if changed
    call s:render_commits(a:state)
  endif
endfunction

function! s:load_more_commits() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif
  if !get(state, 'commit_has_more', 0)
    echomsg 'GitChanges: all commits are already loaded'
    return
  endif

  let before = get(state, 'commit_loaded', 0)
  call s:load_commits(state, 'append',
        \ function('s:after_load_more', [state, before]))
endfunction

function! s:after_load_more(state, before) abort
  if !s:state_alive(a:state)
    return
  endif
  let added = get(a:state, 'commit_loaded', 0) - a:before
  if added > 0
    echomsg printf('GitChanges: loaded %d more commits (%d total)',
          \ added, a:state.commit_loaded)
  endif
endfunction

function! s:load_files(state, entry, ...) abort
  let OnDone = a:0 ? a:1 : 0
  let token = get(a:state, 'files_req', 0) + 1
  let a:state.files_req = token
  " Results for the previous file list / diff are no longer interesting.
  let a:state.diff_req = get(a:state, 'diff_req', 0) + 1
  call s:job_stop(a:state, 'diff-check')
  call s:job_stop(a:state, 'diff-old')
  call s:job_stop(a:state, 'diff-new')
  call s:job_stop(a:state, 'files-body')

  " The commit body is shown in the files header; fetch it in the background
  " before rendering when it is not cached yet.
  if a:entry.kind ==# 'commit' && !has_key(a:entry, 'body_lines')
    call s:git_job(a:state, 'files-body', 'files_req', token,
          \ ['show', '-s', '--format=%b', a:entry.sha],
          \ function('s:after_body_prefetch',
          \   [a:state, a:entry, OnDone, token]))
    return
  endif

  call s:start_files_job(a:state, a:entry, OnDone, token)
endfunction

function! s:after_body_prefetch(state, entry, OnDone, token, result) abort
  if a:token != get(a:state, 'files_req', 0)
    return
  endif
  let lines = copy(a:result.out)
  while !empty(lines) && empty(lines[0])
    call remove(lines, 0)
  endwhile
  while !empty(lines) && empty(lines[-1])
    call remove(lines, -1)
  endwhile
  let limit = s:opt_int('git_changes_commit_body_lines', 20)
  if len(lines) > limit
    let lines = lines[0 : limit - 1]
    call add(lines, '...')
  endif
  let a:entry.body_lines = lines
  call s:start_files_job(a:state, a:entry, a:OnDone, a:token)
endfunction

function! s:start_files_job(state, entry, OnDone, token) abort
  if a:entry.kind ==# 'worktree'
    let args = ['status', '--porcelain=v1', '--untracked-files=all', '-M']
  elseif a:entry.kind ==# 'compare'
    let args = ['diff', '--name-status', '-M', '--no-ext-diff',
          \ a:entry.old_ref, a:entry.new_ref]
  else
    let args = ['show', '--name-status', '--format=', '--no-color',
          \ '--no-ext-diff', '--find-renames', a:entry.sha]
  endif

  call s:git_job(a:state, 'files', 'files_req', a:token, args,
        \ function('s:apply_files', [a:state, a:entry, a:OnDone]))
endfunction

function! s:apply_files(state, entry, on_done, result) abort
  if a:entry.kind ==# 'worktree'
    let files = s:parse_worktree_status(a:result.out)
  else
    let files = s:parse_status_lines(a:result.out)
  endif
  call s:render_files(a:state, a:entry, files)
  if type(a:on_done) == type(function('tr'))
    call a:on_done()
  endif
endfunction

function! s:side_win(state, side) abort
  if a:side ==# 'work'
    return get(a:state, 'work_win', 0)
  endif
  return a:side ==# 'old' ? a:state.old_win : a:state.new_win
endfunction

function! s:side_buf(state, side) abort
  if a:side ==# 'work'
    return get(a:state, 'work_buf', -1)
  endif
  return a:side ==# 'old' ? a:state.old_buf : a:state.new_buf
endfunction

" Unmerged statuses as reported by `git status --porcelain`.
function! s:is_conflict(file) abort
  return get(a:file, 'status_text', '') =~
        \ '^\(DD\|AU\|UD\|UA\|DU\|AA\|UU\)$'
endfunction

function! s:ensure_work_win(state) abort
  if s:win_exists(get(a:state, 'work_win', 0))
    return 1
  endif
  if !s:win_exists(a:state.new_win)
    return 0
  endif

  let curwin = win_getid()
  let old_winwidth = getwinvar(a:state.new_win, '&winwidth')

  " Make room for a third pane on narrow terminals.
  call win_execute(a:state.files_win,
        \ 'silent! vertical resize ' . max([10, &columns / 6]))
  call win_execute(a:state.new_win,
        \ 'setlocal winminwidth=1')
  call win_execute(a:state.new_win,
        \ 'setlocal winwidth=1')
  try
    call win_gotoid(a:state.new_win)
    rightbelow vsplit
  catch
    call s:apply_layout(a:state)
    call win_gotoid(curwin)
    return 0
  finally
    if s:win_exists(a:state.new_win)
      call win_execute(a:state.new_win,
            \ 'setlocal winwidth=' . old_winwidth)
    endif
  endtry
  let a:state.work_win = win_getid()
  let a:state.work_buf = s:new_scratch(
        \ printf('[GitChanges %d] Work', a:state.id), '')
  call s:init_diff_buffer(a:state, 'work')
  call win_gotoid(curwin)
  return 1
endfunction

function! s:close_work_win(state) abort
  let win = get(a:state, 'work_win', 0)
  let had_work = s:win_exists(win)
  if had_work
    if win == win_getid()
      close
    else
      call win_execute(win, 'silent! close')
    endif
  endif
  let buf = get(a:state, 'work_buf', -1)
  if bufexists(buf)
    execute 'silent! bwipeout! ' . buf
  endif
  let a:state.work_win = 0
  let a:state.work_buf = -1
  if had_work
    call s:apply_layout(a:state)
  endif
endfunction

function! s:resize_three_way(state) abort
  if !s:win_exists(get(a:state, 'work_win', 0))
    return
  endif
  let total = winwidth(a:state.old_win) + winwidth(a:state.new_win)
        \ + winwidth(a:state.work_win) + 2
  let each = max([16, total / 3])
  call win_execute(a:state.old_win, 'silent! vertical resize ' . each)
  call win_execute(a:state.new_win, 'silent! vertical resize ' . each)
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
        \ . 'scrollbind cursorbind foldenable foldmethod=diff foldlevel='
        \ . s:fold_level())
endfunction

function! s:load_side_buffer(state, side, path, lines, detect_filetype, label) abort
  " In the editable file diff the new side is the real file buffer: keep its
  " contents and name untouched.
  if a:side ==# 'new' && get(a:state, 'editable', 0)
    return 0
  endif

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
        \ . 'scrollbind cursorbind foldenable foldmethod=diff foldlevel='
        \ . s:fold_level())
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

function! s:diff_windows(state) abort
  let wins = [a:state.old_win, a:state.new_win]
  let work = get(a:state, 'work_win', 0)
  if work > 0
    call add(wins, work)
  endif
  return wins
endfunction

function! s:diff_off(state) abort
  for winid in s:diff_windows(a:state)
    if s:win_exists(winid)
      call win_execute(winid, 'silent! diffoff')
    endif
  endfor
endfunction

function! s:diff_on(state) abort
  for winid in s:diff_windows(a:state)
    if s:win_exists(winid)
      call win_execute(winid, 'silent! diffthis')
    endif
  endfor
  for winid in s:diff_windows(a:state)
    if s:win_exists(winid)
      call win_execute(winid,
            \ 'setlocal foldenable foldmethod=diff foldlevel=' . s:fold_level())
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

  for winid in s:diff_windows(a:state)
    if get(a:state, 'editable', 0) && winid == a:state.new_win
      continue
    endif
    call s:set_cursor(winid, 1)
    call s:scroll_top(winid)
  endfor
endfunction

function! s:show_side_message(state, lines) abort
  call s:close_work_win(a:state)
  let a:state.shown_file = {}
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

function! s:file_paths(file) abort
  let old_path = empty(get(a:file, 'oldpath', '')) ? a:file.path : a:file.oldpath
  let new_path = a:file.path
  let paths = [old_path]
  if new_path !=# old_path
    call add(paths, new_path)
  endif
  return [old_path, new_path, paths]
endfunction

function! s:path_args(paths) abort
  return join(map(copy(a:paths), 'shellescape(v:val)'), ' ')
endfunction

" `git add -A` fails with "pathspec did not match any files" for a path that is
" absent from both the index and the worktree. That happens once a rename or a
" deletion is fully staged, so drop those paths before staging.
function! s:addable_paths(root, paths) abort
  let result = []
  for path in a:paths
    if !empty(getftype(a:root . '/' . path))
          \ || !empty(s:git_one(a:root,
          \       'ls-files --error-unmatch -- ' . shellescape(path)))
      call add(result, path)
    endif
  endfor
  return result
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

function! s:toggle_main_staged_diff() abort
  let state = s:cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif

  let entry = state.commits[state.commit_index]
  if entry.kind !=# 'worktree'
    call s:err('staged view is only available for working tree changes')
    return
  endif

  let index = s:current_file_index(state)
  if index < 0
    let index = state.file_index
  endif
  if index < 0 || index >= len(state.files)
    call s:err('select a file first')
    return
  endif

  let state.diff_cached = !get(state, 'diff_cached', 0)
  call s:show_diff(state, state.files[index], entry)
endfunction

function! s:show_diff(state, file, ...) abort
  if a:state.commit_index < 0 || a:state.commit_index >= len(a:state.commits)
    return
  endif
  let entry = a:0 ? a:1 : a:state.commits[a:state.commit_index]
  let [old_path, new_path, paths] = s:file_paths(a:file)
  let cached = entry.kind ==# 'worktree' && get(a:state, 'diff_cached', 0)

  let token = get(a:state, 'diff_req', 0) + 1
  let a:state.diff_req = token
  call s:job_stop(a:state, 'diff-check')
  call s:job_stop(a:state, 'diff-old')
  call s:job_stop(a:state, 'diff-new')
  let ctx = {
        \ 'file': a:file,
        \ 'entry': entry,
        \ 'old_path': old_path,
        \ 'new_path': new_path,
        \ 'cached': cached,
        \ 'old': [],
        \ 'new': [],
        \ 'pending': 0,
        \ 'token': token,
        \ }

  if entry.kind ==# 'worktree' && !cached && s:is_conflict(a:file)
    call s:show_conflict_diff(a:state, a:file, entry, ctx)
    return
  endif
  call s:close_work_win(a:state)

  if entry.kind ==# 'worktree'
    if cached
      if get(a:file, 'status_text', '') ==# '??'
        call s:show_side_message(a:state,
              \ ['(untracked file - not in the index)'])
        let a:state.shown_file = a:file
        return
      endif
      let ctx.old_label = 'HEAD ' . old_path
      let ctx.new_label = 'INDEX ' . new_path
      let args = ['diff', '--numstat', '--cached']
      if get(a:state, 'has_head', 0)
        call add(args, 'HEAD')
      endif
      let args = args + ['--'] + paths
    else
      let ctx.old_label = 'INDEX ' . old_path
      let ctx.new_label = 'WORKTREE ' . new_path
      let args = ['diff', '--numstat', '--'] + paths
    endif
  elseif entry.kind ==# 'compare'
    let ctx.old_label = entry.old_label . ' ' . old_path
    let ctx.new_label = entry.new_label . ' ' . new_path
    let args = ['diff', '--numstat', entry.old_ref, entry.new_ref, '--'] + paths
  else
    let ctx.old_label = 'PARENT ' . old_path
    let ctx.new_label = entry.short . ' ' . new_path
    let args = ['show', '--numstat', '--format=', entry.sha, '--'] + paths
  endif

  call s:git_job(a:state, 'diff-check', 'diff_req', token, args,
        \ function('s:on_diff_check', [a:state, ctx]))
endfunction

function! s:diff_is_stale(state, ctx) abort
  return a:ctx.token != get(a:state, 'diff_req', 0)
endfunction

function! s:on_diff_check(state, ctx, result) abort
  if s:diff_is_stale(a:state, a:ctx)
    return
  endif

  for line in a:result.out
    if line =~# '^-\t-\t'
      call s:show_side_message(a:state,
            \ ['(binary file - no side-by-side diff)'])
      return
    endif
  endfor

  if a:ctx.entry.kind ==# 'worktree'
        \ && !get(a:ctx, 'cached', 0)
        \ && a:ctx.file.status !=# 'D'
        \ && s:worktree_file_is_binary(a:state.root, a:ctx.new_path)
    call s:show_side_message(a:state,
          \ ['(binary file - no side-by-side diff)'])
    return
  endif

  if a:ctx.entry.kind ==# 'worktree' && !get(a:ctx, 'cached', 0)
    " The working tree file is local, read it directly.  The old side is the
    " index, so the default view is plain "git diff".
    let a:ctx.new = s:read_worktree(a:state.root, a:ctx.new_path)
    call s:git_job(a:state, 'diff-old', 'diff_req', a:ctx.token,
          \ ['show', ':' . a:ctx.old_path],
          \ function('s:on_diff_old', [a:state, a:ctx]))
    return
  endif

  if a:ctx.entry.kind ==# 'worktree'
    let old_args = ['show', 'HEAD:' . a:ctx.old_path]
    let new_args = ['show', ':' . a:ctx.new_path]
  elseif a:ctx.entry.kind ==# 'compare'
    let old_args = ['show', a:ctx.entry.old_ref . ':' . a:ctx.old_path]
    let new_args = ['show', a:ctx.entry.new_ref . ':' . a:ctx.new_path]
  else
    let old_args = ['show', a:ctx.entry.sha . '^:' . a:ctx.old_path]
    let new_args = ['show', a:ctx.entry.sha . ':' . a:ctx.new_path]
  endif

  let a:ctx.pending = 2
  call s:git_job(a:state, 'diff-old', 'diff_req', a:ctx.token, old_args,
        \ function('s:on_diff_part', [a:state, a:ctx, 'old']))
  call s:git_job(a:state, 'diff-new', 'diff_req', a:ctx.token, new_args,
        \ function('s:on_diff_part', [a:state, a:ctx, 'new']))
endfunction

function! s:on_diff_old(state, ctx, result) abort
  if s:diff_is_stale(a:state, a:ctx)
    return
  endif
  let a:ctx.old = a:result.out
  call s:apply_diff(a:state, a:ctx)
endfunction

function! s:on_diff_part(state, ctx, side, result) abort
  if s:diff_is_stale(a:state, a:ctx)
    return
  endif
  let a:ctx[a:side] = a:result.out
  let a:ctx.pending -= 1
  if a:ctx.pending <= 0
    call s:apply_diff(a:state, a:ctx)
  endif
endfunction

function! s:show_conflict_diff(state, file, entry, ctx) abort
  let path = a:ctx.new_path
  let a:ctx.three_way = 1
  let a:ctx.old_path = path
  let a:ctx.new_path = path
  let a:ctx.work_path = path
  let a:ctx.old_label = 'OURS ' . path
  let a:ctx.new_label = 'WORKTREE ' . path
  let a:ctx.work_label = 'THEIRS ' . path

  if s:worktree_file_is_binary(a:state.root, path)
    call s:close_work_win(a:state)
    call s:show_side_message(a:state,
          \ ['(binary file - no side-by-side diff)'])
    return
  endif

  let a:ctx.new = s:read_worktree(a:state.root, path)
  let a:ctx.pending = 2
  call s:git_job(a:state, 'diff-old', 'diff_req', a:ctx.token,
        \ ['show', ':2:' . path],
        \ function('s:on_diff_part', [a:state, a:ctx, 'old']))
  call s:git_job(a:state, 'diff-new', 'diff_req', a:ctx.token,
        \ ['show', ':3:' . path],
        \ function('s:on_diff_part', [a:state, a:ctx, 'work']))
endfunction

function! s:apply_three_way(state, ctx) abort
  if s:diff_is_stale(a:state, a:ctx)
    return
  endif

  let old_lines = a:ctx.old
  let new_lines = a:ctx.new
  let work_lines = a:ctx.work
  let need_diff = s:side_needs_update(a:state, 'old', a:ctx.old_path, old_lines)
        \ || s:side_needs_update(a:state, 'new', a:ctx.new_path, new_lines)
        \ || s:side_needs_update(a:state, 'work', a:ctx.work_path, work_lines)

  let old_lazy = &lazyredraw
  set lazyredraw
  try
    if need_diff
      call s:diff_off(a:state)
    endif

    let curwin = win_getid()
    if !s:ensure_work_win(a:state)
      return
    endif

    call s:load_side_buffer(a:state, 'old', a:ctx.old_path, old_lines, 1,
          \ a:ctx.old_label)
    call s:load_side_buffer(a:state, 'new', a:ctx.new_path, new_lines, 1,
          \ a:ctx.new_label)
    call s:load_side_buffer(a:state, 'work', a:ctx.work_path, work_lines, 1,
          \ a:ctx.work_label)

    if need_diff
      call s:diff_on(a:state)
      call s:sync_diff(a:state)
    endif
    call s:resize_three_way(a:state)
    let a:state.shown_file = a:ctx.file
    call win_gotoid(curwin)
  finally
    let &lazyredraw = old_lazy
  endtry
endfunction

function! s:apply_diff(state, ctx) abort
  if s:diff_is_stale(a:state, a:ctx)
    return
  endif

  if get(a:ctx, 'three_way', 0)
    call s:apply_three_way(a:state, a:ctx)
    return
  endif

  let old_lines = a:ctx.old
  let new_lines = a:ctx.new
  let need_diff = s:side_needs_update(a:state, 'old', a:ctx.old_path, old_lines)
        \ || s:side_needs_update(a:state, 'new', a:ctx.new_path, new_lines)
  if get(a:state, 'editable', 0)
    let need_diff = 1
  endif

  let old_lazy = &lazyredraw
  set lazyredraw
  try
    if need_diff
      call s:diff_off(a:state)
    endif
    call s:load_side_buffer(a:state, 'old', a:ctx.old_path, old_lines, 1,
          \ a:ctx.old_label)
    call s:load_side_buffer(a:state, 'new', a:ctx.new_path, new_lines, 1,
          \ a:ctx.new_label)
    if need_diff
      call s:diff_on(a:state)
      call s:sync_diff(a:state)
    endif
    let a:state.shown_file = a:ctx.file
  finally
    let &lazyredraw = old_lazy
  endtry
endfunction

function! s:select_commit(state, index) abort
  if a:index < 0 || a:index >= len(a:state.commits)
    return
  endif

  call s:cancel_pending(a:state)
  let a:state.commit_index = a:index
  call s:clear_files_state(a:state)
  call s:set_cursor(a:state.commits_win,
        \ a:state.commits_header + 1 + a:index)
  let entry = a:state.commits[a:index]
  call s:load_files(a:state, entry,
        \ function('s:after_select_files', [a:state, entry]))
endfunction

function! s:after_select_files(state, entry) abort
  if !s:state_alive(a:state)
    return
  endif
  if empty(a:state.files)
    let a:state.file_index = -1
    call s:set_cursor(a:state.files_win, 1)
    call s:show_side_message(a:state, [s:empty_message(a:entry)])
  else
    let a:state.file_index = 0
    call s:goto_file_index(a:state, 0)
    call s:show_diff(a:state, a:state.files[0], a:entry)
  endif
endfunction

function! s:show_no_commits(state) abort
  let a:state.commit_index = -1
  let a:state.file_index = -1
  let a:state.files_entry = ''
  let a:state.shown_file = {}
  let a:state.files_req = get(a:state, 'files_req', 0) + 1
  let a:state.diff_req = get(a:state, 'diff_req', 0) + 1
  call s:job_stop(a:state, 'files')
  call s:job_stop(a:state, 'files-body')
  call s:job_stop(a:state, 'diff-check')
  call s:job_stop(a:state, 'diff-old')
  call s:job_stop(a:state, 'diff-new')
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
  else
    " Reuse an existing view for this repository instead of opening another
    " tab every time the command runs.
    let existing = s:find_state_for_root(root)
    if !empty(existing)
      let tabnr = s:state_tab(existing)
      call s:quit_state(existing)
    endif
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
        \ 'commit_loaded': 0,
        \ 'commit_has_more': 0,
        \ 'files': [],
        \ 'files_entry': '',
        \ 'shown_file': {},
        \ 'commit_index': -1,
        \ 'file_index': -1,
        \ 'commits_header': 1,
        \ 'files_header': 1,
        \ 'updating': 1,
        \ 'list_title': list_title,
        \ 'log_range': log_range,
        \ 'start_entries': start_entries,
        \ 'has_head': has_head,
        \ 'diff_cached': 0,
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
        \ 'work_buf': -1,
        \ 'branches_buf': -1,
        \ 'files_win': 0,
        \ 'commits_win': 0,
        \ 'old_win': 0,
        \ 'new_win': 0,
        \ 'work_win': 0,
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

  call s:apply_layout(state)

  call s:load_branches(state, '')
  call s:load_commits(state, 'initial',
        \ function('s:after_initial_commits', [state]))

  let state.updating = 0
  call win_gotoid(state.files_win)
endfunction

" Heights for the commit and branch panes, derived from the current screen
" size so the layout adapts when the terminal is resized.
function! s:layout_heights() abort
  let total_left = max([12, &lines - 4])
  let branch_height = max([6, min([
        \ s:opt_int('git_changes_branches_height', 8), total_left / 4])])
  let commit_height = max([5, min([
        \ s:opt_int('git_changes_commits_height', 12), total_left / 3])])
  if total_left - branch_height - commit_height < 4
    let commit_height = max([4, total_left - branch_height - 4])
  endif
  return [commit_height, branch_height]
endfunction

" Apply the configured proportions to a GitChanges layout. Called on creation
" and again on VimResized, so shrinking and restoring the terminal does not
" leave one pane stretched and the others squeezed.
function! s:apply_layout(state) abort
  if !s:win_exists(a:state.files_win)
        \ || !s:win_exists(a:state.commits_win)
        \ || !s:win_exists(a:state.branches_win)
        \ || !s:win_exists(a:state.old_win)
        \ || !s:win_exists(a:state.new_win)
    return
  endif

  let width = s:opt_int('git_changes_width', 40)
  let [commit_height, branch_height] = s:layout_heights()

  " `:resize` gives or takes lines from the window below (or above for the
  " bottom window), so set the bottom pane first and let the files pane absorb
  " the rest. Resizing commits directly would move space into branches.
  let total_height = getwininfo(a:state.files_win)[0].height
        \ + getwininfo(a:state.commits_win)[0].height
        \ + getwininfo(a:state.branches_win)[0].height
  let files_height = max([1, total_height - commit_height - branch_height])

  call win_execute(a:state.files_win,
        \ 'silent! vertical resize ' . width)
  if s:win_exists(get(a:state, 'work_win', 0))
    let side_total = winwidth(a:state.old_win) + winwidth(a:state.new_win)
          \ + winwidth(a:state.work_win) + 2
    let side_width = max([16, side_total / 3])
    call win_execute(a:state.old_win,
          \ 'silent! vertical resize ' . side_width)
    call win_execute(a:state.new_win,
          \ 'silent! vertical resize ' . side_width)
  else
    let side_total = winwidth(a:state.old_win) + winwidth(a:state.new_win) + 1
    let side_width = max([20, side_total / 2])
    call win_execute(a:state.old_win,
          \ 'silent! vertical resize ' . side_width)
  endif
  call win_execute(a:state.branches_win, 'silent! resize ' . branch_height)
  call win_execute(a:state.files_win, 'silent! resize ' . files_height)
endfunction

function! s:apply_file_diff_layout(state) abort
  if !s:file_diff_alive(a:state)
    return
  endif
  let total = winwidth(a:state.old_win) + winwidth(a:state.new_win) + 1
  let half = max([20, total / 2])
  call win_execute(a:state.old_win, 'silent! vertical resize ' . half)
endfunction

function! s:on_vim_resized() abort
  for state in copy(s:instances)
    if s:state_alive(state)
      call s:apply_layout(state)
    endif
  endfor
  for state in copy(s:file_diff_instances)
    if s:file_diff_alive(state)
      call s:apply_file_diff_layout(state)
    endif
  endfor
endfunction

augroup git_changes_resize
  autocmd!
  execute 'autocmd VimResized * call ' . s:sid . 'on_vim_resized()'
augroup END

function! s:after_initial_commits(state) abort
  if !s:state_alive(a:state)
    return
  endif
  if empty(a:state.commits)
    call s:show_no_commits(a:state)
  else
    call s:select_commit(a:state, 0)
  endif
endfunction

function! s:quit_state(state) abort
  let state = a:state
  call s:cancel_pending(state)
  call s:cancel_refresh(state)
  call s:cancel_jobs(state)
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
        \ state.new_buf, get(state, 'work_buf', -1), state.branches_buf]
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

" Close the current GitChangesDiff view (inline splits or its tab).
function! git_changes#diff_quit() abort
  let state = get(b:, 'git_changes_file_diff', {})
  if empty(state)
    let state = get(t:, 'git_changes_file_diff', {})
  endif
  if empty(state) || !s:file_diff_alive(state)
    call s:err('no GitChangesDiff window found')
    return
  endif
  call s:close_file_diff(state)
endfunction

let s:gitdir_cache = {}

" Find the git directory for {dir} without running git: walk up to .git and
" follow the "gitdir:" file used by worktrees and submodules.
function! s:git_dir_for(dir) abort
  let dir = simplify(fnamemodify(a:dir, ':p'))
  while len(dir) > 1 && dir[-1:] ==# '/'
    let dir = dir[:-2]
  endwhile
  if has_key(s:gitdir_cache, dir)
    return s:gitdir_cache[dir]
  endif

  let current = dir
  let result = ''
  while 1
    let candidate = current . '/.git'
    if isdirectory(candidate)
      let result = candidate
      break
    elseif filereadable(candidate)
      let line = get(readfile(candidate, '', 1), 0, '')
      let gitdir = matchstr(line, '^gitdir:\s*\zs.*')
      if !empty(gitdir)
        if gitdir !~# '^/'
          let gitdir = simplify(current . '/' . gitdir)
        endif
        let result = gitdir
      endif
      break
    endif

    let parent = fnamemodify(current, ':h')
    if parent ==# current
      break
    endif
    let current = parent
  endwhile

  let s:gitdir_cache[dir] = result
  if len(s:gitdir_cache) > 200
    call filter(s:gitdir_cache, 'v:val !=# ""')
  endif
  return result
endfunction

" Lightweight statusline helper: [Git(branch)] inside a repository. The branch
" comes from .git/HEAD directly, so it follows the current buffer's repository
" instead of the working directory. The unstaged marker is computed by a
" background job and never blocks the statusline.
let s:statusline_text_cache = {}
let s:statusline_last = {}
let s:statusline_timer = -1
let s:statusline_unstaged_cache = {}
let s:statusline_unstaged_jobs = {}
let s:statusline_unstaged_interval = 1000

function! s:statusline_mode_ok() abort
  return mode() ==# 'n' || mode() ==# 'c'
endfunction

function! s:statusline_delay() abort
  let value = get(g:, 'git_changes_statusline_delay', 500)
  return type(value) == type(0) && value > 0 ? value : 0
endfunction

function! s:schedule_statusline_redraw() abort
  if s:statusline_timer != -1 || !exists('*timer_start')
    return
  endif
  let s:statusline_timer = timer_start(s:statusline_delay(),
        \ {-> s:redraw_statusline()})
endfunction

function! s:redraw_statusline() abort
  let s:statusline_timer = -1
  if s:statusline_mode_ok()
    silent! redrawstatus
  endif
endfunction

" Whether the current file has unstaged changes, checked in the background so
" statusline redraws stay fast. Returns the last known value until the job is
" done.
function! s:statusline_unstaged(root, path) abort
  let key = a:root . nr2char(31) . a:path
  let cached = get(s:statusline_unstaged_cache, key, {})

  " Drop jobs whose buffer was wiped before the callback could run.
  for job_key in keys(s:statusline_unstaged_jobs)
    let job = s:statusline_unstaged_jobs[job_key]
    if !bufexists(get(job.state, 'files_buf', -1))
      call s:job_stop(job.state, 'unstaged')
      if has_key(s:statusline_unstaged_jobs, job_key)
        call remove(s:statusline_unstaged_jobs, job_key)
      endif
    endif
  endfor

  if empty(cached)
        \ || reltimefloat(reltime(cached.time)) * 1000
        \      >= s:statusline_unstaged_interval
    if !has_key(s:statusline_unstaged_jobs, key)
      call s:start_statusline_unstaged_job(a:root, a:path, key)
    endif
  endif

  return empty(cached) ? 0 : cached.unstaged
endfunction

function! s:start_statusline_unstaged_job(root, path, key) abort
  let fake = {'files_buf': bufnr('%'), 'root': a:root, 'unstaged_tok': 1}
  let ctx = {'key': a:key, 'state': fake}
  let s:statusline_unstaged_jobs[a:key] = {'state': fake, 'ctx': ctx}
  call s:git_job(fake, 'unstaged', 'unstaged_tok', 1,
        \ ['status', '--porcelain=v1', '--untracked-files=normal',
        \  '--', a:path],
        \ function('s:on_statusline_unstaged_job', [ctx]))
endfunction

function! s:on_statusline_unstaged_job(ctx, result) abort
  let key = a:ctx.key
  let job = get(s:statusline_unstaged_jobs, key, {})
  if empty(job) || job.state isnot a:ctx.state
    return
  endif
  call remove(s:statusline_unstaged_jobs, key)

  let unstaged = 0
  for file in s:parse_worktree_status(a:result.out)
    let xy = get(file, 'status_text', '')
    if xy ==# '??'
          \ || (strlen(xy) >= 2 && strpart(xy, 1, 1) !=# ' ')
      let unstaged = 1
      break
    endif
  endfor

  let s:statusline_unstaged_cache[key] = {
        \ 'time': reltime(),
        \ 'unstaged': unstaged,
        \ }
  if len(s:statusline_unstaged_cache) > 200
    call filter(s:statusline_unstaged_cache,
          \ 'reltimefloat(reltime(v:val.time)) * 1000 < 60000')
  endif

  if s:statusline_mode_ok()
    silent! redrawstatus
  endif
endfunction

function! s:statusline_unstaged_marker() abort
  let marker = get(g:, 'git_changes_statusline_unstaged', '*')
  if type(marker) != type('') || empty(marker)
    return ''
  endif
  if &buftype !=# ''
    return ''
  endif

  let [root, path] = s:buffer_repo_path()
  if empty(root) || empty(path)
    return ''
  endif
  return s:statusline_unstaged(root, path) ? marker : ''
endfunction

function! git_changes#statusline() abort
  let dir = expand('%:p:h')
  if empty(dir)
    let dir = getcwd()
  endif
  let file = expand('%:p')
  let key = dir . nr2char(31) . file

  " Refresh only in normal mode; in insert/visual mode show the last value.
  if !s:statusline_mode_ok()
    return get(s:statusline_text_cache, key, '')
  endif

  let delay = s:statusline_delay()
  let last = get(s:statusline_last, key, [])
  if delay > 0 && !empty(last)
        \ && reltimefloat(reltime(last[0])) * 1000 < delay
    call s:schedule_statusline_redraw()
    return last[1]
  endif

  let gitdir = s:git_dir_for(dir)
  if empty(gitdir)
    return ''
  endif

  let head = get(readfile(gitdir . '/HEAD', '', 1), 0, '')
  if head =~# '^ref: '
    let branch = substitute(strpart(head, 5), '^refs/heads/', '', '')
    let label = 'Git(' . branch . ')'
  elseif head =~# '^[0-9a-f]\{40\}'
    let label = 'Git(' . strpart(head, 0, 7) . ')'
  else
    let label = 'Git'
  endif

  let text = '[' . label . s:statusline_unstaged_marker() . ']'
  let s:statusline_text_cache[key] = text
  let s:statusline_last[key] = [reltime(), text]
  return text
endfunction

let s:blame_line_cache = {}
let s:blame_line_jobs = {}
let s:blame_debounce = {}

function! s:statusline_clear() abort
  let s:gitdir_cache = {}
  let s:statusline_text_cache = {}
  let s:statusline_last = {}
  let s:statusline_unstaged_cache = {}
  if s:statusline_timer != -1
    call timer_stop(s:statusline_timer)
    let s:statusline_timer = -1
  endif
  for job in values(s:statusline_unstaged_jobs)
    call s:job_stop(job.state, 'unstaged')
  endfor
  let s:statusline_unstaged_jobs = {}
  let s:blame_line_cache = {}
  for st in values(s:blame_debounce)
    if st.timer != -1
      call timer_stop(st.timer)
    endif
  endfor
  let s:blame_debounce = {}
  for job in values(s:blame_line_jobs)
    call s:job_stop(job.state, 'blame_line')
    if !empty(job.ctx.contents)
      call delete(job.ctx.contents)
    endif
  endfor
  let s:blame_line_jobs = {}
endfunction

function! s:parse_blame_entries(out) abort
  let entries = []
  let meta = {}
  let i = 0
  let total = len(a:out)

  while i < total
    let line = a:out[i]
    if line !~# '^[0-9a-f]\{40\} '
      let i += 1
      continue
    endif

    let sha = strpart(line, 0, 40)
    let author = ''
    let email = ''
    let date = ''
    let summary = ''
    let i += 1
    while i < total && a:out[i][0] !=# "\t"
      let field = a:out[i]
      if field =~# '^author '
        let author = strpart(field, 7)
      elseif field =~# '^author-mail '
        let email = substitute(strpart(field, 12), '^<\(.*\)>$', '\1', '')
      elseif field =~# '^author-time '
        let date = strftime('%Y-%m-%d', str2nr(strpart(field, 12)))
      elseif field =~# '^summary '
        let summary = strpart(field, 8)
      endif
      let i += 1
    endwhile

    if sha =~# '^0\+$'
      let author = 'Uncommitted'
      let email = ''
      let summary = ''
    endif

    if !empty(author)
      let meta[sha] = [author, email, date, summary]
    elseif has_key(meta, sha)
      let [author, email, date, summary] = meta[sha]
    endif

    if i < total && a:out[i][0] ==# "\t"
      let i += 1
    endif

    call add(entries, {
          \ 'sha': sha =~# '^0\+$' ? '' : strpart(sha, 0, 8),
          \ 'author': author,
          \ 'email': email,
          \ 'date': date,
          \ 'summary': summary,
          \ })
  endwhile
  return entries
endfunction

function! s:blame_line_entries(root, path) abort
  let buf = bufnr('%')
  let tick = getbufvar(buf, 'changedtick', 0)
  let key = buf . ':' . tick
  let now = localtime()
  let cached = get(s:blame_line_cache, key, {})
  if !empty(cached) && now - cached.time < 5
    return cached.entries
  endif

  let contents = ''
  if &modified
    let contents = tempname()
    call writefile(getline(1, '$'), contents)
  endif

  let entries = []
  try
    let cmd = 'git --no-pager -c core.quotePath=false -c color.ui=false -C '
          \ . shellescape(a:root) . ' blame --line-porcelain'
    if !empty(contents)
      let cmd .= ' --contents ' . shellescape(contents)
    endif
    let cmd .= ' -- ' . shellescape(a:path)
    let out = systemlist(cmd)
    if !v:shell_error
      let entries = s:parse_blame_entries(out)
    endif
  finally
    if !empty(contents)
      call delete(contents)
    endif
  endtry

  let s:blame_line_cache[key] = {'time': now, 'entries': entries}
  if len(s:blame_line_cache) > 100
    call filter(s:blame_line_cache, 'now - v:val.time < 30')
  endif
  return entries
endfunction

" Resolve the current buffer's worktree root and repo-relative path without
" spawning git. Handles normal .git directories and worktree/submodule .git
" files.
function! s:buffer_repo_path() abort
  let file = expand('%:p')
  if empty(file)
    return ['', '']
  endif

  let current = simplify(fnamemodify(file, ':h'))
  while len(current) > 1 && current[-1:] ==# '/'
    let current = current[:-2]
  endwhile

  let root = ''
  let scan = current
  while 1
    if isdirectory(scan . '/.git') || filereadable(scan . '/.git')
      let root = scan
      break
    endif
    let parent = fnamemodify(scan, ':h')
    if parent ==# scan
      break
    endif
    let scan = parent
  endwhile
  if empty(root)
    return ['', '']
  endif

  return [root, s:repo_relative_path(root, file)]
endfunction

" Blame data for the current line: {sha, author, email, date, summary}.
function! git_changes#blame_line_info() abort
  let [root, path] = s:buffer_repo_path()
  if empty(root) || empty(path) || !filereadable(root . '/' . path)
    return {}
  endif

  let entries = s:blame_line_entries(root, path)
  let lnum = line('.')
  if lnum < 1 || lnum > len(entries)
    return {}
  endif
  return entries[lnum - 1]
endfunction

function! s:format_blame_line(info) abort
  let text = get(g:, 'git_changes_blame_line_format', '%a %d')
  for [key, value] in items({'h': a:info.sha, 'a': a:info.author,
        \ 'e': a:info.email, 'd': a:info.date, 's': a:info.summary})
    let text = substitute(text, '%' . key, escape(value, '\&~'), 'g')
  endfor
  return trim(text)
endfunction

" Formatted blame for the current line. g:git_changes_blame_line_format
" supports %h (short hash), %a (author), %e (email), %d (date), %s (summary).
function! git_changes#blame_line() abort
  let info = git_changes#blame_line_info()
  return empty(info) ? '' : s:format_blame_line(info)
endfunction

function! s:start_blame_line_job(root, path, key) abort
  let contents = ''
  if &modified
    let contents = tempname()
    call writefile(getline(1, '$'), contents)
  endif

  let args = ['blame', '--line-porcelain']
  if !empty(contents)
    call extend(args, ['--contents', contents])
  endif
  call extend(args, ['--', a:path])

  let fake = {'files_buf': bufnr('%'), 'root': a:root, 'blame_tok': 1}
  let ctx = {'key': a:key, 'contents': contents, 'state': fake}
  let s:blame_line_jobs[a:key] = {'state': fake, 'ctx': ctx}
  call s:git_job(fake, 'blame_line', 'blame_tok', 1, args,
        \ function('s:on_blame_line_job', [ctx]))
endfunction

function! s:on_blame_line_job(ctx, result) abort
  let key = a:ctx.key
  let job = get(s:blame_line_jobs, key, {})
  if empty(job) || job.state isnot a:ctx.state
    return
  endif
  call remove(s:blame_line_jobs, key)
  if !empty(a:ctx.contents)
    call delete(a:ctx.contents)
  endif
  let entries = empty(a:result.out)
        \ ? [] : s:parse_blame_entries(a:result.out)
  let s:blame_line_cache[key] = {
        \ 'time': localtime(),
        \ 'entries': entries,
        \ }
  if len(s:blame_line_cache) > 100
    call filter(s:blame_line_cache, 'localtime() - v:val.time < 30')
  endif
  if s:statusline_mode_ok()
    silent! redrawstatus
  endif
endfunction

" Asynchronous variant for statuslines: returns cached data immediately and
" starts a background blame when the cache is missing or stale.
function! git_changes#blame_line_info_async() abort
  let [root, path] = s:buffer_repo_path()
  if empty(root) || empty(path) || !filereadable(root . '/' . path)
    return {}
  endif

  let buf = bufnr('%')
  let tick = getbufvar(buf, 'changedtick', 0)
  let key = buf . ':' . tick
  let now = localtime()
  let cached = get(s:blame_line_cache, key, {})

  " Do not start or refresh jobs outside normal mode.
  if !s:statusline_mode_ok()
    if empty(cached)
      return {}
    endif
    let lnum = line('.')
    if lnum < 1 || lnum > len(cached.entries)
      return {}
    endif
    return cached.entries[lnum - 1]
  endif

  if empty(cached) || now - cached.time >= 10
    if !has_key(s:blame_line_jobs, key)
      call s:start_blame_line_job(root, path, key)
    endif
  endif

  if empty(cached)
    return {}
  endif
  let lnum = line('.')
  if lnum < 1 || lnum > len(cached.entries)
    return {}
  endif
  return cached.entries[lnum - 1]
endfunction

function! s:blame_debounce_fire(buf) abort
  let st = get(s:blame_debounce, a:buf, {})
  if empty(st)
    return
  endif
  let st.timer = -1
  let st.ready = st.want
  if s:statusline_mode_ok()
    silent! redrawstatus
  endif
endfunction

function! git_changes#blame_line_async() abort
  let buf = bufnr('%')
  let key = buf . ':' . getbufvar(buf, 'changedtick', 0)
        \ . ':' . expand('%:p') . ':' . line('.')
  let delay = s:statusline_delay()
  let st = get(s:blame_debounce, buf, {})
  if empty(st)
    let st = {'want': '', 'ready': '', 'shown': {}, 'timer': -1}
    let s:blame_debounce[buf] = st
  endif

  if !empty(st.shown) && get(st.shown, 'key', '') ==# key
    return st.shown.text
  endif

  " Debounce: wait until the cursor stops moving before updating.
  if delay > 0 && st.ready !=# key
    if st.timer != -1
      call timer_stop(st.timer)
    endif
    let st.want = key
    let st.timer = timer_start(delay, {-> s:blame_debounce_fire(buf)})
    return empty(st.shown) ? '' : st.shown.text
  endif

  let info = git_changes#blame_line_info_async()
  let text = empty(info) ? '' : s:format_blame_line(info)
  if !empty(info) || has_key(s:blame_line_cache, key)
    let st.shown = {'key': key, 'text': text}
    let st.ready = ''
  else
    " The background job is still running; poll again on the next redraw.
    let st.ready = key
  endif
  return text
endfunction

" Resolve an optional command argument to a path relative to the repo root.
function! s:resolve_path_arg(root, arg) abort
  if empty(a:arg)
    return s:current_repo_path(a:root)
  endif
  if a:arg =~# '^/'
    return s:repo_relative_path(a:root, a:arg)
  endif

  let abs = fnamemodify(a:arg, ':p')
  let rel = s:repo_relative_path(a:root, abs)
  if !empty(rel) && !empty(getftype(abs))
    return rel
  endif
  return a:arg
endfunction

" Worktree status entry for {path}, used by the stage/unstage/discard commands.
function! s:status_entry(root, path) abort
  let out = s:git(a:root, 'status --porcelain -- ' . shellescape(a:path))
  let files = s:parse_worktree_status(out)
  for file in files
    if file.path ==# a:path || get(file, 'oldpath', '') ==# a:path
      return file
    endif
  endfor
  return empty(files) ? {} : files[0]
endfunction

function! s:refresh_files_for_root(root, path) abort
  let state = s:find_state_for_root(a:root)
  if !empty(state)
    call s:refresh_file_list(state, a:path)
  endif
endfunction

" Stage, unstage, and discard files from any buffer. The optional argument is
" a path; without it the current file is used.
function! git_changes#stage(...) abort
  let root = s:repo_root()
  if empty(root)
    call s:err('not inside a Git repository')
    return
  endif

  let path = s:resolve_path_arg(root, a:0 ? a:1 : '')
  if empty(path)
    call s:err('GitChangesStage: no file in the current buffer')
    return
  endif

  let file = s:status_entry(root, path)
  let paths = empty(file) ? [path] : s:file_paths(file)[2]
  let add_paths = s:addable_paths(root, paths)
  if empty(add_paths)
    echomsg 'Nothing to stage: ' . path
    return
  endif
  if !s:git_do(root, 'add -A -- ' . s:path_args(add_paths))
    return
  endif

  echomsg 'Staged: ' . path
  call s:refresh_files_for_root(root, path)
endfunction

function! git_changes#unstage(...) abort
  let root = s:repo_root()
  if empty(root)
    call s:err('not inside a Git repository')
    return
  endif

  let path = s:resolve_path_arg(root, a:0 ? a:1 : '')
  if empty(path)
    call s:err('GitChangesUnstage: no file in the current buffer')
    return
  endif

  let file = s:status_entry(root, path)
  let paths = empty(file) ? [path] : s:file_paths(file)[2]
  if !s:has_staged_changes(root, paths)
    echomsg 'Not staged: ' . path
    return
  endif

  let args = empty(s:resolve_ref(root, 'HEAD'))
        \ ? 'rm -q --cached -- '
        \ : 'reset -q HEAD -- '
  if !s:git_do(root, args . s:path_args(paths))
    return
  endif

  echomsg 'Unstaged: ' . path
  call s:refresh_files_for_root(root, path)
endfunction

function! git_changes#discard(...) abort
  let root = s:repo_root()
  if empty(root)
    call s:err('not inside a Git repository')
    return
  endif

  let path = s:resolve_path_arg(root, a:0 ? a:1 : '')
  if empty(path)
    call s:err('GitChangesDiscard: no file in the current buffer')
    return
  endif

  let file = s:status_entry(root, path)
  if empty(file)
    echomsg 'No changes: ' . path
    return
  endif
  if !s:discard_file(root, file)
    return
  endif
  call s:refresh_files_for_root(root, path)
endfunction

" Commit, pull, and push from any buffer without opening the GitChanges tab.
function! git_changes#commit(...) abort
  let root = s:repo_root()
  if empty(root)
    call s:err('not inside a Git repository')
    return
  endif

  let state = s:find_state_for_root(root)
  let arg = a:0 ? trim(a:1) : ''

  if arg ==# '-e' || arg ==# '--edit'
    call s:open_commit_editor(root,
          \ empty(state)
          \ ? function('s:noop')
          \ : function('s:reload_current_branch', [state]))
    return
  endif

  let ok = a:0 ? s:commit_index(root, a:1) : s:commit_index(root)
  if ok && !empty(state)
    call s:reload_current_branch(state)
  endif
endfunction

function! git_changes#complete_commit(arglead, cmdline, cursorpos) abort
  return filter(['-e', '--edit'], 'stridx(v:val, a:arglead) == 0')
endfunction

function! git_changes#pull() abort
  let root = s:repo_root()
  if empty(root)
    call s:err('not inside a Git repository')
    return
  endif
  call s:pull_root(root, s:find_state_for_root(root))
endfunction

function! git_changes#push() abort
  let root = s:repo_root()
  if empty(root)
    call s:err('not inside a Git repository')
    return
  endif
  call s:push_root(root, s:find_state_for_root(root))
endfunction


" ============================================================================
" GitChangesDiff
"
" A focused two-window file diff.  It reuses the side-by-side machinery from
" the main browser but keeps its own state and never touches an open
" GitChanges tab.
" ============================================================================

let s:file_diff_next_id = 0
let s:file_diff_instances = []
let s:file_diff_active = {}

function! git_changes#diff_open(raw) abort
  call s:diff_open(a:raw, {'cmd': 'GitChangesDiff'})
endfunction

function! s:diff_usage(defaults) abort
  call s:err('usage: :' . get(a:defaults, 'cmd', 'GitChangesDiff')
        \ . ' [ref1] [ref2] [--staged|--cached] [-w|-b] [-- path]')
endfunction

" Shell-like splitting so quoted paths and escaped spaces survive.
function! s:split_args(raw) abort
  let tokens = []
  let token = ''
  let quote = ''
  let escaped = 0

  for i in range(strlen(a:raw))
    let ch = a:raw[i]
    if escaped
      let token .= ch
      let escaped = 0
    elseif ch ==# "\\"
      let escaped = 1
    elseif !empty(quote)
      if ch ==# quote
        let quote = ''
      else
        let token .= ch
      endif
    elseif ch ==# '"' || ch ==# "'"
      let quote = ch
    elseif ch ==# ' ' || ch ==# "\t"
      if !empty(token)
        call add(tokens, token)
        let token = ''
      endif
    else
      let token .= ch
    endif
  endfor

  if escaped
    let token .= "\\"
  endif
  if !empty(token)
    call add(tokens, token)
  endif
  return tokens
endfunction

function! s:current_repo_path(root) abort
  " Running :GitChangesDiff from one of our diff windows keeps the same file.
  let file_diff = get(t:, 'git_changes_file_diff', {})
  if !empty(file_diff)
    let buf = bufnr('%')
    if (buf == get(file_diff, 'old_buf', -1)
          \ || buf == get(file_diff, 'new_buf', -1))
          \ && get(file_diff, 'root', '') ==# a:root
      return get(get(file_diff, 'spec', {}), 'path', '')
    endif
  endif

  if &buftype !=# ''
    return ''
  endif
  let name = expand('%:p')
  if empty(name)
    return ''
  endif
  return s:repo_relative_path(a:root, name)
endfunction

function! s:repo_relative_path(root, path) abort
  if empty(a:path)
    return ''
  endif

  if a:path =~# '^/'
    let abs = simplify(a:path)
  else
    let abs = simplify(fnamemodify(a:path, ':p'))
  endif

  let root = simplify(fnamemodify(a:root, ':p'))
  while len(root) > 1 && root[-1:] ==# '/'
    let root = root[:-2]
  endwhile

  let relative = s:path_relative_to(abs, root)
  if !empty(relative)
    return relative
  endif

  " /var and /private/var (and similar symlinked roots) should still match.
  let abs = simplify(resolve(abs))
  let root = simplify(resolve(root))
  while len(root) > 1 && root[-1:] ==# '/'
    let root = root[:-2]
  endwhile
  return s:path_relative_to(abs, root)
endfunction

function! s:path_relative_to(path, root) abort
  if a:path ==# a:root
    return ''
  endif
  let prefix = a:root . '/'
  if stridx(a:path, prefix) == 0
    return strpart(a:path, len(prefix))
  endif
  return ''
endfunction

function! s:build_diff_labels(spec) abort
  let path = a:spec.path
  let refs = a:spec.refs

  if get(a:spec, 'conflict', 0)
    let a:spec.old_expr = ':2:' . path
    let a:spec.old_label = 'OURS ' . path
    let a:spec.new_expr = ''
    let a:spec.new_label = 'WORKTREE ' . path
    let a:spec.new_kind = 'worktree'
    let a:spec.work_expr = ':3:' . path
    let a:spec.work_label = 'THEIRS ' . path
    return
  endif

  if len(refs) == 2
    let a:spec.old_expr = refs[0] . ':' . path
    let a:spec.new_expr = refs[1] . ':' . path
    let a:spec.old_label = a:spec.revisions[0] . ' ' . path
    let a:spec.new_label = a:spec.revisions[1] . ' ' . path
    let a:spec.new_kind = 'ref'
    return
  endif

  if a:spec.cached
    if empty(refs)
      let base = a:spec.has_head ? 'HEAD' : ''
      let base_label = a:spec.has_head ? 'HEAD' : '(empty)'
    else
      let base = refs[0]
      let base_label = a:spec.revisions[0]
    endif
    let a:spec.old_expr = empty(base) ? '' : base . ':' . path
    let a:spec.old_label = base_label . ' ' . path
    let a:spec.new_expr = ':' . path
    let a:spec.new_label = 'INDEX ' . path
    let a:spec.new_kind = 'index'
    return
  endif

  if empty(refs)
    " No revision and no --staged: plain "git diff", index vs working tree.
    let a:spec.old_expr = ':' . path
    let a:spec.old_label = 'INDEX ' . path
  else
    let a:spec.old_expr = refs[0] . ':' . path
    let a:spec.old_label = a:spec.revisions[0] . ' ' . path
  endif
  let a:spec.new_expr = ''
  let a:spec.new_label = 'WORKTREE ' . path
  let a:spec.new_kind = 'worktree'
endfunction

function! s:parse_diff_args(root, current, tokens, defaults) abort
  let sep = -1
  for i in range(len(a:tokens))
    if a:tokens[i] ==# '--'
      let sep = i
      break
    endif
  endfor

  if sep >= 0
    let opts = sep == 0 ? [] : a:tokens[0 : sep - 1]
    let paths = sep >= len(a:tokens) - 1 ? [] : a:tokens[sep + 1 :]
  else
    let opts = a:tokens
    let paths = []
  endif

  if len(paths) > 1
    call s:diff_usage(a:defaults)
    return {}
  endif

  let raw_path = empty(paths) ? a:current : paths[0]
  if empty(raw_path)
    call s:err('current buffer is not a file; specify a path after --')
    return {}
  endif

  let path = s:repo_relative_path(a:root, raw_path)
  if empty(path)
    call s:err('path is outside the repository: ' . raw_path)
    return {}
  endif
  if isdirectory(a:root . '/' . path)
    call s:err('path is a directory: ' . path)
    return {}
  endif

  let revisions = []
  let cached = 0
  let saw_w = 0
  let saw_b = 0

  for token in opts
    if token ==# '--staged' || token ==# '--cached'
      let cached = 1
    elseif token ==# '-w' || token ==# '--ignore-all-space'
      let saw_w = 1
    elseif token ==# '-b' || token ==# '--ignore-space-change'
      let saw_b = 1
    else
      call add(revisions, token)
    endif
  endfor

  if len(revisions) > 2 || (cached && len(revisions) > 1)
    call s:diff_usage(a:defaults)
    return {}
  endif

  let ignore = ''
  if saw_w
    let ignore = 'iwhiteall'
  elseif saw_b
    let ignore = 'iwhite'
  endif

  let refs = []
  for rev in revisions
    let sha = s:resolve_ref(a:root, rev)
    if empty(sha)
      call s:err('unknown revision: ' . rev)
      return {}
    endif
    call add(refs, sha)
  endfor

  let spec = {
        \ 'path': path,
        \ 'revisions': revisions,
        \ 'refs': refs,
        \ 'has_head': !empty(s:resolve_ref(a:root, 'HEAD')),
        \ 'cached': cached,
        \ 'ignore': ignore,
        \ }
  let spec.conflict = !cached && empty(refs)
        \ && s:path_is_conflict(a:root, path)
  call s:build_diff_labels(spec)
  return spec
endfunction

function! s:path_is_conflict(root, path) abort
  return !empty(s:git(a:root, 'ls-files -u -- ' . shellescape(a:path)))
endfunction

function! s:diff_path_known(root, spec) abort
  if filereadable(a:root . '/' . a:spec.path)
    return 1
  endif
  if s:git_run(a:root, 'ls-files --error-unmatch -- '
        \ . shellescape(':(literal)' . a:spec.path)).ok
    return 1
  endif
  for expr in [a:spec.old_expr, a:spec.new_expr]
    if !empty(expr)
          \ && s:git_run(a:root, 'cat-file -e ' . shellescape(expr)).ok
      return 1
    endif
  endfor
  " A file that only exists in HEAD has no unstaged diff, but the path is
  " still valid: open an empty index-vs-worktree view instead of erroring.
  if a:spec.has_head
        \ && s:git_run(a:root,
        \      'cat-file -e ' . shellescape('HEAD:' . a:spec.path)).ok
    return 1
  endif
  return 0
endfunction

function! s:prompt_confirm(prompt, choices, default) abort
  if exists('g:git_changes_confirm_override')
    let value = g:git_changes_confirm_override
    unlet g:git_changes_confirm_override
    return type(value) == type(0) ? value : str2nr(value)
  endif
  return confirm(a:prompt, a:choices, a:default)
endfunction

function! s:maybe_save_current(root, spec, current) abort
  if empty(a:current) || a:spec.path !=# a:current
    return 1
  endif
  if !&modified || &buftype !=# ''
    return 1
  endif

  let choice = s:prompt_confirm(
        \ 'GitChangesDiff: save changes before comparing disk contents?',
        \ "&Save\n&Skip\n&Cancel", 1)
  if choice == 2
    echomsg 'GitChangesDiff: comparing disk contents (unsaved changes skipped)'
    return 2
  elseif choice != 1
    return 0
  endif

  try
    silent write
  catch
    call s:err('failed to save: ' . v:exception)
    return 0
  endtry
  if &modified
    call s:err('failed to save the file')
    return 0
  endif
  return 1
endfunction

function! s:diff_open(raw, defaults) abort
  let root = s:repo_root()
  if empty(root)
    call s:err('not inside a Git repository')
    return
  endif

  let current = s:current_repo_path(root)
  let tokens = s:split_args(a:raw)
  let spec = s:parse_diff_args(root, current, tokens, a:defaults)
  if empty(spec)
    return
  endif

  let save_state = 1
  if spec.new_kind ==# 'worktree'
    let save_state = s:maybe_save_current(root, spec, current)
    if save_state == 0
      return
    endif
  endif

  if !s:diff_path_known(root, spec)
    call s:err('path not found: ' . spec.path)
    return
  endif

  let inline = save_state != 2 && spec.new_kind ==# 'worktree'
        \ && !empty(current) && current ==# spec.path && &buftype ==# ''
        \ && !s:worktree_file_is_binary(root, spec.path)

  " Reuse the existing diff tab for this repository instead of opening a new
  " one on every invocation.
  let tabnr = 0
  let existing = s:find_file_diff_state(root)
  if !empty(existing)
    let tabnr = s:close_file_diff(existing)
    if tabnr < 0
      return
    endif
    if inline
      let tabnr = 0
    endif
  endif

  call s:open_sxs_diff(root, spec, tabnr, save_state != 2, inline)
endfunction

function! s:open_sxs_diff(root, spec, ...) abort
  let tabnr = a:0 ? a:1 : 0
  let editable = a:0 > 1 ? a:2 : 1
  let inline = a:0 > 2 ? a:3 : 0
  let id = s:file_diff_next_id + 1
  let s:file_diff_next_id = id

  let initial_buf = -1
  let file_win = 0
  let file_buf = -1
  if inline
    let file_win = win_getid()
    let file_buf = bufnr('%')
  else
    tabnew
    if tabnr > 0
      execute 'silent! tabmove ' . (tabnr - 1)
    endif
    let initial_buf = bufnr('%')
  endif

  let state = {
        \ 'id': id,
        \ 'root': a:root,
        \ 'spec': a:spec,
        \ 'tab': tabpagenr(),
        \ 'old_buf': -1,
        \ 'new_buf': -1,
        \ 'work_buf': -1,
        \ 'old_win': 0,
        \ 'new_win': 0,
        \ 'work_win': 0,
        \ 'editable': 0,
        \ 'inline': inline,
        \ 'diff_req': 0,
        \ 'shown_file': {},
        \ 'clean': 0,
        \ }
  if inline
    let state.saved_opts = {
          \ 'wrap': &wrap,
          \ 'number': &number,
          \ 'relativenumber': &relativenumber,
          \ 'foldmethod': &foldmethod,
          \ 'foldenable': &foldenable,
          \ 'cursorline': &cursorline,
          \ }
  endif
  let t:git_changes_file_diff = state

  if inline
    call win_gotoid(file_win)
    leftabove vsplit
  endif
  let state.old_win = win_getid()
  let state.old_buf = s:new_scratch(
        \ printf('[GitChangesDiff %d] %s', id, a:spec.old_label), '')
  call s:init_file_diff_buffer(state, 'old')

  if inline
    let state.new_win = file_win
    let state.new_buf = file_buf
    let state.editable = editable && a:spec.new_kind ==# 'worktree'
          \ && !s:worktree_file_is_binary(a:root, a:spec.path)
    call win_gotoid(file_win)
    call s:init_file_diff_buffer(state, 'new')
  else
    rightbelow vsplit
    let state.new_win = win_getid()
    if editable && a:spec.new_kind ==# 'worktree'
          \ && !s:worktree_file_is_binary(a:root, a:spec.path)
      execute 'edit ' . fnameescape(a:root . '/' . a:spec.path)
      let state.new_buf = bufnr('%')
      let state.editable = 1
    else
      let state.new_buf = s:new_scratch(
            \ printf('[GitChangesDiff %d] %s', id, a:spec.new_label), '')
    endif
    call s:init_file_diff_buffer(state, 'new')
  endif

  if get(a:spec, 'conflict', 0)
    call win_gotoid(state.new_win)
    rightbelow vsplit
    let state.work_win = win_getid()
    let state.work_buf = s:new_scratch(
          \ printf('[GitChangesDiff %d] %s', id, a:spec.work_label), '')
    call s:init_file_diff_buffer(state, 'work')
  endif

  if initial_buf > 0 && bufexists(initial_buf)
        \ && empty(bufname(initial_buf))
        \ && !getbufvar(initial_buf, '&modified')
    execute 'silent! bwipeout ' . initial_buf
  endif

  " Register only after both sides exist: wiping the initial buffer above
  " triggers a BufWipeout filter that drops states with no live buffers.
  call add(s:file_diff_instances, state)

  if s:win_exists(state.work_win)
    let total = winwidth(state.old_win) + winwidth(state.new_win)
          \ + winwidth(state.work_win) + 2
    let each = max([16, total / 3])
    call win_execute(state.old_win, 'silent! vertical resize ' . each)
    call win_execute(state.new_win, 'silent! vertical resize ' . each)
  else
    let total = winwidth(state.old_win) + winwidth(state.new_win) + 1
    call win_execute(state.old_win,
          \ 'silent! vertical resize ' . max([20, total / 2]))
  endif

  call s:diff_on(state)
  call s:file_diff_activate(state)
  call s:start_sxs_fetch(state)

  for winid in s:diff_windows(state)
    if winid == state.new_win && state.editable
      continue
    endif
    call s:set_cursor(winid, 1)
    call s:scroll_top(winid)
  endfor
  call win_gotoid(state.new_win)
endfunction

function! s:init_file_diff_buffer(state, side) abort
  let b:git_changes_file_diff = a:state
  let b:gc_kind = 'filediff'
  let b:gc_side = a:side
  call s:setup_diff_window()

  if a:side ==# 'new' && get(a:state, 'editable', 0)
    augroup git_changes_file_diff_write
      autocmd! * <buffer>
      execute 'autocmd BufWritePost <buffer> call '
            \ . s:sid . 'refresh_file_diff()'
    augroup END
  endif
endfunction

function! s:diffopt_with_ignore(diffopt, ignore) abort
  " The command's -b/-w flags decide whitespace handling.  Drop any ignore
  " entries from the user's global diffopt for the duration of this view.
  let ignored = ['iwhite', 'iwhiteall', 'iwhiteeol', 'iblank']
  let items = []
  for item in split(a:diffopt, ',')
    if !empty(item) && index(ignored, item) < 0
      call add(items, item)
    endif
  endfor
  if a:ignore ==# 'iwhiteall'
    call add(items, 'iwhiteall')
  elseif a:ignore ==# 'iwhite'
    call add(items, 'iwhite')
  endif
  return join(items, ',')
endfunction

" diffopt is a global option in Vim and Neovim.  Apply the view's ignore
" setting only while its tab is active, and restore it when leaving, so other
" diff windows are never affected.
function! s:file_diff_activate(state) abort
  if empty(a:state) || !s:file_diff_alive(a:state)
    return
  endif
  if s:file_diff_active is a:state
    return
  endif

  call s:file_diff_deactivate(s:file_diff_active)
  let a:state.diffopt_saved = &g:diffopt
  let &g:diffopt = s:diffopt_with_ignore(&g:diffopt, a:state.spec.ignore)
  let s:file_diff_active = a:state
  call s:file_diff_update(a:state)
endfunction

function! s:file_diff_deactivate(state) abort
  if empty(a:state) || s:file_diff_active isnot a:state
    return
  endif
  let &g:diffopt = get(a:state, 'diffopt_saved', &g:diffopt)
  let s:file_diff_active = {}
endfunction

function! s:file_diff_update(state) abort
  let winid = s:win_exists(get(a:state, 'old_win', 0))
        \ ? a:state.old_win : get(a:state, 'new_win', 0)
  if s:win_exists(winid)
    call win_execute(winid, 'silent! diffupdate')
  endif
endfunction

function! s:file_diff_tab_exists(tabnr) abort
  for info in gettabinfo()
    if info.tabnr == a:tabnr
      return 1
    endif
  endfor
  return 0
endfunction

function! s:file_diff_on_tab_enter() abort
  let state = get(t:, 'git_changes_file_diff', {})
  if !empty(state)
    call s:file_diff_activate(state)
  endif
endfunction

function! s:file_diff_on_tab_leave() abort
  let state = get(t:, 'git_changes_file_diff', {})
  if !empty(state)
    call s:file_diff_deactivate(state)
  endif
endfunction

function! s:file_diff_on_tab_closed() abort
  if !empty(s:file_diff_active)
        \ && !s:file_diff_tab_exists(get(s:file_diff_active, 'tab', 0))
    call s:file_diff_deactivate(s:file_diff_active)
  endif
  for state in copy(s:file_diff_instances)
    if !s:file_diff_alive(state) && get(state, 'editable', 0)
      if bufexists(get(state, 'new_buf', -1))
        call setbufvar(state.new_buf, 'git_changes_file_diff', {})
        call setbufvar(state.new_buf, 'gc_kind', '')
        call setbufvar(state.new_buf, 'gc_side', '')
      endif
    endif
  endfor
  call filter(s:file_diff_instances, 's:file_diff_alive(v:val)')
endfunction

function! s:inline_cleanup(state) abort
  let file_win = get(a:state, 'new_win', 0)
  if s:win_exists(file_win)
    let saved = get(a:state, 'saved_opts', {})
    let cmd = 'setlocal noscrollbind nocursorbind'
    if !empty(saved)
      let cmd .= ' ' . (get(saved, 'wrap', 1) ? 'wrap' : 'nowrap')
      let cmd .= ' ' . (get(saved, 'number', 0) ? 'number' : 'nonumber')
      let cmd .= ' ' . (get(saved, 'relativenumber', 0)
            \ ? 'relativenumber' : 'norelativenumber')
      let cmd .= ' foldmethod=' . get(saved, 'foldmethod', 'manual')
      let cmd .= ' ' . (get(saved, 'foldenable', 1)
            \ ? 'foldenable' : 'nofoldenable')
      let cmd .= ' ' . (get(saved, 'cursorline', 0)
            \ ? 'cursorline' : 'nocursorline')
    endif
    call win_execute(file_win, cmd)
    call win_execute(file_win, 'silent! diffoff')
  endif

  if bufexists(get(a:state, 'new_buf', -1))
    call setbufvar(a:state.new_buf, 'git_changes_file_diff', {})
    call setbufvar(a:state.new_buf, 'gc_kind', '')
    call setbufvar(a:state.new_buf, 'gc_side', '')
  endif
endfunction

function! s:file_diff_on_buf_wipeout(buf) abort
  if !empty(s:file_diff_active)
        \ && (a:buf == get(s:file_diff_active, 'old_buf', -1)
        \     || a:buf == get(s:file_diff_active, 'new_buf', -1)
        \     || a:buf == get(s:file_diff_active, 'work_buf', -1))
    call s:file_diff_deactivate(s:file_diff_active)
  endif
  for state in copy(s:file_diff_instances)
    if get(state, 'inline', 0)
          \ && (a:buf == get(state, 'old_buf', -1)
          \     || a:buf == get(state, 'work_buf', -1))
      call s:inline_cleanup(state)
    endif
  endfor
  call filter(s:file_diff_instances, 's:file_diff_alive(v:val)')
endfunction

augroup git_changes_file_diff
  autocmd!
  execute 'autocmd TabEnter * call ' . s:sid . 'file_diff_on_tab_enter()'
  execute 'autocmd TabLeave * call ' . s:sid . 'file_diff_on_tab_leave()'
  execute 'autocmd TabClosed * call ' . s:sid . 'file_diff_on_tab_closed()'
  execute 'autocmd BufWipeout * call ' . s:sid
        \ . 'file_diff_on_buf_wipeout(str2nr(expand("<abuf>")))'
augroup END

function! s:diff_numstat_args(spec) abort
  let args = ['diff', '--numstat']
  if a:spec.ignore ==# 'iwhiteall'
    call add(args, '-w')
  elseif a:spec.ignore ==# 'iwhite'
    call add(args, '-b')
  endif

  if a:spec.new_kind ==# 'index'
    call add(args, '--cached')
  endif

  if a:spec.new_kind ==# 'ref'
    call add(args, a:spec.refs[0])
    call add(args, a:spec.refs[1])
  elseif !empty(a:spec.refs)
    call add(args, a:spec.refs[0])
  elseif a:spec.new_kind ==# 'index' && a:spec.has_head
    call add(args, 'HEAD')
  endif

  call add(args, '--')
  call add(args, ':(literal)' . a:spec.path)
  return args
endfunction

function! s:diff_path_is_untracked(root, spec) abort
  if s:git_run(a:root, 'ls-files --error-unmatch -- '
        \ . shellescape(':(literal)' . a:spec.path)).ok
    return 0
  endif
  for expr in [a:spec.old_expr, a:spec.new_expr]
    if !empty(expr)
          \ && s:git_run(a:root, 'cat-file -e ' . shellescape(expr)).ok
      return 0
    endif
  endfor
  return filereadable(a:root . '/' . a:spec.path)
endfunction

function! s:analyze_diff(root, spec) abort
  let result = {'binary': 0, 'clean': 0}

  if a:spec.new_kind ==# 'worktree'
        \ && s:worktree_file_is_binary(a:root, a:spec.path)
    let result.binary = 1
  endif

  let args = s:diff_numstat_args(a:spec)
  let out = s:git(a:root, join(map(args, 'shellescape(v:val)'), ' '))
  for line in out
    if line =~# '^-\t-\t'
      let result.binary = 1
    endif
  endfor

  if empty(out) && a:spec.has_head
        \ && !s:diff_path_is_untracked(a:root, a:spec)
    let result.clean = 1
  endif
  return result
endfunction

function! s:start_sxs_fetch(state) abort
  if !s:file_diff_alive(a:state)
    return
  endif

  let token = get(a:state, 'diff_req', 0) + 1
  let a:state.diff_req = token
  call s:job_stop(a:state, 'diff-old')
  call s:job_stop(a:state, 'diff-new')

  let spec = a:state.spec
  let analysis = s:analyze_diff(a:state.root, spec)
  if analysis.binary
    call s:show_side_message(a:state, ['(binary file - no side-by-side diff)'])
    return
  endif
  let a:state.clean = get(spec, 'conflict', 0) ? 0 : analysis.clean

  let ctx = {
        \ 'token': token,
        \ 'old': [],
        \ 'new': [],
        \ 'three_way': get(spec, 'conflict', 0),
        \ 'old_path': spec.path,
        \ 'new_path': spec.path,
        \ 'old_label': spec.old_label,
        \ 'new_label': spec.new_label,
        \ 'file': {'path': spec.path},
        \ 'entry': {},
        \ 'pending': 0,
        \ }
  if ctx.three_way
    let ctx.work_path = spec.path
    let ctx.work_label = spec.work_label
  endif
  if spec.new_kind ==# 'worktree'
    if get(a:state, 'editable', 0)
      let ctx.new = getbufline(a:state.new_buf, 1, '$')
    else
      let ctx.new = s:read_worktree(a:state.root, spec.path)
    endif
  endif

  let old_job = !empty(spec.old_expr)
  let new_job = spec.new_kind !=# 'worktree'
  let work_job = ctx.three_way && !empty(get(spec, 'work_expr', ''))
  let ctx.pending = (old_job ? 1 : 0) + (new_job ? 1 : 0)
        \ + (work_job ? 1 : 0)
  if ctx.pending == 0
    call s:apply_sxs_content(a:state, ctx)
    return
  endif

  if old_job
    call s:git_job(a:state, 'diff-old', 'diff_req', token,
          \ ['show', spec.old_expr],
          \ function('s:on_sxs_part', [a:state, ctx, 'old']))
  endif
  if new_job
    call s:git_job(a:state, 'diff-new', 'diff_req', token,
          \ ['show', spec.new_expr],
          \ function('s:on_sxs_part', [a:state, ctx, 'new']))
  endif
  if work_job
    call s:git_job(a:state, 'diff-new', 'diff_req', token,
          \ ['show', spec.work_expr],
          \ function('s:on_sxs_part', [a:state, ctx, 'work']))
  endif
endfunction

function! s:on_sxs_part(state, ctx, side, result) abort
  if get(a:state, 'diff_req', 0) != a:ctx.token
    return
  endif
  if !s:file_diff_alive(a:state)
    return
  endif

  let a:ctx[a:side] = a:result.out
  let a:ctx.pending -= 1
  if a:ctx.pending <= 0
    call s:apply_sxs_content(a:state, a:ctx)
  endif
endfunction

function! s:apply_sxs_content(state, ctx) abort
  if get(a:state, 'diff_req', 0) != a:ctx.token
    return
  endif
  if !s:file_diff_alive(a:state)
    return
  endif

  call s:apply_diff(a:state, a:ctx)
  if get(a:state, 'clean', 0)
    echomsg 'GitChangesDiff: No changes: ' . a:state.spec.path
  endif
endfunction

function! s:refresh_file_diff() abort
  let state = get(b:, 'git_changes_file_diff', {})
  if empty(state) || !s:file_diff_alive(state)
    return
  endif

  call s:start_sxs_fetch(state)
endfunction

function! s:stage_file_diff(mode) abort
  let state = get(b:, 'git_changes_file_diff', {})
  if empty(state) || !s:file_diff_alive(state)
    return
  endif

  let spec = state.spec
  if spec.new_kind ==# 'ref'
    call s:err('stage/unstage is not available when comparing two refs')
    return
  endif

  let path = spec.path
  let pathspec = shellescape(':(literal)' . path)

  if a:mode ==# 'stage'
    if !s:git_do(state.root, 'add -A -- ' . pathspec)
      return
    endif
    echomsg 'Staged: ' . path
  else
    let result = s:git_run(state.root,
          \ 'diff --cached --quiet -- ' . pathspec)
    if result.code != 1
      echomsg 'Not staged: ' . path
      return
    endif

    if spec.has_head
      let args = 'reset -q HEAD -- ' . pathspec
    else
      let args = 'rm -q --cached -- ' . pathspec
    endif
    if !s:git_do(state.root, args)
      return
    endif
    echomsg 'Unstaged: ' . path
  endif

  call s:refresh_file_diff()
endfunction

function! s:open_file_diff() abort
  let state = get(b:, 'git_changes_file_diff', {})
  if empty(state) || !s:file_diff_alive(state)
    return
  endif

  let path = state.root . '/' . state.spec.path
  if !filereadable(path)
    call s:err('file does not exist: ' . state.spec.path)
    return
  endif

  " The side buffers contain the full file, so the cursor line maps directly
  " to a line in the file.
  call s:show_file(path, line('.'))
endfunction

" Open the editable file diff for the selected file from a main diff pane.
function! s:open_file_diff_for_current() abort
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

  let file = state.files[index]
  let path = state.root . '/' . file.path
  if !filereadable(path)
    call s:err('file does not exist: ' . file.path)
    return
  endif

  call git_changes#diff_open('-- ' . shellescape(path))
endfunction

function! s:commit_file_diff() abort
  let state = get(b:, 'git_changes_file_diff', {})
  if empty(state) || !s:file_diff_alive(state)
    return
  endif

  if !s:commit_index(state.root)
    return
  endif
  call s:refresh_file_diff()
endfunction

function! s:commit_file_diff_editor() abort
  let state = get(b:, 'git_changes_file_diff', {})
  if empty(state) || !s:file_diff_alive(state)
    return
  endif

  call s:open_commit_editor(state.root,
        \ function('s:refresh_file_diff_state', [state]))
endfunction

function! s:refresh_file_diff_state(state) abort
  if s:file_diff_alive(a:state)
    call s:start_sxs_fetch(a:state)
  endif
endfunction

function! s:toggle_staged_file_diff() abort
  let state = get(b:, 'git_changes_file_diff', {})
  if empty(state) || !s:file_diff_alive(state)
    return
  endif

  let spec = state.spec
  if len(spec.refs) > 1
    call s:err('staged view is not available when comparing two refs')
    return
  endif

  let spec.cached = !spec.cached
  call s:build_diff_labels(spec)
  call s:refresh_file_diff()
endfunction

function! s:discard_file_diff() abort
  let state = get(b:, 'git_changes_file_diff', {})
  if empty(state) || !s:file_diff_alive(state)
    return
  endif

  let spec = state.spec
  if spec.new_kind ==# 'ref'
    call s:err('discard is not available when comparing two refs')
    return
  endif

  let path = spec.path
  let pathspec = shellescape(':(literal)' . path)
  let abs = state.root . '/' . path
  let tracked = s:git_run(state.root,
        \ 'ls-files --error-unmatch -- ' . pathspec).ok

  if !tracked
    if !filereadable(abs)
      echomsg 'No file to discard: ' . path
      return
    endif
    if get(g:, 'git_changes_confirm_discard', 1)
          \ && s:prompt_confirm('Delete untracked file ' . path . '?',
          \                     "&Yes\n&No", 2) != 1
      return
    endif
    if delete(abs) != 0
      call s:err('failed to delete: ' . path)
      return
    endif
    echomsg 'Deleted: ' . path
    call s:close_file_diff(state)
    return
  endif

  let unstaged = s:git_run(state.root, 'diff --quiet -- ' . pathspec)
  if unstaged.code == 0
    echomsg 'No unstaged changes: ' . path
    return
  endif

  if get(g:, 'git_changes_confirm_discard', 1)
        \ && s:prompt_confirm(
        \      'Discard unstaged changes for ' . path . '?',
        \      "&Yes\n&No", 2) != 1
    return
  endif

  if !s:git_do(state.root, 'checkout -- ' . pathspec)
    return
  endif
  if get(state, 'editable', 0) && s:win_exists(state.new_win)
    call win_execute(state.new_win, 'silent! edit!')
  endif
  echomsg 'Discarded unstaged changes: ' . path
  call s:refresh_file_diff()
endfunction

function! s:cycle_file_diff(delta) abort
  let state = get(b:, 'git_changes_file_diff', {})
  if empty(state)
    return
  endif
  let target = a:delta > 0 ? state.new_win : state.old_win
  if s:win_exists(target)
    call win_gotoid(target)
  endif
endfunction

function! s:file_diff_alive(state) abort
  let old_buf = get(a:state, 'old_buf', 0)
  let new_buf = get(a:state, 'new_buf', 0)
  return old_buf > 0 && bufexists(old_buf)
        \ && new_buf > 0 && bufexists(new_buf)
        \ && s:win_exists(get(a:state, 'old_win', 0))
        \ && s:win_exists(get(a:state, 'new_win', 0))
endfunction

" Find a live file diff view for {root}, so the command can reuse its tab.
function! s:find_file_diff_state(root) abort
  for state in reverse(copy(s:file_diff_instances))
    if s:file_diff_alive(state) && get(state, 'root', '') ==# a:root
      return state
    endif
  endfor
  return {}
endfunction

function! s:close_file_diff(state) abort
  if get(a:state, 'inline', 0)
    call s:file_diff_deactivate(a:state)
    call s:job_stop(a:state, 'diff-old')
    call s:job_stop(a:state, 'diff-new')

    call s:inline_cleanup(a:state)

    for winid in [get(a:state, 'work_win', 0), get(a:state, 'old_win', 0)]
      if s:win_exists(winid)
        if winid == win_getid()
          close
        else
          call win_execute(winid, 'silent! close')
        endif
      endif
    endfor
    for buf in [get(a:state, 'work_buf', -1), get(a:state, 'old_buf', -1)]
      if bufexists(buf)
        execute 'silent! bwipeout! ' . buf
      endif
    endfor

    call filter(s:file_diff_instances, 'v:val isnot a:state')
    silent! unlet! t:git_changes_file_diff
    return 0
  endif

  if get(a:state, 'editable', 0)
        \ && bufexists(get(a:state, 'new_buf', -1))
        \ && getbufvar(a:state.new_buf, '&modified')
    if s:prompt_confirm('GitChangesDiff: save changes before closing?',
          \ "&Save\n&Cancel", 1) != 1
      return -1
    endif
    let win = get(a:state, 'new_win', 0)
    if s:win_exists(win)
      call win_execute(win, 'silent! write')
    endif
    if getbufvar(a:state.new_buf, '&modified')
      call s:err('failed to save: ' . a:state.spec.path)
      return -1
    endif
  endif

  call s:file_diff_deactivate(a:state)
  call s:job_stop(a:state, 'diff-old')
  call s:job_stop(a:state, 'diff-new')

  let tabnr = 0
  for winid in [get(a:state, 'old_win', 0), get(a:state, 'new_win', 0)]
    if s:win_exists(winid)
      let tabwin = win_id2tabwin(winid)
      if !empty(tabwin) && tabwin[0] > 0
        let tabnr = tabwin[0]
        break
      endif
    endif
  endfor

  call filter(s:file_diff_instances, 'v:val isnot a:state')
  if tabnr > 0
    execute 'tabclose ' . tabnr
  endif

  if get(a:state, 'editable', 0)
        \ && bufexists(get(a:state, 'new_buf', -1))
    call setbufvar(a:state.new_buf, 'git_changes_file_diff', {})
    call setbufvar(a:state.new_buf, 'gc_kind', '')
    call setbufvar(a:state.new_buf, 'gc_side', '')
  endif
  return tabnr
endfunction

function! s:close_file_diff_tab() abort
  let state = get(b:, 'git_changes_file_diff', {})
  if !empty(state)
    call s:close_file_diff(state)
  else
    silent! tabclose
  endif
endfunction

function! git_changes#complete_diff(arglead, cmdline, cursorpos) abort
  let before = strpart(a:cmdline, 0, a:cursorpos)
  let tokens = split(before, '\s\+')
  if index(tokens, '--') >= 0
    return getcompletion(a:arglead, 'file')
  endif

  let result = []
  let seen = {}
  for flag in ['--staged', '--cached', '-w',
        \ '--ignore-all-space', '-b', '--ignore-space-change', '--']
    if stridx(flag, a:arglead) == 0 && !has_key(seen, flag)
      let seen[flag] = 1
      call add(result, flag)
    endif
  endfor

  for ref in git_changes#complete_refs(a:arglead, a:cmdline, a:cursorpos)
    if !has_key(seen, ref)
      let seen[ref] = 1
      call add(result, ref)
    endif
  endfor
  return result
endfunction


" ============================================================================
" GitChangesBlame
"
" A read-only pane on the left of the current file with one blame line per
" file line. Both windows scroll and move together; q closes the pane.
" ============================================================================

function! s:blame_lines(root, path, modified) abort
  let contents = ''
  if a:modified
    let contents = tempname()
    call writefile(getline(1, '$'), contents)
  endif

  try
    let cmd = 'git --no-pager -c core.quotePath=false -c color.ui=false -C '
          \ . shellescape(a:root) . ' blame'
    if !empty(contents)
      let cmd .= ' --contents ' . shellescape(contents)
    endif
    let cmd .= ' -- ' . shellescape(a:path)
    let out = systemlist(cmd)
    if v:shell_error
      call s:err('git blame failed: ' . s:output_message(out))
      return []
    endif
    return out
  finally
    if !empty(contents)
      call delete(contents)
    endif
  endtry
endfunction

function! s:blame_cleanup() abort
  let info = get(b:, 'git_changes_blame', {})
  if empty(info)
    return
  endif

  let file_win = get(info, 'file_win', 0)
  if s:win_exists(file_win)
    call win_execute(file_win,
          \ 'setlocal noscrollbind nocursorbind '
          \ . (get(info, 'file_wrap', 1) ? 'wrap' : 'nowrap'))
  endif

  let file_buf = get(info, 'file_buf', -1)
  if bufexists(file_buf)
    call setbufvar(file_buf, 'git_changes_blame', {})
  endif
  silent! unlet! b:git_changes_blame
endfunction

function! s:blame_close() abort
  let info = get(b:, 'git_changes_blame', {})
  if empty(info)
    return
  endif
  call s:blame_cleanup()

  let win = get(info, 'win', 0)
  if s:win_exists(win)
    if win == win_getid()
      close
    else
      call win_execute(win, 'close')
    endif
  endif

  let buf = get(info, 'buf', -1)
  if bufexists(buf)
    execute 'silent! bwipeout! ' . buf
  endif
endfunction

function! git_changes#blame() abort
  let root = s:repo_root()
  if empty(root)
    call s:err('not inside a Git repository')
    return
  endif
  if &buftype !=# ''
    call s:err('GitChangesBlame: open a file first')
    return
  endif

  let path = s:current_repo_path(root)
  if empty(path)
    call s:err('GitChangesBlame: the current file is not in this repository')
    return
  endif
  if !filereadable(root . '/' . path)
    call s:err('GitChangesBlame: file does not exist: ' . path)
    return
  endif

  " Re-running the command replaces the existing blame pane.
  if !empty(get(b:, 'git_changes_blame', {}))
    call s:blame_close()
  endif

  let file_win = win_getid()
  let file_buf = bufnr('%')
  let cur_line = line('.')
  let view = winsaveview()
  let modified = &modified
  let file_wrap = &wrap

  let blame_lines = s:blame_lines(root, path, modified)
  if v:shell_error
    return
  endif

  " Keep the pane aligned even for empty files.
  let target = line('$')
  while len(blame_lines) < target
    call add(blame_lines, '')
  endwhile
  if len(blame_lines) > target
    call remove(blame_lines, target, -1)
  endif

  leftabove vertical split
  let blame_win = win_getid()
  let blame_buf = s:new_scratch(
        \ printf('[GitChangesBlame %d] %s', file_buf, path), '')
  call s:set_lines(blame_buf, blame_lines)

  setlocal scrollbind cursorbind
  setlocal nonumber norelativenumber nolist nowrap
  setlocal signcolumn=no foldcolumn=0 nospell nomodeline
  setlocal nomodifiable
  let configured = get(g:, 'git_changes_blame_width', 40)
  if type(configured) != type(0) || configured <= 0
    let configured = 40
  endif
  execute 'vertical resize ' . max([12, configured])
  execute 'nnoremap <buffer> <silent> q '
        \ . s:cmd_rhs(':<C-u>call ' . s:sid . 'blame_close()<CR>')

  let info = {
        \ 'win': blame_win,
        \ 'buf': blame_buf,
        \ 'file_win': file_win,
        \ 'file_buf': file_buf,
        \ 'file_wrap': file_wrap,
        \ 'root': root,
        \ 'path': path,
        \ }
  let b:git_changes_blame = info
  call setbufvar(file_buf, 'git_changes_blame', info)

  augroup git_changes_blame
    autocmd! * <buffer>
    execute 'autocmd BufWipeout <buffer> call '
          \ . s:sid . 'blame_cleanup()'
  augroup END

  call win_execute(file_win, 'setlocal scrollbind cursorbind nowrap')
  call s:set_cursor(blame_win, cur_line)
  call win_gotoid(file_win)
  call winrestview(view)
  call win_gotoid(blame_win)
endfunction

