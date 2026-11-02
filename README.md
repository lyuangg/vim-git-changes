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

Run `:GitChangesQuit` or press `<leader>gq` to close the tab.

Help is hidden by default in the file list. Press `?` to show it and `?` again to hide it.

### File list

| Key | Action |
| --- | --- |
| `j` / `k` | Move between files |
| `J` / `K` | Scroll the diff |
| `t` | Toggle list/tree view |
| `?` | Show/hide help |
| `r` | Refresh status |
| `s` | Stage file |
| `u` | Unstage file |
| `-` | Stage or unstage file |
| `d` | Discard unstaged changes, or delete an untracked file |
| `yy` | Copy the absolute file path |
| `c` | Commit staged changes |
| `p` | Pull |
| `P` | Push |

Stage, unstage, discard, commit, pull, and push are available for the `WORK` entry.

### Commit list

| Key | Action |
| --- | --- |
| `j` / `k` | Move between commits |
| `J` / `K` | Scroll the diff |

### Branch list

| Key | Action |
| --- | --- |
| `j` / `k` | Move branch selection without changing the other panes |
| `<CR>` | Show the selected branch's commits and files |
| `cc` | Check out the selected branch |
| `n` | Create a branch from the selected branch and switch to it |
| `d` | Delete the selected local branch |
| `yy` | Copy the branch name |

Use `Ctrl-w j` / `Ctrl-w k` to move between the file, commit, and branch panes. Press `Tab` in any of the three left panes to cycle focus among them.

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
```
