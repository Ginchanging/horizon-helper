# 一个为 horizon 设计的小工具

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
- 游戏挂机：可以选择按键循环模式，按脚本逻辑发送 `Enter` 和 `x`，每 10 秒按一次 `Enter`，或执行一套菜单宏。
- 车辆自动化：提供 `AutoBuyCar` 和 `FindNewSubaru` 两个独立自动化流程，可配置循环次数。
- 无额外依赖：基于 Windows 自带的 PowerShell 5.1，不需要 Python、Node.js 或 .NET SDK。

## 适合谁使用

这个工具适合这些场景：

- 想给游戏存档做本地历史备份。
- 不完全放心云存档，想多留一份本地保险。
- 想在尝试不同路线、选择、构筑之前留存档快照。
- 想把备份工具放在 U 盘、移动硬盘或固定工具目录中便携使用。
- 需要一个简单的窗口焦点锁定辅助功能。
- 需要一个简单的游戏挂机按键循环。
- 需要重复执行买车或筛选“全新 1998 斯巴鲁”这类菜单操作。

它不是云同步工具，也不是存档修改器。它只负责读取指定目录，并把内容复制、压缩成 zip 备份。

## 下载与启动

从 GitHub Release 下载类似下面的文件：

```text
gamesave-guardian-v1.4.0.zip
```

解压后，双击：

```text
GameSaveGuardian.cmd
```

打开后会看到四个主要页面：

- `Backup`：管理存档备份。
- `Focus Lock`：管理窗口焦点锁定。
- `AFK`：管理游戏挂机按键循环。
- `Automation`：管理车辆自动化流程。

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
  "maxBackups": 30,
  "afk": {
    "startupDelaySeconds": 5,
    "keyTapHoldMilliseconds": 50,
    "inputMethod": "SendKeys",
    "sequence": {
      "enterDelaySeconds": 55,
      "xDelayMilliseconds": 500,
      "loopDelaySeconds": 10
    },
    "enterEvery10s": {
      "delaySeconds": 10
    },
    "macroCombo": {
      "cycleDelaySeconds": 20,
      "steps": [
        { "key": "Esc", "waitMilliseconds": 2000 },
        { "key": "W", "waitMilliseconds": 500 },
        { "key": "Enter", "waitMilliseconds": 500 }
      ]
    }
  },
  "automation": {
    "startupDelaySeconds": 5,
    "keyTapHoldMilliseconds": 50,
    "inputMethod": "SendKeys",
    "autoBuyCar": {
      "loopCount": 1,
      "betweenLoopsMilliseconds": 1000,
      "steps": [
        { "key": "Space", "waitMilliseconds": 1000 },
        { "key": "Down", "waitMilliseconds": 500 },
        { "key": "Enter", "waitMilliseconds": 1000 },
        { "key": "Enter", "waitMilliseconds": 1000 },
        { "key": "Enter", "waitMilliseconds": 0 }
      ]
    },
    "findNewSubaru": {
      "loopCount": 1,
      "maxSearchAttempts": 50,
      "searchKey": "Left",
      "searchSettleMilliseconds": 500,
      "afterSelectDelayMilliseconds": 2000,
      "targetKeywords": ["1998", "斯巴鲁"],
      "newBadgeText": "全新",
      "requireTargetConfirmation": true
    }
  }
}
```

字段说明：

- `sourcePath`：要备份的存档目录。
- `backupRoot`：备份输出目录。默认 `backups` 表示程序所在文件夹下的 `backups`。
- `debounceSeconds`：检测到变化后等待多少秒再备份。
- `maxBackups`：最多保留多少份备份。设置为 `0` 表示不自动删除旧备份。
- `afk.startupDelaySeconds`：启动 AFK 后等待多少秒再开始发按键。
- `afk.keyTapHoldMilliseconds`：每次按键按下后保持多少毫秒再抬起。
- `afk.inputMethod`：AFK 的按键发送方式。默认 `SendKeys`，更接近最早的 PowerShell `SendKeys` 脚本；如果游戏不响应，可以改成 `SendInputScanCode` 或 `SendInputVirtualKey` 试兼容性。
- `afk.sequence.*`：`Sequence` 模式里的 55 秒、0.5 秒、10 秒等时间。
- `afk.enterEvery10s.delaySeconds`：`EnterEvery10s` 模式每隔多少秒按一次 `Enter`。
- `afk.macroCombo.cycleDelaySeconds`：`MacroCombo` 每轮完整宏之间额外等待多少秒。设置为 `0` 表示不额外等待。
- `afk.macroCombo.steps`：`MacroCombo` 的按键步骤，每一项的 `key` 是按键，`waitMilliseconds` 是这次按键后等待多少毫秒。
- `automation.autoBuyCar.loopCount`：`AutoBuyCar` 默认循环次数。
- `automation.inputMethod`：车辆自动化的按键发送方式。默认 `SendKeys`，如果游戏不响应可改成 `SendInputScanCode` 或 `SendInputVirtualKey` 试兼容性。
- `automation.autoBuyCar.steps`：买车流程每轮按键和等待时间。
- `automation.findNewSubaru.loopCount`：`FindNewSubaru` 默认处理轮数。
- `automation.findNewSubaru.maxSearchAttempts`：每轮最多搜索次数。
- `automation.findNewSubaru.afterSelectDelayMilliseconds`：命中并按 `Enter` 选择车辆后，等待多少毫秒再执行 `MacroCombo`。
- `automation.findNewSubaru.targetKeywords`：OCR 确认车型时必须匹配的关键词。

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

## 游戏挂机功能

`AFK` 功能用于执行简单按键循环，适合需要重复输入的挂机场景。

现在 AFK 默认使用 `SendKeys` 发送按键。如果你在某个游戏菜单里发现没有反应，可以在 `config.json` 里修改 `afk.inputMethod`，然后停止并重新启动 AFK。

目前有三个模式：

- `Sequence`：执行原来的 `Enter` / `x` 循环。
- `EnterEvery10s`：每 10 秒按一次 `Enter`。
- `MacroCombo`：执行 `config.json` 里的菜单宏步骤，每一步都会发送一次按键，再按 `waitMilliseconds` 等待；整轮结束后按配置等待再开始下一轮。

`Sequence` 模式逻辑是：

```text
Enter
等待 55 秒
x
等待 0.5 秒
x
等待 0.5 秒
Enter
等待 10 秒
重新循环
```

`EnterEvery10s` 模式逻辑是：

```text
Enter
等待 10 秒
重新循环
```

`MacroCombo` 模式会循环执行一套较长的菜单操作宏。比如宏录制中出现：

```text
Enter
等待 50 毫秒
Enter
```

这在工具里会被视为一次 `Enter` 输入，而不是连续按两次 `Enter`。后续的等待时间会继续保留。

每轮 `MacroCombo` 完整执行结束后，工具会读取 `config.json` 里的 `afk.macroCombo.cycleDelaySeconds`，按这个秒数等待，然后再开始下一轮循环。具体每个按键之间等多久，则由 `afk.macroCombo.steps` 里每一步的 `waitMilliseconds` 控制。

使用方式：

1. 打开 `GameSaveGuardian.cmd`。
2. 切换到 `AFK` 页面。
3. 在 `AFK mode` 中选择 `Sequence`、`EnterEvery10s` 或 `MacroCombo`。
4. 点击 `Start AFK`。
5. 在提示后 5 秒内切回游戏窗口。
6. 不需要时点击 `Stop AFK`。

停止挂机时，工具会额外发送一次 `W` 释放作为安全兜底，避免旧版本或异常残留导致按键像是卡住。

注意：挂机功能会把按键发送给当前前台窗口。它不会阻止游戏失焦暂停；如果你点击到别的软件，按键可能会发送到别的软件。

## 车辆自动化功能

`Automation` 是独立模块，和备份、焦点锁定、AFK 分开运行。它同样会把按键发送给当前前台窗口，所以启动后需要在倒计时内切回游戏。

目前有两个模式：

- `AutoBuyCar`：按固定买车流程循环执行。默认一轮是 `Space`、等待 1 秒、`Down`、等待 0.5 秒、`Enter`、等待 1 秒、`Enter`、等待 1 秒、`Enter`，两轮之间等待 1 秒。
- `FindNewSubaru`：每轮按 `Left` 搜索车辆，最多搜索 50 次；工具会截图当前游戏窗口，检测绿色边框高亮卡片，检查右下角黄色 `全新` 标签，再用 Windows OCR 确认卡片文字包含 `1998` 和 `斯巴鲁`。命中后按 `Enter`，等待 2 秒，然后执行一次 AFK 的 `MacroCombo`。

使用方式：

1. 打开 `GameSaveGuardian.cmd`。
2. 切换到 `Automation` 页面。
3. 选择 `AutoBuyCar` 或 `FindNewSubaru`。
4. 设置循环次数。
5. 点击 `Start Automation`。
6. 在提示后倒计时内切回游戏窗口。

如果检测到 `全新` 但 OCR 不是目标车型，工具会把原因写进 `logs\automation.log` 并继续搜索，直到命中或达到最大搜索次数。车型确认支持完整匹配 `1998` + `斯巴鲁`，也兼容 OCR 识别成 `1998`、`斯`、`巴` 这类模糊文本。

注意：自动化和 AFK 不能同时运行，避免两个后台任务同时发送按键。

## 高级脚本入口

如果不想打开 GUI，也可以直接使用这些脚本：

```text
BackupNow.cmd
StartBackup.cmd
StopBackup.cmd
StatusBackup.cmd
StartAfk.cmd
StopAfk.cmd
StatusAfk.cmd
StartAutomation.cmd
StopAutomation.cmd
StatusAutomation.cmd
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
- `logs\afk.log`：挂机日志。
- `logs\automation.log`：车辆自动化日志。
- `logs\focus-lock.log`：焦点锁定日志。
- `runtime\watcher.pid`：自动备份后台进程状态。
- `runtime\afk.pid`：挂机后台进程状态。
- `runtime\automation.pid`：车辆自动化后台进程状态。
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

5. 挂机功能会发送真实按键。

   启动挂机前请确认游戏窗口在前台。不要在聊天框、浏览器、编辑器等窗口处于前台时启动，否则 `Enter`、`x`、`Esc`、`WASD` 等按键可能会输入到错误位置。

6. 车辆自动化也会发送真实按键，并依赖当前界面状态。

   启动 `AutoBuyCar` 或 `FindNewSubaru` 前，请确认游戏已经停在对应菜单。`FindNewSubaru` 使用截图、像素检测和 Windows OCR，实际效果会受窗口缩放、语言、亮度和界面遮挡影响。

7. Release 包和源码仓库应该分开管理。

   源码仓库不建议提交 `backups`、`logs`、`runtime`、`dist` 或 zip 包。用户下载包应该放在 GitHub Release。

8. 第一次运行时可能遇到 Windows 安全提示。

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
