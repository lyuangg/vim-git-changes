# vim-git-changes

一个 Vim/Neovim 插件，可以浏览 Git 的改动。

[English](README.md)

## 要求

- Vim 8.1+ 或 Neovim
- `PATH` 中有 `git`

## 安装

### vim-plug

```vim
Plug 'lyuangg/vim-git-changes'
```

### lazy.nvim / LazyVim

在 LazyVim 的插件配置中添加，例如 `lua/plugins/vim-git-changes.lua`：

```lua
return {
  {
    "lyuangg/vim-git-changes",
    cmd = { "GitChanges", "GitChangesQuit" },
  },
}
```

不需要调用 `setup()`。

### 手动安装

```sh
cp -r vim-git-changes ~/.vim/pack/plugins/start/vim-git-changes
```

Neovim：

```sh
cp -r vim-git-changes ~/.local/share/nvim/site/pack/plugins/start/vim-git-changes
```

## 使用

```vim
" 工作区改动
:GitChanges

" 一个 ref 与当前 HEAD 比较
:GitChanges main
:GitChanges v1.0
:GitChanges HEAD~3

" 两个 ref 比较
:GitChanges main feature
:GitChanges v1.0 v2.0
```

执行 `:GitChangesQuit` 关闭 tab。

文件列表中的帮助默认隐藏，按 `?` 显示，再按 `?` 隐藏。

### 文件列表

| 按键 | 操作 |
| --- | --- |
| `j` / `k` | 切换文件 |
| `J` / `K` | 滚动 diff |
| `Ctrl-d` / `Ctrl-u` | 半页滚动 diff |
| `t` | 列表 / tree 样式切换 |
| `?` | 显示 / 隐藏帮助 |
| `r` | 刷新状态 |
| `s` | stage 文件 |
| `u` | unstage 文件 |
| `-` | stage 或 unstage 文件 |
| `d` | 丢弃未暂存改动，或删除未跟踪文件 |
| `o` | 在新标签页打开当前文件（diff 窗口也可用） |
| `yy` | 复制文件绝对路径 |
| `c` | commit 已暂存内容 |
| `p` | pull |
| `P` | push |

stage、unstage、discard、commit、pull、push 只对 `WORK` 条目生效。

### Commit 列表

| 按键 | 操作 |
| --- | --- |
| `j` / `k` | 切换 commit |
| `J` / `K` | 滚动 diff |
| `yy` | 复制完整 commit hash |

### 分支列表

| 按键 | 操作 |
| --- | --- |
| `j` / `k` | 移动分支选择，不改变其他窗口 |
| `<CR>` | 显示所选分支的 commit 和文件 |
| `co` | checkout 所选分支 |
| `n` | 从所选分支新建分支并切换过去 |
| `d` | 删除所选本地分支 |
| `yy` | 复制分支名 |

## 配置

```vim
" 左侧栏宽度
let g:git_changes_width = 40

" commit 列表高度上限
let g:git_changes_commits_height = 12

" 分支列表高度上限
let g:git_changes_branches_height = 8

" 最多加载多少个 commit
let g:git_changes_max_commits = 200

" 是否排除 merge commit
let g:git_changes_exclude_merges = 1

" 启动时是否显示 WORK 条目
let g:git_changes_show_worktree = 1

" 默认使用 tree 样式
let g:git_changes_tree_view = 0

" commit message 正文最多显示多少行
let g:git_changes_commit_body_lines = 20

" discard 文件前是否确认
let g:git_changes_confirm_discard = 1

" 删除分支前是否确认
let g:git_changes_confirm_branch_delete = 1
```

### 快捷键

禁用全部插件快捷键：

```vim
let g:git_changes_keymaps_enabled = 0
```

自定义单个快捷键：

```vim
let g:git_changes_keymaps = {
  \ 'open_file': 'O',
  \ 'stage': 'S',
  \ 'unstage': 'U',
  \ 'toggle_stage': '',
  \ 'quit': '<C-q>',
  \ }
```

| 动作 | 默认按键 |
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
| `commit` | `c` |
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
| `quit` | 无 |
