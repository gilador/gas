# First-time setup (FTU) — design

Date: 2026-09-28 · Status: approved in chat, waiting for spec review

## Goal

A new user installs gas and gets Claude and OpenAI usage with as little manual work as possible. The flow must also work for people who only use Claude Desktop and never use Terminal.

gas reads Claude usage through the Claude Code CLI login and OpenAI usage through the Codex CLI login. So each provider needs its CLI installed and signed in.

## Manual steps that stay

These steps cannot be removed without a paid Developer ID or the user's own consent:

- Gatekeeper "Open Anyway" for a downloaded pkg.
- The macOS "Installer.app would like to modify apps" prompt on updates.
- One sign-in click in the browser for each account (OAuth consent).

Success means that the user does nothing else by hand. Every other step is one click in gas.

## Non-goals

- Reading the Claude Desktop login. It is another app's stored session.
- Installing npm, Node.js or Homebrew.
- Grok/xAI support. It is deferred; see the memory note `grok-support-deferred`.
- Any automatic retry loop that runs installers or sign-ins without a click.

## The setup window

- It opens by itself **one time**, at the first launch after install, and only if at least one turned-on provider is not ready. A `setupShown` flag in UserDefaults records the first launch in both cases. If every provider is ready, gas sets the flag and does not open the window.
- gas preferences survive updates and reinstalls, so the flag stays set. An update or a reinstall does not open the window again. A new Mac or a new macOS user account has no flag, so the window can open there. The first update to the version with this feature has no flag yet, so it acts like a first launch.
- Settings gets a **"Set up providers…"** button that opens it at any time.
- In the menu, a provider that is not ready (for example "Not logged in") also shows a **"Set up…"** link that opens the window. gas never opens the window by itself after the first launch.
- It has a **Done** button at all times.
- It has one row for each provider (Claude, OpenAI), with the provider icon, a status line and at most one button.

| State | Status line | Button |
|---|---|---|
| Ready | "Claude — ready" (green, with a check) | none |
| CLI missing | "Claude Code is not installed. Set up downloads Anthropic's official installer and opens the sign-in page." | **Set up** |
| Not logged in, or expired | "Not logged in. Sign in opens the sign-in page in your browser." | **Sign in** |
| Rate limited | "Server busy — next try at ‹HH:MM›" | none |
| Other read error (network, server) | "Can't read usage: ‹reason›" | **Try again** |
| Turned off | Gray: "Not used" | **Use** |

- The text on the row says what **Set up** will do, so the click is the permission. There is no second confirmation dialog.
- Rows that are not ready also show a small **"Don't use"** link. It turns the provider off (`ProviderSettings`), and gas stops asking about it.
- During a step, the status line shows the progress: "Installing…", then "Waiting for sign-in in your browser…", then "Reading usage…". When gas reads the usage, the row changes to Ready by itself.
- **Try again** checks again (installed, logged in) and then does one manual usage refresh, the same as the menu's Refresh button.
- The OpenAI texts are the same, with "Codex CLI" and OpenAI's installer.

## Set up flow (for each provider)

1. **Install, if the CLI is missing.** Run the official installer in the background. Then find the binary again.
2. **Sign in, if not logged in.** Start the CLI's sign-in command. It opens the browser sign-in page.
3. **Wait.** Check the login status every 2 s, for at most 5 min.
4. **Read usage.** Run a manual refresh through the usual `UsageViewModel.refresh(manual: true)`.
5. **Done.** The row shows Ready.

Only one step runs at a time for each provider. The row's buttons are off while a step runs. When the user closes the window, gas stops the status checks and ends a running sign-in process.

## Tool facts

These were checked on this Mac on 2026-09-28.

**Claude Code**
- Binary: `~/.local/bin/claude`, `~/.claude/local/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`.
- Install: `curl -fsSL https://claude.ai/install.sh | bash`.
- Sign in: `claude auth login --claudeai`.
- Status: `claude auth status`. It prints JSON with `loggedIn` (true/false) and `authMethod`. The exit code is 0 in both states, so gas parses the JSON.
- It is not known whether the status command works offline. gas must not depend on that.

**Codex CLI**
- Binary: `~/.local/bin/codex`, `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`.
- Install: `curl -fsSL https://chatgpt.com/codex/install.sh | sh`. It downloads a ready binary and needs no npm.
- Sign in: `codex login`.
- Status: `codex login status`. Exit code 0 means logged in, and 1 means not logged in.

**Fallback lookup:** if no known path has the binary, gas asks the login shell: `/bin/zsh -lc 'command -v <name>'`.

## Components

1. **`CLITool`** (UsageCore, new). One value for each tool: its name, the binary paths, the install command, the sign-in command, and the status command with its parser. `locate()` checks the paths, then the login shell.
2. **`SetupState`** (UsageCore, new, pure). Its inputs are installed, logged in, provider turned on, the latest `FetchStatus`, and the step in progress. It returns the row state from the table.
3. **`ProcessRunner`** (UsageCore). The process code moves here from `ClaudeCodeRenewer`. It adds a timeout and captures stdout for the status parsers. `ClaudeCodeRenewer` then uses `CLITool.claude.locate()`.
4. **`SetupModel`** (App, `@MainActor`, `ObservableObject`). It keeps each row's state and runs Set up, Try again, Don't use and Use.
5. **`SetupView`** and its window (App). `DesktopPanelController` opens the window in the same way as the Settings window. `AppDelegate` opens it at first launch, when `setupShown` is not set and a turned-on provider is not ready.
6. **Settings**: the "Set up providers…" button.
7. **Menu** (`ProviderSection`): the "Set up…" link next to a provider that is not ready.

## Errors

- **Install fails** (non-zero exit, no network, or more than 5 min): "Install failed: ‹last output line›", with **Try again**.
- **Install works, but no binary is found**, even through the login shell: "Installed, but gas can't find it", with **Try again**.
- **Sign-in not finished in 5 min:** "Sign-in not finished", with **Sign in**.
- **The status output cannot be parsed:** "Can't check the login", with **Try again**.

## Security

- The installer URLs and the commands are fixed in the code, and https only. They never come from user input, from files, or from the network.
- gas never reads, prints or logs token values. The CLIs write their own credential stores, and gas only reads them, as today.
- gas never logs the sign-in command's output, because it can contain a one-time code or URL.

## Logging

Each step writes one line to `UsageLog`, for example `setup claude install exit=0` or `setup codex login status=1`. **Copy diagnostics** shows these lines.

## Testing

- **Unit tests, written first:**
  - `SetupState` for every row state.
  - The Claude JSON parser: `loggedIn` true, false, and bad output.
  - The Codex exit-code parser.
  - `CLITool.locate()` with an injected file check and shell runner.
  - `SetupModel` with a fake runner: full success, install failure, sign-in timeout, and cancel.
- **Manual:**
  - The commands, with empty `CLAUDE_CONFIG_DIR` and `CODEX_HOME` folders.
  - The full first-time flow on a Mac or a macOS user account that does not have the tools. The user or a friend does this.

## Open items

- Check where the Codex installer puts the binary. If it is not a known path, add it to `CLITool.codex`.
