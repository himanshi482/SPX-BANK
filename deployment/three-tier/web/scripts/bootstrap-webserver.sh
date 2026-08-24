#!/usr/bin/env bash
# Run once as root on the web EC2 instance.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

domain=${1:?Usage: sudo ./bootstrap-webserver.sh <domain> <app-private-ip-or-dns>}
app_upstream=${2:?Usage: sudo ./bootstrap-webserver.sh <domain> <app-private-ip-or-dns>}
source_dir=$(cd "$(dirname "$0")/.." && pwd)

apt-get update
apt-get install -y nginx awscli curl

install -d -o ubuntu -g www-data -m 0755 /srv/spx-web/releases
install -o root -g root -m 0755 "$source_dir/scripts/spx-web-deploy" /usr/local/sbin/spx-web-deploy

sed \
  -e "s|__DOMAIN__|${domain}|g" \
  -e "s|__APP_SERVER_PRIVATE_IP__|${app_upstream}|g" \
  "$source_dir/nginx/spx-banking.conf.template" > /etc/nginx/sites-available/spx-banking

ln -sfn /etc/nginx/sites-available/spx-banking /etc/nginx/sites-enabled/spx-banking
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx

echo "Web server bootstrap complete. The GitHub Actions workflow can now deploy to this instance through SSM."
