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
    cmd = {
      "GitChanges",
      "GitChangesQuit",
      "GitChangesDiff",
    },
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

文件列表中的帮助默认隐藏，按 `?` 显示，再按 `?` 隐藏。

主 GitChanges 窗口和单文件 diff 窗口默认都会折叠未改动区域。按 `zR`
展开完整文件，用 `zo` / `zc` 折叠或展开当前块，或设置
`g:git_changes_fold = 0` 关闭折叠。

### 单文件 diff

```vim
" 当前文件：暂存区与工作区（即普通 git diff）
:GitChangesDiff

" 一个 ref 与工作区
:GitChangesDiff HEAD~3

" 两个 ref
:GitChangesDiff main HEAD

" 暂存区改动（HEAD 与 index）；--staged 和 --cached 等价
:GitChangesDiff --staged
:GitChangesDiff --cached

" 忽略所有空白差异 / 忽略空白数量差异
:GitChangesDiff -w
:GitChangesDiff -b

" 指定其它文件：-- 后可以带一个路径
:GitChangesDiff -- src/main.c

" 路径带空格时用单引号或反斜杠
:GitChangesDiff -- 'src/my file.c'
:GitChangesDiff -- src/my\ file.c
```

| 按键 | 操作 |
| --- | --- |
| `q` | 关闭 diff tab |
| `r` | 重新读取两侧内容 |
| `s` | stage 当前文件 |
| `u` | unstage 当前文件 |
| `D` | discard 当前文件的未暂存修改 |
| `dS` | 切换暂存区对比（`git diff --staged`） |
| `Tab` / `S-Tab` | 在两个窗口间切换 |
| `]c` / `[c` | 跳到下一个 / 上一个差异块 |
| `zo` / `zc` | 打开 / 关闭当前折叠 |
| `zR` / `zM` | 打开 / 关闭所有折叠 |

### 文件列表

| 按键 | 操作 |
| --- | --- |
| `j` / `k` | 切换文件 |
| `J` / `K` | 滚动 diff |
| `H` / `L` | 左右滚动 diff |
| `Ctrl-d` / `Ctrl-u` | 半页滚动 diff |
| `t` | 列表 / tree 样式切换 |
| `?` | 显示 / 隐藏帮助 |
| `Esc` | 回到工作区改动 |
| `r` | 刷新文件、commit 和分支 |
| `s` | stage 文件 |
| `u` | unstage 文件 |
| `S` | stage 所有工作区改动（包括未跟踪文件） |
| `U` | unstage 所有已暂存改动 |
| `-` | stage 或 unstage 文件 |
| `d` | 丢弃未暂存改动，或删除未跟踪文件 |
| `o` | 在新标签页打开当前文件 |
| `yy` | 复制文件绝对路径 |
| `cc` | commit 已暂存内容 |
| `C` | 使用编辑器提交已暂存内容（显示分支和暂存状态） |
| `cb` | 从所选分支新建分支并切换过去 |
| `p` | pull |
| `P` | push |
| `q` | 关闭 GitChanges tab |

### Commit 列表

| 按键 | 操作 |
| --- | --- |
| `j` / `k` | 切换 commit |
| `J` / `K` | 滚动 diff |
| `e` | 编辑未 push commit 的 message |
| `l` | 列表显示 `200+` 时，再加载下一批 commit |
| `yy` | 复制完整 commit hash |
| `Esc` | 回到工作区改动 |


### 分支列表

| 按键 | 操作 |
| --- | --- |
| `j` / `k` | 移动分支选择，不改变其他窗口 |
| `<CR>` | 显示所选分支的 commit 和文件 |
| `co` | checkout 所选分支 |
| `cb` | 从所选分支新建分支并切换过去 |
| `d` | 删除所选本地分支 |
| `yy` | 复制分支名 |
| `?` | 显示 / 隐藏帮助（默认隐藏） |

## 配置

```vim
" 是否折叠 diff 窗口中的未改动区域（0 = 显示完整文件）
let g:git_changes_fold = 1

" 左侧栏宽度
let g:git_changes_width = 40

" commit 列表高度上限
let g:git_changes_commits_height = 12

" 分支列表高度上限
let g:git_changes_branches_height = 8

" 每页加载多少个 commit（按 l 加载下一批）
let g:git_changes_max_commits = 200

" 是否排除 merge commit
let g:git_changes_exclude_merges = 1

" 启动时是否显示 WORK 条目
let g:git_changes_show_worktree = 1

" 默认使用 tree 样式
let g:git_changes_tree_view = 0

" commit message 正文最多显示多少行
let g:git_changes_commit_body_lines = 20

" 移动后更新 diff 的延迟毫秒数，0 表示关闭延迟
let g:git_changes_debounce_ms = 300

" 按 r 刷新前的防抖毫秒数，0 表示关闭防抖
let g:git_changes_refresh_debounce_ms = 1000

" discard 文件前是否确认
let g:git_changes_confirm_discard = 1

" 删除分支前是否确认
let g:git_changes_confirm_branch_delete = 1

" 没有 remote 时重写旧 commit 前是否确认
let g:git_changes_confirm_rewrite = 1

" 是否在左侧窗口状态栏显示编号、窗口名字和当前状态（无背景色）
let g:git_changes_statusline = 1

" 分支没有 upstream 时，push 前是否询问并设置 upstream
let g:git_changes_confirm_push_upstream = 1

" 设置 upstream 时使用的 remote（为空则用 origin 或第一个 remote）
let g:git_changes_push_remote = ''
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
| `stage_all` | `S` |
| `unstage_all` | `U` |
| `toggle_stage` | `-` |
| `file_discard` | `d` |
| `file_discard_diff` | `D` |
| `staged_view` | `dS` |
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
