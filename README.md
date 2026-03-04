# 🌉 Claude ↔ Telegram Bridge

Chat with [Claude CLI](https://docs.anthropic.com/en/docs/claude-cli) from Telegram — with session memory, MCP tools support, and a web dashboard.

![Dashboard](https://img.shields.io/badge/dashboard-localhost:7860-d4a574?style=flat-square)
![Python](https://img.shields.io/badge/python-3.10+-blue?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)

## Install

```bash
curl -sSL https://raw.githubusercontent.com/allexp1/telebot/main/install.sh | bash
```

That's it. The interactive installer will:

1. Check prerequisites (Python 3, Claude CLI)
2. Ask for your Telegram bot token (from [@BotFather](https://t.me/BotFather))
3. Ask for your Telegram user ID (from [@userinfobot](https://t.me/userinfobot))
4. Install everything to `~/.claude-telegram-bridge`
5. Create a global `claude-telegram` command
6. Offer to start immediately

## Usage

```bash
claude-telegram list              # List your Claude CLI sessions
claude-telegram start             # Start bridge (continues latest session)
claude-telegram start <session>   # Start bridge connected to a specific session
claude-telegram stop              # Stop
claude-telegram restart           # Restart
claude-telegram bg [session]      # Start in background
claude-telegram status            # Check if running
claude-telegram autostart         # Auto-start on macOS login
claude-telegram config            # Edit config file
claude-telegram logs              # Tail log file
claude-telegram uninstall         # Remove everything
```

## How It Works

```
┌──────────────┐      ┌─────────────────────┐      ┌────────────┐
│  Telegram     │ ───▶ │  Bridge Server       │ ───▶ │ Claude CLI │
│  (your phone) │ ◀─── │  (FastAPI + Bot)     │ ◀─── │ (your Mac) │
└──────────────┘      │                     │      └────────────┘
                      │  📊 Web Dashboard   │
                      │  http://localhost:7860│
                      │  💾 SQLite (history) │
                      └─────────────────────┘
```

Every Telegram message is relayed to Claude CLI using `claude -p --session-id`, so conversations have **full multi-turn memory**. All history is stored in a local SQLite database.

## Web Dashboard

Open **http://localhost:7860** after starting to get:

- **Overview** — message stats, active sessions, 7-day activity chart
- **Sessions** — browse all sessions, read full chat history
- **Settings** — configure bot token, model, MCP tools, system prompt
- **Test** — send test messages to verify the connection

## Telegram Commands

| Command    | Description                          |
|------------|--------------------------------------|
| `/start`   | Welcome message and session info     |
| `/new`     | Reset the bridge session tracker     |
| `/status`  | Check connection and session info    |
| `/id`      | Show your Telegram user ID           |

The session is chosen when you start the bridge from your terminal — not from Telegram. Use `claude-telegram list` to see sessions, then `claude-telegram start <id>` to connect.

## MCP Tools

Use Claude's MCP tools (filesystem, git, databases, etc.) directly from Telegram:

1. Set your MCP config path: `claude-telegram config`  
   → Set `"mcp_config": "~/.claude/mcp.json"`
2. Set allowed tools: `"allowed_tools": "mcp__filesystem__read_file, mcp__git__status"`
3. Restart: `claude-telegram restart`

Now you can ask Claude to read files, check git status, query databases — all from your phone.

## Configuration

All settings live in `~/.claude-telegram-bridge/config.json`:

| Key                    | Description                                          | Default    |
|------------------------|------------------------------------------------------|------------|
| `telegram_token`       | Bot token from @BotFather                            | `""`       |
| `allowed_user_ids`     | Telegram user IDs that can use the bot (array)       | `[]`       |
| `system_prompt`        | Default system prompt for Claude                     | (included) |
| `claude_cli_path`      | Path to Claude CLI binary                            | `"claude"` |
| `claude_model`         | Model override (e.g. `claude-sonnet-4-5-20250929`)   | `""`       |
| `mcp_config`           | Path to MCP config file                              | `""`       |
| `allowed_tools`        | Comma-separated tool names                           | `""`       |
| `max_response_length`  | Max chars per Telegram message (splits if longer)    | `4096`     |
| `web_port`             | Dashboard port                                       | `7860`     |

Edit via dashboard or: `claude-telegram config`

## Requirements

- **Python 3.10+**
- **Claude CLI** — `npm install -g @anthropic-ai/claude-cli`
- A Telegram account

## Security

- **Always set `allowed_user_ids`** — without it, anyone who finds your bot can use your Claude CLI
- Bot token and all data stay local on your machine
- Dashboard is localhost-only by default
- The installer prompts you to lock it down during setup

## Uninstall

```bash
claude-telegram uninstall
```

Removes everything: server, config, database, CLI command, and autostart.

## License

MIT
