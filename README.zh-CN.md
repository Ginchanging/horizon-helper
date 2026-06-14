# GameSave Guardian 游戏存档工具

GameSave Guardian 是一个便携式 Windows 小工具，用来自动备份 Xbox 游戏存档，运行车辆/按键自动化流程，以及独立的 Ultimate 终极流程。

默认备份源是 `C:\XboxGames\GameSave\pgs`。备份文件会写入程序当前所在文件夹的 `backups` 目录，所以你把整个工具文件夹移动到哪里，备份目录也会跟着移动。

## 快速使用

1. 下载 release zip 并解压。
2. 双击 `GameSaveGuardian.cmd` 打开图形界面。
3. 在左侧导航栏切换页面；页面名旁出现绿色圆点表示该子系统正在后台运行。
4. 在 `Backup` 页里启动自动备份、停止自动备份，或立即备份一次。
5. 在 `Automation` 页里选择模式（AutoBuyCar、DeleteCar、FindNewSubaru、Sequence、EnterEvery10s、MacroCombo），设置循环次数或勾选 **Forever**（循环到手动 Stop），然后启动/停止。
6. 在 `Ultimate` 页里启动分享代码、OCR 选车和 Sequence 刷圈的终极流程。运行时界面每 2 秒自动刷新：进度条显示当前大循环进度和预计完成时间，暂停时显示红色 `PAUSED`；界面还实时显示当前内圈阶段（Sequence / AutoBuyCar / FindNewSubaru）执行到第几次，并配一条阶段进度条；日志预览会给 ERROR/WARN 行着色，并提供关键词过滤框和自动滚动开关。

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

车辆 / 按键自动化（Automation）：

启动前会提示你在 5 秒倒计时内切回游戏窗口；按键发送给当前前台窗口。选择一个模式，设置 **Loop count**，或勾选 **Forever** 循环到手动 Stop。停止时会额外发送一次 `W` 释放作为安全兜底。**Automation 和 Ultimate 不能同时运行**（都向前台发按键）。

Automation（以及 Ultimate）默认使用 `SendKeys` 发送按键。**Forza Horizon 完全无视 `SendInput` 注入的键盘**（`SendInputScanCode` / `SendInputVirtualKey` 在游戏里检测不到任何按键——2026-06-10 实测），所以玩 Forza 不要换后端。`SendKeys` 偶发多读/漏读一个键（可能顶错菜单光标），Ultimate 已内置自动恢复（见 ULTIMATE.md「脱格自愈」）。修改 `config.json` 里的 `automation.inputMethod` 后，停止并重新启动即可生效。

模式：

- `AutoBuyCar`：按配置循环执行买车按键。默认一轮是 `Space`、等待 1 秒、`Down`、等待 0.5 秒、`Enter`、等待 1 秒、`Enter`、等待 1 秒、`Enter`，两轮之间等待 1 秒。
- `DeleteCar`：纯按键序列，可设置循环轮数。默认一轮是 `Enter`、等待 0.5 秒、`S` × 4（每次等待 0.5 秒）、`Enter`、等待 0.5 秒、`S`、等待 0.5 秒、`Enter`、等待 1 秒、`S`、等待 0.5 秒，两轮之间等待 1 秒。按键步骤和等待时间都可在 `config.json` 的 `automation.deleteCar` 里修改。
- `FindNewSubaru`：倒计时后锁定当前前台窗口，逐次按 `Left` 搜索；只检查当前绿色边框高亮车辆卡，检测黄色 `全新` 标签，并用 Windows OCR 确认文字包含 `1998` 和 `斯巴鲁`。命中后按 `Enter`，等待 2 秒，再执行一次 `MacroCombo` 买车宏。
- `Sequence`（原 AFK）：一轮 = `Enter` -> 等待 `automation.sequence.enterDelaySeconds` -> `x` -> 等待 -> `x` -> 等待 -> `Enter` -> 等待 `loopDelaySeconds`。
- `EnterEvery10s`（原 AFK）：每隔 `automation.enterEvery10s.delaySeconds` 秒按一次 `Enter`。
- `MacroCombo`（原 AFK）：执行 `config.json` 里的菜单宏步骤（`Enter`/`Esc`/`S`/`D`/`W`/`A`），整轮结束后等待 `automation.macroCombo.cycleDelaySeconds` 再开始下一轮。

原 AFK 那三个按键循环（Sequence / EnterEvery10s / MacroCombo）勾选 **Forever**（或传 `-LoopCount 0`）即可还原旧的「循环到手动 Stop」行为。

注意：自动化不会阻止游戏失焦暂停；如果你点到别的软件，按键可能会发送到别的软件。

注意：如果检测到 `全新` 但 OCR 不是目标车型，工具会写入日志并继续搜索，直到命中或达到最大搜索次数。车型确认支持完整匹配 `1998` + `斯巴鲁`，也兼容 OCR 识别成 `1998`、`斯`、`巴` 这类模糊文本。

Ultimate 终极流程：

- 先执行固定菜单宏，输入分享代码 `705399298`。
- 使用 Windows OCR 查找同时匹配 `1998`、`斯巴`、`S1`、`790` 的车辆卡（目标就是 1998 斯巴鲁 S1 790；这里用 `斯巴` 而不是 `斯巴鲁`，因为 OCR 经常把 `鲁` 误读成 `兽`、`口`，而 `斯`、`巴` 识别稳定）。
- 命中后按 `Enter`，等待配置时间，再执行独立的 80 轮 `Sequence`。
- 每轮 `Sequence` 的 40 秒等待期间，用虚拟手柄按住右扳机（油门）让车持续前进——因为 Forza 开车时会忽略注入的键盘，纯按键无法持续前进。
- **卡死兜底**：车子有时会卡在墙边到不了终点，这时两次 `X` 不会弹出「重新开始赛事」确认框、流程会卡死。Ultimate 会在两次 `X` 后用 OCR 检测该确认框；若没出现，就松开油门、走一小段恢复宏重新进赛事、**保留已完成的小轮数**、原地重做当前这一轮，并把本阶段总轮数 +2；连续恢复太多次仍卡死就软失败退出本阶段交给外层重新归位，避免整条流程卡死。可在 `config.json` 的 `ultimate.sequenceStuckRecovery` 里调整或关闭，详见 `ULTIMATE.md` 的「卡死兜底」。
- **暂停 / 继续**：`Ultimate` 页有 `Pause / Resume` 切换按钮。点 `Pause` 会在**下一个安全边界**（当前这场比赛或这一小轮结束时，而非立刻）停住、松开按键、状态显示 `PAUSED`，此时可自由 alt-tab 去用电脑；点 `Resume` 会倒计时几秒（让你切回游戏）后从原处继续。仅 Ultimate 有此功能，详见 `ULTIMATE.md` 的「暂停 / 继续」。
- Ultimate 和 Automation 不能同时运行。

> **手柄油门依赖（仅 Ultimate）**：上面的手柄油门需要安装 **ViGEmBus 驱动**（<https://github.com/nefarius/ViGEmBus/releases>，现代签名驱动，和 Win11 内存完整性兼容，通常免重启），随附的 `Nefarius.ViGEm.Client.dll` 已在包内。不想用时把 `config.json` 的 `ultimate.gamepadThrottle.enabled` 设为 `false`，第 10 步会退回纯等待。详见 `ULTIMATE.md` 的「虚拟手柄油门」。

## 高级脚本入口

如果你不想打开图形界面，也可以直接双击这些脚本：

- `BackupNow.cmd`：立即手动备份一次。
- `StartBackup.cmd`：启动后台自动备份。
- `StopBackup.cmd`：停止后台自动备份。
- `StatusBackup.cmd`：查看备份状态。
- `StartAutomation.cmd`：启动一个模式：`AutoBuyCar`、`DeleteCar`、`FindNewSubaru`、`Sequence`、`EnterEvery10s` 或 `MacroCombo`。`-LoopCount 0` 表示 Forever（循环到手动停止）。示例：`.\StartAutomation.ps1 -Mode AutoBuyCar -LoopCount 3`、`.\StartAutomation.ps1 -Mode MacroCombo -LoopCount 0`、`.\StartAutomation.ps1 -Mode Sequence -LoopCount 0`。
- `StopAutomation.cmd`：停止当前自动化，并额外释放一次 `W` 作为兜底。
- `StatusAutomation.cmd`：查看自动化状态。
- `StartUltimate.cmd`：启动 Ultimate 终极流程。
- `StopUltimate.cmd`：停止 Ultimate，并额外释放一次 `W` 作为兜底。
- `StatusUltimate.cmd`：查看 Ultimate 状态和配置。

## 配置说明

配置文件是 `config.json`：

```json
{
  "sourcePath": "C:\\XboxGames\\GameSave\\pgs",
  "backupRoot": "backups",
  "debounceSeconds": 30,
  "maxBackups": 30,
  "automation": {
    "startupDelaySeconds": 5,
    "keyTapHoldMilliseconds": 50,
    "inputMethod": "SendKeys",
    "sequence": {
      "enterDelaySeconds": 40,
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
    },
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
- `automation.startupDelaySeconds`：启动自动化后等待多少秒再捕获前台游戏窗口，用来给你切回游戏窗口。
- `automation.keyTapHoldMilliseconds`：每次按键按下后保持多少毫秒再抬起。
- `automation.inputMethod`：按键发送方式。默认 `SendKeys`——**Forza 唯一能识别的后端**（游戏无视 `SendInputScanCode` / `SendInputVirtualKey` 的注入），只有别的游戏才考虑换。
- `automation.sequence.*`：`Sequence` 模式的三段等待（`Enter` 后行驶等待、两次 `x` 前后等待、每轮末尾等待）。
- `automation.enterEvery10s.delaySeconds`：`EnterEvery10s` 模式每隔多少秒按一次 `Enter`。
- `automation.macroCombo.cycleDelaySeconds`：`MacroCombo` 每轮完整宏之间额外等待多少秒。设置为 `0` 表示不额外等待。
- `automation.macroCombo.steps`：`MacroCombo` 的按键步骤，每一项的 `key` 是按键，`waitMilliseconds` 是这次按键后等待多少毫秒。也用作 FindNewSubaru 选车后的买车宏。
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
- `ultimate.sequence.*`：Ultimate 独立 `Sequence` 的等待时间（与 `automation.sequence` 各自独立）。

修改配置后，如果自动备份已经启动，请先停止再重新启动，让新配置生效。

## 日志和状态

- 备份日志：`logs\backup.log`
- 自动化日志：`logs\automation.log`
- Ultimate 日志：`logs\ultimate.log`
- 自动备份 PID：`runtime\watcher.pid`
- 自动化 PID：`runtime\automation.pid`
- Ultimate PID：`runtime\ultimate.pid`

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
