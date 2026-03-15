# 🪞 Claude CLI ↔ Telegram Mirror

Mirror your Claude CLI terminal session to Telegram. See everything. Type back. Approve tool use from your phone.

## Install

```bash
curl -sSL https://raw.githubusercontent.com/allexp1/telebot/main/install.sh -o /tmp/ct.sh && bash /tmp/ct.sh
```

## Usage

```bash
claude-telegram list              # List your Claude CLI sessions
claude-telegram start             # Mirror latest session
claude-telegram start <session>   # Mirror a specific session
claude-telegram stop              # Stop
claude-telegram bg [session]      # Run in background
```

## How It Works

```
┌──────────────┐      ┌──────────────┐      ┌────────────┐
│  Telegram     │ ───▶ │  Mirror      │ ───▶ │ Claude CLI │
│  (your phone) │ ◀─── │  (PTY bridge)│ ◀─── │ (your Mac) │
└──────────────┘      └──────────────┘      └────────────┘
```

The mirror spawns Claude CLI in a pseudo-terminal and:

- **Streams all CLI output** to your Telegram chat in real-time
- **Forwards your messages** from Telegram to CLI as stdin input
- **Shows ✅/❌ buttons** when Claude asks for permission (tool use, file access)

It's like `screen` or `tmux` — but over Telegram.

## Telegram Commands

| Command    | Description             |
|------------|-------------------------|
| `/start`   | Connect and show status |
| `/restart` | Restart the CLI session |
| `/stop`    | Kill the CLI process    |
| `/id`      | Your Telegram user ID   |

Everything else you type goes straight to Claude CLI.

## Requirements

- Python 3.10+
- [Claude CLI](https://docs.anthropic.com/en/docs/claude-cli) (`npm install -g @anthropic-ai/claude-cli`)
- Telegram account + bot token from [@BotFather](https://t.me/BotFather)

## Config

`~/.claude-telegram-bridge/config.json`:

```json
{
  "telegram_token": "your-bot-token",
  "allowed_user_ids": [your-telegram-id],
  "claude_cli_path": "claude"
}
```

## Uninstall

```bash
claude-telegram uninstall
```

## License

MIT
