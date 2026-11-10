
let s:sid = expand('<SID>')
let s:instances = []


function! s:err(msg) abort
  echohl ErrorMsg
  echomsg 'GitChanges: ' . a:msg
  echohl None
endfunction

" Statusline groups are created from the colorscheme (or user overrides) the
" first time a pane statusline is drawn, and rebuilt if the configuration
" changes at runtime.
function! s:init_statusline_highlights() abort
  call s:init_pane_bar_highlights()
endfunction

" True when a color reads as a light background. Uses the GUI hex value when
" available, otherwise approximates the 256-color palette, and falls back to
" 'background'.
function! s:color_is_light(guicolor, ctermcolor) abort
  let hex = tolower(a:guicolor)
  if hex =~# '^#\x\{6}$'
    let r = str2nr(strpart(hex, 1, 2), 16)
    let g = str2nr(strpart(hex, 3, 2), 16)
    let b = str2nr(strpart(hex, 5, 2), 16)
    return 299 * r + 587 * g + 114 * b > 120000
  endif

  if a:ctermcolor =~# '^\d\+$'
    return s:cterm_color_is_light(str2nr(a:ctermcolor))
  endif

  if a:guicolor =~? 'white\|grey\|gray\|light\|yellow\|cyan'
    return 1
  endif
  return &background ==# 'light'
endfunction

function! s:cterm_color_is_light(index) abort
  if a:index < 16
    " Approximate RGB values for the 16 ANSI colors.
    let palette = [
          \ [0, 0, 0], [128, 0, 0], [0, 128, 0], [128, 128, 0],
          \ [0, 0, 128], [128, 0, 128], [0, 128, 128], [192, 192, 192],
          \ [128, 128, 128], [255, 0, 0], [0, 255, 0], [255, 255, 0],
          \ [0, 0, 255], [255, 0, 255], [0, 255, 255], [255, 255, 255],
          \ ]
    let [r, g, b] = palette[a:index]
    return 299 * r + 587 * g + 114 * b > 120000
  elseif a:index < 232
    let cube = [0, 95, 135, 175, 215, 255]
    let i = a:index - 16
    let r = cube[(i / 36) % 6]
    let g = cube[(i / 6) % 6]
    let b = cube[i % 6]
    return 299 * r + 587 * g + 114 * b > 120000
  endif
  " 232-255 is the grayscale ramp, from near-black to near-white.
  return 8 + (a:index - 232) * 10 > 120
endfunction

" Accept a color as {'cterm': ..., 'gui': ...}, a Number, or a String. Plain
" numbers only apply to cterm and hex strings only apply to the GUI; anything
" else is used in both.
function! s:color_pair(value, default) abort
  if type(a:value) == type({})
    let cterm = get(a:value, 'cterm', a:default[0])
    let gui = get(a:value, 'gui', a:default[1])
    return [empty(cterm) ? a:default[0] : cterm,
          \ empty(gui) ? a:default[1] : gui]
  elseif type(a:value) == type(0)
    return [string(a:value), a:default[1]]
  elseif type(a:value) == type('') && !empty(a:value)
    if a:value =~# '^\d\+$'
      return [a:value, a:default[1]]
    elseif a:value =~? '^#\x\{6}$'
      return [a:default[0], a:value]
    endif
    return [a:value, a:value]
  endif
  return a:default
endfunction

" All GitChanges panes share one colored statusline bar. The default is a
" dark slate background with light text; g:git_changes_statusline_colors can
" override any of the colors. Using the same bar everywhere keeps the layout
" visually coherent.
function! s:init_pane_bar_highlights() abort
  let user = get(g:, 'git_changes_statusline_colors', {})
  if type(user) != type({})
    let user = {}
  endif

  " Rebuild when the configuration changes, so colors can be adjusted at
  " runtime without restarting Vim.
  let signature = string(user)
  if hlexists('GitChangesPaneBar') && get(s:, 'pane_bar_sig', '') ==# signature
    return
  endif
  let s:pane_bar_sig = signature

  " Default: dark slate bar with light text.
  let attrs = {'fg#': '#d8dee9', 'fg': '253',
        \ 'bg#': '#2b3a4a', 'bg': '236'}

  if has_key(user, 'bg')
    let pair = s:color_pair(user.bg, [attrs.bg, attrs['bg#']])
    let attrs.bg = pair[0]
    let attrs['bg#'] = pair[1]
    " With a custom background keep the detail text readable unless the user
    " also chose a foreground.
    if !has_key(user, 'fg')
      if s:color_is_light(attrs['bg#'], attrs.bg)
        let attrs.fg = '234'
        let attrs['fg#'] = '#1c1c1c'
      else
        let attrs.fg = '253'
        let attrs['fg#'] = '#e5e9f0'
      endif
    endif
  endif
  if has_key(user, 'fg')
    let pair = s:color_pair(user.fg, [attrs.fg, attrs['fg#']])
    let attrs.fg = pair[0]
    let attrs['fg#'] = pair[1]
  endif

  " The leading text (pane number/name and diff labels) uses a high-contrast
  " accent foreground; the detail text keeps the plain bar foreground. Pick a
  " dark accent on a light bar and a light accent on a dark bar, so the label
  " stays readable regardless of the colorscheme.
  if s:color_is_light(attrs['bg#'], attrs.bg)
    let accent = {'fg#': '#003a7a', 'fg': '18'}
  else
    let accent = {'fg#': '#ffd75f', 'fg': '221'}
  endif
  if has_key(user, 'accent')
    let pair = s:color_pair(user.accent, [accent.fg, accent['fg#']])
    let accent.fg = pair[0]
    let accent['fg#'] = pair[1]
  endif

  let colors = printf('ctermfg=%s ctermbg=%s guifg=%s guibg=%s',
        \ attrs.fg, attrs.bg, attrs['fg#'], attrs['bg#'])
  let accent_colors = printf('ctermfg=%s ctermbg=%s guifg=%s guibg=%s',
        \ accent.fg, attrs.bg, accent['fg#'], attrs['bg#'])
  execute 'highlight GitChangesPaneBar ' . colors
  execute 'highlight GitChangesPaneBarIndex ' . accent_colors
        \ . ' cterm=bold gui=bold'
  execute 'highlight GitChangesPaneBarName ' . accent_colors
        \ . ' cterm=bold gui=bold'
  execute 'highlight GitChangesPaneBarInfo ' . colors
  execute 'highlight GitChangesPaneBarLabel ' . accent_colors
        \ . ' cterm=bold gui=bold'
  execute 'highlight GitChangesPaneBarPath ' . colors
  execute 'highlight GitChangesPaneBarFill ' . colors
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
      let counts = get(a:state, 'worktree_counts', [])
      if empty(counts)
        let counts = s:worktree_summary(a:state.files)
      endif
      let [staged, unstaged, untracked] = counts
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

    let text = printf('%%#GitChangesPaneBarIndex#%s%%#GitChangesPaneBarName# %s',
          \ number, s:pane_label(kind))
    let detail = s:pane_state_text(a:state, kind)
    if !empty(detail)
      let text .= printf('%%#GitChangesPaneBarInfo# %%<· %s',
            \ substitute(detail, '%', '%%', 'g'))
    endif
    let text .= '%#GitChangesPaneBarFill#'
    if getwinvar(winid, '&statusline') !=# text
      call win_execute(winid, 'let &l:statusline = ' . string(text))
    endif
  endfor
endfunction

" Current branch name and its ahead/behind/gone markers, for statuslines.
function! s:current_branch_summary(state) abort
  let branch = ''
  let sync = ''
  for ref in get(a:state, 'refs', [])
    if get(ref, 'current', 0)
      let branch = ref.name
      let sync = s:branch_sync_text(ref)
      break
    endif
  endfor
  if empty(branch)
    let branch = s:current_branch(a:state.root)
  endif
  return [branch, sync]
endfunction

" The status pane's own statusline: repository directory, current branch and
" its sync state. Drawn without a background color, like the other panes.
function! s:status_window_statusline(state) abort
  if !get(g:, 'git_changes_statusline', 1)
    return
  endif
  call s:init_statusline_highlights()

  let [branch, sync] = s:current_branch_summary(a:state)
  let detail = fnamemodify(a:state.root, ':~') . '  ' . branch . sync
  let text = '%#GitChangesPaneBarIndex#0%#GitChangesPaneBarName# Status'
        \ . printf('%%#GitChangesPaneBarInfo# %%<· %s',
        \          substitute(detail, '%', '%%', 'g'))
        \ . '%#GitChangesPaneBarFill#'

  let winid = get(a:state, 'status_win', 0)
  if s:win_exists(winid) && getwinvar(winid, '&statusline') !=# text
    call win_execute(winid, 'let &l:statusline = ' . string(text))
  endif
endfunction

" Detailed lines for a commit, the working tree, or a compare range.
function! s:commit_detail_lines(state, entry) abort
  let entry = a:entry
  let lines = []
  let files_loaded = get(a:state, 'files_entry', '') ==# s:entry_key(entry)

  if entry.kind ==# 'worktree'
    call add(lines, '# WORK  Working tree changes')
    let [branch, sync] = s:current_branch_summary(a:state)
    call add(lines, '# Branch: ' . branch . sync)
    if files_loaded
      let counts = get(a:state, 'worktree_counts', [])
      if empty(counts)
        let counts = s:worktree_summary(a:state.files)
      endif
      call add(lines, s:worktree_status_line(counts))
      call add(lines, '# Changed files: ' . len(a:state.files))
    else
      call add(lines, '# Loading working tree changes...')
    endif
    for candidate in get(a:state, 'commits', [])
      if get(candidate, 'kind', '') ==# 'commit'
        call add(lines, '# HEAD: ' . candidate.short . ' '
              \ . candidate.subject)
        break
      endif
    endfor
  elseif entry.kind ==# 'compare'
    call add(lines, '# CMP  ' . entry.old_label . ' ↔ ' . entry.new_label)
    call add(lines, '# Base: ' . entry.old_ref)
    call add(lines, '# Head: ' . entry.new_ref)
    if files_loaded
      call add(lines, '# Changed files: ' . len(a:state.files))
    else
      call add(lines, '# Loading changed files...')
    endif
  else
    call add(lines, '# commit ' . entry.sha)
    let author = entry.author
    if !empty(get(entry, 'email', ''))
      let author .= ' <' . entry.email . '>'
    endif
    call add(lines, '# Author: ' . author)
    call add(lines, '# Date:   ' . entry.date)
    call add(lines, '# Subject: ' . entry.subject)
    if get(entry, 'unpushed', 0)
      call add(lines, '# Status: not pushed to any remote')
    endif
    if files_loaded
      call add(lines, '# Files:  ' . len(a:state.files) . ' changed')
    endif
    for body_line in s:commit_body_lines(a:state, entry)
      call add(lines, '# ' . body_line)
    endfor
  endif

  return lines
endfunction

" Detailed lines for the branch selected in the branch pane. Remote branches
" and tags have no upstream/worktree, so they only show what applies.
function! s:branch_detail_lines(state) abort
  let ref = s:selected_branch(a:state)
  if empty(ref)
    return ['# No branch selected']
  endif

  let kind = get(ref, 'kind', 'local')
  let lines = []
  if kind ==# 'remote'
    call add(lines, '# Remote branch: ' . ref.name)
    call add(lines, '# Remote: ' . matchstr(ref.name, '^[^/]\+'))
  elseif kind ==# 'tag'
    call add(lines, '# Tag: ' . ref.name)
  else
    call add(lines, '# Branch: ' . ref.name)
    call add(lines, '# Status: '
          \ . (get(ref, 'current', 0) ? 'current branch' : 'not checked out'))
    let upstream = get(ref, 'upstream', '')
    if empty(upstream)
      call add(lines, '# Upstream: (none)')
    else
      call add(lines, '# Upstream: ' . upstream . s:branch_sync_text(ref))
    endif
    if get(ref, 'gone', 0)
      call add(lines, '# Note:   upstream branch is gone')
    endif
    let path = get(get(a:state, 'branch_worktrees', {}), ref.name, '')
    if !empty(path)
      call add(lines, '# Worktree: ' . fnamemodify(path, ':~'))
    endif
  endif

  let tip = get(get(a:state, 'branch_tips', {}), get(ref, 'refname', ''), {})
  if !empty(tip)
    call add(lines, '# Tip:    ' . tip.short . ' ' . tip.subject)
  endif
  return lines
endfunction

function! s:status_detail_lines(state) abort
  if get(a:state, 'detail_mode', 'commit') ==# 'branch'
    return s:branch_detail_lines(a:state)
  endif

  let index = get(a:state, 'commit_index', -1)
  if index < 0 || index >= len(get(a:state, 'commits', []))
    return ['# ' . get(a:state, 'list_title', ''), '# No commit selected']
  endif
  return s:commit_detail_lines(a:state, a:state.commits[index])
endfunction

" Fetch the tip commit of the selected branch once and cache it, so moving
" through the branch list stays responsive.
function! s:ensure_branch_tip(state) abort
  let ref = s:selected_branch(a:state)
  if empty(ref)
    return
  endif

  let refname = get(ref, 'refname', '')
  if empty(refname)
        \ || has_key(get(a:state, 'branch_tips', {}), refname)
        \ || get(a:state, 'branch_tip_pending', '') ==# refname
    return
  endif

  let a:state.branch_tip_pending = refname
  let token = get(a:state, 'branch_tip_req', 0) + 1
  let a:state.branch_tip_req = token
  call s:git_job(a:state, 'branch-tip', 'branch_tip_req', token,
        \ ['log', '-1', '--format=%h%x1f%s', refname],
        \ function('s:apply_branch_tip', [a:state, refname, token]))
endfunction

function! s:apply_branch_tip(state, refname, token, result) abort
  if a:token != get(a:state, 'branch_tip_req', 0)
    return
  endif

  let a:state.branch_tip_pending = ''
  let parts = split(get(a:result.out, 0, ''), nr2char(31))
  if len(parts) >= 2
    let a:state.branch_tips[a:refname] =
          \ {'short': parts[0], 'subject': parts[1]}
  else
    " Cache failures too, so a bad ref is not retried on every redraw.
    let a:state.branch_tips[a:refname] = {}
  endif
  call s:update_status_window(a:state)
endfunction

" Redraw the status pane from the current selection.
function! s:update_status_window(state) abort
  let buf = get(a:state, 'status_buf', -1)
  let winid = get(a:state, 'status_win', 0)
  if !bufexists(buf) || !s:win_exists(winid)
    return
  endif

  if get(a:state, 'detail_mode', 'commit') ==# 'branch'
    call s:ensure_branch_tip(a:state)
  endif

  let changed = s:set_lines(buf, s:status_detail_lines(a:state))
  if changed && win_getid() != winid
    call s:set_cursor(winid, 1)
  endif
  call s:status_window_statusline(a:state)
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
    redraw
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
        \ ['for-each-ref', '--format=%(refname:short)',
        \  'refs/heads', 'refs/tags', 'refs/remotes']))

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

function! git_changes#complete_branches(arglead, cmdline, cursorpos) abort
  let root = s:repo_root()
  if empty(root)
    return []
  endif

  return filter(s:git(root,
        \ ['for-each-ref', '--format=%(refname:short)', 'refs/heads']),
        \ 'stridx(v:val, a:arglead) == 0')
endfunction

function! s:truncate(text, max) abort
  if a:max < 4 || strchars(a:text) <= a:max
    return a:text
  endif
  return strcharpart(a:text, 0, a:max - 3) . '...'
endfunction

" Truncate {text} to {width} display cells, ending with an ellipsis when it
" does not fit. Cells rather than characters keep East Asian names aligned.
function! s:truncate_cells(text, width) abort
  if a:width < 2 || strdisplaywidth(a:text) <= a:width
    return a:text
  endif

  let out = ''
  for char in split(a:text, '\zs')
    if strdisplaywidth(out . char) > a:width - 1
      break
    endif
    let out .= char
  endfor
  return out . '…'
endfunction

" Author column width in display cells; 0 hides the column.
function! s:author_width() abort
  let value = get(g:, 'git_changes_author_width', 8)
  return type(value) == type(0) && value >= 0 ? value : 8
endfunction

" {entry}'s author padded to the column width, followed by two spaces.
" Empty when the entry has no author or the column is hidden.
function! s:author_column(entry) abort
  let width = s:author_width()
  let author = get(a:entry, 'author', '')
  if width <= 0 || empty(author)
    return ''
  endif
  let author = s:truncate_cells(author, width)
  return author . repeat(' ', width - strdisplaywidth(author)) . '  '
endfunction

let s:repo_root_cache = {}

" Worktree root for {dir}, found without spawning git: walk up until a .git
" directory or file is found. Used for the current buffer's repository rather
" than the working directory, so commands work when Vim's cwd is in a different
" repository. The result is cached per directory.
function! s:repo_root_for(dir) abort
  let dir = simplify(fnamemodify(a:dir, ':p'))
  while len(dir) > 1 && dir[-1:] ==# '/'
    let dir = dir[:-2]
  endwhile
  if has_key(s:repo_root_cache, dir)
    return s:repo_root_cache[dir]
  endif

  let current = dir
  let result = ''
  while 1
    if isdirectory(current . '/.git') || filereadable(current . '/.git')
      let result = current
      break
    endif
    let parent = fnamemodify(current, ':h')
    if parent ==# current
      break
    endif
    let current = parent
  endwhile

  let s:repo_root_cache[dir] = result
  if len(s:repo_root_cache) > 200
    call filter(s:repo_root_cache, 'v:val !=# ""')
    if len(s:repo_root_cache) > 200
      let s:repo_root_cache = {}
    endif
  endif
  return result
endfunction

function! s:repo_root() abort
  let state = get(b:, 'git_changes', {})
  if !empty(state) && !empty(get(state, 'root', ''))
    return state.root
  endif

  " A buffer opened through a symlink is edited as its target file. Always
  " prefer the file's repository over the working directory, which may be
  " another repository entirely.
  let file = expand('%:p')
  if !empty(file) && &buftype ==# ''
    let root = s:repo_root_for(fnamemodify(resolve(file), ':h'))
    if !empty(root)
      return root
    endif
  endif

  return s:repo_root_for(getcwd())
endfunction

function! s:git(root, args) abort
  if type(a:args) == type([])
    let cmd = ['git', '--no-pager', '-c', 'core.quotePath=false',
          \ '-C', a:root] + a:args
  else
    let cmd = 'git --no-pager -c core.quotePath=false -C '
          \ . shellescape(a:root) . ' ' . a:args
  endif
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
    " Drop the entry before waiting on the job: in Neovim jobwait() and
    " jobstop() can run the exit callback synchronously, and that callback
    " also removes the entry.
    call remove(a:state, name)
    if has('nvim')
      if jobwait([job], 0)[0] == -1
        call jobstop(job)
      endif
    elseif job_status(job) ==# 'run'
      call job_stop(job)
    endif
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
  for key in ['branch_req', 'branch_tip_req', 'commit_req', 'files_req',
        \ 'diff_req']
    let a:state[key] = get(a:state, key, 0) + 1
  endfor
  for key in ['branches', 'branches-worktrees', 'branch-tip', 'commits-log',
        \ 'commits-remote', 'commits-unpushed', 'files', 'files-body',
        \ 'diff-check', 'diff-old', 'diff-new']
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

" Signature used to skip redundant scratch-buffer updates without copying the
" whole buffer with getbufline() first.
function! s:lines_signature(lines) abort
  let text = join(a:lines, "\n")
  if exists('*sha256')
    return len(a:lines) . ':' . sha256(text)
  endif
  return len(a:lines) . ':' . hash(text)
endfunction

function! s:set_lines(buf, lines) abort
  if !bufexists(a:buf)
    return 0
  endif

  let target = empty(a:lines) ? [''] : a:lines
  let signature = s:lines_signature(target)
  let cached = getbufvar(a:buf, 'git_changes_set_lines', {})
  let tick = getbufvar(a:buf, 'changedtick', 0)
  if !empty(cached) && cached.tick == tick
    if cached.signature ==# signature
      return 0
    endif
  else
    " The buffer changed behind our back; make sure it is not already correct.
    let current = getbufline(a:buf, 1, '$')
    if current ==# target
      call setbufvar(a:buf, 'git_changes_set_lines',
            \ {'tick': tick, 'signature': signature})
      return 0
    endif
  endif

  let line_count = s:buf_linecount(a:buf)
  let was_modifiable = getbufvar(a:buf, '&modifiable')
  call setbufvar(a:buf, '&modifiable', 1)
  try
    call setbufline(a:buf, 1, target)
    if line_count > len(target)
      silent call deletebufline(a:buf, len(target) + 1, '$')
    endif
  finally
    call setbufvar(a:buf, '&modifiable', was_modifiable ? 1 : 0)
  endtry
  call setbufvar(a:buf, 'git_changes_set_lines',
        \ {'tick': getbufvar(a:buf, 'changedtick', 0), 'signature': signature})
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
        \ 'copy_file': 'yy',
        \ 'copy_commit': 'yy',
        \ 'copy_branch': 'yy',
        \ 'branch_group_next': ']]',
        \ 'branch_group_prev': '[[',
        \ 'edit_message': 'e',
        \ 'load_more': 'L',
        \ 'commit': 'cc',
        \ 'commit_editor': 'C',
        \ 'open_main': 'gs',
        \ 'pull': 'p',
        \ 'push': 'P',
        \ 'new_branch': 'cn',
        \ 'branch_delete': 'd',
        \ 'checkout_branch': 'co',
        \ 'merge_branch': 'M',
        \ 'merge_abort': 'A',
        \ 'apply_branch': '<CR>',
        \ 'cycle_next': '<Tab>',
        \ 'cycle_prev': '<S-Tab>',
        \ 'worktree': '<Esc>',
        \ 'pane_files': '1',
        \ 'pane_commits': '2',
        \ 'pane_branches': '3',
        \ 'pane_diff': '4',
        \ 'pane_status': '0',
        \ 'diff_left': 'H',
        \ 'diff_right': 'L',
        \ 'hunk_next': ']c',
        \ 'hunk_prev': '[c',
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

" Map a configurable action to a script-local function call. Keeping the
" <SID> concatenation in one place avoids repeating the same fragile string
" construction at every call site.
function! s:map_action(action, func, ...) abort
  let args = join(a:000, ', ')
  call s:map_keys(a:action,
        \ ':<C-u>call ' . s:sid . a:func . '(' . args . ')<CR>')
endfunction

function! s:map_fixed_action(key, func, ...) abort
  let args = join(a:000, ', ')
  call s:map_fixed(a:key,
        \ ':<C-u>call ' . s:sid . a:func . '(' . args . ')<CR>')
endfunction

function! s:map_quit() abort
  call s:map_keys('quit', ':<C-u>GitChangesQuit<CR>')
endfunction

function! s:map_left_pane_keys() abort
  call s:map_action('pane_files', 'goto_left_pane', 1)
  call s:map_action('pane_commits', 'goto_left_pane', 2)
  call s:map_action('pane_branches', 'goto_left_pane', 3)
  call s:map_action('pane_diff', 'goto_diff_pane')
  call s:map_action('pane_status', 'goto_status_pane')
endfunction

function! s:map_left_action_keys() abort
  call s:map_action('commit', 'commit_current')
  call s:map_action('commit_editor', 'commit_with_editor')
  call s:map_action('pull', 'pull_current')
  call s:map_action('push', 'push_current')
  call s:map_action('new_branch', 'new_branch')
endfunction

function! s:map_open_main() abort
  call s:map_keys('open_main', ':<C-u>GitChanges<CR>')
endfunction

function! s:init_list_buffer(state, kind) abort
  let b:git_changes = a:state
  let b:gc_kind = a:kind

  call s:setup_list_window()

  call s:map_fixed_action('j', 'move_cursor', 1)
  call s:map_fixed_action('k', 'move_cursor', -1)
  call s:map_fixed_action('<Down>', 'move_cursor', 1)
  call s:map_fixed_action('<Up>', 'move_cursor', -1)
  call s:map_fixed_action('J', 'scroll_diff', 1)
  call s:map_fixed_action('K', 'scroll_diff', -1)
  call s:map_action('hunk_next', 'goto_diff_hunk', 1)
  call s:map_action('hunk_prev', 'goto_diff_hunk', -1)
  call s:map_action('refresh', 'refresh_all')
  call s:map_action('cycle_next', 'cycle_pane', 1)
  call s:map_action('cycle_prev', 'cycle_pane', -1)
  call s:map_left_pane_keys()
  call s:map_left_action_keys()
  call s:map_keys('checkout_branch', ':<C-u>GitChangesBranchCheckout<CR>')
  call s:map_keys('merge_branch', ':<C-u>GitChangesBranchMerge<CR>')
  call s:map_open_main()
  call s:map_action('worktree', 'goto_worktree')

  if a:kind ==# 'files'
    call s:map_action('toggle_tree', 'toggle_tree')
    call s:map_fixed_action('?', 'toggle_help')
    call s:map_action('stage', 'stage_current', '"stage"')
    call s:map_action('unstage', 'stage_current', '"unstage"')
    call s:map_action('stage_all', 'stage_all')
    call s:map_action('unstage_all', 'unstage_all')
    call s:map_action('toggle_stage', 'stage_current', '"toggle"')
    call s:map_action('file_discard', 'discard_current')
    call s:map_action('open_file', 'open_file')
    call s:map_action('diff_file', 'open_file_diff_for_current')
    call s:map_action('copy_file', 'copy_file_path')
    call s:map_action('diff_left', 'scroll_diff_horizontal', -1)
    call s:map_action('diff_right', 'scroll_diff_horizontal', 1)
  elseif a:kind ==# 'commits'
    call s:map_action('copy_commit', 'copy_commit_hash')
    call s:map_action('edit_message', 'edit_commit_message')
    call s:map_action('load_more', 'load_more_commits')
  endif

  call s:map_quit()

  let callback = a:kind ==# 'files' ? 'on_files_cursor_moved' : 'on_commits_cursor_moved'
  augroup git_changes
    autocmd! CursorMoved <buffer>
    execute 'autocmd CursorMoved <buffer> call ' . s:sid . callback . '()'
    execute 'autocmd WinEnter <buffer> call ' . s:sid . 'on_pane_enter()'
  augroup END
endfunction

function! s:init_diff_buffer(state, side) abort
  let b:git_changes = a:state
  let b:gc_kind = 'diff'
  let b:gc_side = a:side
  call s:setup_diff_window()
  call s:map_action('refresh', 'refresh_all')
  call s:map_action('open_file', 'open_file')
  call s:map_action('diff_file', 'open_file_diff_for_current')
  call s:map_action('stage', 'stage_current', '"stage"')
  call s:map_action('unstage', 'stage_current', '"unstage"')
  call s:map_action('stage_all', 'stage_all')
  call s:map_action('unstage_all', 'unstage_all')
  call s:map_action('toggle_stage', 'stage_current', '"toggle"')
  call s:map_action('staged_view', 'toggle_main_staged_diff')
  call s:map_action('file_discard_diff', 'discard_current')
  call s:map_action('commit', 'commit_current')
  call s:map_action('pull', 'pull_current')
  call s:map_action('push', 'push_current')
  call s:map_action('new_branch', 'new_branch')
  call s:map_action('commit_editor', 'commit_with_editor')
  call s:map_keys('checkout_branch', ':<C-u>GitChangesBranchCheckout<CR>')
  call s:map_keys('merge_branch', ':<C-u>GitChangesBranchMerge<CR>')
  call s:map_left_pane_keys()
  call s:map_action('cycle_next', 'cycle_pane', 1)
  call s:map_action('cycle_prev', 'cycle_pane', -1)
  call s:map_open_main()
  call s:map_quit()

  augroup git_changes
    autocmd! WinEnter <buffer>
    execute 'autocmd WinEnter <buffer> call ' . s:sid . 'on_pane_enter()'
  augroup END
endfunction

function! s:init_branch_buffer(state) abort
  let b:git_changes = a:state
  let b:gc_kind = 'branches'
  call s:setup_list_window()

  call s:map_fixed_action('j', 'move_cursor', 1)
  call s:map_fixed_action('k', 'move_cursor', -1)
  call s:map_fixed_action('<Down>', 'move_cursor', 1)
  call s:map_fixed_action('<Up>', 'move_cursor', -1)
  call s:map_action('hunk_next', 'goto_diff_hunk', 1)
  call s:map_action('hunk_prev', 'goto_diff_hunk', -1)
  call s:map_action('refresh', 'refresh_all')
  call s:map_fixed_action('?', 'toggle_branch_help')
  call s:map_action('checkout_branch', 'checkout_branch')
  call s:map_action('merge_branch', 'merge_branch')
  call s:map_action('merge_abort', 'merge_abort')
  call s:map_action('apply_branch', 'apply_branch')
  call s:map_action('cycle_next', 'cycle_pane', 1)
  call s:map_action('cycle_prev', 'cycle_pane', -1)
  call s:map_left_pane_keys()
  call s:map_left_action_keys()
  call s:map_open_main()
  call s:map_action('worktree', 'goto_worktree')
  call s:map_action('branch_delete', 'delete_branch')
  call s:map_action('copy_branch', 'copy_branch_name')
  call s:map_action('branch_group_next', 'cycle_branch_kind', 1)
  call s:map_action('branch_group_prev', 'cycle_branch_kind', -1)
  call s:map_quit()

  augroup git_changes
    autocmd! CursorMoved <buffer>
    execute 'autocmd CursorMoved <buffer> call ' . s:sid . 'on_branch_cursor_moved()'
    execute 'autocmd WinEnter <buffer> call ' . s:sid . 'on_pane_enter()'
  augroup END

  call s:update_statusline(a:state)
endfunction

" The status pane mirrors the current selection: a commit and its message,
" the working tree, a compare range, or the selected branch. It is numbered
" 0 so it can be reached from every pane with the 0 key.
function! s:init_status_buffer(state) abort
  let b:git_changes = a:state
  let b:gc_kind = 'status'
  call s:setup_list_window()
  setlocal nowrap

  call s:map_left_pane_keys()
  call s:map_left_action_keys()
  call s:map_keys('checkout_branch', ':<C-u>GitChangesBranchCheckout<CR>')
  call s:map_keys('merge_branch', ':<C-u>GitChangesBranchMerge<CR>')
  call s:map_action('worktree', 'goto_worktree')
  call s:map_action('cycle_next', 'cycle_pane', 1)
  call s:map_action('cycle_prev', 'cycle_pane', -1)
  call s:map_open_main()
  call s:map_quit()
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

function! s:cancel_debounce(state, key) abort
  let timer = get(a:state, a:key, -1)
  if timer != -1
    call timer_stop(timer)
    let a:state[a:key] = -1
  endif
endfunction

function! s:debounce(state, key, delay, Fn) abort
  call s:cancel_debounce(a:state, a:key)
  let a:state[a:key] = timer_start(a:delay, a:Fn)
endfunction

function! s:cancel_pending(state) abort
  call s:cancel_debounce(a:state, 'file_timer')
  call s:cancel_debounce(a:state, 'commit_timer')
endfunction

function! s:flush_pending(state) abort
  if get(a:state, 'commit_timer', -1) != -1
    call s:cancel_pending(a:state)
    call s:apply_commit_select(a:state)
  elseif get(a:state, 'file_timer', -1) != -1
    call s:cancel_debounce(a:state, 'file_timer')
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
  call s:debounce(a:state, 'file_timer', s:debounce_delay(),
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
  let a:state.worktree_counts = []
  let a:state.file_index = -1
endfunction

function! s:schedule_commit_select(state, index) abort
  let a:state.commit_index = a:index
  call s:clear_files_state(a:state)
  let a:state.detail_mode = 'commit'
  call s:update_status_window(a:state)
  call s:cancel_debounce(a:state, 'file_timer')
  if !s:can_debounce()
    call s:apply_commit_select(a:state)
    return
  endif
  call s:debounce(a:state, 'commit_timer', s:debounce_delay(),
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
        \ state.old_win, state.new_win, get(state, 'work_win', 0),
        \ get(state, 'status_win', 0)]
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
      if winid != get(state, 'status_win', 0)
        call s:sync_detail_mode(state,
              \ winid == state.branches_win ? 'branch' : 'commit')
      endif
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
    call s:sync_detail_mode(state, a:index == 3 ? 'branch' : 'commit')
  endif
endfunction

function! s:goto_status_pane() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif

  let winid = get(state, 'status_win', 0)
  if s:win_exists(winid)
    call win_gotoid(winid)
  endif
endfunction

" Switch what the status pane describes without changing the selection.
function! s:sync_detail_mode(state, mode) abort
  if get(a:state, 'detail_mode', 'commit') ==# a:mode
    return
  endif
  let a:state.detail_mode = a:mode
  call s:update_status_window(a:state)
endfunction

" Entering a pane makes the status window describe that pane's selection.
function! s:on_pane_enter() abort
  let state = s:cur_state()
  if empty(state) || !s:win_exists(get(state, 'status_win', 0))
    return
  endif

  call s:sync_detail_mode(state,
        \ get(b:, 'gc_kind', '') ==# 'branches' ? 'branch' : 'commit')
endfunction

" The diff pane that receives focus: the new pane (the side users read and
" act on), then the work pane shown for conflicts, then the old pane.
function! s:diff_pane_win(state) abort
  for winid in [a:state.new_win, get(a:state, 'work_win', 0),
        \ a:state.old_win]
    if winid > 0 && s:win_exists(winid)
      return winid
    endif
  endfor
  return 0
endfunction

function! s:goto_diff_pane() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif

  let winid = s:diff_pane_win(state)
  if winid > 0
    call win_gotoid(winid)
    call s:sync_detail_mode(state, 'commit')
  endif
endfunction

" Move the diff panes to the next or previous change while the cursor stays in
" the list pane.
function! s:goto_diff_hunk(delta) abort
  let state = s:cur_state()
  if empty(state)
    return
  endif

  let winid = s:diff_pane_win(state)
  if winid <= 0
    return
  endif

  let key = a:delta > 0 ? ']c' : '[c'
  if exists('*win_execute')
    call win_execute(winid, 'silent! normal! ' . key)
  else
    let curwin = win_getid()
    call win_gotoid(winid)
    execute 'silent! normal! ' . key
    call win_gotoid(curwin)
  endif
endfunction

" Jump back to the working tree changes from any commit or compare view.
function! s:goto_worktree() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif
  call s:flush_pending(state)
  call s:sync_detail_mode(state, 'commit')

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
  if type(a:args) == type([])
    let cmd = ['git', '--no-pager', '-c', 'core.quotePath=false',
          \ '-c', 'credential.interactive=never', '-C', a:root] + a:args
  else
    let cmd = 'git --no-pager -c core.quotePath=false -c credential.interactive=never -C '
          \ . shellescape(a:root) . ' ' . a:args . ' 2>&1'
  endif
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

function! s:prompt_input(prompt, ...) abort
  if exists('g:git_changes_input_override')
    let value = g:git_changes_input_override
    unlet g:git_changes_input_override
    return value
  endif
  let text = a:0 ? a:1 : ''
  let value = a:0 > 1 && !empty(a:2)
        \ ? input(a:prompt, text, a:2)
        \ : input(a:prompt, text)
  " input() leaves the prompt on the command line; redraw before the next
  " message so the two are not shown on the same line.
  redraw
  return value
endfunction

function! s:has_staged_changes(root, paths) abort
  let result = s:git_run(a:root,
        \ ['diff', '--cached', '--quiet', '--'] + a:paths)
  return result.code == 1
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

  let new_index = get(a:state.file_index_by_path, a:keep_path, -1)
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
  call s:cancel_debounce(a:state, 'refresh_timer')
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
  call s:debounce(state, 'refresh_timer', delay,
        \ {-> s:apply_pending_refresh(state)})
endfunction

" Path of the currently selected file, or '' when no file is selected.
function! s:current_file_path(state) abort
  if a:state.file_index >= 0 && a:state.file_index < len(a:state.files)
    return a:state.files[a:state.file_index].path
  endif
  return ''
endfunction

" Find the commit to keep selected after a reload. Prefer the same sha, then
" the same kind (worktree/compare), then the clamped old index.
function! s:find_commit_index(state, sha, kind, fallback) abort
  if !empty(a:sha)
    for i in range(len(a:state.commits))
      if get(a:state.commits[i], 'sha', '') ==# a:sha
        return i
      endif
    endfor
  elseif !empty(a:kind)
    for i in range(len(a:state.commits))
      if get(a:state.commits[i], 'kind', '') ==# a:kind
        return i
      endif
    endfor
  endif

  if empty(a:state.commits)
    return -1
  endif
  return min([max([a:fallback, 0]), len(a:state.commits) - 1])
endfunction

function! s:set_commit_cursor(state, index) abort
  if a:index < 0
    return
  endif
  let a:state.commit_index = a:index
  call s:set_cursor(a:state.commits_win,
        \ a:state.commits_header + 1 + a:index)
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

  let keep_path = s:current_file_path(state)

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

  let new_index = s:find_commit_index(a:state, a:keep_sha,
        \ a:keep_kind, a:keep_index)
  call s:set_commit_cursor(a:state, new_index)
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
  if !s:git_do(a:root, ['checkout', '--', target])
    return 0
  endif

  if index_status ==# ' ' && !empty(oldpath) && oldpath !=# a:file.path
    let abs_new = a:root . '/' . a:file.path
    if filereadable(abs_new)
      let tracked = !empty(s:git_one(a:root,
            \ ['ls-files', '--error-unmatch', '--', a:file.path]))
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
  let result = s:git_run(a:root,
        \ ['merge-base', '--is-ancestor', a:ancestor, a:descendant])
  return result.code == 0
endfunction

function! s:git_in_progress(root) abort
  let gitdir = s:git_one(a:root, ['rev-parse', '--absolute-git-dir'])
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

  let branch = s:git_one(state.root, ['symbolic-ref', '--short', '-q', 'HEAD'])
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

  let head_sha = s:git_one(state.root, ['rev-parse', 'HEAD'])
  let is_head = entry.sha ==# head_sha
  let has_remote = !empty(s:git(state.root, ['remote']))
  if has_remote && !get(entry, 'unpushed', 0)
    call s:err('only unpushed commits can be edited')
    return
  endif

  if !is_head
        \ && !empty(s:git(state.root, ['status', '--porcelain', '--untracked-files=no']))
    call s:err('commit or stash changes before editing an older commit')
    return
  endif

  if !is_head && get(g:, 'git_changes_confirm_rewrite', 1)
    let rewrite_count = s:git_one(state.root,
          \ ['rev-list', '--count', entry.sha . '..' . branch])
    let total = empty(rewrite_count) ? 1 : str2nr(rewrite_count) + 1
    let prompt = printf('Rewrite %d commit(s) on %s? '
          \ . 'Other branches will not be updated. Continue?', total, branch)
    if confirm(prompt, "&Yes\n&No", 2) != 1
      return
    endif
  endif

  let message = s:git(state.root,
        \ ['log', '-1', '--format=%B', entry.sha])
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
        \ ['for-each-ref', '--format=%(refname)', a:prefix])
    call s:git(a:root, ['update-ref', '-d', ref])
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
        \ ['rev-parse', '--verify', '-q', sha . '^'])
  let range = empty(parent)
        \ ? '--root ' . shellescape(branch)
        \ : shellescape(sha . '^..' . branch)
  let args = 'filter-branch -f'
        \ . ' --original ' . shellescape(backup_ns)
        \ . ' --state-branch ' . shellescape(state_ref)
        \ . ' --msg-filter ' . shellescape(filter)
        \ . ' -- ' . range

  let old_head = s:git_one(root, ['rev-parse', 'HEAD'])
  let old_tree = s:git_one(root, ['rev-parse', 'HEAD^{tree}'])
  let old_count = s:git_one(root, ['rev-list', '--count', 'HEAD'])
  let old_merges = s:git_one(root, ['rev-list', '--count', '--merges', 'HEAD'])

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
          \ ['show', state_ref . ':filter.map'])
      let parts = split(line, ':')
      if len(parts) >= 2 && parts[0] ==# sha
        let new_sha = parts[1]
        break
      endif
    endfor

    let new_head = s:git_one(root, ['rev-parse', 'HEAD'])
    let new_tree = s:git_one(root, ['rev-parse', 'HEAD^{tree}'])
    let new_count = s:git_one(root, ['rev-list', '--count', 'HEAD'])
    let new_merges = s:git_one(root, ['rev-list', '--count', '--merges', 'HEAD'])
    if empty(new_head)
          \ || new_tree !=# old_tree
          \ || str2nr(new_count) != str2nr(old_count)
          \ || str2nr(new_merges) != str2nr(old_merges)
      if !empty(old_head)
        call s:git(root, ['update-ref', 'refs/heads/' . branch, old_head])
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
  let index = s:find_commit_index(a:state, a:sha, '', 0)
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
            \ ['commit', '--amend', '--only', '-F', msgfile])
        return
      endif
      let target_sha = s:git_one(info.state.root, ['rev-parse', 'HEAD'])
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
  let info.is_head = target_sha ==# s:git_one(info.state.root, ['rev-parse', 'HEAD'])
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

  if a:0 && !empty(trim(a:1))
    let message = trim(a:1)
  else
    let prepared = s:prepared_commit_message(a:root)
    let message = trim(s:prompt_input('Commit message: ',
          \ empty(prepared) ? '' : join(prepared, ' ')))
  endif
  if empty(message)
    echomsg 'Commit cancelled'
    return 0
  endif

  if !s:git_do(a:root, ['commit', '-m', message])
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

" Git writes the prepared commit message for merges, cherry-picks, rebases, and
" reverts to .git/MERGE_MSG, including the "Conflicts:" comment block.
function! s:merge_message_lines(root) abort
  let gitdir = s:git_one(a:root, ['rev-parse', '--absolute-git-dir'])
  if empty(gitdir)
    return []
  endif
  let path = gitdir . '/MERGE_MSG'
  return filereadable(path) ? readfile(path) : []
endfunction

" Remove comment lines and surrounding blank lines so the prepared message can
" be passed to git commit -m.
function! s:prepared_commit_message(root) abort
  if empty(s:git_in_progress(a:root))
    return []
  endif

  let lines = filter(s:merge_message_lines(a:root), 'v:val !~# "^#"')
  while !empty(lines) && empty(trim(lines[-1]))
    call remove(lines, -1)
  endwhile
  while !empty(lines) && empty(trim(lines[0]))
    call remove(lines, 0)
  endwhile
  return lines
endfunction

function! s:commit_template(state) abort
  let root = a:state.root
  let in_progress = s:git_in_progress(root)
  let lines = empty(in_progress) ? [] : s:merge_message_lines(root)
  while !empty(lines) && empty(trim(lines[-1]))
    call remove(lines, -1)
  endwhile

  if empty(lines)
    let lines = ['']
  else
    call add(lines, '#')
    if in_progress ==# 'MERGE_HEAD'
      call extend(lines, [
            \ '# It looks like you may be committing a merge.',
            \ '# If this is not correct, please run',
            \ "#\tgit update-ref -d MERGE_HEAD",
            \ '# and try again.',
            \ '',
            \ '',
            \ ])
    elseif in_progress ==# 'CHERRY_PICK_HEAD'
      call extend(lines, [
            \ '# It looks like you may be committing a cherry-pick.',
            \ '# If this is not correct, please run',
            \ "#\tgit update-ref -d CHERRY_PICK_HEAD",
            \ '# and try again.',
            \ '',
            \ '',
            \ ])
    elseif in_progress ==# 'REVERT_HEAD'
      call extend(lines, [
            \ '# It looks like you may be committing a revert.',
            \ '# If this is not correct, please run',
            \ "#\tgit update-ref -d REVERT_HEAD",
            \ '# and try again.',
            \ '',
            \ '',
            \ ])
    endif
  endif

  call extend(lines, [
        \ '# Please enter the commit message for your changes. Lines starting',
        \ '# with ''#'' will be ignored, and an empty message aborts the commit.',
        \ '#',
        \ '# On branch ' . s:current_branch(root),
        \ ])

  if in_progress ==# 'MERGE_HEAD'
    if empty(s:git(root, ['diff', '--name-only', '--diff-filter=U']))
      call add(lines, '# All conflicts fixed but you are still merging.')
      call add(lines, '#')
    endif
  elseif in_progress ==# 'CHERRY_PICK_HEAD'
    let sha = s:git_one(root, ['rev-parse', '--short', 'CHERRY_PICK_HEAD'])
    call add(lines, '# You are currently cherry-picking commit ' . sha . '.')
    call add(lines, '#')
  elseif in_progress ==# 'REVERT_HEAD'
    let sha = s:git_one(root, ['rev-parse', '--short', 'REVERT_HEAD'])
    call add(lines, '# You are currently reverting commit ' . sha . '.')
    call add(lines, '#')
  endif

  call add(lines, '# Changes to be committed:')

  let labels = {
        \ 'M': 'modified',
        \ 'A': 'new file',
        \ 'D': 'deleted',
        \ 'R': 'renamed',
        \ 'C': 'copied',
        \ 'T': 'typechange',
        \ 'U': 'unmerged',
        \ }
  for line in s:git(root,
        \ ['diff', '--cached', '--name-status', '--find-renames'])
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
  setlocal modified
  let b:git_changes_commit_tick = b:changedtick
  execute 'nnoremap <buffer> <silent> q ' . s:cmd_rhs(':<C-u>quit<CR>')

  let b:git_changes_commit = {'root': a:root, 'on_done': a:on_done}
  augroup git_changes_commit_message
    autocmd! * <buffer>
    execute 'autocmd BufWriteCmd <buffer> call '
          \ . s:sid . 'apply_commit_message()'
    execute 'autocmd QuitPre <buffer> call '
          \ . s:sid . 'cancel_unmodified_commit()'
  augroup END

  call cursor(1, 1)
  echomsg 'Write the commit message, then :w or :x to commit or :q to cancel'
endfunction

function! s:cancel_unmodified_commit() abort
  " The template starts the buffer in modified state so :x writes (and commits)
  " even when the message was not edited. Let :q cancel without a warning when
  " the buffer still matches that initial template.
  if get(b:, 'git_changes_commit_tick', -1) == b:changedtick
    setlocal nomodified
  endif
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
          \ ['commit', '--cleanup=strip', '-F', msgfile])
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
        \ ['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}'])
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
          \ ['config', '--get', 'branch.' . branch . '.remote'])
    if !empty(branch_remote)
      return branch_remote
    endif
  endif

  let remotes = s:git(a:root, ['remote'])
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
  let result = s:git_run(a:root, ['pull', '--no-rebase', '--no-edit'])
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
  let keep_path = s:current_file_path(a:state)

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

  let index = s:find_commit_index(a:state, '', '', a:index)
  call s:set_commit_cursor(a:state, index)
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
    let result = s:git_run(a:root, ['push'])
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

  let branch = s:git_one(a:root, ['symbolic-ref', '--short', '-q', 'HEAD'])
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

  let result = s:git_run(a:root,
        \ ['push', '--set-upstream', remote, branch])
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
    if !s:git_do(state.root, ['add', '-A', '--'] + add_paths)
      return
    endif
    echomsg 'Staged: ' . file.path
  else
    if !s:git_do(state.root, ['reset', '-q', 'HEAD', '--'] + paths)
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

  let keep_path = s:current_file_path(state)

  if !s:git_do(state.root, ['add', '-A', '--', '.'])
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

  let keep_path = s:current_file_path(state)

  if !s:git_do(state.root, ['reset', '-q', 'HEAD', '--', '.'])
    return
  endif

  echomsg 'Unstaged all changes'
  call s:refresh_file_list(state, keep_path)
endfunction


" Ref groups shown in the branch list, in the order ]]/[[ cycle through.
function! s:branch_kinds() abort
  return ['local', 'remote', 'tag']
endfunction

function! s:branch_kind_title(kind) abort
  if a:kind ==# 'remote'
    return 'Remote branches'
  elseif a:kind ==# 'tag'
    return 'Tags'
  endif
  return 'Branches'
endfunction

function! s:branch_kind_noun(kind) abort
  return a:kind ==# 'remote' ? 'remote branches'
        \ : a:kind ==# 'tag' ? 'tags' : 'branches'
endfunction

" Parse %(upstream:track), e.g. "[ahead 1, behind 2]" or "[gone]",
" into [ahead, behind, gone].
function! s:parse_upstream_track(track) abort
  if a:track =~# '\[gone\]'
    return [0, 0, 1]
  endif
  return [str2nr(matchstr(a:track, 'ahead \zs\d\+')),
        \ str2nr(matchstr(a:track, 'behind \zs\d\+')), 0]
endfunction

" Sync markers shown after a branch name, relative to its upstream.
function! s:branch_sync_text(ref) abort
  if get(a:ref, 'gone', 0)
    return ' ✗'
  endif

  let text = ''
  if get(a:ref, 'ahead', 0) > 0
    let text .= ' ↑' . a:ref.ahead
  endif
  if get(a:ref, 'behind', 0) > 0
    let text .= ' ↓' . a:ref.behind
  endif
  return text
endfunction

" True when both paths point at the same directory, with symlinks resolved.
function! s:same_dir(path_a, path_b) abort
  let a = substitute(resolve(a:path_a), '/\+$', '', '')
  let b = substitute(resolve(a:path_b), '/\+$', '', '')
  return a ==# b
endfunction

" Directory of the worktree {ref} is checked out in, when it is not the one
" this view belongs to.
function! s:branch_worktree_text(state, ref) abort
  let path = get(get(a:state, 'branch_worktrees', {}), a:ref.name, '')
  if empty(path) || s:same_dir(path, a:state.root)
    return ''
  endif
  return ' [' . fnamemodify(path, ':~') . ']'
endfunction

function! s:load_branches(state, select_name, ...) abort
  let OnDone = a:0 ? a:1 : 0
  " Branch tips may have moved, so fetch them again with the new list.
  let a:state.branch_tips = {}
  let a:state.branch_tip_pending = ''
  let token = get(a:state, 'branch_req', 0) + 1
  let a:state.branch_req = token
  call s:git_job(a:state, 'branches', 'branch_req', token,
        \ ['for-each-ref', '--sort=-committerdate',
        \  '--format=%(HEAD)%09%(refname)%09%(refname:short)'
        \  . '%09%(symref)%09%(upstream:track)%09%(upstream:short)',
        \  'refs/heads', 'refs/remotes', 'refs/tags'],
        \ function('s:apply_branches', [a:state, a:select_name, OnDone]))
  call s:git_job(a:state, 'branches-worktrees', 'branch_req', token,
        \ ['worktree', 'list', '--porcelain'],
        \ function('s:apply_worktrees', [a:state]))
endfunction

" Map each checked-out branch to its worktree directory.
function! s:apply_worktrees(state, result) abort
  let worktrees = {}
  let path = ''
  for line in a:result.out
    if stridx(line, 'worktree ') == 0
      let path = strpart(line, 9)
    elseif stridx(line, 'branch refs/heads/') == 0 && !empty(path)
      let worktrees[strpart(line, 18)] = path
    elseif empty(line)
      let path = ''
    endif
  endfor

  call s:update_branch_worktrees(a:state, worktrees)
endfunction

" Keep the worktree directories in sync without losing the selected branch.
function! s:update_branch_worktrees(state, worktrees) abort
  if get(a:state, 'branch_worktrees', {}) ==# a:worktrees
    return
  endif
  let a:state.branch_worktrees = a:worktrees
  if empty(get(a:state, 'refs', []))
    return
  endif

  let keep = ''
  if a:state.branch_index >= 0 && a:state.branch_index < len(a:state.branches)
    let keep = a:state.branches[a:state.branch_index].name
  endif
  call s:render_branches(a:state, keep)
endfunction

function! s:apply_branches(state, select_name, on_done, result) abort
  let refs = []
  for line in a:result.out
    let parts = split(line, "\t", 1)
    if len(parts) < 3 || !empty(get(parts, 3, ''))
      continue
    endif
    let refname = parts[1]
    let name = parts[2]
    if empty(name)
      continue
    endif
    let [ahead, behind, gone] = s:parse_upstream_track(get(parts, 4, ''))
    call add(refs, {
          \ 'name': name,
          \ 'refname': refname,
          \ 'kind': refname =~# '^refs/remotes/' ? 'remote'
          \       : refname =~# '^refs/tags/' ? 'tag' : 'local',
          \ 'current': parts[0] ==# '*',
          \ 'upstream': get(parts, 5, ''),
          \ 'ahead': ahead,
          \ 'behind': behind,
          \ 'gone': gone,
          \ })
  endfor
  let a:state.refs = refs

  let old_name = ''
  if a:state.branch_index >= 0 && a:state.branch_index < len(a:state.branches)
    let old_name = a:state.branches[a:state.branch_index].name
  endif
  call s:render_branches(a:state,
        \ !empty(a:select_name) ? a:select_name : old_name)

  if type(a:on_done) == type(function('tr'))
    call a:on_done()
  endif
endfunction

" Draw the refs of {state.branch_kind}, selecting {wanted} when present.
function! s:render_branches(state, wanted) abort
  let kind = get(a:state, 'branch_kind', 'local')
  let branches = []
  for ref in get(a:state, 'refs', [])
    if ref.kind ==# kind
      call add(branches, ref)
    endif
  endfor
  let a:state.branches = branches

  let selected = -1
  for i in range(len(branches))
    if branches[i].name ==# a:wanted
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
  let a:state.branch_index = selected

  let header = ['# ' . s:branch_kind_title(kind)]
  if get(a:state, 'branch_show_help', 0)
    let km = s:keymaps()
    call extend(header, [
          \ '# j/k:select Enter:show 1/2/3/4 ]c/[c:hunk Tab/S-Tab',
          \ '# ' . km.branch_group_next . '/'
          \     . km.branch_group_prev . ':groups',
          \ '# ' . km.new_branch . ':new ' . km.commit . ':commit '
          \     . km.commit_editor . ':edit',
          \ '# ' . km.pull . ':pull ' . km.push . ':push '
          \     . km.checkout_branch . ':checkout '
          \     . km.merge_branch . ':merge ' . km.merge_abort . ':abort',
          \ '# ' . km.branch_delete . ':delete ' . km.copy_branch
          \     . ':copy ' . km.worktree . ':worktree ?:hide',
          \ ])
  endif
  let a:state.branch_header = len(header)

  let lines = copy(header)
  for branch in branches
    call add(lines, (branch.current ? '* ' : '  ') . branch.name
          \ . s:branch_sync_text(branch)
          \ . s:branch_worktree_text(a:state, branch))
  endfor
  if empty(branches)
    call add(lines, '  (no ' . s:branch_kind_noun(kind) . ')')
  endif

  call s:set_lines(a:state.branches_buf, lines)
  if selected >= 0
    call s:set_cursor(a:state.branches_win,
          \ a:state.branch_header + 1 + selected)
  endif
  call s:update_statusline(a:state)
  call s:update_status_window(a:state)
endfunction

" Switch the branch list to the next/previous ref group.
function! s:cycle_branch_kind(delta) abort
  let state = s:cur_state()
  if empty(state)
    return
  endif

  let kinds = s:branch_kinds()
  let index = index(kinds, get(state, 'branch_kind', 'local'))
  if index < 0
    let index = 0
  endif
  let next = (index + a:delta) % len(kinds)
  if next < 0
    let next += len(kinds)
  endif

  let state.branch_kind = kinds[next]
  let state.branch_index = -1
  let state.detail_mode = 'branch'
  if empty(get(state, 'refs', []))
    call s:load_branches(state, '')
    return
  endif
  call s:render_branches(state, '')
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
  let state.detail_mode = 'branch'
  call s:update_status_window(state)
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

  if !s:git_do(state.root, ['checkout', branch.name])
    return
  endif

  echomsg 'Switched to branch: ' . branch.name
  execute 'GitChanges'
endfunction

function! s:merge_root(root, branch, ...) abort
  let state = a:0 ? a:1 : s:find_state_for_root(a:root)
  let current = s:current_branch(a:root)

  if get(g:, 'git_changes_confirm_branch_merge', 1)
        \ && s:prompt_confirm(
        \      'Merge branch ' . a:branch . ' into ' . current . '?',
        \      "&Yes\n&No", 2) != 1
    call s:report(state, 'Merge cancelled', 'info')
    return
  endif

  call s:report(state, 'Merging ' . a:branch . '...', 'busy')

  let result = s:git_run(a:root, ['merge', '--no-edit', a:branch])
  if !empty(state)
    call s:reload_current_branch(state)
  endif

  if !result.ok
    call s:report(state,
          \ 'Merge failed: ' . s:output_message(result.out), 'error')
    return
  endif
  call s:report(state, 'Merged branch: ' . a:branch, 'info')
endfunction

function! s:merge_branch() abort
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
    call s:err('cannot merge the current branch into itself')
    return
  endif

  call s:merge_root(state.root, branch.name, state)
endfunction

function! s:abort_merge_root(root, ...) abort
  let state = a:0 ? a:1 : s:find_state_for_root(a:root)
  if s:git_in_progress(a:root) !=# 'MERGE_HEAD'
    call s:report(state, 'No merge in progress', 'info')
    return
  endif

  let result = s:git_run(a:root, ['merge', '--abort'])
  if !empty(state)
    call s:reload_current_branch(state)
  endif

  if !result.ok
    call s:report(state,
          \ 'Merge abort failed: ' . s:output_message(result.out), 'error')
    return
  endif
  call s:report(state, 'Merge aborted', 'info')
endfunction

function! s:merge_abort() abort
  let state = s:cur_state()
  if empty(state)
    return
  endif
  call s:abort_merge_root(state.root, state)
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
        \ ['checkout', '-b', name, branch.name])
    return
  endif

  echomsg 'Created branch: ' . name
  execute 'GitChanges'
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
  if get(branch, 'kind', 'local') !=# 'local'
    call s:err('only local branches can be deleted')
    return
  endif

  if get(g:, 'git_changes_confirm_branch_delete', 1)
        \ && confirm('Delete local branch ' . branch.name . '?',
        \             "&Yes\n&No", 2) != 1
    return
  endif

  if !s:git_do(state.root, ['branch', '-d', branch.name])
    return
  endif

  call s:load_branches(state, '')
  echomsg 'Deleted branch: ' . branch.name
endfunction


function! s:current_branch(root) abort
  let branch = s:git_one(a:root, ['symbolic-ref', '--short', '-q', 'HEAD'])
  if !empty(branch)
    return branch
  endif
  let sha = s:git_one(a:root, ['rev-parse', '--short', 'HEAD'])
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
        \ ['rev-parse', '--verify', '-q', a:ref . '^{commit}'])
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

" Header line for a [staged, unstaged, untracked] summary, or '' when the
" counts are not known yet.
function! s:worktree_status_line(counts) abort
  if empty(a:counts)
    return ''
  endif

  let [staged, unstaged, untracked] = a:counts
  if staged + unstaged + untracked == 0
    return '# Working tree clean'
  endif
  return printf('# Staged %d  Unstaged %d  Untracked %d',
        \ staged, unstaged, untracked)
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
  " Commit messages, authors, dates and bodies are shown in the status pane;
  " this header only identifies what the file list belongs to.
  let lines = a:entry.kind ==# 'commit'
        \ ? ['# commit ' . a:entry.short]
        \ : ['# ' . a:entry.short . '  ' . s:truncate(a:entry.subject, 90)]

  if a:entry.kind ==# 'worktree'
    let counts = get(a:state, 'worktree_counts', [])
    if empty(counts)
      let counts = s:worktree_summary(a:state.files)
    endif
    call add(lines, s:worktree_status_line(counts))
    if a:state.show_help
      call add(lines, '# s:stage u:unstage -:toggle S/U:all t:tree')
      call add(lines, '# r:refresh d:discard o:open gd:diff ?:hide')
      call add(lines, '# Esc:worktree yy:path cc:commit cn:new co:switch M:merge')
      call add(lines, '# C:edit p:pull P:push')
      call add(lines, '# J/K:scroll ]c/[c:hunk 1/2/3/4:panes 0:status Tab/S-Tab')
      call add(lines, '# H/L:scroll diff left/right')
    endif
  elseif a:entry.kind ==# 'compare'
    call add(lines, '# Range: ' . a:state.list_title)
    if a:state.show_help
      call add(lines, '# t:tree r:refresh ?:hide yy:path Esc:worktree')
      call add(lines, '# cc:commit cn:new co:switch M:merge C:edit p:pull P:push')
      call add(lines, '# J/K:scroll ]c/[c:hunk 1/2/3/4:panes 0:status Tab/S-Tab')
      call add(lines, '# H/L:scroll diff left/right')
    endif
  elseif a:state.show_help
    call add(lines, '# t:tree r:refresh ?:hide yy:path Esc:worktree')
    call add(lines, '# cc:commit cn:new co:switch M:merge C:edit p:pull P:push')
    call add(lines, '# J/K:scroll ]c/[c:hunk 1/2/3/4:panes 0:status Tab/S-Tab')
    call add(lines, '# H/L:scroll diff left/right')
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
  let a:state.worktree_counts = s:worktree_summary(a:files)
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
  let index_by_path = {}
  for index in range(len(a:files))
    let index_by_path[a:files[index].path] = index
  endfor
  let a:state.file_index_by_path = index_by_path

  let lines = header_lines + body
  call s:set_lines(a:state.files_buf, lines)
  call s:update_statusline(a:state)
  call s:update_status_window(a:state)
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
    return get(a:state.file_index_by_path, shown.path, -1)
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
            \ . s:author_column(entry) . s:truncate(entry.subject, 88))
    endif
  endfor
  if get(a:state, 'commit_loaded', 0) == 0 && !empty(a:state.commits)
    call add(lines, '   (no commits in range)')
  elseif empty(a:state.commits)
    call add(lines, '   (no commits)')
  endif

  call s:set_lines(a:state.commits_buf, lines)
  call s:update_statusline(a:state)
  call s:update_status_window(a:state)
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
  if get(g:, 'git_changes_exclude_merges', 0)
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
  call s:update_status_window(a:state)
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
  let split_at = stridx(label, ' ')
  if split_at > 0
    let lead = strpart(label, 0, split_at)
    let rest = strpart(label, split_at)
  else
    let lead = label
    let rest = ''
  endif
  call win_execute(winid, 'let &l:statusline = ' . string(
        \ '%#GitChangesPaneBarLabel#' . lead
        \ . '%#GitChangesPaneBarPath#' . rest
        \ . '%#GitChangesPaneBarFill#'))
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

" `git add -A` fails with "pathspec did not match any files" for a path that is
" absent from both the index and the worktree. That happens once a rename or a
" deletion is fully staged, so drop those paths before staging.
function! s:addable_paths(root, paths) abort
  let result = []
  for path in a:paths
    if !empty(getftype(a:root . '/' . path))
          \ || !empty(s:git_one(a:root,
          \       ['ls-files', '--error-unmatch', '--', path]))
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
  call s:clear_files_state(a:state)
  let a:state.detail_mode = 'commit'
  call s:update_status_window(a:state)
  call s:set_commit_cursor(a:state, a:index)
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
  let a:state.detail_mode = 'commit'
  call s:update_statusline(a:state)
  call s:update_status_window(a:state)
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
    let old_label = a:args[0]
    let new_label = 'HEAD'
    let old_ref = s:resolve_ref(a:root, old_label)
    if empty(old_ref)
      call s:err('unknown revision: ' . old_label)
      return {}
    endif
    let new_ref = s:resolve_ref(a:root, new_label)
    if empty(new_ref)
      call s:err('HEAD has no commits')
      return {}
    endif
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
    let old_label = a:args[0]
    let new_label = a:args[1]
    let old_ref = s:resolve_ref(a:root, old_label)
    if empty(old_ref)
      call s:err('unknown revision: ' . old_label)
      return {}
    endif
    let new_ref = s:resolve_ref(a:root, new_label)
    if empty(new_ref)
      call s:err('unknown revision: ' . new_label)
      return {}
    endif
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

function! s:new_state(root, parsed, id) abort
  return {
        \ 'id': a:id,
        \ 'root': a:root,
        \ 'tab': 0,
        \ 'commits': [],
        \ 'commit_loaded': 0,
        \ 'commit_has_more': 0,
        \ 'files': [],
        \ 'files_entry': '',
        \ 'worktree_counts': [],
        \ 'shown_file': {},
        \ 'commit_index': -1,
        \ 'file_index': -1,
        \ 'commits_header': 1,
        \ 'files_header': 1,
        \ 'updating': 1,
        \ 'list_title': a:parsed.list_title,
        \ 'log_range': a:parsed.log_range,
        \ 'start_entries': a:parsed.start_entries,
        \ 'has_head': a:parsed.has_head,
        \ 'diff_cached': 0,
        \ 'log_ref': '',
        \ 'show_help': 0,
        \ 'branch_show_help': 0,
        \ 'file_tree': get(g:, 'git_changes_tree_view', 0) ? 1 : 0,
        \ 'file_line_map': [],
        \ 'file_line_for_index': [],
        \ 'display_file_indexes': [],
        \ 'file_index_by_path': {},
        \ 'branches': [],
        \ 'refs': [],
        \ 'branch_kind': 'local',
        \ 'branch_worktrees': {},
        \ 'branch_index': -1,
        \ 'branch_header': 2,
        \ 'files_buf': -1,
        \ 'commits_buf': -1,
        \ 'old_buf': -1,
        \ 'new_buf': -1,
        \ 'work_buf': -1,
        \ 'branches_buf': -1,
        \ 'status_buf': -1,
        \ 'files_win': 0,
        \ 'commits_win': 0,
        \ 'old_win': 0,
        \ 'new_win': 0,
        \ 'work_win': 0,
        \ 'branches_win': 0,
        \ 'status_win': 0,
        \ 'detail_mode': 'commit',
        \ 'branch_tips': {},
        \ 'branch_tip_pending': '',
        \ 'branch_tip_req': 0,
        \ 'file_timer': -1,
        \ 'commit_timer': -1,
        \ 'refresh_timer': -1,
        \ 'status': '',
        \ 'status_kind': 'info',
        \ }
endfunction

function! s:open_tab(root, parsed, tabnr) abort
  let root = a:root

  let next_id = get(s:, 'next_id', 0) + 1
  let s:next_id = next_id
  let state = s:new_state(root, a:parsed, next_id)

  tabnew
  if a:tabnr > 0
    execute 'silent! tabmove ' . (a:tabnr - 1)
  endif
  let initial_buf = bufnr('%')
  let state.tab = tabpagenr()
  let t:git_changes = state
  call add(s:instances, state)

  " Right side: the two diff panes sit above a status pane that spans both
  " of them, so build the status split before splitting the diff panes.
  let top_left_win = win_getid()
  rightbelow vsplit
  let right_win = win_getid()
  belowright split
  let status_win = win_getid()
  call win_gotoid(right_win)
  rightbelow vsplit
  let old_win = right_win
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

  call win_gotoid(status_win)
  let state.status_win = win_getid()
  let state.status_buf = s:new_scratch(
        \ printf('[GitChanges %d] Status', next_id), 'gitchanges')
  call s:init_status_buffer(state)

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
  call s:update_status_window(state)
  call win_gotoid(state.files_win)
endfunction

" Heights for the commit and branch panes, derived from the current screen
" size so the layout adapts when the terminal is resized.
function! s:layout_heights() abort
  let total_left = max([12, &lines - 4])
  let branch_height = max([6, min([
        \ s:opt_int('git_changes_branches_height', 10), total_left / 4])])
  let commit_height = max([5, min([
        \ s:opt_int('git_changes_commits_height', 14), total_left / 3])])
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
        \ || !s:win_exists(get(a:state, 'status_win', 0))
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

  " The status pane spans the right column; give it its fixed height and let
  " the diff panes above absorb the rest.
  let status_win = get(a:state, 'status_win', 0)
  let right_total = getwininfo(a:state.old_win)[0].height
        \ + getwininfo(status_win)[0].height + 1
  let status_height = max([1, min([
        \ s:opt_int('git_changes_status_height', 6), right_total - 5])])
  call win_execute(status_win, 'silent! resize ' . status_height)
endfunction

function! s:on_vim_resized() abort
  for state in copy(s:instances)
    if s:state_alive(state)
      call s:apply_layout(state)
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
  if empty(wins)
    let wins = win_findbuf(get(state, 'status_buf', -1))
  endif

  if !empty(wins)
    let tabwin = win_id2tabwin(wins[0])
    let tabnr = tabwin[0]
    if tabnr > 0
      execute 'tabclose ' . tabnr
    endif
  endif

  for buf in [state.files_buf, state.commits_buf, state.old_buf,
        \ state.new_buf, get(state, 'work_buf', -1), state.branches_buf,
        \ get(state, 'status_buf', -1)]
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

" The heavy lifting for the statusline and blame-line API lives in
" autoload/git_changes/statusline.vim so it is loaded lazily.
function! s:statusline_clear() abort
  let s:repo_root_cache = {}
  call git_changes#statusline#clear()
endfunction

" Resolve the current buffer's worktree root and repo-relative path without
" spawning git. Handles normal .git directories and worktree/submodule .git
" files. Repository roots are cached per directory by s:repo_root_for().
function! s:buffer_repo_path() abort
  let file = expand('%:p')
  if empty(file)
    return ['', '']
  endif
  let file = resolve(file)

  let root = s:repo_root_for(fnamemodify(file, ':h'))
  if empty(root)
    return ['', '']
  endif

  return [root, s:repo_relative_path(root, file)]
endfunction

" Public wrappers keep the documented API stable while the implementation is
" loaded lazily from autoload/git_changes/statusline.vim.
function! git_changes#statusline() abort
  return git_changes#statusline#text()
endfunction

function! git_changes#blame_line_info() abort
  return git_changes#statusline#blame_line_info()
endfunction

function! git_changes#blame_line() abort
  return git_changes#statusline#blame_line()
endfunction

function! git_changes#blame_line_info_async() abort
  return git_changes#statusline#blame_line_info_async()
endfunction

function! git_changes#blame_line_async() abort
  return git_changes#statusline#blame_line_async()
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
  let out = s:git(a:root, ['status', '--porcelain', '--', a:path])
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
  if !s:git_do(root, ['add', '-A', '--'] + add_paths)
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
        \ ? ['rm', '-q', '--cached', '--']
        \ : ['reset', '-q', 'HEAD', '--']
  if !s:git_do(root, args + paths)
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

function! s:refresh_state_for_root(root) abort
  let state = s:find_state_for_root(a:root)
  if !empty(state)
    call s:reload_current_branch(state)
  endif
endfunction

function! git_changes#branch_create(...) abort
  let root = s:repo_root()
  if empty(root)
    call s:err('not inside a Git repository')
    return
  endif

  let name = a:0 ? trim(a:1) : trim(s:prompt_input('New branch name: '))
  if empty(name)
    echomsg 'Branch creation cancelled'
    return
  endif

  if !s:git_do(root, ['checkout', '-b', name])
    return
  endif

  echomsg 'Created branch: ' . name
  call s:refresh_state_for_root(root)
endfunction

function! git_changes#branch_checkout(...) abort
  let root = s:repo_root()
  if empty(root)
    call s:err('not inside a Git repository')
    return
  endif

  " ":GitChangesBranchCheckout" without an argument still passes an
  " empty <q-args>, so decide on the value rather than a:0.
  let arg = trim(a:0 ? a:1 : '')
  let name = !empty(arg) ? arg
        \ : trim(s:prompt_input('Branch: ', '',
        \       'customlist,git_changes#complete_branches'))
  if empty(name)
    echomsg 'Branch checkout cancelled'
    return
  endif

  if !s:git_do(root, ['checkout', name])
    return
  endif

  echomsg 'Switched to branch: ' . name
  call s:refresh_state_for_root(root)
endfunction

function! git_changes#branch_merge(...) abort
  let root = s:repo_root()
  if empty(root)
    call s:err('not inside a Git repository')
    return
  endif

  " ":GitChangesBranchMerge" without an argument still passes an empty
  " <q-args>, so decide on the value rather than a:0.
  let arg = trim(a:0 ? a:1 : '')
  let name = !empty(arg) ? arg
        \ : trim(s:prompt_input('Merge branch: ', '',
        \       'customlist,git_changes#complete_branches'))
  if empty(name)
    echomsg 'Branch merge cancelled'
    return
  endif

  call s:merge_root(root, name)
endfunction

function! git_changes#branch_merge_abort() abort
  let root = s:repo_root()
  if empty(root)
    call s:err('not inside a Git repository')
    return
  endif

  call s:abort_merge_root(root)
endfunction

function! s:parse_hunks(lines) abort
  let hunks = []
  for line in a:lines
    if line !~# '^@@ '
      continue
    endif

    let match = matchlist(line,
          \ '^@@ -\d\+\%(,\d\+\)\? +\(\d\+\)\%(,\(\d\+\)\)\? @@')
    if empty(match)
      continue
    endif

    let start = str2nr(match[1])
    let new_count = empty(match[2]) ? 1 : str2nr(match[2])
    call add(hunks, {
          \ 'lnum': new_count > 0 ? start : max([1, start]),
          \ 'count': new_count,
          \ })
  endfor
  return hunks
endfunction

" Hunk positions for the current buffer compared with the index, so only
" unstaged and unsaved changes are included.
function! s:unstaged_hunks(root, path) abort
  let index = tempname()
  let work = tempname()
  try
    let result = s:git_run(a:root, ['show', ':' . a:path])
    let index_lines = result.ok
          \ ? map(result.out, 'substitute(v:val, "\r$", "", "")')
          \ : []
    call writefile(index_lines, index)
    call writefile(getline(1, '$'), work)

    let diff = s:git_run(a:root,
          \ ['diff', '--no-index', '--unified=0', '--no-ext-diff',
          \  '--no-color', '--', index, work])
    return s:parse_hunks(diff.out)
  finally
    call delete(index)
    call delete(work)
  endtry
endfunction

function! s:goto_chunk(delta) abort
  if &buftype !=# ''
    call s:err('current buffer is not a file')
    return
  endif

  let [root, path] = s:buffer_repo_path()
  if empty(root) || empty(path)
    call s:err('current file is not inside a Git repository')
    return
  endif

  let hunks = s:unstaged_hunks(root, path)
  if empty(hunks)
    echomsg 'No unstaged chunks: ' . path
    return
  endif

  let line = line('.')
  let target = 0
  if a:delta > 0
    for hunk in hunks
      if hunk.lnum > line
        let target = hunk.lnum
        break
      endif
    endfor
  else
    for hunk in reverse(copy(hunks))
      if hunk.lnum < line
        let target = hunk.lnum
        break
      endif
    endfor
  endif

  if target <= 0
    let message = a:delta > 0
          \ ? 'No next unstaged chunk'
          \ : 'No previous unstaged chunk'
    echomsg message
    return
  endif

  call cursor(target, 1)
  normal! zz
endfunction

function! git_changes#next_chunk() abort
  call s:goto_chunk(1)
endfunction

function! git_changes#prev_chunk() abort
  call s:goto_chunk(-1)
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
  return s:repo_relative_path(a:root, resolve(name))
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

function! s:prompt_confirm(prompt, choices, default) abort
  if exists('g:git_changes_confirm_override')
    let value = g:git_changes_confirm_override
    unlet g:git_changes_confirm_override
    return type(value) == type(0) ? value : str2nr(value)
  endif
  return confirm(a:prompt, a:choices, a:default)
endfunction

" The file diff implementation lives in autoload/git_changes/file_diff.vim.
function! git_changes#diff_open(raw) abort
  call git_changes#file_diff#open(a:raw)
endfunction

function! git_changes#diff_quit() abort
  call git_changes#file_diff#quit()
endfunction

function! s:open_file_diff_for_current() abort
  call git_changes#file_diff#open_current()
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


" The blame pane lives in autoload/git_changes/blame.vim.
function! git_changes#blame() abort
  call git_changes#blame#open()
endfunction


" ============================================================================
" Module bridge
"
" Small public surface for the lazily loaded statusline and blame modules.
" Keeping the implementations here avoids duplicating path, job, and buffer
" helpers in every module.
" ============================================================================

function! git_changes#core_repo_root_for(dir) abort
  return s:repo_root_for(a:dir)
endfunction

function! git_changes#core_repo_root() abort
  return s:repo_root()
endfunction

function! git_changes#core_repo_relative_path(root, path) abort
  return s:repo_relative_path(a:root, a:path)
endfunction

function! git_changes#core_buffer_repo_path() abort
  return s:buffer_repo_path()
endfunction

function! git_changes#core_current_repo_path(root) abort
  return s:current_repo_path(a:root)
endfunction

function! git_changes#core_git_run(root, args) abort
  return s:git_run(a:root, a:args)
endfunction

function! git_changes#core_git_job(state, key, token_key, token, args, callback) abort
  call s:git_job(a:state, a:key, a:token_key, a:token, a:args, a:callback)
endfunction

function! git_changes#core_job_stop(state, key) abort
  call s:job_stop(a:state, a:key)
endfunction

function! git_changes#core_err(msg) abort
  call s:err(a:msg)
endfunction

function! git_changes#core_new_scratch(name, filetype) abort
  return s:new_scratch(a:name, a:filetype)
endfunction

function! git_changes#core_set_lines(buf, lines) abort
  return s:set_lines(a:buf, a:lines)
endfunction

function! git_changes#core_buf_linecount(buf) abort
  return s:buf_linecount(a:buf)
endfunction

function! git_changes#core_win_exists(winid) abort
  return s:win_exists(a:winid)
endfunction

function! git_changes#core_cmd_rhs(rhs) abort
  return s:cmd_rhs(a:rhs)
endfunction

function! git_changes#core_git(root, args) abort
  return s:git(a:root, a:args)
endfunction

function! git_changes#core_git_do(root, args) abort
  return s:git_do(a:root, a:args)
endfunction

function! git_changes#core_apply_diff(state, ctx) abort
  call s:apply_diff(a:state, a:ctx)
endfunction

function! git_changes#core_commit_index(root, ...) abort
  return a:0 ? s:commit_index(a:root, a:1) : s:commit_index(a:root)
endfunction

function! git_changes#core_cur_state() abort
  return s:cur_state()
endfunction

function! git_changes#core_current_file_index(state) abort
  return s:current_file_index(a:state)
endfunction

function! git_changes#core_diff_on(state) abort
  call s:diff_on(a:state)
endfunction

function! git_changes#core_diff_windows(state) abort
  return s:diff_windows(a:state)
endfunction

function! git_changes#core_flush_pending(state) abort
  call s:flush_pending(a:state)
endfunction

function! git_changes#core_open_commit_editor(root, on_done) abort
  call s:open_commit_editor(a:root, a:on_done)
endfunction

function! git_changes#core_prompt_confirm(prompt, choices, default) abort
  return s:prompt_confirm(a:prompt, a:choices, a:default)
endfunction

function! git_changes#core_read_worktree(root, path) abort
  return s:read_worktree(a:root, a:path)
endfunction

function! git_changes#core_resolve_ref(root, ref) abort
  return s:resolve_ref(a:root, a:ref)
endfunction

function! git_changes#core_scroll_top(winid) abort
  call s:scroll_top(a:winid)
endfunction

function! git_changes#core_set_cursor(winid, lnum) abort
  call s:set_cursor(a:winid, a:lnum)
endfunction

function! git_changes#core_setup_diff_window() abort
  call s:setup_diff_window()
endfunction

function! git_changes#core_show_file(path, lnum) abort
  call s:show_file(a:path, a:lnum)
endfunction

function! git_changes#core_show_side_message(state, lines) abort
  call s:show_side_message(a:state, a:lines)
endfunction

function! git_changes#core_worktree_file_is_binary(root, path) abort
  return s:worktree_file_is_binary(a:root, a:path)
endfunction

function! git_changes#core_map_keys(action, rhs) abort
  call s:map_keys(a:action, a:rhs)
endfunction
