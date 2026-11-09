if exists('b:current_syntax')
  finish
endif

syntax match GitChangesHeader     /^#.*$/
syntax match GitChangesStatus     /^# Staged .*$/ contains=GitChangesStagedCount,GitChangesUnstagedCount,GitChangesUntrackedCount
syntax match GitChangesStatus     /^# Working tree clean$/ contains=GitChangesStagedCount,GitChangesUnstagedCount,GitChangesUntrackedCount
syntax match GitChangesStagedCount    /^# Staged \zs\d\+/ contained
syntax match GitChangesUnstagedCount  /Unstaged \zs\d\+/ contained
syntax match GitChangesUntrackedCount /Untracked \zs\d\+/ contained
syntax match GitChangesAdded      /^\s*\zsA\ze\s/
syntax match GitChangesModified   /^\s*\zsM\ze\s/
syntax match GitChangesDeleted    /^\s*\zsD\ze\s/
syntax match GitChangesRenamed    /^\s*\zsR\ze\s/
syntax match GitChangesCopied     /^\s*\zsC\ze\s/
syntax match GitChangesTypeChange /^\s*\zsT\ze\s/
syntax match GitChangesUnmerged   /^\s*\zsU\ze\s/

syntax match GitChangesStaged       /^\s*\zs[A-Z]\ze[·A-Z?]/ nextgroup=GitChangesUnstagedTail
syntax match GitChangesUnstagedTail /[A-Z?]\ze\s/ contained
syntax match GitChangesUnstaged     /^\s*·\zs[A-Z?]\ze\s/
syntax match GitChangesUnmerged     /^\s*\zs\%(UU\|AA\|DD\)\ze\s/
syntax match GitChangesUntracked    /^\s*\zs??\ze\s/
syntax match GitChangesSpecial    /^..\zs\(WORK\|CMP\)\ze\s/
syntax match GitChangesHash       /^..\zs\x\{7,40\}\ze\s/
syntax match GitChangesUnpushed   /^\zs↑/
syntax match GitChangesMuted      /^\s\+([^)]*)$/
syntax match GitChangesDir        /^\s*▾ .*\/$/
syntax match GitChangesBranchCurrent /^\* \S\+\%( \%(↑\d\+\|↓\d\+\|✗\)\)*\%( \[[^\]]*\]\)\?$/ contains=GitChangesBranchAhead,GitChangesBranchBehind,GitChangesBranchGone,GitChangesBranchWorktree
syntax match GitChangesBranch        /^  \S\+\%( \%(↑\d\+\|↓\d\+\|✗\)\)*\%( \[[^\]]*\]\)\?$/ contains=GitChangesBranchAhead,GitChangesBranchBehind,GitChangesBranchGone,GitChangesBranchWorktree
syntax match GitChangesBranchAhead   /↑\d\+/ contained
syntax match GitChangesBranchBehind  /↓\d\+/ contained
syntax match GitChangesBranchGone    /✗/ contained
syntax match GitChangesBranchWorktree /\[[^\]]*\]/ contained

highlight default GitChangesHeader     ctermfg=Gray    guifg=#8a8a8a gui=italic
highlight default link GitChangesStatus String
highlight default GitChangesAdded      ctermfg=Green   cterm=bold guifg=#5faf5f gui=bold
highlight default GitChangesModified   ctermfg=Yellow  cterm=bold guifg=#d7af5f gui=bold
highlight default GitChangesDeleted    ctermfg=Red     cterm=bold guifg=#d75f5f gui=bold
highlight default GitChangesRenamed    ctermfg=Cyan    cterm=bold guifg=#5fafd7 gui=bold
highlight default GitChangesCopied     ctermfg=Magenta cterm=bold guifg=#d787d7 gui=bold
highlight default GitChangesTypeChange ctermfg=Blue    cterm=bold guifg=#5f87d7 gui=bold
highlight default GitChangesUnmerged   ctermfg=Red     cterm=bold guifg=#ff5f5f gui=bold,underline
highlight default GitChangesStaged     ctermfg=Green   cterm=bold guifg=#5faf5f gui=bold
highlight default GitChangesUnstaged   ctermfg=Red     cterm=bold guifg=#d75f5f gui=bold
highlight default link GitChangesUnstagedTail GitChangesUnstaged
highlight default link GitChangesStagedCount GitChangesStaged
highlight default link GitChangesUnstagedCount GitChangesUnstaged
highlight default link GitChangesUntrackedCount GitChangesUnstaged
highlight default GitChangesUntracked  ctermfg=Red     cterm=bold guifg=#d75f5f gui=bold
highlight default GitChangesSpecial    ctermfg=Cyan    cterm=bold guifg=#5fafd7 gui=bold
highlight default GitChangesHash       ctermfg=Cyan    guifg=#5fafd7
highlight default GitChangesUnpushed   ctermfg=Yellow  cterm=bold guifg=#d7af5f gui=bold
highlight default GitChangesMuted      ctermfg=Gray    guifg=#8a8a8a gui=italic
highlight default link GitChangesDir Directory
highlight default GitChangesBranchCurrent ctermfg=Green cterm=bold guifg=#5faf5f gui=bold
highlight default GitChangesBranch        ctermfg=Cyan  guifg=#5fafd7
highlight default GitChangesBranchAhead   ctermfg=Yellow cterm=bold guifg=#d7af5f gui=bold
highlight default GitChangesBranchBehind  ctermfg=Yellow cterm=bold guifg=#d7af5f gui=bold
highlight default GitChangesBranchGone    ctermfg=Red    cterm=bold guifg=#d75f5f gui=bold
highlight default link GitChangesBranchWorktree GitChangesMuted

let b:current_syntax = 'gitchanges'
