import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "Herdr: a place for coding agents to keep working" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 11, day := 26 }
%%%

:::hero "Herdr separates the client you close from the server that keeps your agents running" "static/blog/herdr/thumbnail.png"
:::

Running one coding agent is simple. Open a terminal, describe the problem, read the result. With several agents, the work changes. One is running tests, another is waiting for permission, a third finished ten minutes ago. You spend more time finding the right terminal and remembering what each process was doing.

[Herdr](https://herdr.dev/) addresses that problem. It gives coding agents persistent terminals, a shared view of their status, and a way to control them from scripts or other agents. Its value is easier to understand once you separate three questions: who does the work, where does the process live, and how do you know it needs you?

Herdr now has a customizable desktop app as well as a terminal interface. This post focuses on the terminal runtime, using the stable 0.9.5 documentation and the matching installed CLI. The comparisons describe documented features, checked on 26 November 2026, rather than a performance benchmark.

# A server owns the terminals

Herdr starts a background server. That server owns the terminal processes. A client attaches to display them and send input. Closing the client leaves the server running, so the shells, agents and tests inside its panes can continue.

The organization is straightforward. A session contains workspaces, a workspace contains tabs, and a tab contains panes. A pane is a real terminal. A recognized agent is a process inside one of those panes. This distinction matters: a pane can just as well contain a test runner, a development server or an ordinary shell. See the [concepts guide](https://herdr.dev/tui/docs/concepts/).

![Herdr architecture: a detachable laptop client connects over SSH to a server on a remote host. That server owns agent and test terminals, with separate working directories for independent changes.](static/blog/herdr/process-ownership.svg)

_Figure 1. Put the server on the machine that should keep working. The SSH connection carries interaction; it does not own the remote processes. Separate worktrees in this example are a workflow choice, not an automatic property of every pane._

For remote work, you can SSH to a machine and start Herdr there, or attach with `herdr --remote workbox`. You can also save several SSH machines and see their workspaces in one window. Each machine keeps its own server and processes. One lost connection does not bring down the others. The [remote workflow guide](https://herdr.dev/tui/docs/how-to-work/) and [machine setup guide](https://herdr.dev/tui/docs/connecting-machines/) explain both approaches.

# The useful feature is knowing who needs you

A multiplexer already solves the problem of several terminals. Herdr adds an agent view. It recognizes supported agents, including Claude Code, Codex, Pi and OpenCode, and shows whether they are working, blocked, done or idle. There is also an unknown state when it cannot classify a process confidently.

That changes the question from “what is in terminal seven?” to “which task needs an answer?” My reason for wanting this is attention, rather than a larger number of agents. Starting another agent is cheap. Keeping enough context to review its work is not.

The status is an observation, not a proof. For some agents, Herdr detects the foreground process and interprets the live terminal screen. Others report their state through integrations. A new approval dialog can escape the screen rules and appear idle. The [agent documentation](https://herdr.dev/tui/docs/agents/) describes these limits. A status badge is useful for navigation; it is not permission to approve whatever the terminal is asking.

Consider a small change to an API. An implementation agent works in one checkout. A reviewer examines a fixed commit in another. A test pane runs the relevant suite. You return when the implementation needs a decision or the review is ready. There is no need to keep switching among three terminals just to discover whether anything happened.

Separate checkouts matter here. Three panes pointed at the same directory still share files and an index. Herdr includes [worktree commands](https://herdr.dev/tui/docs/cli-reference/#worktrees), but parallel editing requires you or your workflow to choose that isolation. A worktree separates files; it does not create a security sandbox or allocate a separate database and ports.

# Persistence has a boundary

There are three different things people call “resuming a session”: returning to a live process, recreating a terminal layout, and reopening an agent conversation. They are not interchangeable.

![Persistence comparison: detaching preserves original processes; a laptop sleeping leaves remote processes running but pauses local execution; restarting the host or server requires new processes and optional conversation recovery.](static/blog/herdr/persistence-boundaries.svg)

_Figure 2. Detaching is the strong case because nothing on the execution host stopped. Restoring a layout or conversation after a restart creates a different continuity guarantee._

Herdr keeps processes alive across client detach. After a server restart, it restores the saved layout, but the old processes are gone. Supported agent integrations can resume conversations. Optional screen history can replay terminal contents. Neither action brings an interrupted test process back to life. The [session state documentation](https://herdr.dev/tui/docs/session-state/) makes those distinctions explicit.

The execution host also matters. A local server cannot keep making progress while your laptop sleeps. A server on an awake remote machine can. Herdr gives you the connection and session structure; you still provide the machine, its availability and the credentials the agents need.

# It gives automation something to address

Herdr exposes its runtime through a CLI and a local socket API. A script can create a workspace, start an agent in a pane, send a prompt, inspect output and wait for an agent state. The distinction between pane commands and agent commands is useful: one addresses a terminal, the other addresses the recognized agent currently occupying it.

For example, the documented automation pattern creates a workspace and captures the pane identifier from JSON:

```
created=$(herdr workspace create --cwd ~/project --label review --no-focus)
pane_id=$(printf '%s\n' "$created" | jq -r '.result.root_pane.pane_id')
herdr agent start reviewer --kind codex --pane "$pane_id"
```

This example needs a running Herdr server, `jq`, and an installed, authenticated Codex CLI. It illustrates targeting, not a complete review workflow. Do not guess pane identifiers: use what the command returns.

The [automation guide](https://herdr.dev/tui/docs/agent-automation/) also distinguishes a completed wait from a blocked agent. If an agent is asking for a decision, the coordinator must inspect that question. Sending another instruction blindly is not coordination.

These primitives make Herdr a useful base for orchestration. A reliable workflow still has to define who owns a change, what a reviewer reviews, how results are handed back, and what happens on failure. Opening four panes does not settle any of those questions.

# How it compares

These tools overlap, and the overlap is growing. I would choose by the responsibility I want to hand over, rather than count features.

![Four questions for choosing tools: persistent terminals lead to tmux or Zellij; an agent-aware runtime on your machines leads to Herdr; a native Mac terminal with a browser leads to cmux; managed cloud agent environments lead to Conductor.](static/blog/herdr/alternatives.svg)

_Figure 3. Starting points for a choice, not exclusive capabilities or a ranking. Several of these tools can be used together._

## tmux and Zellij

[tmux](https://github.com/tmux/tmux/wiki) already provides persistent terminal sessions, panes and scripting. If your problem is simply keeping a remote command alive after SSH disconnects, it solves it. Herdr's extra appeal is the built-in view of agent state and the agent-specific control commands. An existing tmux setup with suitable hooks may already cover your needs.

[Zellij](https://zellij.dev/documentation/session-resurrection) is another serious option. Its session resurrection restores layouts and saved commands, with optional terminal history. It can also accept an explicit resume command from a program. Herdr does not have a monopoly on recovery. The reason to prefer it is how its agent view and automation fit your work, rather than a claim that other multiplexers cannot restore sessions.

## cmux

[cmux](https://cmux.com/) is a close alternative for a Mac workflow. It is a native terminal built on Ghostty, with vertical tabs, attention notifications, a programmable browser, and CLI and socket control. It also supports remote work through SSH and tmux. Calling it “just a terminal” would miss much of the point.

I would look at cmux first if the main goal is a Mac terminal with a browser beside the agent, especially for web development. Herdr's terminal interface is attractive when I want a similar working surface inside an existing terminal and on remote hosts. This is a choice of working environment, not a claim that only one can host several agents.

## Conductor and managed agent environments

[Conductor](https://www.conductor.build/) now offers cloud sandboxes running first-party coding agents, with desktop, mobile and API access. That takes responsibility for more of the environment. Herdr's remote model instead lets you bring a machine you control and connect to the processes running there.

The tradeoff is operational. A managed environment can remove machine setup from your daily work. Running Herdr on your own host lets you use that host's existing repositories, dependencies and network access, but you maintain those things. Neither arrangement removes the need to inspect changes and verify results.

## The agent's own interface

For one task, the agent's CLI or app may be enough. It already gives you a conversation, tool output and its own controls. A separate runtime becomes useful when you want to supervise several independent processes, mix agent tools or move the interaction away from the execution machine. It does not make the underlying model better at solving a problem.

# Try one remote task first

On a machine with Homebrew, the documented terminal installation is:

```
brew install herdr
cd ~/project
herdr
```

Start your usual coding agent in the pane. Use the mouse to split panes and navigate, or learn the prefix keys gradually. Detach with `Ctrl+B`, release, then `Q`. Run `herdr` again to reattach. For a machine reachable through your SSH configuration, use `herdr --remote workbox`. The [installation guide](https://herdr.dev/tui/docs/install/) covers other systems and package managers.

I would evaluate it with one task that takes long enough to leave alone, then one independent task beside it. Do the status indicators save you from checking terminals? Can you find the work again after disconnecting? Is reviewing the result easier? Those answers matter more than how many agents fit on the screen.

Herdr earns its place when keeping track of the work becomes harder than starting it.
