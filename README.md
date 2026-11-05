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
    cmd = { "GitChanges", "GitChangesQuit" },
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

### File list

| Key | Action |
| --- | --- |
| `j` / `k` | Move between files |
| `J` / `K` | Scroll the diff |
| `H` / `L` | Scroll the diff left / right |
| `Ctrl-d` / `Ctrl-u` | Scroll the diff by half a page |
| `t` | Toggle list/tree view |
| `?` | Show/hide help |
| `Esc` | Go back to the working tree changes |
| `r` | Refresh files, commits, and branches |
| `s` | Stage file |
| `u` | Unstage file |
| `S` | Stage all working tree changes (including untracked files) |
| `U` | Unstage all staged changes |
| `-` | Stage or unstage file |
| `d` | Discard unstaged changes, or delete an untracked file |
| `o` | Open the current file in a new tab (also in diff windows) |
| `yy` | Copy the absolute file path |
| `cc` | Commit staged changes |
| `C` | Commit staged changes using an editor with a status template |
| `cb` | Create a branch from the selected branch and switch to it |
| `p` | Pull |
| `P` | Push |
| `q` | Close the GitChanges tab |

### Commit list

| Key | Action |
| --- | --- |
| `j` / `k` | Move between commits |
| `J` / `K` | Scroll the diff |
| `e` | Edit an unpushed commit message |
| `l` | Load the next batch of commits when the list says `200+` |
| `yy` | Copy the full commit hash |
| `Esc` | Go back to the working tree changes |


### Branch list

| Key | Action |
| --- | --- |
| `j` / `k` | Move branch selection without changing the other panes |
| `<CR>` | Show the selected branch's commits and files |
| `co` | Check out the selected branch |
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
" Left pane width
let g:git_changes_width = 40

" Commit list height limit
let g:git_changes_commits_height = 12

" Branch list height limit
let g:git_changes_branches_height = 8

" Commits loaded per page (press l to load the next batch)
let g:git_changes_max_commits = 200

" Exclude merge commits from the commit list
let g:git_changes_exclude_merges = 1

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
| `open_file` | `o` |
| `scroll_half_down` | `<C-d>` |
| `scroll_half_up` | `<C-u>` |
| `copy_file` | `yy` |
| `copy_commit` | `yy` |
| `copy_branch` | `yy` |
| `edit_message` | `e` |
| `load_more` | `l` |
| `commit` | `cc` |
| `commit_editor` | `C` |
| `pull` | `p` |
| `push` | `P` |
| `new_branch` | `cb` |
| `branch_delete` | `d` |
| `checkout_branch` | `co` |
| `apply_branch` | `<CR>` |
| `cycle_next` | `<Tab>` |
| `cycle_prev` | `<S-Tab>` |
| `worktree` | `<Esc>` |
| `pane_files` | `1` |
| `pane_commits` | `2` |
| `pane_branches` | `3` |
| `quit` | `q` |
