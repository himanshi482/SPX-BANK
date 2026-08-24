#!/usr/bin/env bash
# One-time web EC2 setup. Run from the cloned repository with sudo.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run with sudo." >&2
  exit 1
fi

domain=${1:?Usage: sudo bash setup-web-complete.sh <domain> <application-private-ip-or-dns>}
app_upstream=${2:?Usage: sudo bash setup-web-complete.sh <domain> <application-private-ip-or-dns>}
repo_dir=$(cd "$(dirname "$0")/../../../.." && pwd)
web_root=/srv/spx-web

apt-get update
apt-get install -y nginx awscli curl

echo "Checking connectivity to the application EC2..."
curl --fail --silent --connect-timeout 5 "http://${app_upstream}:5000/" >/dev/null

install -d -o ubuntu -g www-data -m 0755 "$web_root/releases"
install -o root -g root -m 0755 "$repo_dir/deployment/three-tier/web/scripts/spx-web-deploy" /usr/local/sbin/spx-web-deploy

sed \
  -e "s|__DOMAIN__|${domain}|g" \
  -e "s|__APP_SERVER_PRIVATE_IP__|${app_upstream}|g" \
  "$repo_dir/deployment/three-tier/web/nginx/spx-banking.conf.template" > /etc/nginx/sites-available/spx-banking

release="$web_root/releases/initial-$(date +%Y%m%d%H%M%S)"
install -d -o ubuntu -g www-data -m 0755 "$release"
tar -C "$repo_dir" --exclude-vcs --exclude='.env' --exclude='__pycache__' -cf - . | tar -C "$release" -xf -
chown -R ubuntu:www-data "$release"
ln -sfn "$release" "$web_root/current"

ln -sfn /etc/nginx/sites-available/spx-banking /etc/nginx/sites-enabled/spx-banking
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx
if systemctl is-active --quiet nginx; then
  systemctl reload nginx
else
  systemctl start nginx
fi

echo "Web EC2 setup complete. Open http://${domain} after DNS points to this web EC2 public IP."

