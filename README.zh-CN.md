# GameSave Guardian 游戏存档工具

GameSave Guardian 是一个便携式 Windows 小工具，用来自动备份 Xbox 游戏存档，也可以让你选择一个窗口并持续保持焦点。

默认备份源是 `C:\XboxGames\GameSave\pgs`。备份文件会写入程序当前所在文件夹的 `backups` 目录，所以你把整个工具文件夹移动到哪里，备份目录也会跟着移动。

## 快速使用

1. 下载 release zip 并解压。
2. 双击 `GameSaveGuardian.cmd` 打开图形界面。
3. 在 `Backup` 页里启动自动备份、停止自动备份，或立即备份一次。
4. 在 `Focus Lock` 页里刷新窗口列表，选择窗口，然后启动焦点锁定。

只需要 Windows 自带的 Windows PowerShell 5.1，不需要安装 Python、Node.js、.NET SDK 或安装包。

## 图形界面功能

`GameSaveGuardian.cmd` 是推荐入口。

备份功能：

- 显示存档源目录、备份目录、最近备份和运行状态。
- 启动自动备份。
- 停止自动备份。
- 立即备份一次。
- 打开备份目录。
- 打开备份日志。

窗口焦点锁定：

- 刷新当前可见窗口列表。
- 选择一个窗口并让它保持焦点。
- 停止窗口焦点锁定。
- 查看焦点锁定状态。
- 打开焦点锁定日志。

注意：焦点锁定会主动把选中的窗口拉回前台，可能影响你操作其他窗口。不需要时请及时停止。

## 高级脚本入口

如果你不想打开图形界面，也可以直接双击这些脚本：

- `BackupNow.cmd`：立即手动备份一次。
- `StartBackup.cmd`：启动后台自动备份。
- `StopBackup.cmd`：停止后台自动备份。
- `StatusBackup.cmd`：查看备份状态。
- `StartFocusLock.cmd`：选择一个 Windows 窗口，并让它持续保持焦点。
- `StopFocusLock.cmd`：停止窗口焦点锁定。
- `StatusFocusLock.cmd`：查看窗口焦点锁定状态。

## 配置说明

配置文件是 `config.json`：

```json
{
  "sourcePath": "C:\\XboxGames\\GameSave\\pgs",
  "backupRoot": "backups",
  "debounceSeconds": 30,
  "maxBackups": 30
}
```

- `sourcePath`：要备份的存档目录。默认是 `C:\XboxGames\GameSave\pgs`。
- `backupRoot`：备份 zip 文件保存目录。默认值 `backups` 会按程序当前所在文件夹解析。
- `debounceSeconds`：检测到变化后等待多少秒再备份，避免游戏连续写入时重复备份。
- `maxBackups`：最多保留多少份最新备份。设置为 `0` 表示不自动删除旧备份。

修改配置后，如果自动备份已经启动，请先停止再重新启动，让新配置生效。

## 日志和状态

- 备份日志：`logs\backup.log`
- 焦点锁定日志：`logs\focus-lock.log`
- 自动备份 PID：`runtime\watcher.pid`
- 焦点锁定 PID：`runtime\focus-lock.pid`
- 当前焦点锁定目标：`runtime\focus-lock.target.json`

如果状态显示 `RunningUnverified`，通常是当前 PowerShell 权限不允许读取进程命令行。一般不影响使用，停止按钮仍然可以停止对应后台任务。

## 打包发布

生成便携 release zip：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\BuildRelease.ps1 -Version 1.1.0
```

输出文件：

```text
dist\gamesave-guardian-v1.1.0.zip
```

zip 会包含图形界面、脚本、配置和说明文档，不会包含 `.git`、`backups`、`logs`、`runtime`、旧版 zip 等运行产物。
