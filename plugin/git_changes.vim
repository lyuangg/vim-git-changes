if exists('g:loaded_git_changes')
  finish
endif
let g:loaded_git_changes = 1

command! -bar -nargs=* -complete=customlist,git_changes#complete_refs GitChanges call git_changes#open(<f-args>)
command! -bar GitChangesQuit   call git_changes#quit()
