#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  Claude CLI ↔ Telegram Mirror — One-Command Installer
#  
#  Mirrors your Claude CLI terminal to Telegram.
#  See everything Claude outputs. Type back. Approve tool use.
#
#  Install:  curl -sSL https://raw.githubusercontent.com/allexp1/telebot/main/install.sh -o /tmp/ct.sh && bash /tmp/ct.sh
# ═══════════════════════════════════════════════════════════════
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'

INSTALL_DIR="$HOME/.claude-telegram-bridge"
VENV_DIR="$INSTALL_DIR/venv"

print_banner() {
  echo ""
  echo -e "${CYAN}${BOLD}"
  echo "  ┌─────────────────────────────────────┐"
  echo "  │   🪞  Claude CLI ↔ Telegram Mirror  │"
  echo "  │       Full Terminal Mirroring         │"
  echo "  └─────────────────────────────────────┘"
  echo -e "${RESET}"
}

info()  { echo -e "  ${CYAN}ℹ${RESET}  $1"; }
ok()    { echo -e "  ${GREEN}✓${RESET}  $1"; }
warn()  { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
fail()  { echo -e "  ${RED}✗${RESET}  $1"; }
step()  { echo -e "\n  ${BOLD}$1${RESET}"; echo -e "  ${DIM}$(printf '─%.0s' {1..40})${RESET}"; }
ask()   { echo -ne "  ${CYAN}▸${RESET} $1"; }

check_prerequisites() {
  step "① Checking prerequisites"
  if command -v python3 &>/dev/null; then
    ok "Python: $(python3 --version 2>&1)"
  else
    fail "Python 3 not found"; exit 1
  fi
  python3 -m venv --help &>/dev/null || { fail "Python venv missing"; exit 1; }
  ok "Python venv available"

  CLAUDE_PATH=""
  if command -v claude &>/dev/null; then
    ok "Claude CLI: $(claude --version 2>/dev/null || echo installed)"
    CLAUDE_PATH="claude"
  else
    for p in "$HOME/.npm-global/bin/claude" "/usr/local/bin/claude" "$HOME/.local/bin/claude"; do
      if [ -x "$p" ]; then ok "Claude CLI: $p"; CLAUDE_PATH="$p"; break; fi
    done
    if [ -z "$CLAUDE_PATH" ]; then
      warn "Claude CLI not found"
      ask "Path to claude binary (Enter to skip): "; read -r CLAUDE_PATH
      CLAUDE_PATH="${CLAUDE_PATH:-claude}"
    fi
  fi
}

setup_telegram() {
  step "② Telegram Bot Setup"
  echo ""
  info "Get a bot token from @BotFather on Telegram (/newbot)"
  echo ""
  while true; do
    ask "Paste your bot token: "; read -r BOT_TOKEN
    if [[ "$BOT_TOKEN" =~ ^[0-9]+:.+$ ]]; then ok "Token looks good"; break
    elif [ -z "$BOT_TOKEN" ]; then warn "Skipping"; break
    else fail "Invalid format. Try again or Enter to skip."; fi
  done
  echo ""
  info "Your Telegram user ID (get from @userinfobot)"
  ask "User ID (Enter to skip): "; read -r USER_ID
  ALLOWED_IDS="[]"
  if [[ "$USER_ID" =~ ^[0-9]+$ ]]; then
    ALLOWED_IDS="[$USER_ID]"; ok "Restricted to $USER_ID"
  else warn "No restriction — anyone can use the bot!"; fi
}

install_bridge() {
  step "③ Installing"
  mkdir -p "$INSTALL_DIR"; ok "Created $INSTALL_DIR"

  cat > "$INSTALL_DIR/requirements.txt" << 'EOF'
python-telegram-bot>=20.7
pexpect>=4.9
EOF

  info "Setting up Python env..."
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install -q --upgrade pip 2>/dev/null
  "$VENV_DIR/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt"
  ok "Dependencies installed"

  cat > "$INSTALL_DIR/config.json" << CFGEOF
{
  "telegram_token": "$BOT_TOKEN",
  "allowed_user_ids": $ALLOWED_IDS,
  "claude_cli_path": "${CLAUDE_PATH:-claude}"
}
CFGEOF
  ok "Config saved"

  write_mirror
  ok "Mirror created"
  write_cli
  ok "CLI command: claude-telegram"
}

write_mirror() {
cat > "$INSTALL_DIR/mirror.py" << 'PYEOF'
"""
Claude CLI <-> Telegram Mirror
Spawns Claude CLI in a PTY. Streams all output to Telegram.
Accepts input from Telegram. Shows Yes/No buttons for permission prompts.
"""
import asyncio
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Optional

import pexpect
from telegram import Bot, Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, MessageHandler, CallbackQueryHandler,
    filters, ContextTypes
)

CONFIG_PATH = Path(__file__).parent / "config.json"

def load_config():
    if CONFIG_PATH.exists():
        with open(CONFIG_PATH) as f: return json.load(f)
    return {}

config = load_config()

# ── State ──
cli_process: Optional[pexpect.spawn] = None
output_buffer = ""
buffer_lock = asyncio.Lock()
telegram_chat_id: Optional[int] = None
bot_app: Optional[Application] = None
flush_task: Optional[asyncio.Task] = None
SESSION_MODE = os.environ.get("CLAUDE_SESSION_MODE", "continue")

# ── ANSI / terminal cleanup ──
ANSI_RE = re.compile(
    r'\x1b(?:\[[\d;?]*[A-Za-z]|\(B|\][\d;]*.*?(?:\x07|\x1b\\)|[>=<78HMND])'
    r'|[\x00-\x08\x0b\x0c\x0e-\x1f]',
    re.DOTALL
)
SPINNER_RE = re.compile(r'^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏⣾⣽⣻⢿⡿⣟⣯⣷◐◓◑◒●○◉◎⬤|/\-\\]+\s*', re.UNICODE)

def clean(text: str) -> str:
    text = ANSI_RE.sub('', text)
    # Catch orphaned sequences where ESC was already stripped
    text = re.sub(r'\[\?[\d;]*[A-Za-z]', '', text)
    # Catch other common leaked sequences
    text = re.sub(r'\[[\d;]*[mGKHJP]', '', text)
    lines = []
    for line in text.split('\n'):
        if '\r' in line:
            line = line.split('\r')[-1]
        line = SPINNER_RE.sub('', line.strip())
        if line:
            lines.append(line)
    result = '\n'.join(lines)
    return re.sub(r'\n{3,}', '\n\n', result).strip()

def is_permission_prompt(text: str) -> bool:
    patterns = [
        r'(?:Allow|Approve|Grant|Permit)\s+.*\?',
        r'Do you want to (?:allow|proceed|continue|run|execute)',
        r'\(y(?:es)?/n(?:o)?\)',
        r'\[Y/n\]', r'\[y/N\]',
        r'Do you trust',
        r'(?:Yes|No)\s*/\s*(?:Yes|No)',
    ]
    return any(re.search(p, text, re.IGNORECASE) for p in patterns)

# ── Send to Telegram ──
async def tg_send(text: str, buttons: bool = False):
    if not telegram_chat_id or not bot_app: return
    bot = bot_app.bot
    text = text.strip()
    if not text: return

    # Split at 4000 chars
    chunks = []
    while len(text) > 4000:
        sp = text.rfind('\n', 0, 4000)
        if sp < 1500: sp = 4000
        chunks.append(text[:sp])
        text = text[sp:].strip()
    if text: chunks.append(text)

    for i, chunk in enumerate(chunks):
        is_last = (i == len(chunks) - 1)
        markup = None
        if buttons and is_last:
            markup = InlineKeyboardMarkup([[
                InlineKeyboardButton("✅ Yes", callback_data="perm_y"),
                InlineKeyboardButton("❌ No", callback_data="perm_n"),
            ]])
        try:
            try:
                await bot.send_message(telegram_chat_id, f"```\n{chunk}\n```",
                                       parse_mode="Markdown", reply_markup=markup)
            except Exception:
                await bot.send_message(telegram_chat_id, chunk, reply_markup=markup)
        except Exception as e:
            print(f"[tg] send err: {e}")

# ── Buffer flusher — collects output then sends ──
async def flush_loop():
    global output_buffer
    while True:
        await asyncio.sleep(1.0)
        async with buffer_lock:
            if output_buffer:
                raw = output_buffer
                output_buffer = ""
            else:
                continue
        text = clean(raw)
        if text:
            await tg_send(text, buttons=is_permission_prompt(text))

# ── Read CLI stdout continuously ──
async def read_loop():
    global output_buffer, cli_process
    if not cli_process: return
    loop = asyncio.get_event_loop()
    while cli_process and cli_process.isalive():
        try:
            data = await loop.run_in_executor(
                None, lambda: cli_process.read_nonblocking(4096, timeout=0.3)
            )
            if data:
                async with buffer_lock:
                    output_buffer += data
        except pexpect.TIMEOUT:
            continue
        except pexpect.EOF:
            async with buffer_lock:
                if output_buffer:
                    text = clean(output_buffer); output_buffer = ""
                    if text: await tg_send(text)
            await tg_send("⏹️ CLI session ended.")
            break
        except Exception as e:
            print(f"[read] err: {e}")
            await asyncio.sleep(0.5)

# ── Start CLI ──
def spawn_cli(session_mode: str) -> pexpect.spawn:
    global cli_process
    path = config.get("claude_cli_path", "claude")
    args = []
    if session_mode == "continue":
        args.append("--continue")
    elif session_mode and session_mode != "new":
        args.extend(["--resume", session_mode])

    print(f"[cli] spawn: {path} {' '.join(args)}")
    cli_process = pexpect.spawn(
        path, args,
        encoding='utf-8', timeout=None,
        env={**os.environ, "TERM": "dumb", "NO_COLOR": "1", "FORCE_COLOR": "0"},
        dimensions=(40, 120),
    )
    cli_process.setecho(False)
    cli_process.delaybeforesend = 0.05
    return cli_process

# ── Telegram handlers ──
def authed(update):
    ids = config.get("allowed_user_ids", [])
    return not ids or update.effective_user.id in ids

async def cmd_start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    global telegram_chat_id
    if not authed(update):
        return await update.message.reply_text(f"🚫 ID: {update.effective_user.id}")
    telegram_chat_id = update.effective_chat.id
    alive = cli_process and cli_process.isalive()
    mode = f"`{SESSION_MODE}`" if SESSION_MODE != "continue" else "latest"
    await update.message.reply_text(
        f"🪞 *CLI Mirror*\n\n"
        f"CLI: {'🟢 running' if alive else '🔴 stopped'}\n"
        f"Session: {mode}\n\n"
        f"Type here → goes to CLI\n"
        f"CLI output → appears here\n"
        f"Permission prompts → ✅/❌ buttons\n\n"
        f"/restart — restart CLI\n/stop — stop CLI",
        parse_mode="Markdown")

async def cmd_restart(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    global cli_process
    if not authed(update): return
    if cli_process and cli_process.isalive():
        cli_process.terminate(force=True)
        await asyncio.sleep(1)
    spawn_cli(SESSION_MODE)
    asyncio.create_task(read_loop())
    await update.message.reply_text("🔄 CLI restarted.")

async def cmd_stop(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    global cli_process
    if not authed(update): return
    if cli_process and cli_process.isalive():
        cli_process.terminate(force=True); cli_process = None
        await update.message.reply_text("⏹️ Stopped.")
    else:
        await update.message.reply_text("Not running.")

async def cmd_id(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(f"ID: `{update.effective_user.id}`", parse_mode="Markdown")

async def on_message(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    global telegram_chat_id
    if not authed(update):
        return await update.message.reply_text(f"🚫 ID: {update.effective_user.id}")
    telegram_chat_id = update.effective_chat.id
    msg = update.message.text
    if not msg: return
    if not cli_process or not cli_process.isalive():
        return await update.message.reply_text("⚠️ CLI not running. /restart")
    try:
        cli_process.sendline(msg)
    except Exception as e:
        await update.message.reply_text(f"❌ {e}")

async def on_button(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    if not cli_process or not cli_process.isalive():
        return await q.edit_message_reply_markup(None)
    if q.data == "perm_y":
        cli_process.sendline("y")
        await q.edit_message_reply_markup(None)
        try: await q.message.reply_text("✅ Approved")
        except: pass
    elif q.data == "perm_n":
        cli_process.sendline("n")
        await q.edit_message_reply_markup(None)
        try: await q.message.reply_text("❌ Denied")
        except: pass

# ── Boot ──
async def post_init(app: Application):
    global bot_app
    bot_app = app
    spawn_cli(SESSION_MODE)
    asyncio.create_task(read_loop())
    asyncio.create_task(flush_loop())

def main():
    token = config.get("telegram_token", "")
    if not token:
        print("❌ No telegram_token in config.json"); sys.exit(1)
    mode = f"session {SESSION_MODE}" if SESSION_MODE != "continue" else "latest (--continue)"
    print(f"\n🪞 Claude CLI ↔ Telegram Mirror\n   Session: {mode}\n   Ctrl+C to stop\n")
    app = Application.builder().token(token).post_init(post_init).build()
    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("restart", cmd_restart))
    app.add_handler(CommandHandler("stop", cmd_stop))
    app.add_handler(CommandHandler("id", cmd_id))
    app.add_handler(CallbackQueryHandler(on_button, pattern="^perm_"))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, on_message))
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
PYEOF
}

write_cli() {
  cat > "$INSTALL_DIR/claude-telegram" << CLIEOF
#!/bin/bash
INSTALL_DIR="$INSTALL_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'

case "\${1:-help}" in
  start)
    S="\$2"
    if [ -n "\$S" ]; then
      echo -e "\${CYAN}🪞 Mirroring session: \${BOLD}\$S\${RESET}"
      export CLAUDE_SESSION_MODE="\$S"
    else
      echo -e "\${CYAN}🪞 Mirroring latest CLI session\${RESET}"
      export CLAUDE_SESSION_MODE="continue"
    fi
    echo -e "   Send /start to your bot on Telegram"
    echo -e "   Ctrl+C to stop"
    echo ""
    cd "\$INSTALL_DIR" && source venv/bin/activate && python3 mirror.py
    ;;
  list)
    echo -e "\${CYAN}📋 Claude CLI Sessions:\${RESET}\n"
    cd "\$HOME" && claude sessions list 2>/dev/null || echo -e "\${YELLOW}⚠ Could not list sessions\${RESET}"
    echo -e "\n\${DIM}────────────────────────────────────────\${RESET}"
    echo -e "  \${BOLD}claude-telegram start <session-id>\${RESET}"
    echo -e "  \${BOLD}claude-telegram start\${RESET}  (latest session)"
    ;;
  stop)
    pkill -f "\$INSTALL_DIR/mirror.py" 2>/dev/null && echo -e "\${GREEN}✓ Stopped\${RESET}" || echo -e "\${YELLOW}⚠ Not running\${RESET}"
    ;;
  restart) "\$0" stop; sleep 1; "\$0" start "\$2" ;;
  status)
    pgrep -f "\$INSTALL_DIR/mirror.py" &>/dev/null && echo -e "\${GREEN}● Running\${RESET}" || echo -e "\${RED}● Stopped\${RESET}"
    ;;
  bg)
    export CLAUDE_SESSION_MODE="\${2:-continue}"
    cd "\$INSTALL_DIR" && source venv/bin/activate
    CLAUDE_SESSION_MODE="\$CLAUDE_SESSION_MODE" nohup python3 mirror.py > "\$INSTALL_DIR/mirror.log" 2>&1 &
    echo -e "\${GREEN}✓ Background\${RESET} (PID \$!)\n  Logs: tail -f \$INSTALL_DIR/mirror.log"
    ;;
  config) \${EDITOR:-nano} "\$INSTALL_DIR/config.json" ;;
  logs) [ -f "\$INSTALL_DIR/mirror.log" ] && tail -f "\$INSTALL_DIR/mirror.log" || echo "No logs" ;;
  uninstall)
    read -p "Remove Claude Telegram Mirror? (y/N) " -n 1 -r; echo
    [[ \$REPLY =~ ^[Yy]$ ]] && { "\$0" stop 2>/dev/null; rm -rf "\$INSTALL_DIR" "\$HOME/.local/bin/claude-telegram"; echo -e "\${GREEN}✓ Removed\${RESET}"; }
    ;;
  *)
    echo ""
    echo -e "\${BOLD}🪞 Claude CLI ↔ Telegram Mirror\${RESET}"
    echo ""
    echo "  claude-telegram list                List CLI sessions"
    echo "  claude-telegram start               Mirror latest session"
    echo "  claude-telegram start <session-id>  Mirror specific session"
    echo "  claude-telegram stop                Stop"
    echo "  claude-telegram bg [session-id]     Background mode"
    echo "  claude-telegram status              Check status"
    echo "  claude-telegram config              Edit config"
    echo "  claude-telegram logs                View logs"
    echo "  claude-telegram uninstall           Remove"
    echo ""
    echo -e "  \${BOLD}What it does:\${RESET}"
    echo "    CLI output → Telegram (real-time)"
    echo "    Telegram input → CLI stdin"
    echo "    Permission prompts → ✅/❌ buttons"
    echo ""
    ;;
esac
CLIEOF
  chmod +x "$INSTALL_DIR/claude-telegram"
  mkdir -p "$HOME/.local/bin"
  ln -sf "$INSTALL_DIR/claude-telegram" "$HOME/.local/bin/claude-telegram"
  if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
      if [ -f "$rc" ]; then echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"; break; fi
    done
    export PATH="$HOME/.local/bin:$PATH"
  fi
}

show_done() {
  step "④ Ready!"
  echo ""
  echo -e "  ${GREEN}${BOLD}Installed!${RESET}"
  echo ""
  echo -e "  ${BOLD}Usage:${RESET}"
  echo -e "    ${CYAN}claude-telegram list${RESET}              See sessions"
  echo -e "    ${CYAN}claude-telegram start${RESET}             Mirror latest"
  echo -e "    ${CYAN}claude-telegram start <id>${RESET}        Mirror specific session"
  echo ""
  echo -e "  ${BOLD}In Telegram:${RESET}"
  echo -e "    • All CLI output streams to chat"
  echo -e "    • Type anything → sent to CLI"
  echo -e "    • Permission prompts → ✅/❌ buttons"
  echo ""
  if [ -n "$BOT_TOKEN" ]; then
    ask "Start now? (Y/n) "; read -r SN
    if [[ ! "$SN" =~ ^[Nn]$ ]]; then echo ""; exec "$INSTALL_DIR/claude-telegram" start; fi
  else
    echo -e "  ${YELLOW}→ claude-telegram config${RESET} (add token), then ${CYAN}claude-telegram start${RESET}"
  fi
  echo ""
}

main() {
  print_banner
  check_prerequisites
  setup_telegram
  install_bridge
  show_done
}

main
