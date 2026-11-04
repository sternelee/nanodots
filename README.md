# nanodot

A noop-style console for a team of AI agents, built the way [nanoterm](../nanoterm)
is: [nanoui](https://github.com/justrach/nanoui) draws the native desktop UI and
the [fx](https://github.com/vercel-labs/fx) agent runtime is compiled into the
app, in-process.

You play the owner. The sidebar streams what the team is doing — projects
you added, repos being watched, decisions waiting on you, tasks running,
queued and recent work, and the fleet of agent hosts. The channel is where
agents report; decisions arrive as cards with A/B/C options, and the composer
at the bottom dispatches instructions straight to the embedded fx agent, which
streams its reply and tool calls back into the channel. Instructions run in
the selected project's directory (each project keeps its own fx session), and
every project also opens an interactive multi-turn agent session — like fx
cli or an editor chat panel in that directory. Watches poll GitHub repos on a
schedule (a Grok Bot-style routine): at each interval the app wakes a dedicated
fx session that checks the repo with `gh` (or the GitHub API), reports new
PRs/issues to the channel and stays quiet when nothing changed. Findings land
as decision cards — 快速审阅 / 派任务 / 忽略: A and B start a real review turn
on the team runtime (quick pass or full structured report), C puts the PR
numbers on the watcher's persisted ignore list so they are never reported
again. Reported numbers are persisted too, so restarts diff against them
instead of the fx session's memory. For instant notification the settings page
also runs a GitHub webhook receiver (Rerun's inbound pattern, desktop-sized):
it listens on 127.0.0.1, verifies `X-Hub-Signature-256` when a secret is set,
wakes the matching watcher within a second, and shows the hook URL, setup
instructions and recent deliveries; expose the port with smee.io or ngrok for
GitHub to reach it. The watch list, ignore lists and webhook config live in
`~/.nanodot/`. The gear at the sidebar's bottom opens
the agent settings page: the fx provider, model and custom base_url providers,
read and written through fx's own `~/.fx/settings.json`.

Development status lives in [docs/progress.md](docs/progress.md).

## Build and run

Needs Zig 0.17.0 and a sibling nanoterm checkout (for its patched fx submodule):

```sh
zig build          # compile
zig build run      # run the app
zig build test     # unit tests
```

fx comes from `../nanoterm/vendor/fx` by default; point elsewhere with
`-Dfx-root=/path/to/fx` (the checkout must have nanoterm's embedded.zig patch
applied — building nanoterm once does that).

Headless, the way nanoui checks apps (no window ever appears):

```sh
# a page straight from launch
./zig-out/bin/nanodot --nanoui-snapshot=/tmp/page.png --nanoui-dark

# click a running task in the sidebar, then capture the task page
./zig-out/bin/nanodot --nanoui-snapshot=/tmp/page.png --nanoui-dark \
    --nanoui-script="at:100,212"

# type an instruction, submit, let the agent work, then capture
./zig-out/bin/nanodot --nanoui-snapshot=/tmp/page.png --nanoui-dark \
    --nanoui-script="at:700,875;type:看一下当前目录;key:enter;live:10"
```

The composer needs fx provider credentials in the usual fx places
(`~/.fx/settings.json` or the provider's env vars); without them the agent's
failure is reported into the channel as a normal message.

## Layout

- `src/main.zig` — entry; hands fx's private re-exec args to `engine.runInternal`
- `src/agent.zig` — the fx runtime on a worker thread, events pumped to the UI
  thread with `nanoui.App.after`
- `src/state.zig` — workspace state, navigation, applying agent events, the
  agent settings page's read/write of ~/.fx/settings.json, the projects and
  their per-directory fx runtimes, and the repo watches: a 1-second scheduler
  (`nanoui.App.after`) wakes a dedicated fx session per watcher, the reply is
  parsed (无新动态 stays quiet, findings become decision cards), the list,
  ignore and reported numbers persist to `~/.nanodot/watchers.json`; also the
  webhook receiver's lifecycle, settings and per-second drain
- `src/webhook.zig` — the GitHub webhook receiver: a 127.0.0.1 HTTP server
  (`std.Io.net`) accepting POSTs to /hook/<token>, optional
  X-Hub-Signature-256 verification, events queued for the UI thread
- `src/seed.zig` — the demo workspace (decisions, tasks, hosts, messages)
- `src/ui/` — sidebar, channel (decision cards, composer), task page, host
  page, agent settings page, projects list and project pages, watch list and
  watcher pages

One nanoui rule the views follow: an opened box must be closed with an explicit
`.end()` before its siblings open — `defer box.end()` only works for a
function's outermost container, since defers run at scope exit, not at the end
of the statement.
