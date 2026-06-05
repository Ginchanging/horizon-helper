# GameSave Guardian 游戏存档工具

GameSave Guardian 是一个便携式 Windows 小工具，用来自动备份 Xbox 游戏存档，也可以提供窗口焦点恢复、游戏挂机按键循环、车辆自动化流程和独立的 Ultimate 终极流程。

默认备份源是 `C:\XboxGames\GameSave\pgs`。备份文件会写入程序当前所在文件夹的 `backups` 目录，所以你把整个工具文件夹移动到哪里，备份目录也会跟着移动。

## 快速使用

1. 下载 release zip 并解压。
2. 双击 `GameSaveGuardian.cmd` 打开图形界面。
3. 在 `Backup` 页里启动自动备份、停止自动备份，或立即备份一次。
4. 在 `Focus Lock` 页里刷新窗口列表，选择窗口，然后启动焦点锁定。
5. 在 `AFK` 页里选择模式，并启动或停止挂机按键循环。
6. 在 `Automation` 页里启动 `AutoBuyCar`、`DeleteCar` 或 `FindNewSubaru` 车辆自动化。
7. 在 `Ultimate` 页里启动分享代码、OCR 选车和 80 轮 Sequence 的终极流程。

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

游戏挂机：

- `Sequence` 模式：`Enter` -> 等待 55 秒 -> `x` -> 等待 0.5 秒 -> `x` -> 等待 0.5 秒 -> `Enter` -> 等待 10 秒。
- `EnterEvery10s` 模式：每 10 秒按一次 `Enter`。
- `MacroCombo` 模式：执行 `config.json` 里的菜单宏步骤，每一步都会发送一次按键，再按 `waitMilliseconds` 等待；整轮结束后按配置等待再开始下一轮。
- 启动前会提示你在 5 秒倒计时内切回游戏窗口。
- 停止时会额外发送一次 `W` 释放作为安全兜底，避免旧版本或异常残留导致按键卡住。

注意：挂机功能会把按键发送给当前前台窗口。它不会阻止游戏失焦暂停；如果你点到别的软件，按键可能会发送到别的软件。

AFK 默认使用 `SendKeys` 发送按键。修改 `config.json` 里的 `afk.inputMethod` 后，需要停止并重新启动 AFK 才会生效。

车辆自动化：

- `AutoBuyCar`：按配置循环执行买车按键。默认一轮是 `Space`、等待 1 秒、`Down`、等待 0.5 秒、`Enter`、等待 1 秒、`Enter`、等待 1 秒、`Enter`，两轮之间等待 1 秒。
- `DeleteCar`：与 AFK 类似的纯按键序列，可设置循环轮数。默认一轮是 `Enter`、等待 0.5 秒、`S` × 4（每次等待 0.5 秒）、`Enter`、等待 0.5 秒、`S`、等待 0.5 秒、`Enter`、等待 1 秒、`S`、等待 0.5 秒，两轮之间等待 1 秒。按键步骤和等待时间都可在 `config.json` 的 `automation.deleteCar` 里修改。
- `FindNewSubaru`：倒计时后锁定当前前台窗口，逐次按 `Left` 搜索；只检查当前绿色边框高亮车辆卡，检测黄色 `全新` 标签，并用 Windows OCR 确认文字包含 `1998` 和 `斯巴鲁`。命中后按 `Enter`，等待 2 秒，再执行一次 AFK 的 `MacroCombo`。
- 自动化和 AFK 不能同时运行，避免两个后台任务同时发送按键。

注意：如果检测到 `全新` 但 OCR 不是目标车型，工具会写入日志并继续搜索，直到命中或达到最大搜索次数。车型确认支持完整匹配 `1998` + `斯巴鲁`，也兼容 OCR 识别成 `1998`、`斯`、`巴` 这类模糊文本。

Ultimate 终极流程：

- 先执行固定菜单宏，输入分享代码 `705399298`。
- 使用 Windows OCR 查找同时匹配 `1998`、`斯巴`、`S1`、`790` 的车辆卡（目标就是 1998 斯巴鲁 S1 790；这里用 `斯巴` 而不是 `斯巴鲁`，因为 OCR 经常把 `鲁` 误读成 `兽`、`口`，而 `斯`、`巴` 识别稳定）。
- 命中后按 `Enter`，等待配置时间，再执行独立的 80 轮 `Sequence`。
- Ultimate 和 AFK、Automation 不能同时运行。

## 高级脚本入口

如果你不想打开图形界面，也可以直接双击这些脚本：

- `BackupNow.cmd`：立即手动备份一次。
- `StartBackup.cmd`：启动后台自动备份。
- `StopBackup.cmd`：停止后台自动备份。
- `StatusBackup.cmd`：查看备份状态。
- `StartAfk.cmd`：启动挂机按键循环，可用 `-Mode EnterEvery10s` 启动每 10 秒按 Enter 的模式，或用 `-Mode MacroCombo` 启动菜单宏模式。
- `StopAfk.cmd`：停止挂机，并额外释放一次 `W` 作为兜底。
- `StatusAfk.cmd`：查看挂机状态。
- `StartAutomation.cmd`：启动车辆自动化。示例：`.\StartAutomation.ps1 -Mode AutoBuyCar -LoopCount 3`、`.\StartAutomation.ps1 -Mode DeleteCar -LoopCount 5` 或 `.\StartAutomation.ps1 -Mode FindNewSubaru -LoopCount 1`。
- `StopAutomation.cmd`：停止当前车辆自动化。
- `StatusAutomation.cmd`：查看车辆自动化状态。
- `StartUltimate.cmd`：启动 Ultimate 终极流程。
- `StopUltimate.cmd`：停止 Ultimate，并额外释放一次 `W` 作为兜底。
- `StatusUltimate.cmd`：查看 Ultimate 状态和配置。
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
    "deleteCar": {
      "loopCount": 1,
      "betweenLoopsMilliseconds": 1000,
      "steps": [
        { "key": "Enter", "waitMilliseconds": 500 },
        { "key": "S", "waitMilliseconds": 500 },
        { "key": "S", "waitMilliseconds": 500 },
        { "key": "S", "waitMilliseconds": 500 },
        { "key": "S", "waitMilliseconds": 500 },
        { "key": "Enter", "waitMilliseconds": 500 },
        { "key": "S", "waitMilliseconds": 500 },
        { "key": "Enter", "waitMilliseconds": 1000 },
        { "key": "S", "waitMilliseconds": 500 }
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

- `sourcePath`：要备份的存档目录。默认是 `C:\XboxGames\GameSave\pgs`。
- `backupRoot`：备份 zip 文件保存目录。默认值 `backups` 会按程序当前所在文件夹解析。
- `debounceSeconds`：检测到变化后等待多少秒再备份，避免游戏连续写入时重复备份。
- `maxBackups`：最多保留多少份最新备份。设置为 `0` 表示不自动删除旧备份。
- `afk.startupDelaySeconds`：启动 AFK 后等待多少秒再开始发按键，用来给你切回游戏窗口。
- `afk.keyTapHoldMilliseconds`：每次按键按下后保持多少毫秒再抬起。
- `afk.inputMethod`：AFK 的按键发送方式。默认 `SendKeys`，更接近最早的简单 PowerShell 脚本；如果游戏不响应，可改为 `SendInputScanCode` 或 `SendInputVirtualKey` 测试兼容性。
- `afk.sequence.enterDelaySeconds`：`Sequence` 模式第一次 `Enter` 后等待多少秒。
- `afk.sequence.xDelayMilliseconds`：`Sequence` 模式两次 `x` 前后的等待毫秒数。
- `afk.sequence.loopDelaySeconds`：`Sequence` 模式每轮末尾等待多少秒。
- `afk.enterEvery10s.delaySeconds`：`EnterEvery10s` 模式每隔多少秒按一次 `Enter`。
- `afk.macroCombo.cycleDelaySeconds`：`MacroCombo` 每轮完整宏之间额外等待多少秒。设置为 `0` 表示不额外等待。
- `afk.macroCombo.steps`：`MacroCombo` 的按键步骤，每一项的 `key` 是按键，`waitMilliseconds` 是这次按键后等待多少毫秒。
- `automation.startupDelaySeconds`：启动自动化后等待多少秒再捕获前台游戏窗口。
- `automation.keyTapHoldMilliseconds`：车辆自动化每次按键按下后保持多少毫秒再抬起。
- `automation.inputMethod`：车辆自动化的按键发送方式。默认 `SendKeys`，可改为 `SendInputScanCode` 或 `SendInputVirtualKey` 测试兼容性。
- `automation.autoBuyCar.loopCount`：`AutoBuyCar` 默认循环次数。
- `automation.autoBuyCar.steps`：`AutoBuyCar` 每轮按键和等待时间。
- `automation.autoBuyCar.betweenLoopsMilliseconds`：`AutoBuyCar` 两轮之间等待多少毫秒。
- `automation.deleteCar.loopCount`：`DeleteCar` 默认循环次数。
- `automation.deleteCar.steps`：`DeleteCar` 每轮按键和等待时间，每一项的 `key` 是按键，`waitMilliseconds` 是这次按键后等待多少毫秒。
- `automation.deleteCar.betweenLoopsMilliseconds`：`DeleteCar` 两轮之间等待多少毫秒。
- `automation.findNewSubaru.loopCount`：`FindNewSubaru` 默认处理几轮。
- `automation.findNewSubaru.maxSearchAttempts`：每轮最多按多少次搜索键。
- `automation.findNewSubaru.searchKey`：搜索时发送的方向键，默认 `Left`。
- `automation.findNewSubaru.searchSettleMilliseconds`：每次搜索后等待界面稳定的毫秒数。
- `automation.findNewSubaru.afterSelectDelayMilliseconds`：命中并按 `Enter` 选择车辆后，等待多少毫秒再执行 `MacroCombo`。
- `automation.findNewSubaru.targetKeywords`：OCR 必须识别到的目标关键词。
- `automation.findNewSubaru.requireTargetConfirmation`：为 `true` 时，会用 OCR 确认目标车型；不匹配时继续搜索。
- `ultimate.shareCode`：Ultimate 输入的分享代码，默认 `705399298`。
- `ultimate.targetKeywords`：Ultimate OCR 匹配关键词，默认 `1998`、`斯巴`、`S1`、`790`。用 `斯巴` 而不是完整的 `斯巴鲁`，是为了避免 OCR 把 `鲁` 误读成 `兽`、`口` 导致漏掉目标车；`1998 + S1 + 790` 已经足以唯一锁定目标。
- `ultimate.familyKeywords`：判断当前卡是不是斯巴鲁车系的关键词，默认 `斯巴`。命中车系才会上下扫描该列寻找精确目标。
- `ultimate.sequenceLoopCount`：Ultimate 最后执行多少轮独立 `Sequence`，默认 `80`。
- `ultimate.sequence.*`：Ultimate 独立 `Sequence` 的等待时间，不读取 AFK 配置。

修改配置后，如果自动备份已经启动，请先停止再重新启动，让新配置生效。

## 日志和状态

- 备份日志：`logs\backup.log`
- 挂机日志：`logs\afk.log`
- 车辆自动化日志：`logs\automation.log`
- Ultimate 日志：`logs\ultimate.log`
- 焦点锁定日志：`logs\focus-lock.log`
- 自动备份 PID：`runtime\watcher.pid`
- 挂机 PID：`runtime\afk.pid`
- 车辆自动化 PID：`runtime\automation.pid`
- Ultimate PID：`runtime\ultimate.pid`
- 焦点锁定 PID：`runtime\focus-lock.pid`
- 当前焦点锁定目标：`runtime\focus-lock.target.json`

如果状态显示 `RunningUnverified`，通常是当前 PowerShell 权限不允许读取进程命令行。一般不影响使用，停止按钮仍然可以停止对应后台任务。

## 打包发布

生成便携 release zip：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\BuildRelease.ps1 -Version 1.5.0
```

输出文件：

```text
dist\gamesave-guardian-v1.5.0.zip
```

zip 会包含图形界面、脚本、配置和说明文档，不会包含 `.git`、`backups`、`logs`、`runtime`、旧版 zip 等运行产物。
