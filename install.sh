#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  Claude ↔ Telegram Bridge — One-Command Installer
#  
#  Usage:  curl -sSL https://raw.githubusercontent.com/allexp1/telebot/main/install.sh | bash
#  Or:     bash install-claude-telegram.sh
# ═══════════════════════════════════════════════════════════════
set -e

# ── Colors & Helpers ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'

INSTALL_DIR="$HOME/.claude-telegram-bridge"
VENV_DIR="$INSTALL_DIR/venv"
PLIST_NAME="com.claude.telegram-bridge"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

print_banner() {
  echo ""
  echo -e "${CYAN}${BOLD}"
  echo "  ┌─────────────────────────────────────┐"
  echo "  │   🌉  Claude ↔ Telegram Bridge      │"
  echo "  │       One-Command Installer          │"
  echo "  └─────────────────────────────────────┘"
  echo -e "${RESET}"
}

info()    { echo -e "  ${CYAN}ℹ${RESET}  $1"; }
ok()      { echo -e "  ${GREEN}✓${RESET}  $1"; }
warn()    { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
fail()    { echo -e "  ${RED}✗${RESET}  $1"; }
step()    { echo -e "\n  ${BOLD}$1${RESET}"; echo -e "  ${DIM}$(printf '─%.0s' {1..40})${RESET}"; }
ask()     { echo -ne "  ${CYAN}▸${RESET} $1"; }

# ── Preflight Checks ──
check_prerequisites() {
  step "① Checking prerequisites"

  # Python 3
  if command -v python3 &>/dev/null; then
    PY_VER=$(python3 --version 2>&1)
    ok "Python: $PY_VER"
  else
    fail "Python 3 not found"
    echo ""
    if [[ "$OSTYPE" == "darwin"* ]]; then
      info "Install with: brew install python3"
    else
      info "Install with: sudo apt install python3 python3-venv python3-pip"
    fi
    exit 1
  fi

  # pip / venv
  if python3 -m venv --help &>/dev/null; then
    ok "Python venv module available"
  else
    fail "Python venv module missing"
    info "Install with: sudo apt install python3-venv"
    exit 1
  fi

  # Claude CLI
  if command -v claude &>/dev/null; then
    CLI_VER=$(claude --version 2>/dev/null || echo "installed")
    ok "Claude CLI: $CLI_VER"
    CLAUDE_PATH="claude"
  else
    # Check common locations
    for p in "$HOME/.npm-global/bin/claude" "/usr/local/bin/claude" "$HOME/.local/bin/claude"; do
      if [ -x "$p" ]; then
        ok "Claude CLI found at $p"
        CLAUDE_PATH="$p"
        break
      fi
    done
    if [ -z "$CLAUDE_PATH" ]; then
      warn "Claude CLI not found in PATH"
      ask "Enter full path to claude binary (or press Enter to install later): "
      read -r CLAUDE_PATH
      if [ -z "$CLAUDE_PATH" ]; then
        CLAUDE_PATH="claude"
        warn "Set to 'claude' — install it later: npm install -g @anthropic-ai/claude-cli"
      elif [ ! -x "$CLAUDE_PATH" ]; then
        warn "$CLAUDE_PATH doesn't look executable, continuing anyway"
      fi
    fi
  fi
}

# ── Telegram Setup ──
setup_telegram() {
  step "② Telegram Bot Setup"
  echo ""
  info "You need a Telegram bot token. Here's how:"
  echo -e "  ${DIM}  1. Open Telegram and message ${RESET}${BOLD}@BotFather${RESET}"
  echo -e "  ${DIM}  2. Send ${RESET}${BOLD}/newbot${RESET}"
  echo -e "  ${DIM}  3. Choose a name and username for your bot${RESET}"
  echo -e "  ${DIM}  4. Copy the token (looks like 123456:ABC-DEF1234...)${RESET}"
  echo ""

  while true; do
    ask "Paste your bot token: "
    read -r BOT_TOKEN
    if [[ "$BOT_TOKEN" =~ ^[0-9]+:.+$ ]]; then
      ok "Token format looks good"
      break
    elif [ -z "$BOT_TOKEN" ]; then
      warn "Skipping — you can add it later in config.json"
      break
    else
      fail "That doesn't look like a valid bot token. Try again (or press Enter to skip)."
    fi
  done

  echo ""
  info "Now I need your Telegram user ID (so only YOU can use the bot)."
  echo -e "  ${DIM}  → Message ${RESET}${BOLD}@userinfobot${RESET}${DIM} on Telegram to get your ID${RESET}"
  echo -e "  ${DIM}  → Or message your new bot and send /id after setup${RESET}"
  echo ""

  ask "Your Telegram user ID (numbers only, or Enter to skip): "
  read -r USER_ID

  ALLOWED_IDS="[]"
  if [[ "$USER_ID" =~ ^[0-9]+$ ]]; then
    ALLOWED_IDS="[$USER_ID]"
    ok "Will restrict bot to user ID $USER_ID"
  else
    warn "No user ID set — bot will accept messages from anyone!"
    warn "Set it later in config.json for security."
  fi
}

# ── Install ──
install_bridge() {
  step "③ Installing bridge"

  # Create install directory
  mkdir -p "$INSTALL_DIR"
  ok "Created $INSTALL_DIR"

  # Write requirements
  cat > "$INSTALL_DIR/requirements.txt" << 'REQEOF'
fastapi>=0.104.0
uvicorn>=0.24.0
python-telegram-bot>=20.7
pydantic>=2.0
REQEOF

  # Create venv and install deps
  info "Creating Python virtual environment..."
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install -q --upgrade pip 2>/dev/null
  "$VENV_DIR/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt"
  ok "Dependencies installed"

  # Write config
  cat > "$INSTALL_DIR/config.json" << CFGEOF
{
  "telegram_token": "$BOT_TOKEN",
  "allowed_user_ids": $ALLOWED_IDS,
  "system_prompt": "You are a helpful assistant communicating via Telegram. Keep responses concise and well-formatted for mobile reading.",
  "claude_cli_path": "${CLAUDE_PATH:-claude}",
  "max_response_length": 4096,
  "session_timeout_hours": 24,
  "web_port": 7860,
  "claude_model": "",
  "allowed_tools": "",
  "mcp_config": ""
}
CFGEOF
  ok "Config saved"

  # Write the server
  write_server
  ok "Server created"

  # Write the dashboard
  write_dashboard
  ok "Dashboard created"

  # Write launcher script
  cat > "$INSTALL_DIR/start.sh" << 'STARTEOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
source venv/bin/activate
exec python3 server.py
STARTEOF
  chmod +x "$INSTALL_DIR/start.sh"

  # Create global command
  write_cli_command
  ok "CLI command installed: ${BOLD}claude-telegram${RESET}"
}

# ── CLI command ──
write_cli_command() {
  cat > "$INSTALL_DIR/claude-telegram" << CLIEOF
#!/bin/bash
# Claude ↔ Telegram Bridge CLI
INSTALL_DIR="$INSTALL_DIR"
PLIST_PATH="$PLIST_PATH"
PLIST_NAME="$PLIST_NAME"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'

case "\${1:-start}" in
  start)
    echo -e "\${CYAN}🌉 Starting Claude ↔ Telegram Bridge...\${RESET}"
    echo -e "   Dashboard: \${BOLD}http://localhost:7860\${RESET}"
    echo -e "   Press Ctrl+C to stop"
    echo ""
    cd "\$INSTALL_DIR" && source venv/bin/activate && python3 server.py
    ;;
  stop)
    echo -e "\${CYAN}🛑 Stopping bridge...\${RESET}"
    pkill -f "\$INSTALL_DIR/server.py" 2>/dev/null && echo -e "\${GREEN}✓ Stopped\${RESET}" || echo -e "\${YELLOW}⚠ Not running\${RESET}"
    ;;
  restart)
    "\$0" stop
    sleep 1
    "\$0" start
    ;;
  status)
    if pgrep -f "\$INSTALL_DIR/server.py" &>/dev/null; then
      PID=\$(pgrep -f "\$INSTALL_DIR/server.py")
      echo -e "\${GREEN}● Running\${RESET} (PID \$PID)"
      echo -e "  Dashboard: http://localhost:7860"
    else
      echo -e "\${RED}● Stopped\${RESET}"
    fi
    ;;
  bg)
    echo -e "\${CYAN}🌉 Starting in background...\${RESET}"
    cd "\$INSTALL_DIR" && source venv/bin/activate
    nohup python3 server.py > "\$INSTALL_DIR/bridge.log" 2>&1 &
    PID=\$!
    echo -e "\${GREEN}✓ Running in background\${RESET} (PID \$PID)"
    echo -e "  Dashboard: \${BOLD}http://localhost:7860\${RESET}"
    echo -e "  Logs: tail -f \$INSTALL_DIR/bridge.log"
    ;;
  autostart)
    if [[ "\$OSTYPE" == "darwin"* ]]; then
      mkdir -p "\$HOME/Library/LaunchAgents"
      cat > "\$PLIST_PATH" << PEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>\$PLIST_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>\$INSTALL_DIR/start.sh</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>\$INSTALL_DIR/bridge.log</string>
    <key>StandardErrorPath</key><string>\$INSTALL_DIR/bridge.err</string>
</dict>
</plist>
PEOF
      launchctl load "\$PLIST_PATH" 2>/dev/null
      echo -e "\${GREEN}✓ Autostart enabled\${RESET} — bridge will start on login"
    else
      echo -e "\${YELLOW}⚠ Autostart is macOS only. Use systemd on Linux.\${RESET}"
    fi
    ;;
  no-autostart)
    if [ -f "\$PLIST_PATH" ]; then
      launchctl unload "\$PLIST_PATH" 2>/dev/null
      rm -f "\$PLIST_PATH"
      echo -e "\${GREEN}✓ Autostart disabled\${RESET}"
    else
      echo -e "\${DIM}Autostart wasn't enabled\${RESET}"
    fi
    ;;
  config)
    \${EDITOR:-nano} "\$INSTALL_DIR/config.json"
    ;;
  logs)
    if [ -f "\$INSTALL_DIR/bridge.log" ]; then
      tail -f "\$INSTALL_DIR/bridge.log"
    else
      echo -e "\${DIM}No logs yet. Start in background first: claude-telegram bg\${RESET}"
    fi
    ;;
  uninstall)
    echo -e "\${RED}This will remove the Claude Telegram Bridge.\${RESET}"
    read -p "  Are you sure? (y/N) " -n 1 -r
    echo
    if [[ \$REPLY =~ ^[Yy]$ ]]; then
      "\$0" stop 2>/dev/null
      "\$0" no-autostart 2>/dev/null
      rm -rf "\$INSTALL_DIR"
      rm -f "\$HOME/.local/bin/claude-telegram"
      echo -e "\${GREEN}✓ Uninstalled\${RESET}"
    fi
    ;;
  *)
    echo ""
    echo -e "\${BOLD}Claude ↔ Telegram Bridge\${RESET}"
    echo ""
    echo "  Usage: claude-telegram <command>"
    echo ""
    echo -e "  \${BOLD}Commands:\${RESET}"
    echo "    start         Start the bridge (foreground)"
    echo "    stop          Stop the bridge"
    echo "    restart       Restart the bridge"
    echo "    bg            Start in background"
    echo "    status        Check if running"
    echo "    autostart     Start on macOS login"
    echo "    no-autostart  Disable autostart"
    echo "    config        Edit configuration"
    echo "    logs          Tail log file"
    echo "    uninstall     Remove everything"
    echo ""
    ;;
esac
CLIEOF
  chmod +x "$INSTALL_DIR/claude-telegram"

  # Symlink to PATH
  mkdir -p "$HOME/.local/bin"
  ln -sf "$INSTALL_DIR/claude-telegram" "$HOME/.local/bin/claude-telegram"

  # Ensure ~/.local/bin is in PATH
  if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    SHELL_RC=""
    if [ -f "$HOME/.zshrc" ]; then
      SHELL_RC="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
      SHELL_RC="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
      SHELL_RC="$HOME/.bash_profile"
    fi
    if [ -n "$SHELL_RC" ]; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
      info "Added ~/.local/bin to PATH in $SHELL_RC"
    fi
    export PATH="$HOME/.local/bin:$PATH"
  fi
}

# ── Server Code (embedded) ──
write_server() {
cat > "$INSTALL_DIR/server.py" << 'SERVEREOF'
import asyncio, json, os, sqlite3, subprocess, sys, time, uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from pydantic import BaseModel
from telegram import Bot, Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes

CONFIG_PATH = Path(__file__).parent / "config.json"
DB_PATH = Path(__file__).parent / "bridge.db"
DASH_PATH = Path(__file__).parent / "dashboard.html"

DEFAULT_CONFIG = {
    "telegram_token": "", "allowed_user_ids": [],
    "system_prompt": "You are a helpful assistant communicating via Telegram. Keep responses concise and well-formatted for mobile reading.",
    "claude_cli_path": "claude", "max_response_length": 4096,
    "session_timeout_hours": 24, "web_port": 7860,
    "claude_model": "", "allowed_tools": "", "mcp_config": "",
}

def load_config():
    if CONFIG_PATH.exists():
        with open(CONFIG_PATH) as f: return {**DEFAULT_CONFIG, **json.load(f)}
    return DEFAULT_CONFIG.copy()

def save_config(cfg):
    with open(CONFIG_PATH, "w") as f: json.dump(cfg, f, indent=2)

config = load_config()

def init_db():
    conn = sqlite3.connect(str(DB_PATH)); conn.execute("PRAGMA journal_mode=WAL")
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, telegram_chat_id INTEGER, claude_session_id TEXT, name TEXT, created_at TEXT DEFAULT (datetime('now')), last_active TEXT DEFAULT (datetime('now')), message_count INTEGER DEFAULT 0, is_active INTEGER DEFAULT 1);
        CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT, role TEXT, content TEXT, timestamp TEXT DEFAULT (datetime('now')), tokens_used INTEGER DEFAULT 0, response_time_ms INTEGER DEFAULT 0, FOREIGN KEY (session_id) REFERENCES sessions(id));
        CREATE INDEX IF NOT EXISTS idx_msg_sess ON messages(session_id);
        CREATE INDEX IF NOT EXISTS idx_sess_chat ON sessions(telegram_chat_id);
    """); conn.close()

def get_db():
    conn = sqlite3.connect(str(DB_PATH)); conn.row_factory = sqlite3.Row; return conn

async def call_claude_cli(message, session_id=None):
    cmd = [config["claude_cli_path"], "-p", message]
    if session_id: cmd.extend(["--resume", session_id])
    if config.get("system_prompt"): cmd.extend(["--system-prompt", config["system_prompt"]])
    if config.get("claude_model"): cmd.extend(["--model", config["claude_model"]])
    if config.get("allowed_tools"): cmd.extend(["--allowedTools", config["allowed_tools"]])
    if config.get("mcp_config"):
        p = Path(config["mcp_config"]).expanduser()
        if p.exists(): cmd.extend(["--mcp-config", str(p)])
    start = time.monotonic()
    try:
        proc = await asyncio.create_subprocess_exec(*cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=180)
        elapsed = int((time.monotonic() - start) * 1000)
        resp = stdout.decode().strip()
        if not resp and stderr: resp = f"⚠️ {stderr.decode().strip()}"
        return resp or "⚠️ No response.", elapsed
    except asyncio.TimeoutError: return "⏱️ Timed out (3 min).", int((time.monotonic()-start)*1000)
    except FileNotFoundError: return "❌ Claude CLI not found. Check claude_cli_path in config.", 0
    except Exception as e: return f"❌ {e}", int((time.monotonic()-start)*1000)

def get_or_create_session(chat_id):
    db = get_db()
    row = db.execute("SELECT * FROM sessions WHERE telegram_chat_id=? AND is_active=1 ORDER BY last_active DESC LIMIT 1",(chat_id,)).fetchone()
    if row: db.close(); return dict(row)
    sid, csid = str(uuid.uuid4())[:8], str(uuid.uuid4())
    db.execute("INSERT INTO sessions (id,telegram_chat_id,claude_session_id,name) VALUES (?,?,?,?)",(sid,chat_id,csid,f"Chat {sid}"))
    db.commit(); r = dict(db.execute("SELECT * FROM sessions WHERE id=?",(sid,)).fetchone()); db.close(); return r

def save_message(sid, role, content, ms=0):
    db = get_db(); db.execute("INSERT INTO messages (session_id,role,content,response_time_ms) VALUES (?,?,?,?)",(sid,role,content,ms)); db.commit(); db.close()

def update_session(sid):
    db = get_db(); db.execute("UPDATE sessions SET last_active=datetime('now'),message_count=message_count+1 WHERE id=?",(sid,)); db.commit(); db.close()

telegram_app = None

async def cmd_start(update, context):
    if config["allowed_user_ids"] and update.effective_user.id not in config["allowed_user_ids"]:
        return await update.message.reply_text(f"🚫 Unauthorized. Your ID: {update.effective_user.id}")
    await update.message.reply_text("👋 *Claude CLI Bridge*\n\nSend any message to chat with Claude.\n\n/new — New session\n/status — Connection info\n/id — Your user ID", parse_mode="Markdown")

async def cmd_new(update, context):
    if config["allowed_user_ids"] and update.effective_user.id not in config["allowed_user_ids"]: return
    db = get_db(); db.execute("UPDATE sessions SET is_active=0 WHERE telegram_chat_id=?",(update.effective_chat.id,)); db.commit(); db.close()
    s = get_or_create_session(update.effective_chat.id)
    await update.message.reply_text(f"🆕 New session: `{s['id']}`", parse_mode="Markdown")

async def cmd_status(update, context):
    if config["allowed_user_ids"] and update.effective_user.id not in config["allowed_user_ids"]: return
    s = get_or_create_session(update.effective_chat.id)
    await update.message.reply_text(f"✅ *Bridge Active*\nSession: `{s['id']}`\nMessages: {s['message_count']}", parse_mode="Markdown")

async def cmd_id(update, context):
    await update.message.reply_text(f"Your Telegram user ID: `{update.effective_user.id}`", parse_mode="Markdown")

async def handle_message(update, context):
    uid = update.effective_user.id
    if config["allowed_user_ids"] and uid not in config["allowed_user_ids"]:
        return await update.message.reply_text(f"🚫 Unauthorized. Your ID: {uid}")
    msg = update.message.text
    if not msg: return
    s = get_or_create_session(update.effective_chat.id)
    save_message(s["id"], "user", msg)
    await context.bot.send_chat_action(chat_id=update.effective_chat.id, action="typing")
    resp, ms = await call_claude_cli(msg, s["claude_session_id"])
    save_message(s["id"], "assistant", resp, ms)
    update_session(s["id"])
    for i in range(0, len(resp), 4096):
        chunk = resp[i:i+4096]
        try: await update.message.reply_text(chunk, parse_mode="Markdown")
        except: await update.message.reply_text(chunk)

@asynccontextmanager
async def lifespan(app):
    global telegram_app; init_db()
    if config.get("telegram_token"):
        telegram_app = Application.builder().token(config["telegram_token"]).build()
        telegram_app.add_handler(CommandHandler("start", cmd_start))
        telegram_app.add_handler(CommandHandler("new", cmd_new))
        telegram_app.add_handler(CommandHandler("status", cmd_status))
        telegram_app.add_handler(CommandHandler("id", cmd_id))
        telegram_app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
        await telegram_app.initialize(); await telegram_app.start()
        await telegram_app.updater.start_polling(drop_pending_updates=True)
        print("✅ Telegram bot started!")
    else: print("⚠️  No Telegram token. Set via dashboard or config.json")
    yield
    if telegram_app and telegram_app.running:
        await telegram_app.updater.stop(); await telegram_app.stop(); await telegram_app.shutdown()

app = FastAPI(title="Claude Telegram Bridge", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

@app.get("/")
async def dash():
    return FileResponse(DASH_PATH, media_type="text/html") if DASH_PATH.exists() else HTMLResponse("<h1>Dashboard not found</h1>", 404)

class CfgUpdate(BaseModel):
    telegram_token: Optional[str]=None; allowed_user_ids: Optional[list[int]]=None
    system_prompt: Optional[str]=None; claude_cli_path: Optional[str]=None
    max_response_length: Optional[int]=None; session_timeout_hours: Optional[int]=None
    claude_model: Optional[str]=None; allowed_tools: Optional[str]=None; mcp_config: Optional[str]=None

@app.get("/api/config")
async def get_cfg():
    safe = {**config}
    if safe.get("telegram_token"):
        t = safe["telegram_token"]; safe["telegram_token"] = t[:8]+"..."+t[-4:] if len(t)>12 else "***"
    return safe

@app.post("/api/config")
async def set_cfg(body: CfgUpdate):
    global config; u = body.model_dump(exclude_none=True)
    if "telegram_token" in u and "..." in u["telegram_token"]: del u["telegram_token"]
    config.update(u); save_config(config)
    return {"status":"ok","message":"Saved. Restart to apply token changes."}

@app.get("/api/sessions")
async def list_sess():
    db=get_db(); r=db.execute("SELECT * FROM sessions ORDER BY last_active DESC LIMIT 50").fetchall(); db.close(); return [dict(x) for x in r]

@app.delete("/api/sessions/{sid}")
async def end_sess(sid:str):
    db=get_db(); db.execute("UPDATE sessions SET is_active=0 WHERE id=?",(sid,)); db.commit(); db.close(); return {"status":"ok"}

@app.get("/api/sessions/{sid}/messages")
async def get_msgs(sid:str):
    db=get_db(); r=db.execute("SELECT * FROM messages WHERE session_id=? ORDER BY timestamp",(sid,)).fetchall(); db.close(); return [dict(x) for x in r]

@app.get("/api/stats")
async def stats():
    db=get_db()
    tm=db.execute("SELECT COUNT(*) c FROM messages").fetchone()["c"]
    ts=db.execute("SELECT COUNT(*) c FROM sessions").fetchone()["c"]
    ac=db.execute("SELECT COUNT(*) c FROM sessions WHERE is_active=1").fetchone()["c"]
    ar=db.execute("SELECT AVG(response_time_ms) a FROM messages WHERE role='assistant' AND response_time_ms>0").fetchone()["a"]
    da=db.execute("SELECT date(timestamp) day,COUNT(*) count FROM messages WHERE timestamp>datetime('now','-7 days') GROUP BY day ORDER BY day").fetchall()
    db.close()
    return {"total_messages":tm,"total_sessions":ts,"active_sessions":ac,"avg_response_ms":round(ar or 0),"daily_activity":[dict(x) for x in da]}

@app.get("/api/health")
async def health():
    bot_ok = telegram_app is not None and telegram_app.running
    try:
        p=await asyncio.create_subprocess_exec(config["claude_cli_path"],"--version",stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.PIPE)
        o,_=await asyncio.wait_for(p.communicate(),5); cli_ver=o.decode().strip(); cli_ok=True
    except: cli_ver="not found"; cli_ok=False
    return {"status":"ok","telegram_bot":"running" if bot_ok else "stopped","claude_cli":cli_ver,"cli_available":cli_ok}

@app.post("/api/test")
async def test(request:Request):
    b=await request.json(); r,ms=await call_claude_cli(b.get("message","Say 'test ok' in 5 words.")); return {"response":r,"elapsed_ms":ms}

if __name__=="__main__":
    init_db(); port=config.get("web_port",7860)
    print(f"\n🌉 Claude ↔ Telegram Bridge\n   Dashboard: http://localhost:{port}\n   Ctrl+C to stop\n")
    uvicorn.run(app,host="0.0.0.0",port=port,log_level="info")
SERVEREOF
}

# ── Dashboard (embedded) ──
write_dashboard() {
cat > "$INSTALL_DIR/dashboard.html" << 'DASHEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Claude ↔ Telegram Bridge</title>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&family=Outfit:wght@300;400;500;600;700&display=swap" rel="stylesheet">
<style>
:root{--bg:#0a0a0f;--s:#12121a;--s2:#1a1a26;--s3:#222233;--b:#2a2a3d;--t:#e4e4ef;--td:#8888a0;--a:#d4a574;--ag:#d4a57440;--g:#6ec87a;--r:#e06b6b;--bl:#6ba3e0;--p:#a78bdb;--rad:12px}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Outfit',sans-serif;background:var(--bg);color:var(--t);min-height:100vh}
body::before{content:'';position:fixed;top:-50%;left:-50%;width:200%;height:200%;background:radial-gradient(ellipse at 30% 20%,#d4a57408 0%,transparent 50%),radial-gradient(ellipse at 70% 80%,#6ba3e008 0%,transparent 50%);animation:drift 20s ease-in-out infinite alternate;pointer-events:none;z-index:0}
@keyframes drift{0%{transform:translate(0,0)}100%{transform:translate(-3%,3%) rotate(2deg)}}
.sh{position:relative;z-index:1;max-width:1280px;margin:0 auto;padding:24px}
header{display:flex;align-items:center;justify-content:space-between;padding:20px 0 32px;border-bottom:1px solid var(--b);margin-bottom:32px}
.logo{display:flex;align-items:center;gap:14px}
.logo-i{width:44px;height:44px;border-radius:12px;background:linear-gradient(135deg,var(--a),#b8845a);display:flex;align-items:center;justify-content:center;font-size:20px;box-shadow:0 4px 20px var(--ag)}
.logo h1{font-size:22px;font-weight:600;letter-spacing:-.5px} .logo span{font-size:13px;color:var(--td);font-weight:400}
.sp{display:flex;align-items:center;gap:8px;padding:8px 16px;border-radius:20px;background:var(--s);border:1px solid var(--b);font-size:13px;font-family:'JetBrains Mono',monospace}
.sd{width:8px;height:8px;border-radius:50%;animation:pulse 2s ease-in-out infinite}
.sd.ok{background:var(--g);box-shadow:0 0 8px #6ec87a60} .sd.err{background:var(--r)}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.5}}
.tabs{display:flex;gap:4px;margin-bottom:28px;background:var(--s);border-radius:10px;padding:4px;border:1px solid var(--b);width:fit-content}
.tab{padding:10px 20px;border-radius:8px;cursor:pointer;font-size:14px;font-weight:500;color:var(--td);transition:.2s;border:none;background:none;font-family:'Outfit',sans-serif}
.tab:hover{color:var(--t)} .tab.act{background:var(--s3);color:var(--a)}
.pn{display:none;animation:fi .3s} .pn.act{display:block} @keyframes fi{from{opacity:0;transform:translateY(8px)}to{opacity:1}}
.cg{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px;margin-bottom:28px}
.cd{background:var(--s);border:1px solid var(--b);border-radius:var(--rad);padding:20px;transition:.2s} .cd:hover{border-color:var(--a)}
.cl{font-size:12px;color:var(--td);text-transform:uppercase;letter-spacing:1px;margin-bottom:8px}
.cv{font-size:28px;font-weight:700;font-family:'JetBrains Mono',monospace}
.tw{background:var(--s);border:1px solid var(--b);border-radius:var(--rad);overflow:hidden}
.th{padding:16px 20px;border-bottom:1px solid var(--b);font-weight:600;font-size:15px}
table{width:100%;border-collapse:collapse} th{text-align:left;padding:12px 20px;font-size:11px;text-transform:uppercase;letter-spacing:1px;color:var(--td);border-bottom:1px solid var(--b)}
td{padding:14px 20px;font-size:14px;border-bottom:1px solid var(--b)} tr:last-child td{border-bottom:none} tr:hover td{background:var(--s2)}
.bg{display:inline-block;padding:3px 10px;border-radius:6px;font-size:12px;font-weight:500;font-family:'JetBrains Mono',monospace}
.bg.a{background:#6ec87a20;color:var(--g)} .bg.e{background:#8888a020;color:var(--td)}
.cv-wrap{background:var(--s);border:1px solid var(--b);border-radius:var(--rad);max-height:500px;overflow-y:auto;padding:20px;display:none;margin-top:16px}
.cv-wrap.open{display:block}
.cm{margin-bottom:16px} .cm .rl{font-size:11px;text-transform:uppercase;letter-spacing:1px;margin-bottom:4px;font-weight:600}
.cm .rl.user{color:var(--bl)} .cm .rl.assistant{color:var(--a)}
.cm .bb{padding:12px 16px;border-radius:10px;font-size:14px;line-height:1.6;white-space:pre-wrap;max-width:85%}
.cm.um .bb{background:var(--s2)} .cm.am .bb{background:var(--s3);border:1px solid var(--b)}
.ct{font-size:11px;color:var(--td);margin-top:4px;font-family:'JetBrains Mono',monospace}
.fg{margin-bottom:20px} .fg label{display:block;font-size:13px;font-weight:500;margin-bottom:6px;color:var(--td)}
.fg input,.fg textarea,.fg select{width:100%;padding:12px 16px;background:var(--s2);border:1px solid var(--b);border-radius:8px;color:var(--t);font-family:'JetBrains Mono',monospace;font-size:14px;transition:.2s;outline:none}
.fg input:focus,.fg textarea:focus{border-color:var(--a)} .fg textarea{min-height:100px;resize:vertical}
.fh{font-size:12px;color:var(--td);margin-top:4px}
.btn{padding:10px 24px;border-radius:8px;border:1px solid var(--b);background:var(--s2);color:var(--t);cursor:pointer;font-family:'Outfit',sans-serif;font-size:14px;font-weight:500;transition:.2s}
.btn:hover{border-color:var(--a);background:var(--s3)} .btn.pr{background:linear-gradient(135deg,var(--a),#b8845a);color:#0a0a0f;border:none;font-weight:600} .btn.pr:hover{opacity:.9}
.br{display:flex;gap:12px;margin-top:24px}
.ta{background:var(--s);border:1px solid var(--b);border-radius:var(--rad);padding:24px;margin-top:24px}
.ta h3{font-size:16px;margin-bottom:16px}
.tr{margin-top:16px;padding:16px;background:var(--s2);border-radius:8px;font-family:'JetBrains Mono',monospace;font-size:13px;line-height:1.6;white-space:pre-wrap;display:none}
.tr.vis{display:block}
.cw{background:var(--s);border:1px solid var(--b);border-radius:var(--rad);padding:24px;margin-bottom:28px}
.cw h3{font-size:15px;margin-bottom:16px}
.cb{display:flex;align-items:flex-end;gap:8px;height:120px;padding-bottom:24px}
.bar{flex:1;background:linear-gradient(to top,var(--a),#d4a57480);border-radius:4px 4px 0 0;min-height:4px;position:relative}
.bar-l{position:absolute;bottom:-22px;left:50%;transform:translateX(-50%);font-size:10px;color:var(--td);font-family:'JetBrains Mono',monospace;white-space:nowrap}
.bar-c{position:absolute;top:-20px;left:50%;transform:translateX(-50%);font-size:11px;color:var(--a);font-family:'JetBrains Mono',monospace}
.sb{background:linear-gradient(135deg,var(--s),var(--s2));border:1px solid var(--a);border-radius:var(--rad);padding:32px;margin-bottom:28px;text-align:center}
.sb h2{color:var(--a);margin-bottom:8px} .sb p{color:var(--td);margin-bottom:20px}
.ss{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:16px;margin-top:20px;text-align:left}
.sst{background:var(--s3);border-radius:8px;padding:16px;border:1px solid var(--b)}
.sst .sn{display:inline-block;width:24px;height:24px;background:var(--a);color:var(--bg);border-radius:50%;text-align:center;line-height:24px;font-size:12px;font-weight:700;margin-bottom:8px}
.sst h4{font-size:14px;margin-bottom:4px} .sst p{font-size:12px;color:var(--td)}
::-webkit-scrollbar{width:6px} ::-webkit-scrollbar-track{background:transparent} ::-webkit-scrollbar-thumb{background:var(--b);border-radius:3px}
@media(max-width:768px){.sh{padding:16px}.cg{grid-template-columns:1fr 1fr}header{flex-direction:column;gap:16px;align-items:flex-start}}
</style></head><body>
<div class="sh">
<header><div class="logo"><div class="logo-i">🌉</div><div><h1>Claude ↔ Telegram</h1><span>CLI Bridge Dashboard</span></div></div><div class="sp"><div class="sd" id="sd"></div><span id="st">Checking...</span></div></header>
<div class="tabs"><button class="tab act" onclick="sw('ov')">Overview</button><button class="tab" onclick="sw('se')">Sessions</button><button class="tab" onclick="sw('cf')">Settings</button><button class="tab" onclick="sw('te')">Test</button></div>

<div class="pn act" id="pn-ov"><div id="sB"></div>
<div class="cg"><div class="cd"><div class="cl">Total Messages</div><div class="cv" style="color:var(--a)" id="sM">—</div></div><div class="cd"><div class="cl">Active Sessions</div><div class="cv" style="color:var(--g)" id="sA">—</div></div><div class="cd"><div class="cl">All Sessions</div><div class="cv" style="color:var(--bl)" id="sS">—</div></div><div class="cd"><div class="cl">Avg Response</div><div class="cv" style="color:var(--p)" id="sR">—</div></div></div>
<div class="cw"><h3>7-Day Activity</h3><div class="cb" id="cB"><div style="color:var(--td);font-size:13px;display:flex;align-items:center;justify-content:center;width:100%">No data yet</div></div></div></div>

<div class="pn" id="pn-se"><div class="tw"><div class="th">Sessions</div><table><thead><tr><th>Session</th><th>Chat ID</th><th>Messages</th><th>Last Active</th><th>Status</th><th></th></tr></thead><tbody id="sT"><tr><td colspan="6" style="text-align:center;color:var(--td);padding:32px">Loading...</td></tr></tbody></table></div>
<div class="cv-wrap" id="cV"><div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px"><h3 id="cVt">Messages</h3><button class="btn" onclick="cC()" style="padding:6px 14px;font-size:12px">✕</button></div><div id="cMs"></div></div></div>

<div class="pn" id="pn-cf"><div style="display:grid;grid-template-columns:1fr 1fr;gap:24px">
<div><h3 style="margin-bottom:20px;font-size:16px">Telegram</h3>
<div class="fg"><label>Bot Token</label><input type="password" id="cT" placeholder="123456:ABC-DEF..."><div class="fh">From @BotFather</div></div>
<div class="fg"><label>Allowed User IDs</label><input id="cU" placeholder="123456789, 987654321"><div class="fh">Comma-separated. Empty = allow all</div></div>
<div class="fg"><label>Max Response Length</label><input type="number" id="cL" value="4096"></div></div>
<div><h3 style="margin-bottom:20px;font-size:16px">Claude CLI</h3>
<div class="fg"><label>CLI Path</label><input id="cP" placeholder="claude"></div>
<div class="fg"><label>Model</label><input id="cMo" placeholder="default"><div class="fh">e.g. claude-sonnet-4-5-20250929</div></div>
<div class="fg"><label>Allowed Tools</label><input id="cTo" placeholder="mcp__filesystem, computer"></div>
<div class="fg"><label>MCP Config Path</label><input id="cMc" placeholder="~/.claude/mcp.json"></div></div></div>
<div class="fg" style="margin-top:12px"><label>System Prompt</label><textarea id="cPr" placeholder="You are a helpful assistant..."></textarea></div>
<div class="br"><button class="btn pr" onclick="sC()">💾 Save</button><button class="btn" onclick="lC()">↺ Reset</button></div>
<div id="cMsg" style="margin-top:12px;font-size:13px;color:var(--g);display:none"></div></div>

<div class="pn" id="pn-te"><div class="ta"><h3>🧪 Test Connection</h3><p style="color:var(--td);font-size:14px;margin-bottom:16px">Send a test message to Claude CLI</p>
<div class="fg"><label>Test Message</label><input id="tM" value="Say 'Bridge test OK' in under 10 words."></div>
<button class="btn pr" onclick="rT()" id="tB">▶ Send</button><div class="tr" id="tR"></div></div>
<div class="ta"><h3>ℹ️ System</h3><div id="sI" style="font-family:'JetBrains Mono',monospace;font-size:13px;color:var(--td);line-height:2">Loading...</div></div></div>
</div>
<script>
const A=location.origin;
function sw(n){document.querySelectorAll('.tab').forEach(t=>t.classList.remove('act'));event.target.classList.add('act');document.querySelectorAll('.pn').forEach(p=>p.classList.remove('act'));document.getElementById('pn-'+n).classList.add('act');({ov:lS,se:lSe,cf:lC,te:lH})[n]?.()}
async function cH(){try{const r=await fetch(A+'/api/health'),d=await r.json(),dot=document.getElementById('sd'),t=document.getElementById('st');if(d.telegram_bot==='running'&&d.cli_available){dot.className='sd ok';t.textContent='Bot Running • CLI OK'}else if(d.cli_available){dot.className='sd ok';t.textContent='CLI OK • Bot '+d.telegram_bot}else{dot.className='sd err';t.textContent='CLI Not Found'}return d}catch{document.getElementById('sd').className='sd err';document.getElementById('st').textContent='Offline';return null}}
async function lS(){try{const r=await fetch(A+'/api/stats'),d=await r.json();document.getElementById('sM').textContent=d.total_messages.toLocaleString();document.getElementById('sA').textContent=d.active_sessions;document.getElementById('sS').textContent=d.total_sessions;document.getElementById('sR').textContent=d.avg_response_ms?d.avg_response_ms+'ms':'—';const c=document.getElementById('cB');if(d.daily_activity?.length){const mx=Math.max(...d.daily_activity.map(x=>x.count),1);c.innerHTML=d.daily_activity.map(x=>{const h=Math.max((x.count/mx)*100,4),dy=new Date(x.day).toLocaleDateString('en',{weekday:'short'});return`<div class="bar" style="height:${h}%"><span class="bar-c">${x.count}</span><span class="bar-l">${dy}</span></div>`}).join('')}const h=await cH(),b=document.getElementById('sB');if(!h||h.telegram_bot==='stopped')b.innerHTML=`<div class="sb"><h2>🚀 Get Started</h2><p>Configure your Telegram bot token in Settings</p><div class="ss"><div class="sst"><div class="sn">1</div><h4>Create Bot</h4><p>@BotFather → /newbot</p></div><div class="sst"><div class="sn">2</div><h4>Configure</h4><p>Paste token in Settings</p></div><div class="sst"><div class="sn">3</div><h4>Restart</h4><p>Restart server to activate</p></div></div></div>`;else b.innerHTML=''}catch(e){console.error(e)}}
async function lSe(){try{const r=await fetch(A+'/api/sessions'),s=await r.json(),tb=document.getElementById('sT');if(!s.length){tb.innerHTML='<tr><td colspan="6" style="text-align:center;color:var(--td);padding:32px">No sessions yet</td></tr>';return}tb.innerHTML=s.map(x=>`<tr><td><code style="color:var(--a)">${x.id}</code></td><td style="font-family:'JetBrains Mono',monospace;font-size:13px">${x.telegram_chat_id}</td><td>${x.message_count}</td><td style="font-size:13px;color:var(--td)">${new Date(x.last_active).toLocaleString()}</td><td><span class="bg ${x.is_active?'a':'e'}">${x.is_active?'active':'ended'}</span></td><td><button class="btn" style="padding:4px 12px;font-size:12px" onclick="vS('${x.id}')">View</button>${x.is_active?` <button class="btn" style="padding:4px 12px;font-size:12px" onclick="eS('${x.id}')">End</button>`:''}</td></tr>`).join('')}catch(e){console.error(e)}}
async function vS(id){try{const r=await fetch(A+'/api/sessions/'+id+'/messages'),m=await r.json(),v=document.getElementById('cV'),c=document.getElementById('cMs');document.getElementById('cVt').textContent='Session '+id;c.innerHTML=m.length?m.map(x=>`<div class="cm ${x.role[0]}m"><div class="rl ${x.role}">${x.role}</div><div class="bb">${esc(x.content)}</div><div class="ct">${new Date(x.timestamp).toLocaleString()}${x.response_time_ms?' • '+x.response_time_ms+'ms':''}</div></div>`).join(''):'<p style="color:var(--td)">Empty</p>';v.classList.add('open');v.scrollIntoView({behavior:'smooth'})}catch(e){console.error(e)}}
function cC(){document.getElementById('cV').classList.remove('open')}
async function eS(id){if(!confirm('End session '+id+'?'))return;await fetch(A+'/api/sessions/'+id,{method:'DELETE'});lSe()}
async function lC(){try{const r=await fetch(A+'/api/config'),c=await r.json();document.getElementById('cT').value=c.telegram_token||'';document.getElementById('cU').value=(c.allowed_user_ids||[]).join(', ');document.getElementById('cL').value=c.max_response_length||4096;document.getElementById('cP').value=c.claude_cli_path||'claude';document.getElementById('cMo').value=c.claude_model||'';document.getElementById('cTo').value=c.allowed_tools||'';document.getElementById('cMc').value=c.mcp_config||'';document.getElementById('cPr').value=c.system_prompt||''}catch(e){console.error(e)}}
async function sC(){const tk=document.getElementById('cT').value.trim(),b={allowed_user_ids:document.getElementById('cU').value.split(',').map(s=>parseInt(s.trim())).filter(n=>!isNaN(n)),max_response_length:parseInt(document.getElementById('cL').value)||4096,claude_cli_path:document.getElementById('cP').value.trim()||'claude',claude_model:document.getElementById('cMo').value.trim(),allowed_tools:document.getElementById('cTo').value.trim(),mcp_config:document.getElementById('cMc').value.trim(),system_prompt:document.getElementById('cPr').value};if(tk&&!tk.includes('...'))b.telegram_token=tk;try{const r=await fetch(A+'/api/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)}),d=await r.json(),m=document.getElementById('cMsg');m.textContent='✓ '+d.message;m.style.display='block';setTimeout(()=>m.style.display='none',4000)}catch{alert('Save error')}}
async function rT(){const b=document.getElementById('tB'),r=document.getElementById('tR');b.textContent='⏳ Testing...';b.disabled=true;r.classList.remove('vis');try{const res=await fetch(A+'/api/test',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({message:document.getElementById('tM').value})}),d=await res.json();r.textContent=`Response (${d.elapsed_ms}ms):\n\n${d.response}`;r.classList.add('vis')}catch(e){r.textContent='Error: '+e.message;r.classList.add('vis')}b.textContent='▶ Send';b.disabled=false}
async function lH(){const h=await cH(),e=document.getElementById('sI');if(h)e.innerHTML=`Telegram: <b style="color:${h.telegram_bot==='running'?'var(--g)':'var(--r)'}">${h.telegram_bot}</b><br>Claude CLI: <b style="color:${h.cli_available?'var(--g)':'var(--r)'}">${h.claude_cli}</b><br>Server: <b style="color:var(--g)">online</b>`;else e.textContent='Offline'}
function esc(s){const d=document.createElement('div');d.textContent=s;return d.innerHTML}
cH();lS();setInterval(cH,15000);
</script></body></html>
DASHEOF
}

# ── Final Summary ──
show_done() {
  step "④ Ready!"
  echo ""
  echo -e "  ${GREEN}${BOLD}Installation complete!${RESET}"
  echo ""
  echo -e "  ${BOLD}Commands:${RESET}"
  echo -e "    ${CYAN}claude-telegram start${RESET}         Start (foreground)"
  echo -e "    ${CYAN}claude-telegram bg${RESET}            Start in background"
  echo -e "    ${CYAN}claude-telegram status${RESET}        Check status"
  echo -e "    ${CYAN}claude-telegram stop${RESET}          Stop"
  echo -e "    ${CYAN}claude-telegram autostart${RESET}     Auto-start on login (macOS)"
  echo -e "    ${CYAN}claude-telegram config${RESET}        Edit config"
  echo -e "    ${CYAN}claude-telegram logs${RESET}          View logs"
  echo -e "    ${CYAN}claude-telegram uninstall${RESET}     Remove everything"
  echo ""
  echo -e "  ${BOLD}Dashboard:${RESET} ${CYAN}http://localhost:7860${RESET}"
  echo ""

  if [ -n "$BOT_TOKEN" ]; then
    ask "Start the bridge now? (Y/n) "
    read -r START_NOW
    if [[ ! "$START_NOW" =~ ^[Nn]$ ]]; then
      echo ""
      exec "$INSTALL_DIR/claude-telegram" start
    fi
  else
    echo -e "  ${YELLOW}→ Add your bot token first:${RESET}"
    echo -e "    claude-telegram config"
    echo -e "    ${DIM}Then run: claude-telegram start${RESET}"
  fi
  echo ""
}

# ── Main ──
main() {
  print_banner
  check_prerequisites
  setup_telegram
  install_bridge
  show_done
}

main
