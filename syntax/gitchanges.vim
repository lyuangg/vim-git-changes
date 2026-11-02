if exists('b:current_syntax')
  finish
endif

syntax match GitChangesHeader     /^#.*$/
syntax match GitChangesStatus     /^# Staged .*$/
syntax match GitChangesStatus     /^# Working tree clean$/
syntax match GitChangesAdded      /^\s*\zsA\ze\s/
syntax match GitChangesModified   /^\s*\zsM\ze\s/
syntax match GitChangesDeleted    /^\s*\zsD\ze\s/
syntax match GitChangesRenamed    /^\s*\zsR\ze\s/
syntax match GitChangesCopied     /^\s*\zsC\ze\s/
syntax match GitChangesTypeChange /^\s*\zsT\ze\s/
syntax match GitChangesUnmerged   /^\s*\zsU\ze\s/

syntax match GitChangesStagedAdded      /^\s*\zsA[·MDRCTU?]\ze\s/
syntax match GitChangesStagedModified   /^\s*\zsM[·MDRCTU?]\ze\s/
syntax match GitChangesStagedDeleted    /^\s*\zsD[·MDRCTU?]\ze\s/
syntax match GitChangesStagedRenamed    /^\s*\zsR[·MDRCTU?]\ze\s/
syntax match GitChangesStagedCopied     /^\s*\zsC[·MDRCTU?]\ze\s/
syntax match GitChangesStagedTypeChange /^\s*\zsT[·MDRCTU?]\ze\s/
syntax match GitChangesStagedUnmerged   /^\s*\zsU[·MDRCTU?]\ze\s/

syntax match GitChangesUnstagedAdded      /^\s*\zs·A\ze\s/
syntax match GitChangesUnstagedModified   /^\s*\zs·M\ze\s/
syntax match GitChangesUnstagedDeleted    /^\s*\zs·D\ze\s/
syntax match GitChangesUnstagedRenamed    /^\s*\zs·R\ze\s/
syntax match GitChangesUnstagedCopied     /^\s*\zs·C\ze\s/
syntax match GitChangesUnstagedTypeChange /^\s*\zs·T\ze\s/
syntax match GitChangesUnstagedUnmerged   /^\s*\zs·U\ze\s/

syntax match GitChangesUntracked  /^\s*\zs??\ze\s/
syntax match GitChangesSpecial    /^\(WORK\|CMP\)\ze\s/
syntax match GitChangesHash       /^\x\{7,40\}\ze\s/
syntax match GitChangesMuted      /^\s\+([^)]*)$/
syntax match GitChangesDir        /^\s*▾ .*\/$/
syntax match GitChangesBranchCurrent /^\* \S\+$/
syntax match GitChangesBranch        /^  \S\+$/

highlight default GitChangesHeader     ctermfg=Gray    guifg=#8a8a8a gui=italic
highlight default link GitChangesStatus String
highlight default GitChangesAdded      ctermfg=Green   cterm=bold guifg=#5faf5f gui=bold
highlight default GitChangesModified   ctermfg=Yellow  cterm=bold guifg=#d7af5f gui=bold
highlight default GitChangesDeleted    ctermfg=Red     cterm=bold guifg=#d75f5f gui=bold
highlight default GitChangesRenamed    ctermfg=Cyan    cterm=bold guifg=#5fafd7 gui=bold
highlight default GitChangesCopied     ctermfg=Magenta cterm=bold guifg=#d787d7 gui=bold
highlight default GitChangesTypeChange ctermfg=Blue    cterm=bold guifg=#5f87d7 gui=bold
highlight default GitChangesUnmerged   ctermfg=Red     cterm=bold guifg=#ff5f5f gui=bold,underline
highlight default GitChangesUntracked  ctermfg=Green   cterm=bold guifg=#5faf5f gui=bold
highlight default GitChangesSpecial    ctermfg=Cyan    cterm=bold guifg=#5fafd7 gui=bold
highlight default GitChangesHash       ctermfg=Cyan    guifg=#5fafd7
highlight default GitChangesMuted      ctermfg=Gray    guifg=#8a8a8a gui=italic
highlight default link GitChangesDir Directory
highlight default GitChangesBranchCurrent ctermfg=Green cterm=bold guifg=#5faf5f gui=bold
highlight default GitChangesBranch        ctermfg=Cyan  guifg=#5fafd7

highlight default link GitChangesStagedAdded      GitChangesAdded
highlight default link GitChangesStagedModified   GitChangesModified
highlight default link GitChangesStagedDeleted    GitChangesDeleted
highlight default link GitChangesStagedRenamed    GitChangesRenamed
highlight default link GitChangesStagedCopied     GitChangesCopied
highlight default link GitChangesStagedTypeChange GitChangesTypeChange
highlight default link GitChangesStagedUnmerged   GitChangesUnmerged

highlight default link GitChangesUnstagedAdded      GitChangesAdded
highlight default link GitChangesUnstagedModified   GitChangesModified
highlight default link GitChangesUnstagedDeleted    GitChangesDeleted
highlight default link GitChangesUnstagedRenamed    GitChangesRenamed
highlight default link GitChangesUnstagedCopied     GitChangesCopied
highlight default link GitChangesUnstagedTypeChange GitChangesTypeChange
highlight default link GitChangesUnstagedUnmerged   GitChangesUnmerged

let b:current_syntax = 'gitchanges'
