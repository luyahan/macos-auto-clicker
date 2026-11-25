# macOS Auto Clicker 代码审核报告

## 1. 审核概况

- **仓库**：`/Users/luyahan/Documents/Work/source/macos-auto-clicker`
- **审核时间**：2026-11-25
- **分支 / HEAD**：`main` / `a264f20be5059a6572614171b34aa9ad6187dade`
- **审核对象**：当前工作树，而非仅 HEAD。审核前工作区已有 9 个修改项，涉及宏模型、事件模拟、宏运行器、设置面板、本地化、`Info.plist` 和 `.DS_Store`；这些修改不是本报告产生的。
- **方法**：人工静态审查、调用链追踪、全仓关键词检查和 Git 只读检查。
- **范围**：生产 Swift 代码、宏与偏好持久化、事件注入、权限、通知、菜单栏、Xcode 构建脚本、依赖锁、GitHub Actions、Fastlane、Makefile 和安装说明。
- **验证边界**：未编译、未启动应用、未执行 SwiftLint、未发送真实键鼠事件、未修改权限或偏好。下文“静态确认”表示代码路径可确定，“风险”表示仍需隔离环境验证实际系统行为。

> 本报告中的行号对应当前工作树。工作区已有修改可能使它们与 HEAD 或其他分支不同。

## 2. 执行摘要

当前最优先的问题不是代码风格，而是**自动操作与用户意图不一致**：空的同时按下宏会退化为普通左键，侧键会被执行为左键，目标应用限定不能约束一轮内的全部事件。同步睡眠又会延迟停止操作，放大非预期输入的影响。

共记录 **16 项问题/改进项**：高 3 项、中 9 项、低 4 项。

| 优先级 | 问题             | 首要处理方向           |
| --- | -------------- | ---------------- |
| P0  | 空宏回退左键、侧键映射左键  | 拒绝无效宏，修正按钮映射     |
| P1  | 应用限定间隙、主线程同步睡眠 | 可取消调度，逐事件检查并保证释放 |
| P1  | 配置边界与权限门禁      | 统一执行前校验，撤权即停止    |
| P2  | 构建副作用、公证与 CI   | 隔离构建副作用，完善发布链    |

建议修复顺序：先处理 H-01、M-01，再重构 H-02、M-02，随后统一配置校验与权限门禁，最后处理构建、公证和 CI。项目没有测试 target，修复核心逻辑时应同步补充纯逻辑测试。

## 3. 高严重度问题

### H-01：空的同时按下宏、仅修饰键宏会静默退化为左键

**位置**

- `auto-clicker/Models/Macro.swift:264-308,315-322`
- `auto-clicker/Observable Objects/MacroRunner.swift:70-100`
- `auto-clicker/Observable Objects/AutoClickSimulator.swift:97-101,416-454`
- `auto-clicker/Models/Input.swift:28-35`

**静态确认**

1. 同时按下模式只拒绝多个普通键，不拒绝空 `caps`；长按仅检查 `caps.isEmpty`，也不拒绝仅修饰键。
2. 两者找不到普通按键或鼠标键时，`pressInputs` 返回空数组。
3. `MacroRunner.start()` 只依据 `unsupportedReason` 拒绝运行，随后将 `pressState` 交给模拟器。
4. 模拟器过滤后将空输入替换为 `[Input()]`，而 `Input()` 是无修饰键的普通左键。
5. 设置面板允许删除全部按键：`MacroSettingsPanel.swift:225-231,300-307`，所以空宏不只是理论上的手工配置。

**影响**

- 空的同时按下宏会执行普通左键。
- 同时按下或长按仅含 `CMD` 等修饰键时，也会执行左键；长按路径会保持按下约 2 秒再释放。

这会使“没有可执行输入”变成一次真实 UI 操作，属于本仓库最高优先级的正确性和安全问题。

**修复方向**

在 `Macro.unsupportedReason` 和统一运行入口同时拒绝 `pressInputs.isEmpty`；显式宏运行不得使用默认左键兜底。默认左键若用于旧版普通设置迁移，应限定在迁移逻辑中，而非执行层。

**建议测试**

分别覆盖 simultaneous 的空数组、仅 `CMD`、仅 `CMD+SHIFT`，以及 longPress 的仅修饰键；预期均为拒绝运行且不创建任何事件。

### H-02：应用限定只按轮检查，不能约束一轮内的每个事件

**位置**

- `auto-clicker/Observable Objects/MacroRunner.swift:90-100`
- `auto-clicker/Observable Objects/AutoClickSimulator.swift:227-251,416-454`

**静态确认**

目标 Bundle ID 只在 `performRound()` 开头比较一次。一轮内可连续投递多个 down/up 事件，输入之间还会睡眠；所有事件统一发到 `.cghidEventTap`，没有绑定目标进程。

**风险与影响**

依次触发宏执行期间，如果前一个输入导致应用切换，或用户在输入间隔切换应用，后续输入可能进入另一个应用。检查与投递之间也存在前台应用变化窗口。因此“仅目标应用执行”目前更接近“仅在前台为目标应用时开始一轮”，不是逐事件安全边界。

另一个确定的行为是：目标不匹配时直接 `return`，不减少剩余次数也不停止 Timer；界面可继续显示运行，但实际没有事件执行。

**修复方向**

- 在每个 down/up 事件前重新检查目标，目标变化时取消本轮并保证已按下的输入被释放。
- 将阻塞睡眠替换为可取消的异步调度。
- 评估进程定向投递，但需验证其事件语义，不能假定它与 HID 注入等价。
- 明确 Bundle ID 只标识应用，不区分同一应用的多个进程实例。

**建议测试**

使用至少 4 个输入、输入间隔 2 秒的应用限定顺序宏，在第一个输入后切换到隔离测试应用，确认后续输入不会落入新应用；另测目标不匹配时的状态显示和停止行为。

### H-03：发布链未配置 Developer ID 公证，文档指导绕过 Gatekeeper

**位置**

- `auto-clicker.xcodeproj/project.pbxproj:817-847`
- `fastlane/Fastfile:53-70,120-141`
- `README.md:119-147`

**静态确认**

Release 配置使用 `Apple Development` 签名身份；发布流程包含构建、压缩和上传，但未见 Developer ID 签名、公证、stapling 或最终产物门禁验证。README 明确说明未公证，并指导用户点击 `Open Anyway`。

**影响**

应用具备辅助功能和事件注入能力，却要求用户绕过系统分发保护。用户难以确认下载物是否被替换，也无法获得公证提供的基本分发检查。此项影响正式发布安全，不代表源码本身含有恶意行为。

**修复方向**

使用 Developer ID Application 签名，在 CI 中完成公证和 stapling，对最终 ZIP 内的应用执行门禁验证，并发布 SHA-256 校验值。公证完成前，应将其视为正式发布限制，而不只是文档说明。

**建议验证**

对最终发布产物执行 `codesign --verify --deep --strict`、`spctl -a -vv -t execute` 和 `xcrun stapler validate`，核对 Team ID、签名时间戳、hardened runtime 和公证票据。本次未执行这些命令。

## 4. 中严重度问题

### M-01：鼠标侧键被错误执行为左键

**位置**

- `auto-clicker/Views/Main/TriggerPilot/Components/KeyCapView.swift:185-192`
- `auto-clicker/Models/Macro.swift:72-78,129-140`
- `auto-clicker/Models/Input.swift:45-58`
- `auto-clicker/Observable Objects/AutoClickSimulator.swift:384-396`

**静态确认**

录制时侧键通过 `event.buttonNumber` 保存为 3 或更大；但 `Input(mouseButton:)` 只特殊处理 1 和 2，其他值（包括 0、3、4……）都进入 `default`，被设为 `.leftMouseDown`。模拟器只有映射结果为 `.center` 时才使用原始按钮号，因此侧键无法走该分支。

**影响**：用户录制侧键，实际却注入左键，可能触发完全不同的 UI 操作。

**修复方向与测试**：将非左右键统一映射为 `.otherMouseDown`，保留经过边界检查的按钮号；对 0、1、2、3、4、5 分别做映射单元测试，再在隔离环境用事件监视工具验证实际投递。

### M-02：主线程同步睡眠延迟 UI、停止与按键释放

**位置**

- `auto-clicker/Observable Objects/AutoClickSimulator.swift:67-145,219-251,416-454`
- `auto-clicker/Views/Main/TriggerPilot/TriggerPilotView.swift:18-29`
- `auto-clicker/Init/AppDelegate.swift:13-111`

**静态确认**

首次 `performRound()` 由 `start()` 直接同步调用，后续由主 RunLoop 的 `Timer` 调用。输入间隔和长按时长均通过 `usleep` 实现，长按的 up 事件只在睡眠结束后发送。未发现将 `press()` 移到后台线程的调度，也没有 `applicationWillTerminate` 停止/释放清理。

**风险与影响**

- 同步睡眠期间，主线程上的 UI、Timer 和停止处理会被延迟。
- 设置面板允许输入间隔最大 2 秒，5 个输入一轮可产生约 8 秒的内部间隔；长按另固定睡眠约 2 秒。
- 在 down 与 up 之间异常终止，存在遗留按下状态的风险，实际系统表现未运行验证。

**修复方向与测试**

改为可取消的 Timer、DispatchQueue 或结构化 Task 调度，用集中状态机/`defer` 保证释放；停止和退出必须取消待执行任务。补充“长按时立即停止”“输入间隔中停止”“退出时释放”的测试，并用 Instruments 检查主线程阻塞。

### M-03：持久化配置缺少统一执行前校验，存在崩溃与资源耗尽路径

**位置**

- `auto-clicker/Models/FormState.swift:73-97`
- `auto-clicker/Models/Macro.swift:226-241,315-326`
- `auto-clicker/Models/Input.swift:45-58`
- `auto-clicker/Observable Objects/AutoClickSimulator.swift:88-115,227-247,354-396,416-495`
- `README.md:155-175`

**静态确认与触发条件**

解码逻辑提供缺省值，但不统一验证范围、数组长度或字段一致性。示例：

- `pressIntervalMin > pressIntervalMax` 时，`Int.random(in: min...max)` 会因非法闭合区间触发运行时错误（`AutoClickSimulator.swift:90-94,238-243`）。
- `interval * max(0, repeatAmount - 1)` 等 `Int` 运算可能溢出（`AutoClickSimulator.swift:103-115`）。
- 宏的 `delaySeconds` 直接转换为 `Int`；非有限值或超范围值存在转换风险（`Macro.swift:321-322`）。
- 非法鼠标按钮整数转 `UInt16` 存在转换风险（`Input.swift:58`）。
- `inputInterval`、`holdInterval` 转 `UInt32`、乘以 1000 后睡眠，未做上限和溢出保护（`AutoClickSimulator.swift:440-452`）。
- 事件类型字典和可选 `CGEvent` 被强制解包；不支持的鼠标事件类型或事件创建失败可导致崩溃（`AutoClickSimulator.swift:360-361,390,432-435,469,489`）。

**影响与边界**

主要威胁是损坏配置、旧版配置或手工迁移配置导致的可靠性和可用性问题；未发现远程攻击者可直接提供这些值的入口。README 明确支持备份和迁移偏好文件，因此不能假设偏好永远由当前 UI 生成。

**修复方向与测试**

建立统一 `validatedForExecution()`，检查数值范围、有限浮点数、区间顺序、数组上限、输入类型一致性及溢出；`CGEvent` 创建失败应安全停止。为损坏 JSON、极值、非法 EventType、空数组和超长数组添加 fixture 测试。

### M-04：辅助功能权限只限制界面，不是执行层的强制前置条件

**位置**

- `auto-clicker/Init/AppDelegate.swift:21-39`
- `auto-clicker/Observable Objects/MacroRunner.swift:70-113`
- `auto-clicker/Observable Objects/AutoClickSimulator.swift:67-145,197-209,254-257,416-459`
- `auto-clicker/Services/PermissionsService.swift:20-38`

**静态确认**

快捷键和可选的鼠标启动监听在权限确认前注册；`MacroRunner.start()` 和模拟器入口均不检查 `AXIsProcessTrusted()`。权限轮询一旦变为 trusted 就停止，未处理运行期间撤权。全局监听创建失败也没有用户可见错误。

**风险与影响**

无权限时仍可能进入“运行中”、调度通知和计数流程，无法区分实际投递与系统拒绝。权限撤销后没有统一停止逻辑。此处不是断言可以绕过 macOS TCC；实际事件是否被系统接受需运行验证。

**修复方向与测试**

在统一执行入口强制检查权限，应用重新激活时刷新状态，权限丢失时停止并释放事件；监听创建失败应反馈。覆盖未授权、运行中撤权、重新授权和干净 macOS 账户测试。

### M-05：每次构建都会重置辅助功能权限并改写源码树

**位置**

- `auto-clicker.xcodeproj/project.pbxproj:436-443,532-568`
- `auto-clicker/Build Assets/Info.plist:32-33`

**静态确认**

两个脚本属于统一 target build phases，没有 Debug-only 条件：

|   |   |   |
| - | - | - |

- `tccutil reset Accessibility $PRODUCT_BUNDLE_IDENTIFIER || true` 每次构建执行，并忽略错误。
- `PlistBuddy` 将 git 短哈希直接写入受版本控制的 `Info.plist`，而非仅修改构建产物。

**影响**

本地 Release 构建也会撤销同 Bundle ID 应用的辅助功能授权；构建会弄脏工作区并降低可重复性，错误被忽略后还会掩盖真实权限状态。本次审核因此没有运行构建。

**修复方向与测试**

权限重置改为显式 opt-in 的 Debug-only 开发脚本；版本写入构建产物，不修改源文件。在隔离测试账户记录构建前后 TCC 状态、`git status` 和最终产物 plist。

### M-06：发布 CI 使用可变 Action 引用，令第三方构建链接触发布令牌

**位置**

- `.github/workflows/cicd.yml:13-44`
- `.github/workflows/swiftlint.yml:24-46`
- `fastlane/Fastfile:81-99,127-141`

**静态确认**

工作流使用 `actions/checkout@v3`、`ruby/setup-ruby@v1`、`maierj/fastlane-action@v3.0.0` 等标签，而非不可变提交 SHA；未声明显式最小 `permissions`。Fastlane action 直接获得 `GITHUB_TOKEN`，构建链可推送提交、标签并创建 Release。

**影响**

上游 Action 或构建依赖被 compromise 时，影响可扩展到源码和 Release。实际令牌权限取决于仓库设置，本次无法仅凭源码确认；未发现明文令牌。

**修复方向与测试**

固定 Action 完整 SHA；显式声明最小权限；checkout 设置 `persist-credentials: false`；拆分无令牌构建与受环境保护的发布 job，仅发布步骤获得写令牌。用 actionlint 和测试仓库验证权限。

### M-07：宏启动通知不遵守通知开关，可能暴露宏名称

**位置**

- `auto-clicker/Observable Objects/MacroRunner.swift:110-121`
- `auto-clicker/Observable Objects/AutoClickSimulator.swift:127-135`
- `auto-clicker/Constants/Defaults.swift:43-44`

**静态确认**

通用 Started 通知读取 `Defaults[.notifyOnStart]`，但宏名称通知由 `MacroRunner.run()` 无条件调度。宏名称会进入系统通知内容。

**影响**

用户关闭开始通知后仍可能看到宏启动通知；通知中心可能显示用户自定义的敏感宏名。

**修复方向与测试**

宏通知复用统一通知策略，避免绕过开关；测试授权后关闭开关、未授权通知和宏名隐私场景。

### M-08：完成通知存在取消和时序问题

**位置**

- `auto-clicker/Observable Objects/AutoClickSimulator.swift:109-145,148-189,227-251`
- `auto-clicker/Services/NotificationService.swift:12-38`

**静态确认**

开始运行时就按 `finalClickAt` 调度完成通知，而自然 `stop()` 会移除全部待处理通知。单轮运行会先安排完成通知，再立即执行第一轮并停止，因而取消刚安排的完成通知。通知使用随机 UUID，无法按运行实例精准取消；添加通知的错误也被忽略。

**影响**

完成通知可能不出现、与当前运行不匹配，或在目标应用不匹配导致运行暂停时仍按原时间触发。

**修复方向与测试**

将完成通知与实际完成状态绑定，按 run ID 管理通知；自然完成、手动停止、鼠标停止、目标不匹配分别测试，并处理系统通知错误。

### M-09：依赖更新命令使用 `sudo`

**位置**：`Makefile:5-11`

`make update` 执行 `sudo bundle update fastlane`，随后更新插件。以 root 权限更新 Ruby 依赖会扩大依赖安装脚本的影响范围，并可能污染系统 Ruby 环境。这属于开发链安全改进项，不是已发现恶意依赖。

建议改用用户级 Bundler 环境和锁定依赖，在干净 CI 环境验证无需提权的安装与执行流程。

## 5. 低严重度问题

### L-01：长按模式接受多个普通键，但只执行第一个

**位置**：`auto-clicker/Models/Macro.swift:276-308`；`auto-clicker/Views/Main/TriggerPilot/MacroSettingsPanel.swift:695-721`

`pressInputs` 对 simultaneous 和 longPress 都只选择第一个键，但保存前的裁剪只应用于 simultaneous；longPress 不拒绝多个普通键。用户看到的宏和实际执行内容不一致。应明确长按只支持单键并拒绝/提示，或正式实现多键语义；测试 `A+B` 和 `CMD+A+B`。

### L-02：状态栏销毁未显式移除 `NSStatusItem`

**位置**：`auto-clicker/Services/MenuBarService.swift:35-58,124-140`

`create()` 每次创建新状态栏项，`destroy()` 只清空静态引用，未显式调用 `NSStatusBar.removeStatusItem`。反复切换状态栏图标或快捷键存在重复项/生命周期异常的风险；是否出现重复图标需运行确认。建议销毁前显式移除并清空关联菜单引用。

### L-03：Debug 日志记录按键、修饰键和鼠标坐标

**位置**：`auto-clicker/Services/LoggerService.swift:11-18,57-69`

日志由 `#if DEBUG` 排除于 Release，这是正面控制；但开发日志仍可能持久化敏感操作。建议改用统一日志的 privacy 脱敏，避免记录完整按键和坐标，或仅在显式诊断开关下记录。

### L-04：链接了未使用的 SwiftPM 依赖 `DateStrings`

**位置**：`auto-clicker.xcodeproj/project.pbxproj:449-453,873-879,907-912`

target 链接 `DateStrings`，但应用 Swift 源码未检索到对应 import 或引用。移除未使用依赖可减少构建与供应链表面。此项只说明当前源码未见使用，不代表依赖存在漏洞。

## 6. 测试缺口与建议

**现状**：未找到测试文件；`auto-clicker.xcodeproj/xcshareddata/xcschemes/auto-clicker.xcscheme:25-32` 的 `Testables` 为空。没有本次可运行的现成测试套件。

建议优先增加不依赖真实键鼠注入的纯逻辑测试：

1. **宏结构与映射**：空宏、仅修饰键、多普通键、鼠标按钮 0/1/2/3+、组合修饰键。
2. **配置校验**：缺失字段、反向区间、极值、非有限浮点数、非法事件类型、旧配置迁移。
3. **运行状态机**：开始、逐轮结束、目标不匹配、手动/鼠标停止、取消长按、退出释放。
4. **通知策略**：开关、自然完成、提前停止、目标暂停、通知授权失败。
5. **事件抽象层**：将事件创建和投递抽象为协议，用 fake 记录 down/up 顺序、按钮号和目标检查次数，避免测试真实操作系统 UI。


动态测试应在专用 macOS 测试账户和无害测试应用中进行，先修复构建时的 TCC 重置，再验证权限、实际投递和 Instruments 主线程阻塞。

## 7. 正面发现

- Debug 和 Release 均启用 hardened runtime：`project.pbxproj:785-847`。
- 未发现禁用 library validation、允许 JIT 等额外高风险 entitlement；应用明确关闭 App Sandbox：`auto_clicker.entitlements:5-8`。非沙盒不自动等于漏洞，但意味着一旦被利用，默认拥有当前用户权限，应谨慎控制依赖和发布链。
- SwiftPM 使用精确版本及锁文件，Ruby git 插件也锁定 revision：`Gemfile.lock:1-5`。
- <u>未</u>在应用 Swift 源码发现明文密码、私钥或访问令牌，未发现运行时网络上传、任意 shell 执行或任意文件删除路径。
- 全局监听只匹配鼠标移动；键盘录制发生在应用内第一响应者/局部监听，未发现全局键盘记录器。
- 宏编辑面板在正常消失路径移除局部鼠标监听：`MacroSettingsPanel.swift:85-89,275-282`；模拟器正常停止路径也移除监听。
- `MacroRunner` 统一了菜单、快捷键和界面启动路径，并对无激活宏、不支持组合等情况提供拒绝原因；问题集中在校验覆盖和执行语义，而非完全没有防护。

## 8. 残余风险与审核限制

- 本报告是**静态审核**，不是渗透测试、运行时安全认证或第三方依赖完整审计。
- 未编译、未运行 SwiftLint、未执行测试、未检查最终发布二进制签名；不能据此表述“构建通过”“测试通过”或“无安全问题”。
- 未在线核查依赖 CVE，也未展开 SwiftPM/Ruby 依赖源码；锁定版本只提升可重复性，不证明版本无漏洞。
- 真实 `CGEvent` 投递、TCC 撤权、状态栏重复、通知显示和 Instruments 行为均需后续隔离验证。
- 本次未运行构建的重要原因，是构建脚本会重置辅助功能权限并改写源码 `Info.plist`；也未启动应用或发送任何键鼠事件。

---

**结论**：优先消除非预期左键和侧键错误，随后将事件执行重构为可取消、逐事件受目标约束且保证释放的状态机，再补齐配置校验、权限门禁和自动化测试。发布前还应移除构建副作用并完成 Developer ID 公证与 CI 权限隔离。

---

## 9. 修复实施记录（2026-11-25）

报告列出的 16 项均已在当前工作树处理：

| ID | 处理 | 关键位置 |
|---|---|---|
| H-01 | `unsupportedReason` 拒绝空/仅修饰键/多非修饰键的 chord；模拟器不再用 `[Input()]` 兜底 | `Macro.swift`、`MacroRunner.swift`、`AutoClickSimulator.swift` |
| H-02 | 逐事件检查目标 bundle ID；目标不匹配或运行中切换时停止并用 run token 取消；事件投递移到串行后台队列 | `AutoClickSimulator.swift` |
| H-03 | Release 改用 Developer ID Application；Fastlane 增加 notarize/staple/codesign 验证和 SHA-256；README 更新 | `project.pbxproj`、`Fastfile`、`README.md` |
| M-01 | 按钮 0 为左键、1 为右键、其余（含侧键）为 `.otherMouseDown` 并保留按钮号 | `Input.swift`、`AutoClickSimulator.swift` |
| M-02 | `usleep` 改为可取消的条件等待；停止会唤醒并释放已按下输入；终止时清理 | `AutoClickSimulator.swift`、`AppDelegate.swift` |
| M-03 | 新增 `FormState/Macro.validatedForExecution()`，钳制区间、次数、时长、数组长度；移除事件字典强解包并用饱和乘法 | `FormState.swift`、`Macro.swift`、`Input.swift`、`AutoClickSimulator.swift` |
| M-04 | 执行入口检查 `AXIsProcessTrusted()`，每轮/每事件复核；权限轮询去重并在激活时刷新 | `MacroRunner.swift`、`AutoClickSimulator.swift`、`PermissionsService.swift`、`AppDelegate.swift` |
| M-05 | TCC 重置改为 Debug 且需 `RESET_ACCESSIBILITY=1`；版本号写入构建产物而不是源码 plist | `project.pbxproj` |
| M-06 | Actions 固定到 commit SHA；显式权限；lint 工作流 checkout 不持久化凭据 | 两个 workflow |
| M-07 | 宏启动通知遵守 `notifyOnStart`，且只在模拟器确实启动后发送 | `MacroRunner.swift` |
| M-08 | 通知带 run ID，停止只取消本次通知；完成通知仅在实际完成/鼠标停止时发送；处理添加失败 | `NotificationService.swift`、`AutoClickSimulator.swift` |
| M-09 | 移除 `sudo bundle update` | `Makefile` |
| L-01 | longPress 与 simultaneous 一样拒绝多按键，保存时同样裁剪 | `Macro.swift`、`MacroSettingsPanel.swift` |
| L-02 | `destroy()` 显式 `removeStatusItem` 并清空菜单引用 | `MenuBarService.swift` |
| L-03 | Debug 输入日志改为显式开关 `debug_verbose_input_logging` | `LoggerService.swift` |
| L-04 | 移除未使用的 `DateStrings` 依赖及锁文件条目 | `project.pbxproj`、`Package.resolved` |

**验证状态**：全部改动 Swift 文件通过 `swiftc -parse` 语法检查。用户手动执行 `xcodebuild` 后，构建暴露出两处由修复引入的编译错误并已修正：

1. `MacroRunner.swift` 调用 `AXIsProcessTrusted()` 但缺少 `import ApplicationServices`。
2. `AutoClickSimulator.swift` 的事件生成函数返回 `[CGEvent?]`，长按路径把首元素当成非可选 `CGEvent` 使用；现已改为返回过滤 nil 后的 `[CGEvent]`，投递路径同步改为非可选。

修正后，以当前工作树全部 Swift 源文件为输入、带上 macOS SwiftUI 宏插件路径的 `swiftc -typecheck` 已通过（`EXIT=0`）。完整 `xcodebuild` 仍需在用户终端重新执行，因为本会话环境的 SwiftPM manifest 沙箱限制会拦截包解析；未运行应用或真实键鼠事件。公证需要 CI 配置 `APPLE_ID`、`APPLE_APP_PASSWORD`、`APPLE_TEAM_ID` secrets。测试 target 仍未建立，建议按第 6 节优先级补充。
