" GitChangesBlame: a read-only pane on the left of the current file with one
" blame line per file line. Both windows scroll and move together; q closes
" the pane. Kept in its own module because it is independent from the browser.

let s:sid = expand('<SID>')

" Start git blame in the background. The pane is created first with empty
" lines, so opening it does not block on Git.
function! s:start_blame_job(info, contents) abort
  let args = ['-c', 'color.ui=false', '-c', 'blame.coloring=none',
        \ '-c', 'blame.blankBoundary=false', 'blame', '--show-number']
  if !empty(a:contents)
    call extend(args, ['--contents', a:contents])
  endif
  call extend(args, ['--', a:info.path])

  let fake = {
        \ 'files_buf': a:info.buf,
        \ 'root': a:info.root,
        \ 'blame_pane_tok': 1,
        \ }
  let a:info.state = fake
  call git_changes#core_git_job(fake, 'blame_pane', 'blame_pane_tok', 1, args,
        \ function('s:on_blame_job', [a:info]))
endfunction

function! s:on_blame_job(info, result) abort
  let info = a:info
  if !empty(get(info, 'contents', ''))
    call delete(info.contents)
    let info.contents = ''
  endif
  if !bufexists(get(info, 'buf', -1))
        \ || !git_changes#core_win_exists(get(info, 'win', 0))
    return
  endif

  let lines = copy(a:result.out)
  let target = git_changes#core_buf_linecount(get(info, 'file_buf', -1))
  if target < 1
    let target = 1
  endif
  if empty(lines) && target > 1
    call git_changes#core_err('git blame failed')
    let lines = ['git blame failed']
  endif
  while len(lines) < target
    call add(lines, '')
  endwhile
  if len(lines) > target
    call remove(lines, target, -1)
  endif

  call git_changes#core_set_lines(info.buf, lines)
endfunction

function! s:blame_cleanup(...) abort
  let info = a:0 ? a:1 : get(b:, 'git_changes_blame', {})
  if empty(info)
    return
  endif

  if !empty(get(info, 'state', {}))
    call git_changes#core_job_stop(info.state, 'blame_pane')
  endif
  if !empty(get(info, 'contents', ''))
    call delete(info.contents)
    let info.contents = ''
  endif
  let s:blame_cursor_sync = []

  let file_win = get(info, 'file_win', 0)
  if git_changes#core_win_exists(file_win)
    let options = [
          \ get(info, 'file_wrap', 1) ? 'wrap' : 'nowrap',
          \ get(info, 'file_scrollbind', 0) ? 'scrollbind' : 'noscrollbind',
          \ get(info, 'file_cursorbind', 0) ? 'cursorbind' : 'nocursorbind',
          \ get(info, 'file_foldenable', 1) ? 'foldenable' : 'nofoldenable',
          \ ]
    call win_execute(file_win, 'setlocal ' . join(options, ' '))
  endif

  for buf in [get(info, 'file_buf', -1), get(info, 'buf', -1)]
    if buf > 0 && bufexists(buf)
      call setbufvar(buf, 'git_changes_blame', {})
    endif
  endfor
endfunction

function! s:blame_close_info(info) abort
  if empty(a:info)
    return
  endif
  call s:blame_cleanup(a:info)

  let win = get(a:info, 'win', 0)
  if git_changes#core_win_exists(win)
    if win == win_getid()
      close
    else
      call win_execute(win, 'close')
    endif
  endif

  let buf = get(a:info, 'buf', -1)
  if bufexists(buf)
    execute 'silent! bwipeout! ' . buf
  endif
endfunction

function! s:blame_close() abort
  let info = get(b:, 'git_changes_blame', {})
  if empty(info)
    return
  endif
  call s:blame_close_info(info)
endfunction

" Match fugitive's behavior: scrollbind (not cursorbind) keeps the windows
" aligned, while the cursor line follows when focus moves between them.
let s:blame_cursor_sync = []

function! s:blame_record_cursor() abort
  let info = get(b:, 'git_changes_blame', {})
  if empty(info)
    return
  endif
  let win = win_getid()
  if win == get(info, 'file_win', 0)
    let s:blame_cursor_sync = [get(info, 'win', 0), line('.')]
  elseif win == get(info, 'win', 0)
    let s:blame_cursor_sync = [get(info, 'file_win', 0), line('.')]
  endif
endfunction

function! s:blame_apply_cursor() abort
  if empty(s:blame_cursor_sync)
    return
  endif
  let [win, lnum] = s:blame_cursor_sync
  let s:blame_cursor_sync = []
  if win_getid() != win || !git_changes#core_win_exists(win)
    return
  endif
  let pos = getpos('.')
  let pos[1] = lnum
  call setpos('.', pos)
endfunction

augroup git_changes_blame_sync
  autocmd!
  autocmd WinLeave * call s:blame_record_cursor()
  autocmd WinEnter * call s:blame_apply_cursor()
augroup END

function! git_changes#blame#open() abort
  let root = git_changes#core_repo_root()
  if empty(root)
    call git_changes#core_err('not inside a Git repository')
    return
  endif
  if &buftype !=# ''
    call git_changes#core_err('GitChangesBlame: open a file first')
    return
  endif

  let path = git_changes#core_current_repo_path(root)
  if empty(path)
    call git_changes#core_err('GitChangesBlame: the current file is not in this repository')
    return
  endif
  if !filereadable(root . '/' . path)
    call git_changes#core_err('GitChangesBlame: file does not exist: ' . path)
    return
  endif

  " Re-running the command replaces the existing blame pane.
  if !empty(get(b:, 'git_changes_blame', {}))
    call s:blame_close()
  endif

  let file_win = win_getid()
  let file_buf = bufnr('%')
  let file_wrap = &wrap
  let file_scrollbind = &l:scrollbind
  let file_cursorbind = &l:cursorbind
  let file_foldenable = &l:foldenable
  let modified = &modified
  let file_line_count = line('$')

  let contents = ''
  if modified
    let contents = tempname()
    call writefile(getline(1, '$'), contents)
  endif

  " Match fugitive: use scrollbind only, and disable folds so both windows
  " have the same visible lines.
  setlocal scrollbind nowrap nofoldenable nocursorbind
  let top = line('w0')
  let cur_line = line('.')
  let s:blame_cursor_sync = []

  leftabove vertical split
  let blame_win = win_getid()
  let blame_buf = git_changes#core_new_scratch(
        \ printf('[GitChangesBlame %d] %s', file_buf, path), '')
  call git_changes#core_set_lines(blame_buf,
        \ repeat([''], max([1, file_line_count])))

  setlocal scrollbind nowrap nofoldenable nocursorbind
  setlocal nonumber norelativenumber nolist
  setlocal signcolumn=no foldcolumn=0 nospell nomodeline
  setlocal nomodifiable
  let configured = get(g:, 'git_changes_blame_width', 40)
  if type(configured) != type(0) || configured <= 0
    let configured = 40
  endif
  execute 'vertical resize ' . max([12, configured])
  setlocal winfixwidth
  execute 'nnoremap <buffer> <silent> q '
        \ . git_changes#core_cmd_rhs(':<C-u>call ' . s:sid . 'blame_close()<CR>')

  " Align the blame pane with the file window before loading the text.
  execute top
  normal! zt
  execute cur_line
  silent! syncbind

  let info = {
        \ 'win': blame_win,
        \ 'buf': blame_buf,
        \ 'file_win': file_win,
        \ 'file_buf': file_buf,
        \ 'file_wrap': file_wrap,
        \ 'file_scrollbind': file_scrollbind,
        \ 'file_cursorbind': file_cursorbind,
        \ 'file_foldenable': file_foldenable,
        \ 'contents': contents,
        \ 'state': {},
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

  redraw
  call s:start_blame_job(info, contents)
endfunction
