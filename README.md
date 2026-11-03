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
| `r` | Refresh status |
| `s` | Stage file |
| `u` | Unstage file |
| `-` | Stage or unstage file |
| `d` | Discard unstaged changes, or delete an untracked file |
| `o` | Open the current file in a new tab (also in diff windows) |
| `yy` | Copy the absolute file path |
| `c` | Commit staged changes |
| `C` | Commit staged changes using an editor with a status template |
| `p` | Pull |
| `P` | Push |
| `q` | Close the GitChanges tab |

### Commit list

| Key | Action |
| --- | --- |
| `j` / `k` | Move between commits |
| `J` / `K` | Scroll the diff |
| `e` | Edit an unpushed commit message |
| `yy` | Copy the full commit hash |

### Branch list

| Key | Action |
| --- | --- |
| `j` / `k` | Move branch selection without changing the other panes |
| `<CR>` | Show the selected branch's commits and files |
| `co` | Check out the selected branch |
| `n` | Create a branch from the selected branch and switch to it |
| `d` | Delete the selected local branch |
| `yy` | Copy the branch name |

## Configuration

```vim
" Left pane width
let g:git_changes_width = 40

" Commit list height limit
let g:git_changes_commits_height = 12

" Branch list height limit
let g:git_changes_branches_height = 8

" Maximum number of commits to load
let g:git_changes_max_commits = 200

" Exclude merge commits from the commit list
let g:git_changes_exclude_merges = 1

" Show the WORK entry on startup
let g:git_changes_show_worktree = 1

" Use tree view by default
let g:git_changes_tree_view = 0

" Maximum commit message body lines to show
let g:git_changes_commit_body_lines = 20

" Confirm before discarding a file
let g:git_changes_confirm_discard = 1

" Confirm before deleting a branch
let g:git_changes_confirm_branch_delete = 1

" Confirm before rewriting an older commit without a remote
let g:git_changes_confirm_rewrite = 1
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
  \ 'stage': 'S',
  \ 'unstage': 'U',
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
| `toggle_stage` | `-` |
| `file_discard` | `d` |
| `open_file` | `o` |
| `scroll_half_down` | `<C-d>` |
| `scroll_half_up` | `<C-u>` |
| `copy_file` | `yy` |
| `copy_commit` | `yy` |
| `copy_branch` | `yy` |
| `edit_message` | `e` |
| `commit` | `c` |
| `commit_editor` | `C` |
| `pull` | `p` |
| `push` | `P` |
| `new_branch` | `n` |
| `branch_delete` | `d` |
| `checkout_branch` | `co` |
| `apply_branch` | `<CR>` |
| `cycle_next` | `<Tab>` |
| `cycle_prev` | `<S-Tab>` |
| `pane_files` | `1` |
| `pane_commits` | `2` |
| `pane_branches` | `3` |
| `diff_left` | `H` |
| `diff_right` | `L` |
| `quit` | `q` |
