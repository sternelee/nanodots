//! The demo workspace, seeded to look like the noop film: a Rust team's
//! agents working gpui-kit and nsh PRs across two hosts.
const model = @import("model.zig");
const Agent = model.Agent;
const Decision = model.Decision;
const Task = model.Task;
const Machine = model.Machine;
const Message = model.Message;

pub const ferris = Agent{ .name = "Ferris", .letter = 'F', .color = 0x8a9a5b };
pub const hermes = Agent{ .name = "Hermes", .letter = 'H', .color = 0xb0719e };
pub const hub = Agent{ .name = "hub", .letter = 'h', .color = 0x6e7681 };
/// The repo watcher's reports in the channel.
pub const watcher = Agent{ .name = "watcher", .letter = 'w', .color = 0x58a6ff };

pub const decisions = [_]Decision{
    .{
        .id = "D-0001",
        .title = "使用哪个告警来源？",
        .body = "候选：Uptime Kuma 自托管（已有一台）或 Grafana Alerting（团队已有 Grafana）。Kuma 五分钟接好但只有 webhook；Grafana 规则与现有面板共用，但配置繁琐。需要定一个方向，后续 on-call 流程照此搭建。",
        .options = &.{
            .{ .label = "A", .detail = "Uptime Kuma — 先跑起来，告警走 webhook 到团队频道" },
            .{ .label = "B", .detail = "Grafana Alerting — 与现有面板统一，一次配置到位" },
            .{ .label = "C", .detail = "两个都接 — Kuma 管存活，Grafana 管指标" },
        },
        .outcome = "按所选方案接入告警，搭好 on-call 流程后回报",
    },
    .{
        .id = "D-0008",
        .title = "合并 nsh #747 吗？",
        .body = "nsh #747 引入 lifecycle API，surface 属公共 API，且合并后会进入 0.2 之后的兼容性锁定，所以等所有者确认。",
        .options = &.{
            .{ .label = "A", .detail = "squash 合并 nsh #747 — lifecycle API 进入下周三的 NSH 发布" },
            .{ .label = "B", .detail = "要求继续修改 — 说明还有哪里不满意" },
            .{ .label = "C", .detail = "暂不处理 — PR 保持打开" },
        },
        .outcome = "合并 nsh #747，按发布流程进入下周的 NSH 发布",
    },
    .{
        .id = "D-0010",
        .title = "关闭 omamail #403 吗？",
        .body = "关闭 PR 必须由老板决定（自主政策），且老板的原则是贡献者 PR 尽量在原有基础上修而不是关闭；这是老板自己的 PR，但关闭同样不可逆，也没有先例。从技术上看 A 合理：main 的 #412 已经修好了同一个问题。",
        .options = &.{
            .{ .label = "A", .detail = "关闭 omamail #403 — main 已用另一种方式修好同一个超时，这个 PR 没有剩余价值" },
            .{ .label = "B", .detail = "保留并按 main 解决冲突，只留诊断代码 — PR 变成很小的诊断补充" },
            .{ .label = "C", .detail = "暂不处理 — PR 继续显示冲突" },
        },
        .outcome = "处理 omamail #403：任务已重新排队",
    },
};

pub const tasks = [_]Task{
    .{
        .id = "T-0059",
        .title = "gpu-kit: 升级到 gpu-pre 0.3.11 + gpu-fast 0.13",
        .role = "rust-maintainer",
        .host = "huacnlee-omarchy-lb",
        .model = "claude-opus-5-5",
        .status = .running,
        .started_min_ago = 2,
        .request = "把 workspace 里 gpu-kit 0.10.x 分支的 gpu-pre 0.10.8、gpu-fast 0.10.8 一起升到 gpu-pre 0.3.11 + gpu-fast 0.13（已发布，tag 打好了）。目前没有完全解决 gpu-fast 运行合并后的问题，只先升级。\n\nCargo.toml 里的 gpu-fast、gpu-fast-platform、gpu-fast-web 改成 0.1.13，然后运行 cargo update -w，并修复 API 变化。分别检查默认 feature 和 gpu-fast feature 下的 cargo check --workspace --all-targets，再跑相关的目标测试；不要做完整构建。推送分支并开 draft PR（英文、带签名），标题用组件前缀风格。验收标准：CI 全绿（重点看 Windows），PR 描述里列出 API 变化。不要打 tag，也不要发布；发布 0.8.2 时给老板发决策卡。",
        .result = "PR gpu-kit#3766（升级 gpu-pre 0.3.11 + gpu-fast 0.13）19 项 CI 全部通过，可合并。按老板指示尝试 squash 合并时被权限拦下；按 CONTRIBUTING 发布流程，合并后需提交 Bump v0.8.2（./script/bump-version.sh 0.8.2）并推送 tag v0.8.2 触发 crates.io 发布。",
        .result_status = "needs_decision",
        .progress = &.{
            "20:09 T-0059 Ferris/claude: gpu-kit: 升级到 gpu-pre 0.3.11 + gpu-fast 0.13",
            "20:09 T-0059 等待 PR gpu-kit#3766 最后一项 CI：GPU Shell Standard Runtime (x86_64-windows-msvc)",
            "20:30 T-0059 PR gpu-kit#3766 已通过 18/19 项检查，无失败，只剩 GPU Shell Standard Runtime (x86_64-windows-msvc) 在运行",
            "20:41 T-0059 PR gpu-kit#3766 已通过 19 项检查（含 Windows 的 Test 和 GPU Fast），无失败，按老板指示合并并发布 0.8.2",
        },
    },
    .{
        .id = "T-0089",
        .title = "nsh #810: 在 huacnlee-macbook 上补 iOS/macOS 修复前后对比截图",
        .role = "rust-maintainer",
        .host = "huacnlee-macbook",
        .model = "claude-opus-5-5",
        .status = .running,
        .started_min_ago = 24,
        .request = "必须在 huacnlee-macbook 上执行（需要 iOS 模拟器和 macOS；先 export PATH=$HOME/.cargo/bin:$PATH）。PR: github.com/longbridge/nsh/pull/810（分支 agent/text-inline-line-height），修复的是行内 view（例如 D-0003、T-0071 这类标签）比行高更高时压住上一行文字的问题。1) 用 gallery 或最小示例渲染一段行内带标签 view 的多行文字；2) 在 main（修复前）和 PR 分支（修复后）上分别截图，iOS 模拟器一组、macOS 一组；3) 用 gh pr edit 把图片排成 Before/After 表格写进 PR 描述，结尾加签名：— Kai (lead) · AI agent acting for @huacnlee；4) 如果修复后效果仍然不对，直接在这个 PR 里修好再重新截图，不要另开 PR。返回结果时附上截图文件路径。",
        .result = "第三次被调度到 Linux 主机 huacnlee-omarchy-lb，这里没有 iOS 模拟器和 macOS，无法给 PR nsh#810 补修复前后对比截图，PR 未改动。需要调度器把该任务限定为只派给 huacnlee-macbook (os:macos) 后再执行；没有新建后续任务，避免再次派回 Linux。",
        .result_status = "failed",
        .progress = &.{
            "19:26 T-0089 → rust-maintainer: nsh #810: 在 huacnlee-macbook 上补 iOS/macOS 修复前后对比截图",
            "19:27 T-0089 Ferris/claude: nsh #810: 在 huacnlee-macbook 上补 iOS/macOS 修复前后对比截图",
            "19:27 T-0089 又被调度到 Linux 主机 huacnlee-omarchy-lb，这里没有 iOS 模拟器和 macOS，需要调度器把该任务限定为只派给 huacnlee-macbook (os:macos) 上执行",
            "19:27 T-0089 retry 2 (task failure)",
            "19:28 T-0089 Ferris/claude: nsh #810: 在 huacnlee-macbook 上补 iOS/macOS 修复前后对比截图",
            "19:28 T-0089 第三次被调度到 Linux 主机 huacnlee-omarchy-lb。需要调度器把该任务限定为只派给 huacnlee-macbook (os:macos) 后再执行",
        },
    },
    .{
        .id = "T-0096",
        .title = "nsh: iOS/macOS TextView inline 节点与文字垂直对齐 + 行距不均（#810 后续），附修复前后截图",
        .role = "rust-maintainer",
        .host = "huacnlee-macbook",
        .model = "claude-opus-5-5",
        .status = .running,
        .started_min_ago = 24,
        .request = "背景：#810（已合并）把 MaximumLineHeight 改成 max(lineHeight, attachment 行高)，解决了芯片压到上一行的问题。但 owner 在 iOS noop 截图里看到两个问题：芯片 (T-0089、PR nsh#810) 明显高于同行文字基线，没有和文字视觉居中；含芯片的行比普通行高很多，段落行距不均。目标：inline 节点和文字的 x-height/cap 中线对齐（参考 web 后端 vertical-align: middle 的效果）；芯片不超过 lineHeight 时不撑高这一行，超过时只增加必要的高度并上下均分。检查 TextAttachment::extent 的 ascent/descent 分配和 run delegate 的 baseline offset。验收：1) 在 ~/work/nsh gallery 里加一个用例，正文多行，包含 inline chip；2) 拍 iOS 模拟器和 macOS 上修复前后的截图，贴到 PR 描述里；3) 补 CoreText 单测，验证芯片中线和文字中线的误差小于 1pt、各行行距一致；4) 开 Draft PR，标题以 text: 为前缀。",
        .progress = &.{
            "19:59 T-0096 → rust-maintainer: nsh: iOS/macOS TextView inline 节点与文字垂直对齐 + 行距不均（#810 后续）",
            "19:59 T-0096 delegated to T-0096",
            "20:00 T-0096 parked until a host with os:macos+host:huacnlee-macbook comes online",
            "20:00 T-0096 planned: os:macos, host:huacnlee-macbook · claude",
            "20:35 T-0096 Ferris/claude: nsh: iOS/macOS TextView inline 节点与文字垂直对齐 + 行距不均，附修复前后截图",
        },
    },
    .{
        .id = "T-0100",
        .title = "nsh: #793 后单选 Combobox 输入后列表项按 label 找不到（compat base step ~1576）",
        .role = "rust-maintainer",
        .host = "huacnlee-omarchy-lb",
        .model = "claude-opus-5-5",
        .status = .waiting,
        .started_min_ago = 43,
        .request = "PR github.com/longbridge/nsh/pull/813 修了 footer 期望值后，Compat 失败在 base 用例 `type label:One re` → `expect label:Red`。屏幕上有 \"Red\"、\"Green\"，但按 label 找不到，把输入拆成 `type r` + `type e` 也一样失败。需要查明 #793 (a2efbd59) 改 crates/nsh-base/src/combobox.rs / listbox.rs 后，单选 combobox 输入打开的列表项是否丢了 accessibility label，还是 on_change 里 typed/strip_prefix 的逻辑有问题，然后把修复推到 agent/T-0092-compat-combobox-footer (#813)。本地复现方法：~/agent-hub/work/c92（nsh-compat 加 nsh 软链接），在 nsh-compat 目录运行 cargo test --target-dir ../nsh/target checkout_apps_run。",
        .result = "单选 Combobox 的修复已推到 PR nsh#813（8cf09634 修复输入时搜索词带上已选标题，254740e7 修正 coverage 声明）。本地 compat 的 base 脚本步骤已全部通过，最后只失败在 coverage 声明上，已改正但未在本地重跑，等 CI 确认。",
        .result_status = "waiting",
        .progress = &.{
            "20:12 T-0100 → rust-maintainer: nsh: #793 后单选 Combobox 输入后列表项按 label 找不到",
            "20:13 T-0100 planned: any host · claude",
            "20:13 T-0100 Ferris/claude: nsh: #793 后单选 Combobox 输入后列表项按 label 找不到",
            "20:56 T-0100 等待 PR nsh#813 在提交 254740e7 上的 Compat CI，15 分钟后再看",
        },
    },
    .{
        .id = "T-0105",
        .title = "own-prs-ci · 2026-11-02 20:57",
        .role = "rust-maintainer",
        .host = "huacnlee-omarchy-lb",
        .model = "claude-opus-5-5",
        .status = .running,
        .started_min_ago = 1,
        .routine = true,
        .request = "Keep the owner's own open PRs mergeable without asking him. List them with `gh search prs --author=@me --state=open --json repository,number,url` and, per PR, `gh pr view <n> -R <repo> --json mergeable,mergeStateStatus,statusCheckRollup,reviewDecision,headRefName`.\n1. mergeable == CONFLICTING (GitHub shows \"This branch has conflicts\", checks stuck \"awaiting conflict resolution\"): in a fresh worktree of the PR branch, `git merge <base>` (never rebase: force-push is forbidden), resolve every conflict preserving the PR's intent and main's newer changes (read both sides' commits), run the repo's real build + tests (cargo test / bun test etc.), then push normally to the PR branch. Comment a short signed note listing the resolved files.\n2. CI red because of main drift, or a trivial failure (fmt, clippy, snapshot, lockfile): fix on the branch the same way.\n3. Unaddressed review comments with an obvious fix: fix them.\nOnly if a conflict needs a product/design choice the code can't settle → needs_decision with both versions summarized and a recommendation. Skip PRs marked draft-WIP by the owner within the last hour (he is likely still pushing).",
        .progress = &.{
            "20:57 routine `own-prs-ci` → T-0105 (rust-maintainer)",
            "20:57 T-0105 planned: os:linux · claude",
            "20:57 T-0105 Ferris/claude: own-prs-ci · 2026-11-02 20:57",
        },
    },
    .{
        .id = "T-0106",
        .title = "在 macOS 上验证 nsh #4…",
        .role = "rust-maintainer",
        .host = "huacnlee-macbook",
        .model = "claude-opus-5-5",
        .status = .queued,
        .started_min_ago = 0,
        .request = "在 macOS 上验证 nsh #4 的修复效果，跑 gallery 用例并截图。",
    },
    .{
        .id = "T-0091",
        .title = "更新 MacBook 上的 noop 到最新代码",
        .role = "ops",
        .host = "huacnlee-macbook",
        .model = "claude-opus-5-5",
        .status = .done,
        .started_min_ago = 24,
        .request = "git pull --rebase 并重建 noop，确认版本号与服务器一致。",
        .progress = &.{"19:45 T-0091 done: noop 已更新到 0.4.2 (main@f3d1a9c)"},
    },
    .{
        .id = "T-0092",
        .title = "Recheck huacnlee/noop#2 e2e failure after owner stops pushing",
        .role = "rust-maintainer",
        .host = "huacnlee-omarchy-lb",
        .model = "claude-opus-5-5",
        .status = .done,
        .started_min_ago = 12,
        .request = "owner 停止推送后复查 noop#2 的 e2e 失败。",
        .progress = &.{"20:46 T-0092 e2e 在 ubuntu 和 macOS 都通过了，已直接推到 PR 分支"},
    },
    .{
        .id = "T-0093",
        .title = "triage-inbound · 2026-11-02 20:35",
        .role = "triage",
        .host = "huacnlee-omarchy-lb",
        .model = "claude-opus-5-5",
        .status = .done,
        .started_min_ago = 22,
        .request = "扫描入站信号并与现有任务去重。",
        .progress = &.{"20:36 T-0093 未确认的新线程留待下次巡检；受团队 GitHub API 规则限制，未逐条标记已读"},
    },
    .{
        .id = "T-0094",
        .title = "gpu-component: 开启 gpu-fast 时 lib 测试有 21 个失败（main 上已存在）",
        .role = "rust-maintainer",
        .host = "huacnlee-omarchy-lb",
        .model = "claude-opus-5-5",
        .status = .done,
        .started_min_ago = 23,
        .request = "排查开启 gpu-fast feature 时的 lib 测试失败。",
        .progress = &.{"20:35 T-0094 根因是 gpu-fast 在窗口没有改动时会重放上一帧；已修好并把 CI 里 GPU Fast 只跑 tooltip 测试改成跑整组 lib 测试"},
    },
    .{
        .id = "T-0102",
        .title = "pr-review · 2026-11-02 19:56",
        .role = "reviewer",
        .host = "huacnlee-omarchy-lb",
        .model = "claude-opus-5-5",
        .status = .done,
        .started_min_ago = 28,
        .request = "复查今天的 PR：gpu-kit#3766、nsh#810、nsh#813。",
        .progress = &.{"20:28 T-0102 三个 PR 都已复查，gpu-kit#3766 可合并"},
    },
};

pub const machines = [_]Machine{
    .{
        .name = "huacnlee-macbook",
        .kind = "macos arm64",
        .online = true,
        .load_pct = 88,
        .cores = 8,
        .mem_pct = 64,
        .disk_free_gb = 309,
        .tools = &.{ "claude", "codex", "gh", "bun", "node" },
        .heartbeat = "刚刚",
    },
    .{
        .name = "huacnlee-omarchy-lb",
        .kind = "linux x64",
        .online = true,
        .load_pct = 39,
        .cores = 24,
        .mem_pct = 38,
        .disk_free_gb = 1777,
        .tools = &.{ "claude", "codex", "gh", "cargo", "bun", "node" },
        .heartbeat = "刚刚",
    },
    .{
        .name = "omarchy-jason",
        .kind = "linux x64",
        .online = false,
        .load_pct = 0,
        .cores = 16,
        .mem_pct = 0,
        .disk_free_gb = 0,
        .tools = &.{ "claude", "gh", "cargo" },
        .heartbeat = "1 小时前",
    },
};

/// Channel messages in chronological order; decision cards index `decisions`.
pub const messages = [_]_MessageSeed{
    .{ .agent = &ferris, .time = "20:35", .text = "gpu-component: 开启 gpu-fast 时 lib 测试有 21 个失败（main 上已存在）。根因是 gpu-fast 在窗口没有改动时会重放上一帧、复用没变化的视图（accordion、dock、popover、label 的测试要先强制刷新窗口再绘制，window_selection 测试里的选区适配器要和绘制出的元素绑定）。已修好，并把 CI 里 GPU Fast 只跑 tooltip 测试改成跑整组 lib 测试，见 Draft PR gpu-kit#3766。本地 758 个测试全部通过，PR 的 CI 已有 17 项通过，还剩 Windows Standard Runtime 一项在跑。" },
    .{ .agent = &hermes, .time = "20:36", .text = "triage-inbound · 2026-11-02 20:35：已扫描入站信号并与现有任务去重，未发现需要新增分派的事项。通知列表输出被截断，未确认的线程留待下次巡检；受团队 GitHub API 规则限制，未逐条标记已读。" },
    .{ .agent = &ferris, .time = "20:46", .text = "Recheck huacnlee/noop#2 e2e failure after owner stops pushing：noop#2 的 e2e 现在 ubuntu 和 macOS 都通过了，已直接推到 PR 分支，main 上同样的失败合并后也会消失。主因是 AI 规划器上线后，测试里的假 agent 没有回复规划结果，任务一直不运行；另外修了 macOS 上的三个问题：sed -i 写法、mac only 任务会在 macOS runner 上直接运行、按固定次数 tick 不够。PR noop#2" },
    .{ .agent = null, .time = "20:55", .owner = "合并，但这次得看是否有 Breaking Changes 来决定是发布 0.8.2 还是 0.9.0（D-0009）" },
    .{ .agent = &hub, .time = "20:56", .text = "收到 D-0009：合并，但这次得看是否有 Breaking Changes 来决定是发布 0.8.2 还是 0.9.0 — 任务已重新排队" },
    .{ .agent = &ferris, .time = "20:58", .decision = 2 },
};

const _MessageSeed = struct {
    agent: ?*const Agent,
    time: []const u8,
    text: []const u8 = "",
    owner: []const u8 = "",
    decision: ?usize = null,
};
