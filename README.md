# nanodot

A noop-style console for a team of AI agents, built the way [nanoterm](../nanoterm)
is: [nanoui](https://github.com/justrach/nanoui) draws the native desktop UI and
the [fx](https://github.com/vercel-labs/fx) agent runtime is compiled into the
app, in-process.

You play the owner. The sidebar streams what the team is doing — projects
you added, decisions waiting on you, tasks running, queued and recent work,
and the fleet of agent hosts. The channel is where agents report; decisions
arrive as cards with A/B/C options, and the composer at the bottom dispatches
instructions straight to the embedded fx agent, which streams its reply and
tool calls back into the channel. Instructions run in the selected project's
directory (each project keeps its own fx session); the gear at the sidebar's
bottom opens the agent settings page: the fx provider, model and custom
base_url providers, read and written through fx's own `~/.fx/settings.json`.

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
  their per-directory fx runtimes
- `src/seed.zig` — the demo workspace (decisions, tasks, hosts, messages)
- `src/ui/` — sidebar, channel (decision cards, composer), task page, host
  page, agent settings page, projects list and project pages

One nanoui rule the views follow: an opened box must be closed with an explicit
`.end()` before its siblings open — `defer box.end()` only works for a
function's outermost container, since defers run at scope exit, not at the end
of the statement.
