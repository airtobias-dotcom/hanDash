#!/bin/bash
set -e

REPO_URL="https://github.com/airtobias-dotcom/hanDash.git"
BRANCH="master"
POLL_INTERVAL=60  # seconds

echo "=== hanDash Auto-Deploy Setup ==="
echo ""

# --- 1. Find or create repo clone ---
REPO_DIR=""

# Search common locations
for candidate in /home/*/hanDash /var/www/hanDash /opt/hanDash /srv/hanDash; do
  if [ -d "$candidate/.git" ]; then
    REPO_DIR="$candidate"
    break
  fi
done

if [ -z "$REPO_DIR" ]; then
  REPO_DIR="/opt/hanDash"
  echo "Kein vorhandener Clone gefunden. Klone nach $REPO_DIR ..."
  git clone "$REPO_URL" "$REPO_DIR"
else
  echo "Repo gefunden: $REPO_DIR"
fi

# --- 2. Find web root for /dashboard ---
WEB_ROOT=""

# Try nginx
if command -v nginx &>/dev/null; then
  WEB_ROOT=$(nginx -T 2>/dev/null | grep -A5 "location.*dashboard\|alias.*dashboard\|root.*" \
    | grep -E "root|alias" | head -1 | awk '{print $2}' | tr -d ';')
fi

# Try apache
if [ -z "$WEB_ROOT" ] && command -v apache2ctl &>/dev/null; then
  WEB_ROOT=$(apache2ctl -S 2>/dev/null | grep DocumentRoot | head -1 | awk '{print $2}')
fi

# Check if index.html is served directly from repo (symlink or same path)
if [ -z "$WEB_ROOT" ]; then
  # Try to find dashboard index.html via common web roots
  for candidate in /var/www/html /var/www/html/dashboard /srv/http /usr/share/nginx/html; do
    if [ -f "$candidate/index.html" ] || [ -d "$candidate" ]; then
      WEB_ROOT="$candidate"
      break
    fi
  done
fi

if [ -z "$WEB_ROOT" ]; then
  WEB_ROOT="$REPO_DIR"
  echo "Web-Root nicht erkannt – nehme Repo-Verzeichnis direkt."
else
  echo "Web-Root gefunden: $WEB_ROOT"
fi

# --- 3. Write deploy script ---
DEPLOY_SCRIPT="/usr/local/bin/handash-deploy"

cat > "$DEPLOY_SCRIPT" <<DEPLOY
#!/bin/bash
REPO_DIR="$REPO_DIR"
WEB_ROOT="$WEB_ROOT"
BRANCH="$BRANCH"
LOGFILE="/var/log/handash-deploy.log"

cd "\$REPO_DIR"

CURRENT=\$(git rev-parse HEAD 2>/dev/null)
git fetch origin "\$BRANCH" --quiet 2>>\$LOGFILE
REMOTE=\$(git rev-parse "origin/\$BRANCH" 2>/dev/null)

if [ "\$CURRENT" != "\$REMOTE" ]; then
  echo "\$(date '+%Y-%m-%d %H:%M:%S') Neuer Commit \${REMOTE:0:7} – deploye..." >> \$LOGFILE
  git pull origin "\$BRANCH" --quiet >> \$LOGFILE 2>&1

  # Copy if web root differs from repo
  if [ "\$WEB_ROOT" != "\$REPO_DIR" ]; then
    cp "\$REPO_DIR/index.html" "\$WEB_ROOT/index.html"
    echo "\$(date '+%Y-%m-%d %H:%M:%S') index.html nach \$WEB_ROOT kopiert." >> \$LOGFILE
  fi

  # Reload web server if running
  if systemctl is-active --quiet nginx;   then systemctl reload nginx   >> \$LOGFILE 2>&1; fi
  if systemctl is-active --quiet apache2; then systemctl reload apache2 >> \$LOGFILE 2>&1; fi
  echo "\$(date '+%Y-%m-%d %H:%M:%S') Deploy abgeschlossen." >> \$LOGFILE
fi
DEPLOY

chmod +x "$DEPLOY_SCRIPT"
echo "Deploy-Script erstellt: $DEPLOY_SCRIPT"

# --- 4. Set up cron job ---
CRON_LINE="* * * * * $DEPLOY_SCRIPT"
CRON_JOB="*/$((POLL_INTERVAL / 60)) * * * * $DEPLOY_SCRIPT"

# Use every-minute cron if interval < 120s
if [ "$POLL_INTERVAL" -lt 120 ]; then
  CRON_JOB="* * * * * $DEPLOY_SCRIPT"
fi

(crontab -l 2>/dev/null | grep -v "handash-deploy"; echo "$CRON_JOB") | crontab -
echo "Cron-Job eingerichtet: jede Minute wird auf neue Commits geprüft."

# --- 5. First deploy now ---
echo ""
echo "Führe ersten Deploy durch..."
"$DEPLOY_SCRIPT"

echo ""
echo "=== Setup abgeschlossen ==="
echo "Logs: tail -f /var/log/handash-deploy.log"
echo "Jeder Push auf GitHub wird innerhalb von ~60 Sekunden live."
