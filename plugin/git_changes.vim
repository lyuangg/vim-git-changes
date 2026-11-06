if exists('g:loaded_git_changes')
  finish
endif
let g:loaded_git_changes = 1

function! GitChangesStatusline() abort
  return git_changes#statusline()
endfunction

function! GitChangesBlameLine() abort
  return git_changes#blame_line_async()
endfunction

function! GitChangesBlameLineSync() abort
  return git_changes#blame_line()
endfunction

function! GitChangesBlameLineInfo() abort
  return git_changes#blame_line_info()
endfunction

function! GitChangesBlameLineAsync() abort
  return git_changes#blame_line_async()
endfunction

command! -bar -nargs=* -complete=customlist,git_changes#complete_refs GitChanges call git_changes#open(<f-args>)
command! -bar GitChangesQuit   call git_changes#quit()
command! -bar GitChangesDiffQuit call git_changes#diff_quit()
command! -bar -nargs=* -complete=customlist,git_changes#complete_diff GitChangesDiff
      \ call git_changes#diff_open(<q-args>)
command! -nargs=? -complete=customlist,git_changes#complete_commit GitChangesCommit
      \ call git_changes#commit(<q-args>)
command! -bar GitChangesPull call git_changes#pull()
command! -bar GitChangesPush call git_changes#push()
command! -nargs=? GitChangesBranchCreate call git_changes#branch_create(<q-args>)
command! -nargs=? -complete=customlist,git_changes#complete_branches
      \ GitChangesBranchCheckout call git_changes#branch_checkout(<q-args>)
command! -nargs=? -complete=customlist,git_changes#complete_branches
      \ GitChangesBranchMerge call git_changes#branch_merge(<q-args>)
command! -bar GitChangesBranchMergeAbort call git_changes#branch_merge_abort()
command! -bar GitChangesNextChunk call git_changes#next_chunk()
command! -bar GitChangesPrevChunk call git_changes#prev_chunk()
command! -bar GitChangesBlame call git_changes#blame()
command! -nargs=? -complete=file GitChangesStage call git_changes#stage(<q-args>)
command! -nargs=? -complete=file GitChangesUnstage call git_changes#unstage(<q-args>)
command! -nargs=? -complete=file GitChangesDiscard call git_changes#discard(<q-args>)
