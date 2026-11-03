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

## 排障记录

- **容器嵌套错乱（主要 bug）**：nanoui 的 `.end()` 只弹内层盒子栈。最初在函数作用域
  用 `defer box.end()`，defer 到函数退出才执行，导致后续同级容器全部嵌进前一个
  容器（侧边栏文字挤压重叠、决策卡片空白）。修复：所有视图改为显式 `.end()` 或
  块级作用域 defer。定位手段：`ui.Tester` 单测 dump 节点 rect。
- **u24 颜色**：`ui.Color.hex` 参数是 `u24`，颜色常量与组件参数需统一。
- **`std.time.milliTimestamp` 移除**：改用 fx 的 `shared_io.milliTimestamp()`。

## 已知限制

- 团队状态来自 `src/seed.zig` 种子数据（真实 noop 服务端是私有的）；只有
  通过输入框创建的 fx 任务是真实事件驱动
- 决策点选后只更新本地状态，不会真实触发合并/关闭 PR
- 只有「hub」一个真实 fx 会话；演示中的 Ferris / Hermes 是静态消息
- fx 运行依赖本机 `~/.fx` 的提供商凭证；无凭证时失败原因以普通消息进频道
- 尚未接 nanoterm 的 ACP 通道，外部 agent（claude / codex 等）不能接入

## 下一步（M2 剩余 / M3 候选）

- [ ] 任务状态接入真实事件源（本地 agent-hub 协议或 noop 服务器），替换种子数据
- [ ] 多 agent：为不同角色建独立 fx 会话（独立 session_id），按任务路由指令
- [ ] 决策与真实动作挂钩（合并 PR / 打 tag 前走 fx 工具执行）
- [ ] macOS 打包（参考 `nanoterm/macos/package.sh`）与自动更新
