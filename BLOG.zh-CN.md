# GameSave Guardian：一个 Windows 游戏存档自动备份小工具

玩游戏时最怕什么？不是打不过 Boss，而是存档坏了、误删了、同步失败了，或者某次操作之后想回到之前的状态却发现已经晚了。

`GameSave Guardian` 是一个面向 Windows 的便携式游戏存档备份工具。它可以监听指定的存档目录，在文件发生变化并稳定后，自动打包生成 zip 备份。当前默认适配的存档路径是：

```text
C:\XboxGames\GameSave\pgs
```

备份文件会保存在程序所在文件夹的 `backups` 目录中。也就是说，你把程序解压到哪里，备份就默认放在哪里，方便移动和管理。

## 项目特点

- 便携使用：下载 zip，解压后双击即可运行。
- 图形界面：普通用户优先使用 `GameSaveGuardian.cmd` 打开 GUI。
- 自动备份：监听存档目录变化，等待写入稳定后自动备份。
- 手动备份：支持一键立即备份。
- 保留策略：默认只保留最近 30 份备份，避免无限占用磁盘。
- 窗口焦点锁定：可以选择一个 Windows 窗口，并尝试让它持续保持焦点。
- 无额外依赖：基于 Windows 自带的 PowerShell 5.1，不需要 Python、Node.js 或 .NET SDK。

## 适合谁使用

这个工具适合这些场景：

- 想给游戏存档做本地历史备份。
- 不完全放心云存档，想多留一份本地保险。
- 想在尝试不同路线、选择、构筑之前留存档快照。
- 想把备份工具放在 U 盘、移动硬盘或固定工具目录中便携使用。
- 需要一个简单的窗口焦点锁定辅助功能。

它不是云同步工具，也不是存档修改器。它只负责读取指定目录，并把内容复制、压缩成 zip 备份。

## 下载与启动

从 GitHub Release 下载类似下面的文件：

```text
gamesave-guardian-v1.1.0.zip
```

解压后，双击：

```text
GameSaveGuardian.cmd
```

打开后会看到两个主要页面：

- `Backup`：管理存档备份。
- `Focus Lock`：管理窗口焦点锁定。

推荐普通用户只使用图形界面。项目里仍然保留了多个 `.cmd` / `.ps1` 脚本入口，主要是给高级用户或排查问题时使用。

## 备份功能怎么用

进入 `Backup` 页面后，可以看到：

- 当前存档源目录。
- 当前备份输出目录。
- 最近一次备份文件。
- 自动备份运行状态。

常用按钮：

- `Backup Now`：立即备份一次。
- `Start Auto Backup`：启动后台自动备份。
- `Stop Auto Backup`：停止后台自动备份。
- `Refresh`：刷新状态。
- `Open Backups`：打开备份目录。
- `Open Backup Log`：打开备份日志。

建议第一次使用时先点一次 `Backup Now`，确认能够成功生成 zip 文件。确认没有问题后，再启动 `Start Auto Backup`。

## 自动备份逻辑

工具使用 Windows 文件系统监听能力监控存档目录。

当目录内发生新增、修改、删除或重命名时，工具不会立刻备份，而是先等待一段时间。默认等待时间是 30 秒：

```json
"debounceSeconds": 30
```

这样做是为了避免游戏连续写入存档时重复打包，也能降低备份到半写入文件的概率。

备份文件名类似：

```text
GameSave_20260520_111200.zip
```

默认最多保留最近 30 份：

```json
"maxBackups": 30
```

超过数量后，旧备份会自动清理。

## 配置文件

配置文件是程序目录下的：

```text
config.json
```

默认内容：

```json
{
  "sourcePath": "C:\\XboxGames\\GameSave\\pgs",
  "backupRoot": "backups",
  "debounceSeconds": 30,
  "maxBackups": 30
}
```

字段说明：

- `sourcePath`：要备份的存档目录。
- `backupRoot`：备份输出目录。默认 `backups` 表示程序所在文件夹下的 `backups`。
- `debounceSeconds`：检测到变化后等待多少秒再备份。
- `maxBackups`：最多保留多少份备份。设置为 `0` 表示不自动删除旧备份。

如果你修改了配置，并且自动备份已经启动，请先停止自动备份，再重新启动，让新配置生效。

## 窗口焦点锁定功能

除了备份，项目还带了一个可选的 `Focus Lock` 功能。

它可以列出当前可见的 Windows 窗口。选择一个窗口后，工具会在后台尝试让这个窗口保持前台焦点。

使用方式：

1. 打开 `GameSaveGuardian.cmd`。
2. 切换到 `Focus Lock` 页面。
3. 点击 `Refresh Windows`。
4. 选择一个窗口。
5. 点击 `Start Focus Lock`。
6. 不需要时点击 `Stop Focus Lock`。

这个功能会主动把选中的窗口拉回前台，所以可能影响你操作其他程序。使用完一定记得停止。

## 高级脚本入口

如果不想打开 GUI，也可以直接使用这些脚本：

```text
BackupNow.cmd
StartBackup.cmd
StopBackup.cmd
StatusBackup.cmd
StartFocusLock.cmd
StopFocusLock.cmd
StatusFocusLock.cmd
```

一般用户不需要关心这些文件。它们主要用于命令行操作、排查问题，或者和其他自动化工具配合。

## 日志和运行状态

工具会在程序目录下创建这些运行目录：

```text
backups\
logs\
runtime\
```

其中：

- `backups\`：存放 zip 备份。
- `logs\backup.log`：存档备份日志。
- `logs\focus-lock.log`：焦点锁定日志。
- `runtime\watcher.pid`：自动备份后台进程状态。
- `runtime\focus-lock.pid`：焦点锁定后台进程状态。

如果遇到问题，优先查看 `logs` 目录里的日志。

## 注意事项

1. 备份目录不要放进存档源目录里面。

   如果备份目录位于源目录内，监听器可能会监听到自己生成的 zip，造成循环触发。

2. 如果存档目录没有权限读取，请用管理员身份运行。

   某些 Xbox 或商店游戏目录可能权限比较严格。右键 `GameSaveGuardian.cmd`，选择“以管理员身份运行”可以解决一部分权限问题。

3. 不要在游戏正在频繁写入时立刻关闭电脑。

   工具会等待写入稳定后备份，但如果系统被直接关机，仍然可能错过最后一次变化。

4. 焦点锁定会影响正常操作。

   它会尝试把指定窗口拉回前台。如果你发现鼠标键盘操作其他窗口很别扭，先停止焦点锁定。

5. Release 包和源码仓库应该分开管理。

   源码仓库不建议提交 `backups`、`logs`、`runtime`、`dist` 或 zip 包。用户下载包应该放在 GitHub Release。

6. 第一次运行时可能遇到 Windows 安全提示。

   这是未签名脚本或压缩包常见情况。公开发布时，如果希望进一步减少提示，需要代码签名或正式安装包流程。

## 常见问题

### Windows 10 可以用吗？

可以。工具基于 Windows PowerShell 5.1，Windows 10 默认自带。

### 需要安装 PowerShell 7 吗？

不需要。Windows 自带的 PowerShell 5.1 就可以运行。

### 会修改我的游戏存档吗？

不会。工具只读取 `sourcePath` 指向的目录，把内容复制到临时目录，再压缩成 zip。

### 备份文件能放到别的盘吗？

可以。修改 `config.json` 里的 `backupRoot`，例如：

```json
"backupRoot": "E:\\GameSaveBackups"
```

### 状态显示 `RunningUnverified` 是什么意思？

这通常表示当前 PowerShell 权限不允许读取后台进程命令行。一般不影响使用，停止按钮仍然可以停止对应后台任务。

### 可以做成单文件 exe 吗？

理论上可以，但第一版没有选择这个方案。原因是 PowerShell 打包成 exe 后，可能遇到 SmartScreen 提示、杀毒软件误报、签名和运行目录处理等问题。

目前采用便携 zip + GUI 启动器的方式，更透明，也更容易排查问题。

## 结语

`GameSave Guardian` 的定位很简单：给游戏存档多一层本地保险。

它不追求复杂，也不替代云存档。它更像一个放在旁边的小工具：需要时启动，默默保存历史备份；出问题时，至少还有一个可以回退的 zip。

如果你经常玩有长流程、高投入、容易产生分支选择的游戏，这类小工具会非常有安全感。
