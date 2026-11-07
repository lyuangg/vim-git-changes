" GitChangesDiff: focused two-window file diffs.
"
" The browser and this module share a few helpers through git_changes#core_*.
" Keeping the diff view here makes the browser autoload file smaller and lets
" the feature load only when :GitChangesDiff or gd is used.

let s:sid = expand('<SID>')

function! s:map_action(action, func, ...) abort
  let args = join(a:000, ', ')
  call git_changes#core_map_keys(a:action,
        \ ':<C-u>call ' . s:sid . a:func . '(' . args . ')<CR>')
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

function! git_changes#file_diff#open(raw) abort
  call s:diff_open(a:raw, {'cmd': 'GitChangesDiff'})
endfunction

function! s:diff_usage(defaults) abort
  call git_changes#core_err('usage: :' . get(a:defaults, 'cmd', 'GitChangesDiff')
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
    call git_changes#core_err('current buffer is not a file; specify a path after --')
    return {}
  endif

  if empty(paths)
    " a:current is already relative to the repository root. Resolving it again
    " would use the working directory, which may be a different repository.
    let path = a:current
  else
    let path = git_changes#core_repo_relative_path(a:root, raw_path)
    " A relative explicit path is normally relative to the working directory.
    " Fall back to the repository root when cwd points at another repository.
    if empty(path) && raw_path !~# '^/'
          \ && !empty(getftype(a:root . '/' . raw_path))
      let path = raw_path
    endif
  endif
  if empty(path)
    call git_changes#core_err('path is outside the repository: ' . raw_path)
    return {}
  endif
  if isdirectory(a:root . '/' . path)
    call git_changes#core_err('path is a directory: ' . path)
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
    let sha = git_changes#core_resolve_ref(a:root, rev)
    if empty(sha)
      call git_changes#core_err('unknown revision: ' . rev)
      return {}
    endif
    call add(refs, sha)
  endfor

  let spec = {
        \ 'path': path,
        \ 'revisions': revisions,
        \ 'refs': refs,
        \ 'has_head': !empty(git_changes#core_resolve_ref(a:root, 'HEAD')),
        \ 'cached': cached,
        \ 'ignore': ignore,
        \ }
  let spec.conflict = !cached && empty(refs)
        \ && s:path_is_conflict(a:root, path)
  call s:build_diff_labels(spec)
  return spec
endfunction

function! s:path_is_conflict(root, path) abort
  return !empty(git_changes#core_git(a:root, ['ls-files', '-u', '--', a:path]))
endfunction

function! s:diff_path_known(root, spec) abort
  if filereadable(a:root . '/' . a:spec.path)
    return 1
  endif
  if git_changes#core_git_run(a:root, ['ls-files', '--error-unmatch', '--',
        \ ':(literal)' . a:spec.path]).ok
    return 1
  endif
  for expr in [a:spec.old_expr, a:spec.new_expr]
    if !empty(expr)
          \ && git_changes#core_git_run(a:root, ['cat-file', '-e', expr]).ok
      return 1
    endif
  endfor
  " A file that only exists in HEAD has no unstaged diff, but the path is
  " still valid: open an empty index-vs-worktree view instead of erroring.
  if a:spec.has_head
        \ && git_changes#core_git_run(a:root,
        \      ['cat-file', '-e', 'HEAD:' . a:spec.path]).ok
    return 1
  endif
  return 0
endfunction


function! s:maybe_save_current(root, spec, current) abort
  if empty(a:current) || a:spec.path !=# a:current
    return 1
  endif
  if !&modified || &buftype !=# ''
    return 1
  endif

  let choice = git_changes#core_prompt_confirm(
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
    call git_changes#core_err('failed to save: ' . v:exception)
    return 0
  endtry
  if &modified
    call git_changes#core_err('failed to save the file')
    return 0
  endif
  return 1
endfunction

function! s:diff_open(raw, defaults) abort
  let root = git_changes#core_repo_root()
  if empty(root)
    call git_changes#core_err('not inside a Git repository')
    return
  endif

  let current = git_changes#core_current_repo_path(root)
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
    call git_changes#core_err('path not found: ' . spec.path)
    return
  endif

  let inline = save_state != 2 && spec.new_kind ==# 'worktree'
        \ && !empty(current) && current ==# spec.path && &buftype ==# ''
        \ && !git_changes#core_worktree_file_is_binary(root, spec.path)

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
  let state.old_buf = git_changes#core_new_scratch(
        \ printf('[GitChangesDiff %d] %s', id, a:spec.old_label), '')
  call s:init_file_diff_buffer(state, 'old')

  if inline
    let state.new_win = file_win
    let state.new_buf = file_buf
    let state.editable = editable && a:spec.new_kind ==# 'worktree'
          \ && !git_changes#core_worktree_file_is_binary(a:root, a:spec.path)
    call win_gotoid(file_win)
    call s:init_file_diff_buffer(state, 'new')
  else
    rightbelow vsplit
    let state.new_win = win_getid()
    if editable && a:spec.new_kind ==# 'worktree'
          \ && !git_changes#core_worktree_file_is_binary(a:root, a:spec.path)
      execute 'edit ' . fnameescape(a:root . '/' . a:spec.path)
      let state.new_buf = bufnr('%')
      let state.editable = 1
    else
      let state.new_buf = git_changes#core_new_scratch(
            \ printf('[GitChangesDiff %d] %s', id, a:spec.new_label), '')
    endif
    call s:init_file_diff_buffer(state, 'new')
  endif

  if get(a:spec, 'conflict', 0)
    call win_gotoid(state.new_win)
    rightbelow vsplit
    let state.work_win = win_getid()
    let state.work_buf = git_changes#core_new_scratch(
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

  if git_changes#core_win_exists(state.work_win)
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

  call git_changes#core_diff_on(state)
  call s:file_diff_activate(state)
  call s:start_sxs_fetch(state)

  for winid in git_changes#core_diff_windows(state)
    if winid == state.new_win && state.editable
      continue
    endif
    call git_changes#core_set_cursor(winid, 1)
    call git_changes#core_scroll_top(winid)
  endfor
  call win_gotoid(state.new_win)
endfunction

function! s:init_file_diff_buffer(state, side) abort
  let b:git_changes_file_diff = a:state
  let b:gc_kind = 'filediff'
  let b:gc_side = a:side
  call git_changes#core_setup_diff_window()

  " q is safe in every side. The remaining actions are only mapped in
  " read-only sides: the editable side must keep s/u/d/o/cc available for
  " normal editing.
  call s:map_action('quit', 'close_file_diff_tab')
  if !(a:side ==# 'new' && get(a:state, 'editable', 0))
    call s:map_action('refresh', 'refresh_file_diff')
    call s:map_action('stage', 'stage_file_diff', '"stage"')
    call s:map_action('unstage', 'stage_file_diff', '"unstage"')
    call s:map_action('toggle_stage', 'stage_file_diff', '"toggle"')
    call s:map_action('file_discard_diff', 'discard_file_diff')
    call s:map_action('staged_view', 'toggle_staged_file_diff')
    call s:map_action('commit', 'commit_file_diff')
    call s:map_action('commit_editor', 'commit_file_diff_editor')
    call s:map_action('open_file', 'open_file_diff')
    call s:map_action('cycle_next', 'cycle_file_diff', 1)
    call s:map_action('cycle_prev', 'cycle_file_diff', -1)
  endif

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
  let winid = git_changes#core_win_exists(get(a:state, 'old_win', 0))
        \ ? a:state.old_win : get(a:state, 'new_win', 0)
  if git_changes#core_win_exists(winid)
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
  if git_changes#core_win_exists(file_win)
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
  if git_changes#core_git_run(a:root, ['ls-files', '--error-unmatch', '--',
        \ ':(literal)' . a:spec.path]).ok
    return 0
  endif
  for expr in [a:spec.old_expr, a:spec.new_expr]
    if !empty(expr)
          \ && git_changes#core_git_run(a:root, ['cat-file', '-e', expr]).ok
      return 0
    endif
  endfor
  return filereadable(a:root . '/' . a:spec.path)
endfunction

function! s:analyze_diff(root, spec) abort
  let result = {'binary': 0, 'clean': 0}

  if a:spec.new_kind ==# 'worktree'
        \ && git_changes#core_worktree_file_is_binary(a:root, a:spec.path)
    let result.binary = 1
  endif

  let out = git_changes#core_git(a:root, s:diff_numstat_args(a:spec))
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
  call git_changes#core_job_stop(a:state, 'diff-old')
  call git_changes#core_job_stop(a:state, 'diff-new')

  let spec = a:state.spec
  let analysis = s:analyze_diff(a:state.root, spec)
  if analysis.binary
    call git_changes#core_show_side_message(a:state, ['(binary file - no side-by-side diff)'])
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
      let ctx.new = git_changes#core_read_worktree(a:state.root, spec.path)
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
    call git_changes#core_git_job(a:state, 'diff-old', 'diff_req', token,
          \ ['show', spec.old_expr],
          \ function('s:on_sxs_part', [a:state, ctx, 'old']))
  endif
  if new_job
    call git_changes#core_git_job(a:state, 'diff-new', 'diff_req', token,
          \ ['show', spec.new_expr],
          \ function('s:on_sxs_part', [a:state, ctx, 'new']))
  endif
  if work_job
    call git_changes#core_git_job(a:state, 'diff-new', 'diff_req', token,
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

  call git_changes#core_apply_diff(a:state, a:ctx)
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
    call git_changes#core_err('stage/unstage is not available when comparing two refs')
    return
  endif

  let path = spec.path
  let literal = ':(literal)' . path

  let mode = a:mode
  if mode ==# 'toggle'
    let staged = git_changes#core_git_run(state.root,
          \ ['diff', '--cached', '--quiet', '--', literal])
    let mode = staged.code == 1 ? 'unstage' : 'stage'
  endif

  if mode ==# 'stage'
    if !git_changes#core_git_do(state.root, ['add', '-A', '--', literal])
      return
    endif
    echomsg 'Staged: ' . path
  else
    let result = git_changes#core_git_run(state.root,
          \ ['diff', '--cached', '--quiet', '--', literal])
    if result.code != 1
      echomsg 'Not staged: ' . path
      return
    endif

    if spec.has_head
      let args = ['reset', '-q', 'HEAD', '--', literal]
    else
      let args = ['rm', '-q', '--cached', '--', literal]
    endif
    if !git_changes#core_git_do(state.root, args)
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
    call git_changes#core_err('file does not exist: ' . state.spec.path)
    return
  endif

  " The side buffers contain the full file, so the cursor line maps directly
  " to a line in the file.
  call git_changes#core_show_file(path, line('.'))
endfunction

" Open the editable file diff for the selected file from a main diff pane.
function! s:open_file_diff_for_current() abort
  let state = git_changes#core_cur_state()
  if empty(state) || empty(state.commits) || state.commit_index < 0
    return
  endif
  call git_changes#core_flush_pending(state)

  let index = git_changes#core_current_file_index(state)
  if index < 0 || index >= len(state.files)
    call git_changes#core_err('select a file first')
    return
  endif

  let file = state.files[index]
  let path = state.root . '/' . file.path
  if !filereadable(path)
    call git_changes#core_err('file does not exist: ' . file.path)
    return
  endif

  call git_changes#diff_open('-- ' . shellescape(path))
endfunction

function! s:commit_file_diff() abort
  let state = get(b:, 'git_changes_file_diff', {})
  if empty(state) || !s:file_diff_alive(state)
    return
  endif

  if !git_changes#core_commit_index(state.root)
    return
  endif
  call s:refresh_file_diff()
endfunction

function! s:commit_file_diff_editor() abort
  let state = get(b:, 'git_changes_file_diff', {})
  if empty(state) || !s:file_diff_alive(state)
    return
  endif

  call git_changes#core_open_commit_editor(state.root,
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
    call git_changes#core_err('staged view is not available when comparing two refs')
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
    call git_changes#core_err('discard is not available when comparing two refs')
    return
  endif

  let path = spec.path
  let literal = ':(literal)' . path
  let abs = state.root . '/' . path
  let tracked = git_changes#core_git_run(state.root,
        \ ['ls-files', '--error-unmatch', '--', literal]).ok

  if !tracked
    if !filereadable(abs)
      echomsg 'No file to discard: ' . path
      return
    endif
    if get(g:, 'git_changes_confirm_discard', 1)
          \ && git_changes#core_prompt_confirm('Delete untracked file ' . path . '?',
          \                     "&Yes\n&No", 2) != 1
      return
    endif
    if delete(abs) != 0
      call git_changes#core_err('failed to delete: ' . path)
      return
    endif
    echomsg 'Deleted: ' . path
    call s:close_file_diff(state)
    return
  endif

  let unstaged = git_changes#core_git_run(state.root,
        \ ['diff', '--quiet', '--', literal])
  if unstaged.code == 0
    echomsg 'No unstaged changes: ' . path
    return
  endif

  if get(g:, 'git_changes_confirm_discard', 1)
        \ && git_changes#core_prompt_confirm(
        \      'Discard unstaged changes for ' . path . '?',
        \      "&Yes\n&No", 2) != 1
    return
  endif

  if !git_changes#core_git_do(state.root, ['checkout', '--', literal])
    return
  endif
  if get(state, 'editable', 0) && git_changes#core_win_exists(state.new_win)
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
  if git_changes#core_win_exists(target)
    call win_gotoid(target)
  endif
endfunction

function! s:file_diff_alive(state) abort
  let old_buf = get(a:state, 'old_buf', 0)
  let new_buf = get(a:state, 'new_buf', 0)
  return old_buf > 0 && bufexists(old_buf)
        \ && new_buf > 0 && bufexists(new_buf)
        \ && git_changes#core_win_exists(get(a:state, 'old_win', 0))
        \ && git_changes#core_win_exists(get(a:state, 'new_win', 0))
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
    call git_changes#core_job_stop(a:state, 'diff-old')
    call git_changes#core_job_stop(a:state, 'diff-new')

    call s:inline_cleanup(a:state)

    for winid in [get(a:state, 'work_win', 0), get(a:state, 'old_win', 0)]
      if git_changes#core_win_exists(winid)
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
    if git_changes#core_prompt_confirm('GitChangesDiff: save changes before closing?',
          \ "&Save\n&Cancel", 1) != 1
      return -1
    endif
    let win = get(a:state, 'new_win', 0)
    if git_changes#core_win_exists(win)
      call win_execute(win, 'silent! write')
    endif
    if getbufvar(a:state.new_buf, '&modified')
      call git_changes#core_err('failed to save: ' . a:state.spec.path)
      return -1
    endif
  endif

  call s:file_diff_deactivate(a:state)
  call git_changes#core_job_stop(a:state, 'diff-old')
  call git_changes#core_job_stop(a:state, 'diff-new')

  let tabnr = 0
  for winid in [get(a:state, 'old_win', 0), get(a:state, 'new_win', 0)]
    if git_changes#core_win_exists(winid)
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


function! git_changes#file_diff#quit() abort
  let state = get(b:, 'git_changes_file_diff', {})
  if empty(state)
    let state = get(t:, 'git_changes_file_diff', {})
  endif
  if empty(state) || !s:file_diff_alive(state)
    call git_changes#core_err('no GitChangesDiff window found')
    return
  endif
  call s:close_file_diff(state)
endfunction

function! s:apply_file_diff_layout(state) abort
  if !s:file_diff_alive(a:state)
    return
  endif
  let total = winwidth(a:state.old_win) + winwidth(a:state.new_win) + 1
  let half = max([20, total / 2])
  call win_execute(a:state.old_win, 'silent! vertical resize ' . half)
endfunction

function! s:on_resized() abort
  for state in copy(s:file_diff_instances)
    if s:file_diff_alive(state)
      call s:apply_file_diff_layout(state)
    endif
  endfor
endfunction

augroup git_changes_file_diff_resize
  autocmd!
  autocmd VimResized * call s:on_resized()
augroup END
