" Statusline integration and per-line blame helpers.
"
" This module is loaded lazily, so users who only put GitChangesStatusline()
" in their statusline do not load the whole GitChanges browser. Shared helpers
" live in autoload/git_changes.vim and are reached through git_changes#core_*.

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

  let result = ''
  let root = git_changes#core_repo_root_for(dir)
  if !empty(root)
    let candidate = root . '/.git'
    if isdirectory(candidate)
      let result = candidate
    elseif filereadable(candidate)
      let line = get(readfile(candidate, '', 1), 0, '')
      let gitdir = matchstr(line, '^gitdir:\s*\zs.*')
      if !empty(gitdir)
        if gitdir !~# '^/'
          let gitdir = simplify(root . '/' . gitdir)
        endif
        let result = gitdir
      endif
    endif
  endif

  let s:gitdir_cache[dir] = result
  if len(s:gitdir_cache) > 200
    call filter(s:gitdir_cache, 'v:val !=# ""')
    if len(s:gitdir_cache) > 200
      let s:gitdir_cache = {}
    endif
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

function! s:statusline_unstaged_interval() abort
  let value = get(g:, 'git_changes_statusline_unstaged_interval', 1000)
  return type(value) == type(0) && value > 0 ? value : 1000
endfunction

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
" statusline redraws stay fast. One job per repository collects the whole
" worktree status, and every buffer in that repository shares the result. This
" avoids spawning a git process per buffer (and avoids refreshing the index
" once per buffer) on every statusline tick.
function! s:statusline_unstaged(root, path) abort
  let cached = get(s:statusline_unstaged_cache, a:root, {})

  " Drop jobs whose buffer was wiped before the callback could run.
  for root in keys(s:statusline_unstaged_jobs)
    let job = s:statusline_unstaged_jobs[root]
    if !bufexists(get(job.state, 'files_buf', -1))
      call git_changes#core_job_stop(job.state, 'unstaged')
      if has_key(s:statusline_unstaged_jobs, root)
        call remove(s:statusline_unstaged_jobs, root)
      endif
    endif
  endfor

  if empty(cached)
        \ || reltimefloat(reltime(cached.time)) * 1000
        \      >= s:statusline_unstaged_interval()
    if !has_key(s:statusline_unstaged_jobs, a:root)
      call s:start_statusline_unstaged_job(a:root)
    endif
  endif

  return empty(cached) ? 0 : get(cached.files, a:path, 0)
endfunction

function! s:start_statusline_unstaged_job(root) abort
  let fake = {'files_buf': bufnr('%'), 'root': a:root, 'unstaged_tok': 1}
  let ctx = {'root': a:root, 'state': fake}
  let s:statusline_unstaged_jobs[a:root] = {'state': fake, 'ctx': ctx}
  call git_changes#core_git_job(fake, 'unstaged', 'unstaged_tok', 1,
        \ ['status', '--porcelain=v1', '--untracked-files=normal'],
        \ function('s:on_statusline_unstaged_job', [ctx]))
endfunction

" Build a path -> 1 map for paths with unstaged/untracked changes. This is a
" hot path (one call per repository per statusline tick), so parse the status
" lines directly instead of allocating a dict for every changed file.
function! s:unstaged_files(lines) abort
  let files = {}
  for line in a:lines
    if strlen(line) < 4 || strpart(line, 0, 2) ==# '!!'
      continue
    endif
    let xy = strpart(line, 0, 2)
    let rest = strpart(line, 3)
    let oldpath = ''
    if xy =~# '[RC]' && rest =~# ' -> '
      let pieces = split(rest, ' -> ', 1)
      if len(pieces) >= 2
        let oldpath = pieces[0]
        let rest = pieces[-1]
      endif
    endif
    if xy ==# '??'
          \ || (strlen(xy) >= 2 && strpart(xy, 1, 1) !=# ' ')
      let files[rest] = 1
      if !empty(oldpath)
        let files[oldpath] = 1
      endif
    endif
  endfor
  return files
endfunction

function! s:on_statusline_unstaged_job(ctx, result) abort
  let root = a:ctx.root
  let job = get(s:statusline_unstaged_jobs, root, {})
  if empty(job) || job.state isnot a:ctx.state
    return
  endif
  call remove(s:statusline_unstaged_jobs, root)

  let s:statusline_unstaged_cache[root] = {
        \ 'time': reltime(),
        \ 'files': s:unstaged_files(a:result.out),
        \ }
  if len(s:statusline_unstaged_cache) > 50
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

  let [root, path] = git_changes#core_buffer_repo_path()
  if empty(root) || empty(path)
    return ''
  endif
  return s:statusline_unstaged(root, path) ? marker : ''
endfunction

function! git_changes#statusline#text() abort
  let file = expand('%:p')
  if !empty(file)
    let file = resolve(file)
  endif
  let dir = empty(file) ? '' : fnamemodify(file, ':h')
  if empty(dir)
    let dir = getcwd()
  endif
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
  if len(s:statusline_last) > 200
    let now = reltime()
    call filter(s:statusline_last,
          \ 'reltimefloat(reltime(v:val[0], now)) < 60')
    call filter(s:statusline_text_cache, 'has_key(s:statusline_last, v:key)')
  endif
  return text
endfunction

let s:blame_line_cache = {}
let s:blame_line_jobs = {}
let s:blame_debounce = {}

" Release per-buffer caches when their buffer disappears. Without this,
" s:blame_debounce keeps an entry per edited buffer for the whole session.
function! s:clear_buffer_caches(buf) abort
  let st = get(s:blame_debounce, a:buf, {})
  if !empty(st)
    call remove(s:blame_debounce, a:buf)
    if st.timer != -1
      call timer_stop(st.timer)
    endif
  endif
  let prefix = a:buf . ':'
  call filter(s:blame_line_cache, 'stridx(v:key, prefix) != 0')
endfunction

augroup git_changes_buffer_cache
  autocmd!
  autocmd BufWipeout * call s:clear_buffer_caches(str2nr(expand('<abuf>')))
augroup END

" Clear every cache owned by this module. Called when the branch or repository
" changes, and by :GitChangesQuit when no view is left.
function! git_changes#statusline#clear() abort
  let s:gitdir_cache = {}
  let s:statusline_text_cache = {}
  let s:statusline_last = {}
  let s:statusline_unstaged_cache = {}
  if s:statusline_timer != -1
    call timer_stop(s:statusline_timer)
    let s:statusline_timer = -1
  endif
  for job in values(s:statusline_unstaged_jobs)
    call git_changes#core_job_stop(job.state, 'unstaged')
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
    call git_changes#core_job_stop(job.state, 'blame_line')
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
      " Prefix checks are much cheaper than a regex per metadata field.
      if strpart(field, 0, 7) ==# 'author '
        let author = strpart(field, 7)
      elseif strpart(field, 0, 12) ==# 'author-mail '
        let email = substitute(strpart(field, 12), '^<\(.*\)>$', '\1', '')
      elseif strpart(field, 0, 12) ==# 'author-time '
        let date = strftime('%Y-%m-%d', str2nr(strpart(field, 12)))
      elseif strpart(field, 0, 8) ==# 'summary '
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

" Cache key for one line's blame. Including the line number keeps a cursor
" move from reusing (or invalidating) another line's cached entry.
function! s:blame_key(buf, tick, lnum) abort
  return a:buf . ':' . a:tick . ':' . a:lnum
endfunction

function! s:blame_args(path, lnum, contents) abort
  let args = ['-c', 'color.ui=false', 'blame', '--line-porcelain',
        \ '-L', a:lnum . ',' . a:lnum]
  if !empty(a:contents)
    call extend(args, ['--contents', a:contents])
  endif
  call extend(args, ['--', a:path])
  return args
endfunction

" Blame a single line. Blaming the whole file just to read one line is very
" expensive on large files, so limit git to the requested line.
function! s:blame_line_entry(root, path, lnum) abort
  let buf = bufnr('%')
  let key = s:blame_key(buf, getbufvar(buf, 'changedtick', 0), a:lnum)
  let now = localtime()
  let cached = get(s:blame_line_cache, key, {})
  if !empty(cached) && now - cached.time < 5
    return cached.entry
  endif

  let contents = ''
  if &modified
    let contents = tempname()
    call writefile(getline(1, '$'), contents)
  endif

  let entry = {}
  try
    let result = git_changes#core_git_run(a:root,
          \ s:blame_args(a:path, a:lnum, contents))
    if result.ok
      let entries = s:parse_blame_entries(result.out)
      if !empty(entries)
        let entry = entries[0]
      endif
    endif
  finally
    if !empty(contents)
      call delete(contents)
    endif
  endtry

  let s:blame_line_cache[key] = {'time': now, 'entry': entry}
  if len(s:blame_line_cache) > 200
    call filter(s:blame_line_cache, 'localtime() - v:val.time < 30')
  endif
  return entry
endfunction

" Blame data for the current line: {sha, author, email, date, summary}.
function! git_changes#statusline#blame_line_info() abort
  let [root, path] = git_changes#core_buffer_repo_path()
  if empty(root) || empty(path) || !filereadable(root . '/' . path)
    return {}
  endif

  let lnum = line('.')
  if lnum < 1
    return {}
  endif
  return s:blame_line_entry(root, path, lnum)
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
function! git_changes#statusline#blame_line() abort
  let info = git_changes#statusline#blame_line_info()
  return empty(info) ? '' : s:format_blame_line(info)
endfunction

function! s:start_blame_line_job(root, path, key, lnum) abort
  let contents = ''
  if &modified
    let contents = tempname()
    call writefile(getline(1, '$'), contents)
  endif

  let args = s:blame_args(a:path, a:lnum, contents)

  let fake = {'files_buf': bufnr('%'), 'root': a:root, 'blame_tok': 1}
  let ctx = {'key': a:key, 'contents': contents, 'state': fake}
  let s:blame_line_jobs[a:key] = {'state': fake, 'ctx': ctx}
  call git_changes#core_git_job(fake, 'blame_line', 'blame_tok', 1, args,
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
        \ 'entry': empty(entries) ? {} : entries[0],
        \ }
  if len(s:blame_line_cache) > 200
    call filter(s:blame_line_cache, 'localtime() - v:val.time < 30')
  endif
  if s:statusline_mode_ok()
    silent! redrawstatus
  endif
endfunction

" Asynchronous variant for statuslines: returns cached data immediately and
" starts a background blame when the cache is missing or stale.
function! git_changes#statusline#blame_line_info_async() abort
  let [root, path] = git_changes#core_buffer_repo_path()
  if empty(root) || empty(path) || !filereadable(root . '/' . path)
    return {}
  endif

  let buf = bufnr('%')
  let lnum = line('.')
  if lnum < 1
    return {}
  endif
  let key = s:blame_key(buf, getbufvar(buf, 'changedtick', 0), lnum)
  let now = localtime()
  let cached = get(s:blame_line_cache, key, {})

  " Do not start or refresh jobs outside normal mode.
  if !s:statusline_mode_ok()
    return empty(cached) ? {} : cached.entry
  endif

  if empty(cached) || now - cached.time >= 10
    if !has_key(s:blame_line_jobs, key)
      call s:start_blame_line_job(root, path, key, lnum)
    endif
  endif

  return empty(cached) ? {} : cached.entry
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

function! git_changes#statusline#blame_line_async() abort
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

  let info = git_changes#statusline#blame_line_info_async()
  let text = empty(info) ? '' : s:format_blame_line(info)
  if !empty(info)
    let st.shown = {'key': key, 'text': text}
    let st.ready = ''
  else
    " The background job is still running; poll again on the next redraw.
    let st.ready = key
  endif
  return text
endfunction
