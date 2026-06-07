# Ultimate 工作流程详解

> **维护规则:每次修改 Ultimate 的任何执行步骤(宏、时序、流程顺序、识别逻辑),都必须同步更新本文件。**
> 这是该工作流唯一的「人类可读真相来源」。代码改了文档没改 = 文档失效。

本文件描述 `Ultimate` 子系统从启动到结束的**完整、按顺序**的执行步骤。

- 入口 worker:`scripts/RunUltimate.ps1`
- 库:`scripts/UltimateLib.ps1`(四个写死的宏 + 配置/选项解析)、`scripts/AfkLib.ps1`(按键发送)、`scripts/AutomationLib.ps1`(截图/OCR、AutoBuyCar 步骤复用、FindNewSubaru 整段循环 `Invoke-AutomationFindNewSubaruLoop` 复用)
- 配置节:`config.json` → `ultimate`(以及复用的 `automation.autoBuyCar`、`automation.findNewSubaru`)
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
| 8 | **目标搜索** | 可配置(见下) | Right 遍历 + 上下扫列找目标车 |
| 9 | **目标确认** | 可配置 `afterTargetSelect*` / `afterTargetConfirm*` | Enter 选中 → 等待 → Enter 确认 |
| 10 | **Sequence 循环 × N** | 可配置 `sequence.*`;次数 = GUI/`sequenceLoopCount` | 刷循环主体 |
| 11 | **Post-sequence 宏** | 写死 `Get-DefaultUltimatePostSequenceSteps` | 48 步,卖车/回到列表等 |
| 12 | **AutoBuyCar × M** | 复用 `automation.autoBuyCar` 步骤;次数 = GUI/`autoBuyCar.loopCount` | 买推荐车 |
| 13 | **Post-buy 宏** | 写死 `Get-DefaultUltimatePostBuySteps` | 16 步,退出购买界面、回到车展网格 |
| 14 | **FindNewSubaru × K** | 复用 `automation.findNewSubaru`;次数 = GUI/`findNewSubaru.loopCount` | 找带「全新」徽章的目标斯巴鲁并买入 |
| 15 | 收尾 | 代码 | `Release-AfkKeys`(抬起 W)+ 删除 PID |

GUI 上可直接设置的:**Ultimate loops**(整条流程重复几次,见下「整条流程循环」)、**Sequence loops**(第 10 步次数)、**AutoBuyCar loops**(第 12 步次数)、**FindNewSubaru loops**(第 14 步次数)、**Debug start step**(调试用,从第几步开始,见下「调试:从指定步骤开始」)。其余时序/宏改 config.json 或代码。

> **整条流程(5–14 步)外面套了一层循环**:见下「整条流程循环 + 估计完成时间」。第 0–4 步(DPI、互斥、加载、启动倒计时、捕获前台窗口)只在最开始执行一次,循环只重复 5–14 步。

---

## 整条流程循环 + 估计完成时间(WorkflowLoopCount)

整条 Ultimate 工作流(第 5–14 步)外面套了一层循环,可以**重复整条流程**。

- **入口:**
  - GUI「Ultimate」标签页的 **Ultimate loops** 数字框 = 重复次数;勾上旁边的 **Forever** = 无限循环(跑到按 Stop 为止)。
  - CLI:`RunUltimate.ps1` / `StartUltimate.ps1` 的 `-WorkflowLoopCount <N>`(`0` = 无限,`>=1` = 次数)。
  - 配置:`config.json` → `ultimate.workflowLoopCount`(默认 `1`,`0` = 无限)。
- **每轮重复整条 5–14 步**(重输分享码、重新找车、刷 Sequence、买车、FindNewSubaru)。Prelude(Esc×4…)本来就是回菜单复位的动作,所以每轮能重新对齐状态。**第 0–4 步只在最开始执行一次**(尤其启动倒计时只倒一次),前台窗口句柄捕获一次、循环内复用。
- **两轮之间的间隔**:一轮跑完(第 14 步 FindNewSubaru 之后)、下一轮开始(下一轮第 5 步 Prelude 之前)插入一段可配置等待 `betweenWorkflowLoopsMilliseconds`(默认 **2000ms**),让菜单状态稳定后再让下一轮的 Prelude 复位。**仅在后面还有下一轮时才等待**(无限循环每轮都等,定次数循环最后一轮跑完不等),`DryRun` 下不真正 sleep。代码在 `RunUltimate.ps1` 外层循环体末尾。
- **AutoBuyCar 累计买车数**在循环里持续累加(每轮的第 12 步都计数),所以无限循环会一直累加总数。
- **估计完成时间(ETA):**
  - 启动时按各阶段写死/可配的等待先算一个**每轮预估耗时**(`Get-UltimateEstimatedLoopSeconds`):宏 + 分享码 + 目标确认 + Sequence(大头,确定) + AutoBuyCar + Post-buy + 两个视觉阶段(目标搜索、FindNewSubaru)各给约 45s 的**粗略**估值。
  - 每跑完一轮用**实测耗时**算平均并校准。
  - **定次数**:状态栏/日志显示 `Loop x/N - avg M/loop, k left, ETA finish ~HH:mm (in …)`。
  - **无限**:没有"完成时间",显示 `Loop x (infinite) - ~M/loop, running …`。
  - 进度快照写入 `runtime/ultimate-progress.json`(`Set-/Get-/Clear-UltimateProgress`);worker 在每轮开始和结束各写一次,GUI 状态栏读它显示。`ultimate.log` 也每轮写 `Ultimate loop started/completed …`。
- **DryRun + 无限**:为防止空跑刷爆日志,DryRun 时无限会被**限制为 1 轮**(日志里有 WARN 说明)。
- 停止:`Stop` 用 `Stop-Process -Force` 直接杀进程;进度文件会停在最后一次快照,GUI 据进程状态显示 `(stopped) …`。

---

## 调试:从指定步骤开始(StartFromStep)

为方便调试/测试某个中段阶段,可以让 Ultimate **跳过前面的阶段、直接从某一步开始**。

- **入口:**
  - GUI「Ultimate」标签页的 **Debug start step** 数字框(范围 5–14,默认 **5 = 完整跑**)。
  - CLI:`RunUltimate.ps1` / `StartUltimate.ps1` 的 `-StartFromStep <N>` 参数(同样默认完整跑)。
- **编号对应上面的「顶层执行顺序」表**:`5`=Prelude、`6`=输入分享码、`7`=After-code、`8`=目标搜索、`9`=目标确认、`10`=Sequence、`11`=Post-sequence、`12`=AutoBuyCar、`13`=Post-buy、`14`=FindNewSubaru。
- **第 0–4 步(基础设施:DPI 感知、互斥检查+写 PID、加载 WinForms、启动倒计时、捕获前台窗口句柄)永远执行**,不受 `StartFromStep` 影响。尤其**启动倒计时照常进行**,你仍有时间切到游戏窗口。
- 实现:`Resolve-UltimateRuntimeOptions` 解析出 `StartFromStep`(<5 一律当 5;>14 抛错);worker 里每个阶段用 `Test-UltimateShouldRunStep -StepNumber N` 包一层,`StartFromStep > N` 的阶段被跳过并写一条 `WARN`:`Step N (Name) skipped because StartFromStep=...`。日志开头的 `Ultimate started ...` 行也带上 `StartFromStep=`。
- **⚠️ 前提:从第 N 步开始,意味着游戏画面必须已经处于第 N 步所期望的 UI 状态**(例如从 14 开始,游戏需已停在车展网格;从 11 开始,需已在 Sequence 结束后的界面)。这是纯调试便利功能,不做任何状态校验。

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

### 7. After-code 宏(写死,27 步)
确认 / 进入车辆列表。

| # | 按键 | 等待 |
|---|---|---|
| 1 | Enter | 1.0s |
| 2 | S | 0.5s |
| 3 | Enter | 5.0s |
| 4 | Enter | 1.0s |
| 5 | Enter | 2.0s |
| 6 | Backspace | 1.0s |
| 7–25 | S ×19 | 每次 0.5s |
| 26 | D | 0.5s |
| 27 | Enter | 1.0s |

### 8. 目标搜索(可配置)
逻辑在 `Invoke-UltimateTargetSearch`:

- 持续按 `searchKey` = `Right` 遍历车格,列表会从一端绕回另一端,走完一整圈(回到起始卡)就停。(方向由配置决定,默认向右;日志里这一计数现在叫 `SearchPresses=`。)
- 每按一次 `searchKey` 等待 `searchSettleMilliseconds` = 500ms,然后识别当前卡。
- `maxSearchAttempts` = 0 → 不设次数上限(靠「绕一圈」检测停止);>0 则作为按键次数安全上限。
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
| Enter | `sequence.enterDelaySeconds` = 40s ←**这 40s 内按住手柄 RT(油门)前进** |
| X | `sequence.xDelayMilliseconds` = 500ms |
| X | 500ms |
| Enter | `sequence.loopDelaySeconds` = 10s |

> **40s 等待期间的手柄油门(虚拟手柄)**:Enter 按下后进入这段 40s 的"开车"等待,期间用 ViGEm 虚拟 Xbox 360 手柄把**右扳机(RT)按到底**让车一直前进,等待结束、按 X 之前松开油门。代码 `Invoke-UltimateThrottleWait`(`RunUltimate.ps1`)。
> - 为什么用手柄:Forza 开车时**忽略 SendInput 注入的键盘**,纯键盘"按住 W"无效;Forza 原生读 XInput,虚拟手柄油门最稳。
> - **手柄全程只连一次**:在第 2 步(启动阶段 `Connect-AfkGamepad`)插入虚拟手柄并**保持连接到整轮结束**,中途只改 RT 数值、不拔。这样游戏不会每圈都弹"手柄已断开"。正常结束/出错时 `Disconnect-AfkGamepad` 归零并拔出;被强制 Stop 时进程退出由系统自动拔出(此时游戏可能弹一次断开,属正常)。
> - 关闭/调整:`config.json` → `ultimate.gamepadThrottle`(`enabled` 默认 `true`、`rightTriggerValue` 默认 `255`、`dllPath` 留空则自动找根目录的 `Nefarius.ViGEm.Client.dll`)。`enabled=false` 时退回纯等待。
> - 依赖:ViGEmBus 驱动 + 根目录 `Nefarius.ViGEm.Client.dll`(详见下「虚拟手柄油门」)。
> - ⚠️ 手柄全程连接时,游戏菜单提示会变成手柄图标;Ultimate 的菜单操作仍走键盘(分享码数字、Enter/X/S/D 等)。Forza 一般键鼠手柄并存可用,但若发现连接手柄后键盘菜单失灵,需要排查。

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
| 16 | Enter | 20.0s |
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

**累计买车计数(持久化)**:每完成一次 AutoBuyCar 循环(= 买入 1 辆车),把累计总数 **+1** 写入 `runtime/ultimate-autobuy-count.txt`(ASCII)。该数**跨多次运行、跨 GUI 重启累加**,只有按 GUI 的 **Clear Count** 按钮才清零。GUI「Ultimate」标签页状态栏显示 `AutoBuyCar bought (total)=N`,刷新状态时更新;`ultimate.log` 每买一辆写一行 `AutoBuyCar bought a car. Loop=x/M CumulativeTotal=N`。
- `DryRun` 不买车,**不计数**(不污染真实统计)。
- Debug start step 跳过第 12 步(StartFromStep > 12)时,本阶段不执行,自然不计数。
- 计数读写函数在 `UltimateLib.ps1`:`Get-/Set-/Add-/Reset-UltimateAutoBuyCount`;计数文件路径在 `Get-UltimatePaths` 的 `AutoBuyCountPath`。

### 13. Post-buy 宏(写死,16 步)
`Get-DefaultUltimatePostBuySteps`。在 AutoBuyCar 之后退出购买/车库界面,导航回车展网格,为 FindNewSubaru 扫描做准备。

| # | 按键 | 等待 |
|---|---|---|
| 1–4 | Esc ×4 | 每次 2.0s |
| 5–6 | D ×2 | 每次 1.0s |
| 7 | S | 0.5s |
| 8 | Enter | 1.0s |
| 9–15 | S ×7 | 每次 0.5s |
| 16 | Enter | 1.0s |

> **第 12 ↔ 13 步之间的间隔**:AutoBuyCar 结束后、Post-buy 宏开始前,插入一段可配置等待 `afterAutoBuyCarDelayMilliseconds`(默认 **2000ms**),让购买界面稳定后再开始退出。仅当第 12 步实际执行时才等待(Debug start step 跳到 13 及以后会跳过这段等待)。代码在 `RunUltimate.ps1` 第 12、13 步之间。

### 14. FindNewSubaru × K(复用 automation 配置)
`Invoke-UltimateFindNewSubaru` → 直接调用 AutomationLib 抽出来的共享函数 `Invoke-AutomationFindNewSubaruLoop`(与 Automation 子系统的 FindNewSubaru **完全同一份实现**,不再重复代码)。

- 行为、关键词、徽章检测、搜索/扫列时序全部取自 `config.json` → `automation.findNewSubaru`(以及 `automation` 顶层的 `inputMethod`/`keyTapHoldMilliseconds`),**仅循环次数**由 GUI「FindNewSubaru loops」设置(默认取 `automation.findNewSubaru.loopCount` = 1)。
- 每个循环:按 `searchKey`(默认 `Left`)遍历车格 → 检测绿色高亮卡 → 判定「全新」徽章(黄色像素)+ 目标文字(默认 `1998`+`斯巴鲁`);若目标车出现但当前行无徽章,则向下扫 `verticalScanSteps` 行找带徽章的那辆。命中后 Enter 选中 → 等 `afterSelectDelayMilliseconds` → 跑一次 AFK MacroCombo(买车序列)。
- **选中判据(向下扫列分支)**:只在 ① OCR 正面命中目标关键词(`Match=True`),或 ② 有「全新」徽章**且 OCR 读不出该卡**(`OcrSuccess=False`,无法证伪,保底兜住真目标)时才选中。**单凭一个黄色徽章不足以选中**——特别版车(如 VIVIO RX-R「极限竞速特别版」Forza Edition,1994 斯巴鲁 S2 900)带金色徽章会被黄色像素检测误判为「全新」;当 OCR 成功且文字明确不是 1998 目标(`Match=False, OcrSuccess=True`)时,必须跳过、继续找,绝不能选中那辆 S2 斯巴鲁。主搜索分支(行 0)本来就只认 `Match`,此规则把向下扫列分支对齐到同样严格。
- 日志写入 `logs/ultimate.log`(传入的是 Ultimate 的 `$paths`),整段 Ultimate 流程日志连续。
- **这是 CV 阶段**:需要真实桌面 + 游戏窗口;headless / 无游戏时会一直找不到,直到 `maxSearchAttempts` 上限后抛错。

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
| `afterAutoBuyCarDelayMilliseconds` | 2000 | 第 12 步(AutoBuyCar)与第 13 步(Post-buy 宏)之间的间隔 |
| `workflowLoopCount` | 1 | 整条流程重复次数(0 = 无限;GUI「Ultimate loops」/「Forever」可覆盖) |
| `betweenWorkflowLoopsMilliseconds` | 2000 | 两轮整条流程之间的间隔(仅在后面还有下一轮时等待) |
| `sequenceLoopCount` | 80 | Sequence 次数默认(GUI 可覆盖) |
| `sequence.enterDelaySeconds` | 40 | Sequence 内 Enter 后等待 |
| `sequence.xDelayMilliseconds` | 500 | Sequence 内 X 后等待 |
| `sequence.loopDelaySeconds` | 10 | Sequence 末 Enter 后等待 |
| `targetKeywords` | `1998,斯巴,S1,790` | 目标车严格关键词(全含才算中) |
| `familyKeywords` | `斯巴` | 触发上下扫列的家族关键词 |
| `searchKey` | `Right` | 横向遍历键(向右) |
| `searchSettleMilliseconds` | 500 | 每次移动后等待 |
| `maxSearchAttempts` | 0 | Left 次数上限,0 = 无限 |
| `verticalScanSteps` | 2 | 向下扫的最大行数(到第 3 行) |
| `gamepadThrottle.enabled` | `true` | 第 10 步 40s 等待期间是否用虚拟手柄按住 RT 前进 |
| `gamepadThrottle.rightTriggerValue` | 255 | 右扳机油门值(0–255,255 = 踩到底) |
| `gamepadThrottle.dllPath` | `""` | `Nefarius.ViGEm.Client.dll` 路径,留空自动找根目录 / `lib\` |

AutoBuyCar 复用:`automation.autoBuyCar.{loopCount,betweenLoopsMilliseconds,steps}`。
FindNewSubaru 复用:`automation.findNewSubaru.{loopCount,betweenLoopsMilliseconds,maxSearchAttempts,searchKey,searchSettleMilliseconds,afterSelectDelayMilliseconds,targetKeywords,newBadgeText,requireTargetConfirmation,verticalScanSteps}`(仅 `loopCount` 被 GUI 覆盖)。

---

## 虚拟手柄油门(ViGEm)

第 10 步 Sequence 的 40s 等待期间靠**虚拟 Xbox 360 手柄按住右扳机(RT)**让车一直前进(纯键盘"按住 W"被 Forza 忽略,见上)。实现走 ViGEm:

- **依赖(一次性)**
  1. 装 **ViGEmBus 驱动**:<https://github.com/nefarius/ViGEmBus/releases>。现代签名驱动,**与 Win11 内存完整性(HVCI)兼容,不用关任何安全设置,通常免重启**。
  2. 根目录放 **`Nefarius.ViGEm.Client.dll`**(来自官方 NuGet `Nefarius.ViGEm.Client`,单文件、原生库已内嵌、零依赖)。`gamepadThrottle.dllPath` 留空时自动在根目录 / `lib\` 找。
  > 注:之前评估过 Interception 路线,但它是 2018 老过滤驱动,会被 Win11 内存完整性拦截、需先关 HVCI(降低系统安全);ViGEm 无此问题,故选 ViGEm。
- **代码**:输入仍统一归 `AfkLib.ps1`。新增 `Connect-AfkGamepad` / `Set-AfkGamepadRightTrigger` / `Disconnect-AfkGamepad` / `Test-AfkGamepadConnected` / `Get-AfkGamepadDllPath`(均**惰性加载** DLL,GUI 等 dot-source 本文件但不连接时零开销)。`RunUltimate.ps1` 启动阶段 `Connect-AfkGamepad` 连一次、`finally` 里 `Disconnect-AfkGamepad`;`Invoke-UltimateThrottleWait` 在 40s 等待里按住/松开 RT。
- **始终连接、避免断开弹窗**:手柄在一轮开始**只插一次**并保持到整轮结束,中途只改 RT 值(255↔0),**绝不中途拔**。这样游戏不会每圈弹"手柄已断开"。被强制 Stop 时进程退出由系统自动拔出(此时弹一次断开属正常)。
- **DryRun**:不连接手柄,40s 等待只记日志(`Connect-AfkGamepad -DryRun` 返回 `$false`,`Invoke-UltimateThrottleWait` 走"未连接"分支)。
- **关掉**:`config.json` → `ultimate.gamepadThrottle.enabled = false`,第 10 步退回纯 `Wait-UltimateSeconds`。
- ⚠️ **键鼠/手柄并存**:手柄全程连着时,游戏提示图标会变手柄,但 Ultimate 菜单仍走键盘(分享码数字、Enter/X/S/D)。Forza 一般并存可用;若连手柄后键盘菜单失灵需排查(可考虑把菜单也改手柄,但当前未做)。

> 改 ViGEmBus 之外的依赖名/路径或新增到发布包时记得同步 `BuildRelease.ps1` 的文件清单(`Nefarius.ViGEm.Client.dll` 目前不在清单里,发布前需补)。

---

## 已知问题与修复

### FindNewSubaru 误选 S2 斯巴鲁(VIVIO RX-R 极限竞速特别版)—— 真因:向下扫列「凭徽章选车」(2026-06-07,已修复)
**现象:** Ultimate 第 14 步 FindNewSubaru 反复**误选中** `VIVIO RX-R 1994 斯巴鲁 S2 900`(极限竞速特别版),而不是 `1998 斯巴鲁` 目标。

**真因(日志实证):** `logs/ultimate.log` 中所有 `SelectMode=BadgeOnly` 选中**全都是这辆 VIVIO**,例如:
```
Vertical scan recognition. ... Match=False New=True OcrSuccess=True MatchMode=None
  OcrText='VIVIO RX-R 1994 极 限 党 速 特 别 版 ... S2 900'
Vertical scan matched new target car. Enter sent. ... SelectMode=BadgeOnly
```
向下扫列分支的选中条件是 `if ($vRecognition.Match -or $vRecognition.HasNewBadge)`——**单凭一个「全新」徽章就选**。VIVIO 是 Forza Edition 特别版,带金色徽章,被 `Test-AutomationNewBadge` 的黄色像素检测误判为 `New=True`;它又是斯巴鲁,与目标 1998 斯巴鲁同列,向下扫列时光标落到它身上 → 凭徽章直接选中。OCR 其实成功且明确读出 `1994`/`S2 900`(`Match=False, OcrSuccess=True`),却被 `-or HasNewBadge` 覆盖。主搜索分支(行 0)只认 `if ($recognition.Match)`,没这问题——宽松只在向下扫列分支。

**修复:**(`AutomationLib.ps1` 的 `Invoke-AutomationFindNewSubaruLoop`)把向下扫列选中条件改为 `Match` 或「有徽章**且** OCR 读不出该卡(`OcrSuccess=False`)」:
```powershell
$vsBadgeOnlyTrust = $vRecognition.HasNewBadge -and -not $vRecognition.OcrSuccess
if ($vRecognition.Match -or $vsBadgeOnlyTrust) { ... }   # 旧:Match -or HasNewBadge
```
即 **OCR 成功且证伪目标 → 绝不选中**(VIVIO 被跳过,继续找,最终经 `FullMatch` 命中真 1998 目标);只有 OCR 真读不出时才退回信任徽章(保住真目标的兜底),`SelectMode` 相应记为 `BadgeOnlyOcrUnreadable`。纯函数验证:VIVIO 串(徽章+可读)→ 不选;1998 斯巴鲁(徽章+可读)→ 选;徽章+OCR 失败 → 选。

> **提醒:** 别去试图用颜色区分「全新」徽章与「极限竞速特别版」金徽章——太脆。正确的兜底层是**决策层**:没有 OCR 正面确认目标关键词,就不选(徽章只当预筛,不能单独定案)。此规则对任何**其它带徽章的特别版斯巴鲁**同样有效。

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
- 四个宏写死在 `UltimateLib.ps1`:`Get-DefaultUltimatePreludeSteps` / `Get-DefaultUltimateAfterCodeSteps` / `Get-DefaultUltimatePostSequenceSteps` / `Get-DefaultUltimatePostBuySteps`。改宏改这里,**并更新本文档对应表格**。
- FindNewSubaru 的整段循环是 `AutomationLib.ps1` 里的共享函数 `Invoke-AutomationFindNewSubaruLoop`(Automation 与 Ultimate 共用)。改 FindNewSubaru 行为只改这一处,两边同时生效。
- 加新阶段要同时改 worker 主流程顺序、可能的 `Resolve-UltimateRuntimeOptions` 选项、GUI、`StartUltimate.ps1`,以及本文档。**新阶段也要用 `Test-UltimateShouldRunStep -StepNumber N` 包一层**(N = 它在顶层表里的步号),否则 Debug start step 跳不过/跳不到它;同时更新上面「调试」一节的编号对应表。
- 本文档未列入 `BuildRelease.ps1` 的发布清单(内部规格文档,不随发布包分发)。如需随包分发,把 `ULTIMATE.md` 加进 `$rootFiles`。
