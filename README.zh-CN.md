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
      "GitChangesDiffQuit",
      "GitChangesCommit",
      "GitChangesPull",
      "GitChangesPush",
      "GitChangesBlame",
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

### Git 命令

```vim
" stage / unstage / discard 当前文件，也可以带路径
:GitChangesStage
:GitChangesStage src/main.c
:GitChangesUnstage
:GitChangesDiscard
:GitChangesDiscard src/main.c

" 提交已暂存内容；不带参数时会提示输入 commit message
:GitChangesCommit
:GitChangesCommit fix typo in README

" 打开新标签页编辑 commit message，:w 或 :x 提交
:GitChangesCommit -e

" pull / push 当前分支
:GitChangesPull
:GitChangesPush

" 创建并切换到新分支
:GitChangesBranchCreate feature

" 切换到已有分支
:GitChangesBranchCheckout main

" 把指定分支合并到当前分支
:GitChangesBranchMerge feature

" 撤销正在进行的合并（例如合并冲突后）
:GitChangesBranchMergeAbort

" 跳到当前文件下一个 / 上一个未暂存的 chunk
:GitChangesNextChunk
:GitChangesPrevChunk
```

### 状态栏

```vim
set statusline+=%{GitChangesStatusline()}
```

当前行 blame：

```vim
set statusline+=%{GitChangesBlameLine()}
```

默认格式是 `作者 日期`，可用 `g:git_changes_blame_line_format` 修改
（`%h` 短 hash、`%a` 作者、`%e` 邮箱、`%d` 日期、`%s` 提交信息）。
`git_changes#blame_line_info()` 返回包含 `sha`、`author`、`email`、`date`、
`summary` 的字典。

`GitChangesBlameLine()` 默认是异步的，适合放在状态栏：立即返回缓存值，并在后台
执行 blame，完成后刷新状态栏；修改后的第一次调用可能会短暂为空。需要同步取值时
使用 `GitChangesBlameLineSync()`（或 `git_changes#blame_line()`）。

### Blame

```vim
" 在当前文件左侧打开 git blame 窗口
:GitChangesBlame
```

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
| `]c` / `[c` | 跳到下一个 / 上一个差异块 |
| `zo` / `zc` | 打开 / 关闭当前折叠 |
| `zR` / `zM` | 打开 / 关闭所有折叠 |
| `q` | 关闭 diff 标签页 |
| `r` | 刷新 diff |
| `s` / `u` / `-` | stage / unstage / 切换文件（只读面板） |
| `D` | 丢弃未暂存改动（只读面板） |
| `dS` | 切换暂存区视图（只读面板） |
| `cc` / `C` | 提交，或用编辑器提交（只读面板） |
| `o` | 在新标签页打开文件（只读面板） |
| `Tab` / `S-Tab` | 切到新 / 旧面板（只读面板） |

对比两个 ref 时，文件 diff 是只读的：stage、discard、commit 和打开文件等操作不可用。

### 文件列表

| 按键 | 操作 |
| --- | --- |
| `j` / `k` | 切换文件 |
| `J` / `K` | 滚动 diff |
| `]c` / `[c` | 跳到下一个 / 上一个 diff 改动 |
| `H` / `L` | 左右滚动 diff |
| `4` | 跳到 diff 窗口 |
| `0` | 跳到状态窗口 |
| `t` | 列表 / tree 样式切换 |
| `?` | 显示 / 隐藏帮助 |
| `Esc` | 回到工作区改动 |
| `r` | 刷新文件、commit 和分支（在 diff 面板里也可用） |
| `s` | stage 文件 |
| `u` | unstage 文件 |
| `S` | stage 所有工作区改动（包括未跟踪文件） |
| `U` | unstage 所有已暂存改动 |
| `-` | stage 或 unstage 文件 |
| `d` | 丢弃未暂存改动，或删除未跟踪文件 |
| `o` | 在新标签页打开当前文件 |
| `gd` | 打开当前文件的可编辑 diff（在 diff 面板里也可用） |
| `yy` | 复制文件绝对路径 |
| `cc` | commit 已暂存内容 |
| `C` | 使用编辑器提交已暂存内容（显示分支和暂存状态） |
| `cn` | 从所选分支新建分支并切换过去 |
| `co` | 切换到其它分支（在 commit 列表和 diff 面板里也可用） |
| `M` | 把指定分支合并到当前分支（在 commit 列表和 diff 面板里也可用） |
| `p` | pull |
| `P` | push |
| `gs` | 打开主 GitChanges 视图 |
| `q` | 关闭 GitChanges tab |

### Commit 列表

| 按键 | 操作 |
| --- | --- |
| `j` / `k` | 切换 commit |
| `J` / `K` | 滚动 diff |
| `e` | 编辑未 push commit 的 message |
| `L` | 列表显示 `200+` 时，再加载下一批 commit |
| `yy` | 复制完整 commit hash |
| `Esc` | 回到工作区改动 |


### 分支列表

| 按键 | 操作 |
| --- | --- |
| `j` / `k` | 移动分支选择，不改变其他窗口 |
| `<CR>` | 显示所选分支的 commit 和文件 |
| `Esc` | 回到工作区改动 |
| `]]` / `[[` | 在本地分支、远程分支和标签之间切换列表 |
| `co` | checkout 所选分支 |
| `M` | 把所选分支合并到当前分支 |
| `A` | 撤销正在进行的合并 |
| `cn` | 从所选分支新建分支并切换过去 |
| `d` | 删除所选本地分支 |
| `yy` | 复制分支名 |
| `?` | 显示 / 隐藏帮助（默认隐藏） |

### 状态窗口

| 按键 | 操作 |
| --- | --- |
| `q` | 关闭 GitChanges tab |
| `cc` / `C` | 提交，或用编辑器提交 |
| `co` / `M` | 切换或合并分支 |
| `cn` | 新建分支 |
| `p` / `P` | pull / push |
| `Esc` | 回到工作区改动 |
| `0` | 跳到状态窗口（任意窗口可用） |
| `1` / `2` / `3` / `4` | 跳到文件 / commit / 分支 / diff 窗口 |

默认是深色背景配浅色文字；可用下面的 `g:git_changes_statusline_colors` 修改。

## 配置

```vim
" 是否折叠 diff 窗口中的未改动区域（0 = 显示完整文件）
let g:git_changes_fold = 1

" 左侧栏宽度
let g:git_changes_width = 40

" GitChangesBlameLine() 的格式（%h %a %e %d %s）
let g:git_changes_blame_line_format = '%a %d'

" 状态栏防抖延迟毫秒数（0 = 立即更新）
let g:git_changes_statusline_delay = 500

" 当前文件有未暂存改动时显示的标记（空字符串关闭）
let g:git_changes_statusline_unstaged = '*'

" 未暂存标记的刷新间隔毫秒数
let g:git_changes_statusline_unstaged_interval = 1000

" blame 窗口宽度
let g:git_changes_blame_width = 40

" commit 列表高度上限
let g:git_changes_commits_height = 14

" 分支列表高度上限
let g:git_changes_branches_height = 10

" diff 窗口下方状态窗口的高度
let g:git_changes_status_height = 6

" GitChanges 各窗口状态栏的颜色。每个值可以是 cterm 颜色编号/名称、GUI 十六
" 进制颜色，或者同时包含两者的字典。
let g:git_changes_statusline_colors = {
      \ 'bg': {'cterm': '236', 'gui': '#2f3b4a'},
      \ 'fg': {'cterm': '253', 'gui': '#d8dee9'},
      \ 'accent': {'cterm': '221', 'gui': '#ffd75f'},
      \ }

" 每页加载多少个 commit（按 L 加载下一批）
let g:git_changes_max_commits = 200

" commit 列表中作者列的宽度（按显示宽度计算，0 = 隐藏）
let g:git_changes_author_width = 8

" 是否排除 merge commit（0 = 显示）
let g:git_changes_exclude_merges = 0

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

" 合并分支前是否确认（0 = 直接合并）
let g:git_changes_confirm_branch_merge = 1

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
| `diff_file` | `gd` |
| `hunk_next` | `]c` |
| `hunk_prev` | `[c` |
| `copy_file` | `yy` |
| `copy_commit` | `yy` |
| `copy_branch` | `yy` |
| `branch_group_next` | `]]` |
| `branch_group_prev` | `[[` |
| `edit_message` | `e` |
| `load_more` | `L` |
| `commit` | `cc` |
| `commit_editor` | `C` |
| `open_main` | `gs` |
| `pull` | `p` |
| `push` | `P` |
| `new_branch` | `cn` |
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
| `pane_status` | `0` |
| `quit` | `q` |
