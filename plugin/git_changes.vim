if exists('g:loaded_git_changes')
  finish
endif
let g:loaded_git_changes = 1

command! -bar -nargs=* -complete=customlist,git_changes#complete_refs GitChanges call git_changes#open(<f-args>)
command! -bar GitChangesQuit   call git_changes#quit()
command! -bar -nargs=* -complete=customlist,git_changes#complete_diff GitChangesDiff
      \ call git_changes#diff_open(<q-args>)
command! -nargs=? GitChangesCommit call git_changes#commit(<q-args>)
command! -bar GitChangesPull call git_changes#pull()
command! -bar GitChangesPush call git_changes#push()
