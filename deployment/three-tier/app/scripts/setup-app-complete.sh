#!/usr/bin/env bash
# One-time application EC2 setup. Run from the cloned repository with sudo.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run with sudo: sudo bash deployment/three-tier/app/scripts/setup-app-complete.sh" >&2
  exit 1
fi

repo_dir=$(cd "$(dirname "$0")/../../../.." && pwd)
rds_ca=/etc/ssl/certs/rds-global-bundle.pem
app_root=/srv/spx-app

ask() {
  local prompt=$1 default=${2:-} value
  if [[ -n $default ]]; then
    read -r -p "$prompt [$default]: " value
    printf '%s' "${value:-$default}"
  else
    read -r -p "$prompt: " value
    printf '%s' "$value"
  fi
}

ask_secret() {
  local prompt=$1 value
  read -r -s -p "$prompt: " value
  # Write the visual line break to stderr so command substitution captures only
  # the password itself, without a leading newline.
  echo >&2
  printf '%s' "$value"
}

escape_env() {
  local value=${1//$'\n'/}
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '%s' "$value"
}

echo "SPX Banking application EC2 setup"
echo "This script will prompt for credentials but will not print them."
rds_endpoint=$(ask "RDS endpoint (for example, database.xxxxxx.us-east-1.rds.amazonaws.com)")
rds_master_user=$(ask "RDS master username" "admin")
rds_master_password=$(ask_secret "RDS master password")
smtp_server=$(ask "SMTP server" "smtp.hostinger.com")
smtp_port=$(ask "SMTP port" "465")
smtp_user=$(ask "SMTP mailbox username")
smtp_password=$(ask_secret "SMTP mailbox password")
admin_email=$(ask "Application admin email")
admin_password=$(ask_secret "New application admin password")
admin_name=$(ask "Application admin display name" "Bank Administrator")

[[ -n $rds_endpoint && -n $rds_master_password && -n $smtp_user && -n $smtp_password && -n $admin_email && -n $admin_password ]] || {
  echo "All required values must be supplied." >&2
  exit 1
}

app_db_user=spxapp
app_db_name=spxbank
app_db_password=$(openssl rand -hex 24)
secret_key=$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')

apt-get update
apt-get install -y python3 python3-venv python3-pip mysql-client awscli curl ca-certificates

id -u spxapp >/dev/null 2>&1 || useradd --system --home "$app_root" --shell /usr/sbin/nologin spxapp
install -d -o spxapp -g spxapp -m 0755 "$app_root/releases"
install -d -o root -g root -m 0750 /etc/spx-banking

curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o "$rds_ca"
chmod 0644 "$rds_ca"

echo "Testing the RDS master connection..."
mysql --host="$rds_endpoint" --port=3306 --user="$rds_master_user" --password="$rds_master_password" --ssl-ca="$rds_ca" -e 'SELECT 1;'

echo "Creating the SPX database tables..."
mysql --host="$rds_endpoint" --port=3306 --user="$rds_master_user" --password="$rds_master_password" --ssl-ca="$rds_ca" < "$repo_dir/database/setup_db.sql"

echo "Creating the limited application database user..."
mysql --host="$rds_endpoint" --port=3306 --user="$rds_master_user" --password="$rds_master_password" --ssl-ca="$rds_ca" -e \
  "CREATE USER IF NOT EXISTS '${app_db_user}'@'%' IDENTIFIED BY '${app_db_password}'; ALTER USER '${app_db_user}'@'%' IDENTIFIED BY '${app_db_password}'; GRANT SELECT, INSERT, UPDATE, DELETE ON ${app_db_name}.* TO '${app_db_user}'@'%'; FLUSH PRIVILEGES;"

umask 077
{
  printf 'SMTP_SERVER="%s"\n' "$(escape_env "$smtp_server")"
  printf 'SMTP_PORT="%s"\n' "$(escape_env "$smtp_port")"
  printf 'SMTP_USER="%s"\n' "$(escape_env "$smtp_user")"
  printf 'SMTP_PASS="%s"\n\n' "$(escape_env "$smtp_password")"
  printf 'DB_HOST="%s"\n' "$(escape_env "$rds_endpoint")"
  printf 'DB_PORT="3306"\n'
  printf 'DB_USER="%s"\n' "$app_db_user"
  printf 'DB_PASS="%s"\n' "$app_db_password"
  printf 'DB_NAME="%s"\n' "$app_db_name"
  printf 'DB_SSL_CA="%s"\n' "$rds_ca"
  printf 'DB_SSL_VERIFY_CERT="true"\n'
  printf 'DB_SSL_VERIFY_IDENTITY="true"\n\n'
  printf 'SECRET_KEY="%s"\n' "$secret_key"
  printf 'ADMIN_EMAIL="%s"\n' "$(escape_env "$admin_email")"
  printf 'ADMIN_PASSWORD="%s"\n' "$(escape_env "$admin_password")"
  printf 'ADMIN_NAME="%s"\n' "$(escape_env "$admin_name")"
} > /etc/spx-banking.env
chown root:spxapp /etc/spx-banking.env
chmod 0640 /etc/spx-banking.env

install -o root -g root -m 0755 "$repo_dir/deployment/three-tier/app/scripts/spx-app-deploy" /usr/local/sbin/spx-app-deploy
install -o root -g root -m 0644 "$repo_dir/deployment/three-tier/app/systemd/spx-banking.service" /etc/systemd/system/spx-banking.service

release="$app_root/releases/initial-$(date +%Y%m%d%H%M%S)"
install -d -o spxapp -g spxapp -m 0755 "$release"
tar -C "$repo_dir" --exclude-vcs --exclude='.env' --exclude='__pycache__' -cf - . | tar -C "$release" -xf -
python3 -m venv "$app_root/venv"
"$app_root/venv/bin/pip" install --disable-pip-version-check --upgrade pip
"$app_root/venv/bin/pip" install --disable-pip-version-check -r "$release/requirements.txt"
chown -R spxapp:spxapp "$release" "$app_root/venv"
ln -sfn "$release" "$app_root/current"

systemctl daemon-reload
systemctl enable --now spx-banking.service

for _ in {1..20}; do
  curl --fail --silent http://127.0.0.1:5000/ >/dev/null && break
  sleep 1
done
curl --fail --silent http://127.0.0.1:5000/ >/dev/null

unset rds_master_password smtp_password admin_password app_db_password secret_key
echo "Application EC2 setup complete. Gunicorn is listening on port 5000."

