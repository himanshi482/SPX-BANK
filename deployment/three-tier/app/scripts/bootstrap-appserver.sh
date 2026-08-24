#!/usr/bin/env bash
# Run once as root on the application EC2 instance.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

source_dir=$(cd "$(dirname "$0")/.." && pwd)

apt-get update
apt-get install -y python3 python3-venv python3-pip awscli curl ca-certificates

id -u spxapp >/dev/null 2>&1 || useradd --system --home /srv/spx-app --shell /usr/sbin/nologin spxapp
install -d -o spxapp -g spxapp -m 0755 /srv/spx-app/releases
install -d -o root -g root -m 0750 /etc/spx-banking

curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
  -o /etc/ssl/certs/rds-global-bundle.pem
chmod 0644 /etc/ssl/certs/rds-global-bundle.pem

install -o root -g root -m 0755 "$source_dir/scripts/spx-app-deploy" /usr/local/sbin/spx-app-deploy
install -o root -g root -m 0644 "$source_dir/systemd/spx-banking.service" /etc/systemd/system/spx-banking.service
systemctl daemon-reload
systemctl enable spx-banking.service

if [[ ! -f /etc/spx-banking.env ]]; then
  install -o root -g spxapp -m 0640 "$source_dir/spx-banking.env.example" /etc/spx-banking.env
  echo "Created /etc/spx-banking.env. Edit it with the RDS endpoint and real credentials before deploying."
fi

echo "Application server bootstrap complete."
