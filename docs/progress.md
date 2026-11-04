# 开发进度

目标：参考 [nanoterm](../nanoterm)（nanoui + 内嵌 fx agent 的 Zig 桌面应用），
复刻 noop 影片中的「AI agent 团队指挥台」。当前为第一个可用版本（M1）。

## 里程碑

### M2：交互与可观测性完善（2026-11-03 进行中）

- [x] 任务时长动起来：Task 增加 `started_at_ms` 真实时间戳，运行中任务的
      "N 分钟"按墙钟实时换算（侧边栏、任务页、机器页三处）
- [x] fx 工具调用结构化展示：接入 `embedded_tool` 回调，每次工具调用渲染为
      右侧等宽卡片（工具名 · 状态 + 截断的输出摘要）
- [x] 诊断输出合并：fx raw 模式逐行推送的 shell 输出（diagnostic）合并为
      一张整宽等宽卡片；"Running …"回声由结构化工具卡片取代，不再重复显示
- [x] 任务取消：活动 fx 回合的任务页显示「× 取消任务」，点击后
      `runtime.cancel()`、任务标记为新的 `cancelled` 状态并移入「最近」分组
- [x] 消息流自动跟随底部：滚动容器改用 `follow_end`（用户上翻时不打扰，
      回底部后恢复跟随）
- [x] 侧边栏「团队频道」的待决定计数改为动态
- [x] Agent 设置页（侧边栏底部 ⚙）：读取并展示 fx 的 ~/.fx/settings.json
      （提供商、模型、自定义提供商的 base_url 与凭证环境变量、FX_PROVIDER /
      FX_MODEL 环境变量覆盖提示）；表单经 fx 的 settings store 写回
      （`provider`、`models` 映射、`providers` 定义 upsert 并选中），
      下一条指令生效；两个表单各自独立的结果提示
- [x] UI/UX 打磨：决策卡片使用消息的真实 agent 头像与名字（原先写死
      Ferris）；进度时间线的失败步骤红点标记；顶栏「N 项待决定」pill 可点击
      回频道；输入框点击空白处聚焦；决策选项与侧边栏条目的 hover 高亮修复
      （nanoui 要求 `.bg()` 在 `.hover()` 之前）；离线机器在侧边栏显示红色
      「离线」、机器页显示离线 chip 并用说明卡片替代资源仪表；「排队」分组
      增加计数；设置页错误提示红色、成功绿色
- [x] Projects 版块：侧边栏「项目」分组 + 项目列表页（路径输入添加，
      realpath 规范化与目录/重复校验）+ 项目详情页（设为目标、移除、
      项目任务列表）；每个项目绑定独立 fx 会话，选中的项目接收频道输入框
      的指令并在其目录中执行；频道头部显示当前目标 chip，输入框占位符
      提示执行位置；任务带 project 归属，取消按回合所属 runtime 中止
- [x] 项目内交互式 agent 会话（fx cli / Cursor 式）：项目页「进入 agent
      会话」→ 会话页多轮对话，回合在项目目录执行，fx session 跨回合保持
      上下文；忙碌时头部显示「运行中」与「中止」；会话线程复用频道的
      气泡/工具/诊断渲染；projects 改存堆指针以稳定 runtime 回调 context
- [x] GitHub 监听（调研 rerun / Meta Muse / Grok Bot 后选的 Grok Bot
      式轮询方案）：监听页添加 owner/repo + 检查目标（PR / Issue）+
      间隔（5/15/30/60 分钟）；1 秒调度 tick（`nanoui.App.after` 自回泵）
      到点唤醒 watcher 专属 fx 会话，指令要求 gh（未登录则 curl GitHub
      公开 API）查询、对比会话历史只报新增；首次检查建基线（「基线已
      建立」），无新动态回复「无新动态」安静结束，发现则推送到团队频道
      （watcher 头像）并记任务（W- 序号，routine）；详情页含状态卡片
      （上次检查/结论/下次检查/累计）、立即检查、暂停/启用（恢复即查）、
      移除、检查记录（复用频道渲染，follow_end）；侧边栏「监听」分组
      显示倒计时/检查中/已暂停；任务页可取消检查；列表持久化到
      ~/.nanodot/watchers.json（重启恢复，启动即补一次检查）；已汇报
      编号持久化（reported，上限 100，指令附最近 24 条「不要重复报告」），
      重启后不再依赖会话记忆去重，重复汇报与误报都大幅减少
- [x] 监听发现升级为决策卡：从发现回复解析 `#编号` 生成 D- 序号决策
      卡（A 快速审阅 / B 派任务完整审查 / C 忽略），卡片入侧边栏「待你
      决定」并动态计数；A/B 在 hub runtime 起真实审查回合（gh pr diff，
      不可用降级 curl .diff），生成 T- 序号任务、流式回频道；C 把编号
      写入 watcher 持久化忽略清单（检查指令附带「已忽略不要报」），
      watcher 变更索引时按 repo 校验再执行；动态决策的字符串在退出时
      释放（seed 决策为静态数据不动）
- [x] 已汇报编号持久化（reported）：基线与发现解析出的编号去重合并
      （上限 100，指令附最近 24 条「不要重复报告」），重启后检查不再
      依赖 fx 会话记忆去重；无历史可对比时（如基线后新条目出现）指令
      改为「列出当前最新 3 条」完成自举，避免模型保守漏报
- [x] GitHub webhook 接收器（设置页配置，调研 rerun 的入站触发模式）：
      127.0.0.1 本地 HTTP 服务（std.Io.net），POST /hook/<token>，token
      首次随机生成；可选 Secret 对 X-Hub-Signature-256 做 HMAC-SHA256
      常量时间验签；接收线程只入队，调度 tick 每秒在 UI 线程弹出（不
      跨线程碰状态）；事件按仓库唤醒对应监听（约 1 秒内开始检查），
      轮询照旧兜底；ping 连通探针照常记录；设置页含启用开关、端口、
      Hook URL（可复制）、Secret、GitHub 配置流程指引（smee/ngrok
      暴露说明）与最近 20 条事件记录（✓/✗ 验签状态）；配置持久化
      ~/.nanodot/settings.json
- [x] 修复两个崩溃：频道消息 for 迭代在选项点击追加消息导致
      ArrayList 重分配后继续在已释放缓冲区上迭代（改索引循环 +
      note() 对空 agent 兜底）；onAgentEvent 诊断卡片把事件缓冲直接
      存进消息、回调后缓冲被释放，后续增长触发 @memcpy alias
       panic（改为 dup）

### M1：单机可用版（2026-11-03 完成）

- [x] 项目骨架：`build.zig` / `build.zig.zon`，nanoui 与 nanoterm 同 pin；
      fx 通过 `../nanoterm/vendor/fx`（nanoterm 已打补丁的 submodule）编译进
      本应用，可用 `-Dfx-root` 覆盖
- [x] 数据模型与演示内容：决策卡（D-0001/0008/0010）、任务（T-0059/0089/0096/
      0100/0105 等，含请求/结果/进度全文）、三台机器、频道消息，均复刻自影片
- [x] 三页 UI（nanoui 原生深色）：
  - 侧边栏：待决定 / 进行中 / 排队 / 最近 / 机器，含计数徽标与状态色点
  - 团队频道：消息流（agent 汇报、老板右对齐气泡）、决策卡片（A/B/C 选项）、
    底部输入框（bare multiline textField + 发送按钮）
  - 任务详情页：状态 chip、元信息行、请求 / 结果 / 进度时间线
  - 机器详情页：负载 / 内存 / 磁盘仪表（高负载橙色）、工具与账号 chips、
    该机任务列表
- [x] fx agent 内嵌运行：工作线程执行 `engine.run`，text / diagnostic / done /
  failed 事件经互斥队列 + `nanoui.App.after` 泵回 UI 线程，流式追加到频道消息
- [x] 决策交互闭环：点选选项 → 卡片标记选中 → 追加老板决策消息与 hub 确认 →
  侧边栏待决定计数实时减少

## 验证记录（全部 headless，`--nanoui-snapshot`，未在用户屏幕弹窗）

| 项目 | 方法 | 结果 |
| --- | --- | --- |
| 构建 / 单测 | `zig build` / `zig build test` | 通过 |
| 频道页渲染 | 快照截图 | 消息流、决策卡 D-0010、输入框均正确 |
| 任务页渲染 | `at:100,212` 点击侧边栏任务后快照 | T-0059 请求/结果/进度完整 |
| 机器页渲染 | `click:huacnlee-macbook` 后快照 | 资源仪表、工具 chips、任务列表正确 |
| 决策交互 | 点击选项 A 后快照 | 选中态、确认消息、计数 3→2 正确 |
| fx 端到端 | 输入「看一下当前目录」+ `live:25` | 中文回复 + `pwd && ls -la && git status` 工具调用；工具卡片「shell · success」+ 诊断合并卡片 + 「任务完成」消息；任务自动移入「最近」 |
| 任务取消 | 输入长任务 → 打开任务页 → 点击「× 取消任务」 | 状态变为「已取消」，移入「最近」，进行中计数恢复 |
| 设置页读取 | 点击 ⚙ 后快照（真实 HOME） | 正确显示自定义提供商 magpie、本地 base_url 与"跟随提供商默认"的模型 |
| 设置页写入 | 临时 HOME 下点击「添加并选中」与「保存」 | providers.local.base_url 被改写；模型写入 models.local；预填（含凭证环境变量）在重开页面后正确回显 |
| UX 打磨 | T-0089 任务页、omarchy-jason 机器页、频道页快照 | 失败步骤红点、离线机器说明卡片与红色「离线」标记、排队计数正确显示 |
| Projects | 添加 /tmp/nd-proj → 频道发「pwd」→ 快照 | 项目出现在侧边栏并标记「目标」；频道头部目标 chip 与占位符提示生效；工具卡片 cwd 为 /private/tmp/nd-proj，任务在项目目录执行 |
| 项目会话 | 添加项目 → 进入会话 → 两轮对话 → 快照 | 第一轮「记住 4242」、第二轮「我让你记的数字是？」正确答出 4242——fx session 跨回合保持上下文，回合在项目目录执行 |
| 监听 | 隔离 HOME（拷贝真实 ~/.fx）→ 添加 vercel-labs/fx → live:55 → 详情页与频道快照 | 添加后调度 1 秒内触发基线检查；agent 先用 gh（未登录）再自动降级 curl 公开 API，工具卡片成功；频道收到 watcher 推送的新 PR（#1602 等，含链接+中文摘要）；计数「检查 N 次·发现 M 次」正确；watchers.json 重启后恢复（计数保留、下次检查「即将」并补查） |
| webhook | 预置 settings.json（启用+secret）→ 启动 app → 并行 curl 投递 4 类请求 → 设置页快照 | 无签名 404（验签失败记录）、正确 HMAC 200、错误 token 404、ping 200；事件列表与「运行中 · 127.0.0.1:9781」状态正确；投递 sternelee/nanodots 后该 watcher 约 1 秒内被唤醒（侧边栏「检查中」） |
| 决策卡交互 | 建 issue#4 → live:175 → click:快速审阅 → live:75 → 快照 | nanodots 检查发现 #4 → 频道决策卡（待决定 3→4）；点 A 后卡片标记已选、待决定恢复 3、hub runtime 起「review: sternelee/nanodots #…」任务；审阅回合流式输出 gh 工具卡片（fx 子环境 gh 未登录按指令降级）与诊断卡片 |

## 排障记录

- **容器嵌套错乱（主要 bug）**：nanoui 的 `.end()` 只弹内层盒子栈。最初在函数作用域
  用 `defer box.end()`，defer 到函数退出才执行，导致后续同级容器全部嵌进前一个
  容器（侧边栏文字挤压重叠、决策卡片空白）。修复：所有视图改为显式 `.end()` 或
  块级作用域 defer。定位手段：`ui.Tester` 单测 dump 节点 rect。
- **u24 颜色**：`ui.Color.hex` 参数是 `u24`，颜色常量与组件参数需统一。
- **`std.time.milliTimestamp` 移除**：改用 fx 的 `shared_io.milliTimestamp()`。

## 已知限制

- 团队状态来自 `src/seed.zig` 种子数据（真实 noop 服务端是私有的）；频道
  输入、项目会话与仓库监听是真实事件驱动
- 决策点选后只更新本地状态，不会真实触发合并/关闭 PR
- 只有「hub」一个真实 fx 会话；演示中的 Ferris / Hermes 是静态消息
- fx 运行依赖本机 `~/.fx` 的提供商凭证；无凭证时失败原因以普通消息进频道
- 尚未接 nanoterm 的 ACP 通道，外部 agent（claude / codex 等）不能接入
- watcher 的 fx 会话与检查记录不持久（只持久列表、计数与已汇报编号），
  重启后首次检查按已汇报编号去重，无历史时退化为「列出最新 3 条」
- webhook 接收器绑定 127.0.0.1，GitHub 无法直接推送；需要先用
  smee.io / ngrok 等把端口暴露到公网。Secret 明文存放在本机
  ~/.nanodot/settings.json
- gh 未登录时 watcher 走 GitHub 公开 API（未认证限额 60 次/小时）；
  私有仓库监听需要先 `gh auth login`。审阅回合跑在 fx 子进程里，看不到
  钥匙串里的 gh 登录态：私有仓库审阅需 `export GH_TOKEN`，否则按指令
  降级 curl 公开 API（只能读公开内容）

## 下一步（M2 剩余 / M3 候选）

- [x] ~~任务状态接入真实事件源~~ — 已由仓库监听覆盖 GitHub 侧；
      其余事件源（CI、YouTrack）待接
- [ ] watcher 报告升级为决策卡（发现新 PR 时让老板在卡片里决定
      「审阅 / 派任务 / 忽略」），并支持 YouTrack 轮询
- [ ] 多 agent：为不同角色建独立 fx 会话（独立 session_id），按任务路由指令
- [ ] 决策与真实动作挂钩（合并 PR / 打 tag 前走 fx 工具执行）
- [ ] macOS 打包（参考 `nanoterm/macos/package.sh`）与自动更新
