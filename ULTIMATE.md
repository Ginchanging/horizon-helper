# Ultimate 工作流程详解

> **维护规则:每次修改 Ultimate 的任何执行步骤(宏、时序、流程顺序、识别逻辑),都必须同步更新本文件。**
> 这是该工作流唯一的「人类可读真相来源」。代码改了文档没改 = 文档失效。

本文件描述 `Ultimate` 子系统从启动到结束的**完整、按顺序**的执行步骤。

- 入口 worker:`scripts/RunUltimate.ps1`
- 库:`scripts/UltimateLib.ps1`(三个写死的宏 + 配置/选项解析)、`scripts/AfkLib.ps1`(按键发送)、`scripts/AutomationLib.ps1`(截图/OCR/AutoBuyCar 复用)
- 配置节:`config.json` → `ultimate`(以及 AutoBuyCar 复用的 `automation.autoBuyCar`)
- 日志:`logs/ultimate.log`

「写死(hard-coded)」= 直接写在 `*Lib.ps1` 代码里,**不读 config.json**,改它要改代码。
「可配置」= 从 `config.json` 读,改它改配置即可,下次启动生效。

---

## 顶层执行顺序

| 步骤 | 名称 | 来源 | 说明 |
|---|---|---|---|
| 0 | **设置 DPI 感知** | 代码(worker 顶部) | `SetProcessDPIAware()`,必须在加载 WinForms/GDI+ **之前**。见文末「DPI / 第三行截断」 |
| 1 | 互斥检查 + 写 PID | 代码 | AFK 或 Automation 在运行则拒绝启动 |
| 2 | 加载 WinForms + `Initialize-AfkNative` | 代码 | 准备按键发送 |
| 3 | **启动倒计时** | 可配置 `startupDelaySeconds` (5s) | 切换到游戏窗口的时间 |
| 4 | 捕获前台窗口句柄 | 代码 | `AssumeTargetFound` / `RecognitionImagePath` 时跳过 |
| 5 | **Prelude 宏** | 写死 `Get-DefaultUltimatePreludeSteps` | 进入分享码输入界面 |
| 6 | **输入分享码** | 可配置 `shareCode` / `digitIntervalMilliseconds` | 逐位输入 |
| 7 | **After-code 宏** | 写死 `Get-DefaultUltimateAfterCodeSteps` | 确认 / 进入车辆列表 |
| 8 | **目标搜索** | 可配置(见下) | Left 遍历 + 上下扫列找目标车 |
| 9 | **目标确认** | 可配置 `afterTargetSelect*` / `afterTargetConfirm*` | Enter 选中 → 等待 → Enter 确认 |
| 10 | **Sequence 循环 × N** | 可配置 `sequence.*`;次数 = GUI/`sequenceLoopCount` | 刷循环主体 |
| 11 | **Post-sequence 宏** | 写死 `Get-DefaultUltimatePostSequenceSteps` | 48 步,卖车/回到列表等 |
| 12 | **AutoBuyCar × M** | 复用 `automation.autoBuyCar` 步骤;次数 = GUI/`autoBuyCar.loopCount` | 买推荐车 |
| 13 | 收尾 | 代码 | `Release-AfkKeys`(抬起 W)+ 删除 PID |

GUI 上可直接设置的:**Sequence loops**(第 10 步次数)、**AutoBuyCar loops**(第 12 步次数)。其余时序/宏改 config.json 或代码。

---

## 各步骤明细

### 5. Prelude 宏(写死)
进入分享码输入界面。

| # | 按键 | 等待 |
|---|---|---|
| 1 | Esc | 2.0s |
| 2 | Esc | 2.0s |
| 3 | Esc | 20.0s |
| 4 | Esc | 2.0s |
| 5–16 | D ×12 | 每次 1.5s |
| 17 | Enter | 1.0s |
| 18 | Enter | 10.0s |
| 19 | Backspace | 1.0s |
| 20 | W | 0.5s |
| 21 | Enter | 1.0s |

### 6. 输入分享码(可配置)
- `shareCode` = `705399298`(仅数字,校验 `^\d+$`)
- 每位之间等待 `digitIntervalMilliseconds` = 500ms(最后一位后不等)

### 7. After-code 宏(写死)
确认 / 进入车辆列表。

| # | 按键 | 等待 |
|---|---|---|
| 1 | Enter | 1.0s |
| 2 | S | 0.5s |
| 3 | Enter | 5.0s |
| 4 | Enter | 1.0s |
| 5 | Enter | 2.0s |
| 6 | A | 0.5s |
| 7 | A | 0.5s |

### 8. 目标搜索(可配置)
逻辑在 `Invoke-UltimateTargetSearch`:

- 持续按 `searchKey` = `Left` 遍历车格,列表会从最左绕回末尾,走完一整圈(回到起始卡)就停。
- 每按一次 `Left` 等待 `searchSettleMilliseconds` = 500ms,然后识别当前卡。
- `maxSearchAttempts` = 0 → 不设次数上限(靠「绕一圈」检测停止);>0 则作为 Left 次数安全上限。
- 只有当识别到**斯巴鲁家族**(`familyKeywords` = `斯巴`)时,才在当前列**向下扫** `verticalScanSteps` = 2 行(按 S),逐行识别;没中就按 W 退回去继续 Left。
- 目标判定:OCR 文本需**同时包含** `targetKeywords` = `1998` + `斯巴` + `S1` + `790`(**精确**子串匹配,经 `ConvertTo-UltimateMatchKey` 容错归一化后)。
- **OCR 容错靠字形折叠,不靠模糊匹配**:`ConvertTo-UltimateMatchKey` 把「形似数字的字母」折成数字——`i/l/|/! → 1`、`o → 0`、`g/q → 9`(再去标点)。于是 `790` 读成 `7g0`/`79o` 也能精确匹配 `790`,`S1` 读成 `SI` 也能匹配。**只折叠「字母→数字」,绝不折叠「数字→数字」**,所以两个不同的数不会互相串(`790`≠`990`、`1998`≠`1990`)——这点很关键:早期用过编辑距离 ≤1 的模糊匹配,结果把 `1990 斯巴鲁 Legacy` 误判成目标(1990≈1998、990≈790),已废弃。

> `verticalScanSteps = 2` 表示从顶行向下最多到**第 3 行**(顶行 + 2 次 S)。

### 9. 目标确认(可配置)
`Invoke-UltimateTargetConfirm`:

| 动作 | 等待 |
|---|---|
| Enter(选中) | `afterTargetSelectDelayMilliseconds` = 20.0s |
| Enter(确认) | `afterTargetConfirmDelayMilliseconds` = 2.0s |

### 10. Sequence 循环 × N(可配置)
`Invoke-UltimateSequenceLoops`,循环 `sequenceLoopCount` 次(默认 80,**GUI「Sequence loops」可改**)。单次:

| 按键 | 等待 |
|---|---|
| Enter | `sequence.enterDelaySeconds` = 40s |
| X | `sequence.xDelayMilliseconds` = 500ms |
| X | 500ms |
| Enter | `sequence.loopDelaySeconds` = 10s |

### 11. Post-sequence 宏(写死,48 步)
`Get-DefaultUltimatePostSequenceSteps`。

| # | 按键 | 等待 |
|---|---|---|
| 1–4 | S ×4 | 每次 0.5s |
| 5 | Enter | 0.5s |
| 6 | Enter | 10.0s |
| 7 | Esc | 7.0s |
| 8 | Esc | 2.0s |
| 9–14 | D ×6 | 每次 1.5s |
| 15 | Enter | 1.5s |
| 16 | Enter | 15.0s |
| 17 | S | 1.5s |
| 18 | Enter | 1.0s |
| 19 | D | 0.5s |
| 20 | Enter | 1.0s |
| 21 | S | 0.5s |
| 22 | Enter | 1.0s |
| 23 | Backspace | 1.0s |
| 24–42 | S ×19 | 每次 0.5s |
| 43–45 | D ×3 | 每次 0.5s |
| 46 | Enter | 1.0s |
| 47 | S | 0.5s |
| 48 | Enter | 1.0s |

### 12. AutoBuyCar × M(复用 automation 配置)
`Invoke-UltimateAutoBuyCar`。步骤和循环间隔取自 `config.json` → `automation.autoBuyCar`,**仅循环次数**由 GUI「AutoBuyCar loops」设置(默认取 `automation.autoBuyCar.loopCount` = 1)。单次步骤(当前默认):

| 按键 | 等待 |
|---|---|
| Space | 1.0s |
| Down | 0.5s |
| Enter | 1.0s |
| Enter | 1.0s |
| Enter | 0s |

循环之间等待 `automation.autoBuyCar.betweenLoopsMilliseconds` = 1.0s。

---

## 配置项速查(`config.json` → `ultimate`)

| 字段 | 当前值 | 含义 |
|---|---|---|
| `startupDelaySeconds` | 5 | 启动倒计时 |
| `inputMethod` | `SendKeys` | 按键后端(另有 `SendInputScanCode` / `SendInputVirtualKey`) |
| `keyTapHoldMilliseconds` | 50 | 单次按键按住时长 |
| `shareCode` | `705399298` | 分享码 |
| `digitIntervalMilliseconds` | 500 | 分享码每位间隔 |
| `afterTargetSelectDelayMilliseconds` | 20000 | 选中后等待 |
| `afterTargetConfirmDelayMilliseconds` | 2000 | 确认后等待 |
| `sequenceLoopCount` | 80 | Sequence 次数默认(GUI 可覆盖) |
| `sequence.enterDelaySeconds` | 40 | Sequence 内 Enter 后等待 |
| `sequence.xDelayMilliseconds` | 500 | Sequence 内 X 后等待 |
| `sequence.loopDelaySeconds` | 10 | Sequence 末 Enter 后等待 |
| `targetKeywords` | `1998,斯巴,S1,790` | 目标车严格关键词(全含才算中) |
| `familyKeywords` | `斯巴` | 触发上下扫列的家族关键词 |
| `searchKey` | `Left` | 横向遍历键 |
| `searchSettleMilliseconds` | 500 | 每次移动后等待 |
| `maxSearchAttempts` | 0 | Left 次数上限,0 = 无限 |
| `verticalScanSteps` | 2 | 向下扫的最大行数(到第 3 行) |

AutoBuyCar 复用:`automation.autoBuyCar.{loopCount,betweenLoopsMilliseconds,steps}`。

---

## 已知问题与修复

### 第三行目标车识别失败 —— 真因:OCR 数字误读(2026-06-05,已修复)
**现象:** 目标车(`1998 斯巴鲁 S1 790`)在车格**第三行**时,绿框光标移过去也不选中,程序继续找别的车直至失败。第 1、2 行正常。

**真因(日志实证):** `logs/ultimate.log` 中 `LeftPresses=18 Row=2` 那行:
```
Bitmap=1627x952  CardRect=[345,631,284,218]  IsFamily=True  Match=False
OcrText='IMPREZA 22B · S 引 VERSIOI 传 奇 1998 斯 巴 鲁 SI 7g0'  Reason=Missing target keywords: 790
```
光标**确实到达**第三行,卡片**完整截到**(高 218,与第 1、2 行一致;游戏窗口化 1627×952,**没有截断**)。匹配要 `1998+斯巴+S1+790` 全中,前三个都中(`SI`→`s1`),唯独 **`790` 被 OCR 读成 `7g0`**(数字 9→字母 g),严格 `Contains` 失败 → 整车判负。又因同列有 `S1 917`(第二行)和 `S1 790`(第三行)两辆几乎一样的车,只能靠数值区分,不能去掉 `790`。

**修复:** 在 `ConvertTo-UltimateMatchKey` 增加「字母→数字」字形折叠 `g/q → 9`(沿用已有的 `i/l/|/! → 1`、`o → 0`),保持**精确**子串匹配。这样 `7g0`/`79o` 精确等于 `790`,而 `917`/`600`/`1990` 不会误命中。

> **弯路提醒:** 一开始用编辑距离 ≤1 的模糊匹配(`Get-UltimateEditDistance`/`Test-UltimateApproxContains`),结果把 **`1990 斯巴鲁 Legacy`** 误选为目标——因为 `1990` 与 `1998`、`1990` 里的 `990` 与 `790` 都只差 1 个编辑。**数值不能做数字↔数字的模糊匹配**,只能折叠字母↔数字。该方案已废弃删除。

### 关于 DPI(已排除,但保留改动)
最初怀疑是 DPI 缩放(2560×1440 @ 125%)导致 `CopyFromScreen` 把截图底部截断、第三行徽章丢失。后用日志证实截图完整(`Bitmap`/`CardRect` 高度正常),**截断不是本 bug 的原因**。但「worker 顶部、dot-source 之前调用 `SetProcessDPIAware()`」这个改动对**全屏缩放**场景仍是正确且无害的,予以保留;同时保留的还有识别日志里的 `Bitmap=宽x高`、`CardRect=[x,y,w,h]`、`DpiAware=` 诊断字段——正是它们让我们定位到真因。**不要**把 `SetProcessDPIAware()` 挪进 `AfkLib`(GUI 也用它,会破坏 GUI 排版)。

**再出问题先看 `Recognition result`:** 位图非满屏或第三行 `CardRect` 高度明显偏小 → 截断;位图满、`CardRect` 正常但 `OcrText` 缺 `790/S1` → OCR 漏读(可调模糊匹配阈值或关键词)。

---

## 改动须知
- 三个宏写死在 `UltimateLib.ps1`:`Get-DefaultUltimatePreludeSteps` / `Get-DefaultUltimateAfterCodeSteps` / `Get-DefaultUltimatePostSequenceSteps`。改宏改这里,**并更新本文档对应表格**。
- 加新阶段要同时改 worker 主流程顺序、可能的 `Resolve-UltimateRuntimeOptions` 选项、GUI、`StartUltimate.ps1`,以及本文档。
- 本文档未列入 `BuildRelease.ps1` 的发布清单(内部规格文档,不随发布包分发)。如需随包分发,把 `ULTIMATE.md` 加进 `$rootFiles`。
