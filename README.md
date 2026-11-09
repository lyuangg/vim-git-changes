# vim-git-changes

A Vim/Neovim plugin for browsing Git changes.

[中文说明](README.zh-CN.md)

## Requirements

- Vim 8.1+ or Neovim
- `git` available in `PATH`

## Installation

### vim-plug

```vim
Plug 'lyuangg/vim-git-changes'
```

### lazy.nvim / LazyVim

Add a plugin spec, for example in `lua/plugins/vim-git-changes.lua`:

```lua
return {
  {
    "lyuangg/vim-git-changes",
    cmd = {
      "GitChanges",
      "GitChangesQuit",
      "GitChangesDiff",
      "GitChangesDiffQuit",
      "GitChangesCommit",
      "GitChangesPull",
      "GitChangesPush",
      "GitChangesBlame",
      "GitChangesStage",
      "GitChangesUnstage",
      "GitChangesDiscard",
    },
  },
}
```

No `setup()` call is required.

### Manual

```sh
cp -r vim-git-changes ~/.vim/pack/plugins/start/vim-git-changes
```

Neovim:

```sh
cp -r vim-git-changes ~/.local/share/nvim/site/pack/plugins/start/vim-git-changes
```

## Usage

```vim
" Working tree changes
:GitChanges

" One ref vs current HEAD
:GitChanges main
:GitChanges v1.0
:GitChanges HEAD~3

" Two refs
:GitChanges main feature
:GitChanges v1.0 v2.0
```

Help is hidden by default in the file list. Press `?` to show it and `?` again to hide it.

Diff panes fold unchanged blocks by default, both in the main browser and in
the file diff views. Press `zR` to show the full files, use `zo` / `zc` to
toggle one fold, or set `g:git_changes_fold = 0` to keep everything expanded.

### Git commands

```vim
" Stage, unstage, or discard the current file (or an optional path)
:GitChangesStage
:GitChangesStage src/main.c
:GitChangesUnstage
:GitChangesDiscard
:GitChangesDiscard src/main.c

" Commit staged changes; asks for a message unless one is given
:GitChangesCommit
:GitChangesCommit fix typo in README

" Edit the message in a new tab, then :w or :x to commit
:GitChangesCommit -e

" Pull or push the current branch
:GitChangesPull
:GitChangesPush

" Create and switch to a new branch
:GitChangesBranchCreate feature

" Switch to an existing branch
:GitChangesBranchCheckout main

" Merge a branch into the current branch
:GitChangesBranchMerge feature

" Abort an in-progress merge (for example after a conflict)
:GitChangesBranchMergeAbort

" Jump to the next or previous unstaged chunk in the current file
:GitChangesNextChunk
:GitChangesPrevChunk
```

### Statusline

```vim
set statusline+=%{GitChangesStatusline()}
```

For the blame of the current line:

```vim
set statusline+=%{GitChangesBlameLine()}
```

The default format is `author date`; set `g:git_changes_blame_line_format` to
change it (`%h` short hash, `%a` author, `%e` email, `%d` date, `%s` summary).
`git_changes#blame_line_info()` returns a dict with `sha`, `author`, `email`,
`date`, and `summary`.

`GitChangesBlameLine()` is asynchronous and safe for statuslines: it returns
the cached value immediately and refreshes it with a background job, then
redraws the statusline. The first call after a change may be empty for a moment.
Use `GitChangesBlameLineSync()` (or `git_changes#blame_line()`) when you need a
value synchronously.

### Blame

```vim
" Show git blame for the current file in a window on the left
:GitChangesBlame
```

### File diff

```vim
" Current file: index vs working tree (plain git diff)
:GitChangesDiff

" One ref vs working tree
:GitChangesDiff HEAD~3

" Two refs
:GitChangesDiff main HEAD

" Staged changes (HEAD vs index); --staged and --cached are synonyms
:GitChangesDiff --staged
:GitChangesDiff --cached

" Ignore all whitespace changes / changes in whitespace amount
:GitChangesDiff -w
:GitChangesDiff -b

" Another file: an optional path after --
:GitChangesDiff -- src/main.c

" Paths with spaces: use single quotes or a backslash
:GitChangesDiff -- 'src/my file.c'
:GitChangesDiff -- src/my\ file.c
```

| Key | Action |
| --- | --- |
| `]c` / `[c` | Jump to the next / previous hunk |
| `zo` / `zc` | Open / close a fold |
| `zR` / `zM` | Open / close all folds |
| `q` | Close the diff tab |
| `r` | Refresh the diff |
| `s` / `u` / `-` | Stage / unstage / toggle the file (read-only panes) |
| `D` | Discard unstaged changes (read-only panes) |
| `dS` | Toggle the staged view (read-only panes) |
| `cc` / `C` | Commit, or commit with an editor (read-only panes) |
| `o` | Open the file in a tab (read-only panes) |
| `Tab` / `S-Tab` | Move to the new / old pane (read-only panes) |

When comparing two refs, the file diff is read-only: stage, discard, commit, and
open-file actions are unavailable.

### File list

| Key | Action |
| --- | --- |
| `j` / `k` | Move between files |
| `J` / `K` | Scroll the diff |
| `]c` / `[c` | Jump to the next / previous diff change |
| `H` / `L` | Scroll the diff left / right |
| `4` | Jump to the diff pane |
| `t` | Toggle list/tree view |
| `?` | Show/hide help |
| `Esc` | Go back to the working tree changes |
| `r` | Refresh files, commits, and branches (also in diff panes) |
| `s` | Stage file |
| `u` | Unstage file |
| `S` | Stage all working tree changes (including untracked files) |
| `U` | Unstage all staged changes |
| `-` | Stage or unstage file |
| `d` | Discard unstaged changes, or delete an untracked file |
| `o` | Open the current file in a new tab (also in diff windows) |
| `gd` | Open the editable file diff for the selected file (also in diff panes) |
| `yy` | Copy the absolute file path |
| `cc` | Commit staged changes |
| `C` | Commit staged changes using an editor with a status template |
| `cb` | Create a branch from the selected branch and switch to it |
| `p` | Pull |
| `P` | Push |
| `gs` | Open the main GitChanges view |
| `q` | Close the GitChanges tab |

### Commit list

| Key | Action |
| --- | --- |
| `j` / `k` | Move between commits |
| `J` / `K` | Scroll the diff |
| `e` | Edit an unpushed commit message |
| `L` | Load the next batch of commits when the list says `200+` |
| `yy` | Copy the full commit hash |
| `Esc` | Go back to the working tree changes |


### Branch list

| Key | Action |
| --- | --- |
| `j` / `k` | Move branch selection without changing the other panes |
| `<CR>` | Show the selected branch's commits and files |
| `co` | Check out the selected branch |
| `M` | Merge the selected branch into the current branch |
| `A` | Abort an in-progress merge |
| `cb` | Create a branch from the selected branch and switch to it |
| `d` | Delete the selected local branch |
| `yy` | Copy the branch name |
| `?` | Show/hide help (hidden by default) |

### Status messages

Refresh, pull, and push show progress in the Vim command line (the message area
at the bottom of the screen); `:messages` keeps the history. Results such as
`Already up to date` or `Pushed to origin/main` stay visible until the next
operation. The left pane statuslines only show each pane's name and a summary of
what it displays, so they never hide progress behind a stale status.

If `P` is pressed on a branch without an upstream, the plugin asks whether to
push it to the preferred remote (usually `origin/<branch>`) and set the
upstream, instead of failing with
`fatal: The current branch ... has no upstream branch`. When no remote is
configured, push fails with `Cannot push: no remote configured`.

## Configuration

```vim
" Fold unchanged blocks in diff panes (0 = show full files)
let g:git_changes_fold = 1

" Left pane width
let g:git_changes_width = 40

" Format for GitChangesBlameLine() (%h %a %e %d %s)
let g:git_changes_blame_line_format = '%a %d'

" Statusline debounce delay in ms (0 = immediate)
let g:git_changes_statusline_delay = 500

" Marker shown when the current file has unstaged changes (empty disables)
let g:git_changes_statusline_unstaged = '*'

" How often the unstaged marker is refreshed, in ms
let g:git_changes_statusline_unstaged_interval = 1000

" Blame pane width
let g:git_changes_blame_width = 40

" Commit list height limit
let g:git_changes_commits_height = 12

" Branch list height limit
let g:git_changes_branches_height = 8

" Commits loaded per page (press L to load the next batch)
let g:git_changes_max_commits = 200

" Exclude merge commits from the commit list (0 = show them)
let g:git_changes_exclude_merges = 0

" Show the WORK entry on startup
let g:git_changes_show_worktree = 1

" Use tree view by default
let g:git_changes_tree_view = 0

" Maximum commit message body lines to show
let g:git_changes_commit_body_lines = 20

" Delay before updating the diff after moving (ms, 0 disables)
let g:git_changes_debounce_ms = 300

" Delay before refreshing after r (ms, 0 disables)
let g:git_changes_refresh_debounce_ms = 1000

" Confirm before discarding a file
let g:git_changes_confirm_discard = 1

" Confirm before deleting a branch
let g:git_changes_confirm_branch_delete = 1

" Confirm before merging a branch (0 = merge immediately)
let g:git_changes_confirm_branch_merge = 1

" Confirm before rewriting an older commit without a remote
let g:git_changes_confirm_rewrite = 1

" Show each left pane's number, name and state in its statusline
" (the statusline has no background color)
let g:git_changes_statusline = 1

" Ask before pushing a branch that has no upstream and setting one
let g:git_changes_confirm_push_upstream = 1

" Remote used when setting an upstream (empty: origin, or the first remote)
let g:git_changes_push_remote = ''
```

### Keymaps

To disable every plugin shortcut:

```vim
let g:git_changes_keymaps_enabled = 0
```

Customize individual actions:

```vim
let g:git_changes_keymaps = {
  \ 'open_file': 'O',
  \ 'toggle_stage': '',
  \ 'quit': '<C-q>',
  \ }
```

| Action | Default |
| --- | --- |
| `toggle_tree` | `t` |
| `refresh` | `r` |
| `stage` | `s` |
| `unstage` | `u` |
| `stage_all` | `S` |
| `unstage_all` | `U` |
| `toggle_stage` | `-` |
| `file_discard` | `d` |
| `file_discard_diff` | `D` |
| `staged_view` | `dS` |
| `open_file` | `o` |
| `diff_file` | `gd` |
| `hunk_next` | `]c` |
| `hunk_prev` | `[c` |
| `copy_file` | `yy` |
| `copy_commit` | `yy` |
| `copy_branch` | `yy` |
| `edit_message` | `e` |
| `load_more` | `L` |
| `commit` | `cc` |
| `commit_editor` | `C` |
| `open_main` | `gs` |
| `pull` | `p` |
| `push` | `P` |
| `new_branch` | `cb` |
| `branch_delete` | `d` |
| `checkout_branch` | `co` |
| `merge_branch` | `M` |
| `merge_abort` | `A` |
| `apply_branch` | `<CR>` |
| `cycle_next` | `<Tab>` |
| `cycle_prev` | `<S-Tab>` |
| `worktree` | `<Esc>` |
| `pane_files` | `1` |
| `pane_commits` | `2` |
| `pane_branches` | `3` |
| `pane_diff` | `4` |
| `quit` | `q` |
