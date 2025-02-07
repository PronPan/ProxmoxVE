#!/usr/bin/env bash

echo "[INFO] Sourcing external functions..."
source <(curl -s https://raw.githubusercontent.com/PronPan/ProxmoxVE/main/misc/build.func)

echo "[INFO] Script Metadata - Author: tteck (tteckster), License: MIT"
echo "[INFO] App Source: https://nginxproxymanager.com/"

# App Default Values
APP="Nginx Proxy Manager"
var_tags="proxy"
var_cpu="2"
var_ram="1024"
var_disk="4"
var_os="debian"
var_version="12"
var_unprivileged="1"

echo "[INFO] Default Values Set - APP: $APP, CPU: $var_cpu, RAM: $var_ram MB, Disk: $var_disk GB, OS: $var_os $var_version, Unprivileged: $var_unprivileged"

# App Output & Base Settings
echo "[INFO] Running header_info for $APP..."
header_info "$APP"

echo "[INFO] Running base_settings..."
base_settings

# Core 
echo "[INFO] Initializing core components..."
variables
color
catch_errors

function update_script() {
  echo "[INFO] Starting script update process..."

  header_info
  check_container_storage
  check_container_resources

  echo "[INFO] Checking for existing $APP installation..."
  if [[ ! -f /lib/systemd/system/npm.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  echo "[INFO] Fetching latest release info from GitHub API..."
  RELEASE=$(curl -s https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  echo "[INFO] Latest release version: $RELEASE"

  msg_info "Stopping Services"
  echo "[INFO] Stopping openresty and npm services..."
  systemctl stop openresty
  systemctl stop npm
  msg_ok "Stopped Services"

  msg_info "Cleaning Old Files"
  echo "[INFO] Removing old application files..."
  rm -rf /app /var/www/html /etc/nginx /var/log/nginx /var/lib/nginx /var/cache/nginx &>/dev/null
  msg_ok "Cleaned Old Files"

  msg_info "Downloading NPM v${RELEASE}"
  echo "[INFO] Downloading NPM version $RELEASE from GitHub..."
  wget -q https://codeload.github.com/NginxProxyManager/nginx-proxy-manager/tar.gz/v${RELEASE} -O - | tar -xz &>/dev/null
  cd nginx-proxy-manager-${RELEASE}
  msg_ok "Downloaded NPM v${RELEASE}"

  msg_info "Setting up Environment"
  echo "[INFO] Setting up environment links and configurations..."
  ln -sf /usr/bin/python3 /usr/bin/python
  ln -sf /usr/bin/certbot /opt/certbot/bin/certbot
  ln -sf /usr/local/openresty/nginx/sbin/nginx /usr/sbin/nginx
  ln -sf /usr/local/openresty/nginx/ /etc/nginx

  echo "[INFO] Updating version information in package.json files..."
  sed -i "s|\"version\": \"0.0.0\"|\"version\": \"$RELEASE\"|" backend/package.json
  sed -i "s|\"version\": \"0.0.0\"|\"version\": \"$RELEASE\"|" frontend/package.json
  sed -i 's|"fork-me": ".*"|"fork-me": "Proxmox VE Helper-Scripts"|' frontend/js/i18n/messages.json
  sed -i "s|https://github.com.*source=nginx-proxy-manager|https://helper-scripts.com|g" frontend/js/app/ui/footer/main.ejs
  sed -i 's+^daemon+#daemon+g' docker/rootfs/etc/nginx/nginx.conf

  echo "[INFO] Adjusting nginx configuration file paths..."
  NGINX_CONFS=$(find "$(pwd)" -type f -name "*.conf")
  for NGINX_CONF in $NGINX_CONFS; do
    echo "[INFO] Updating $NGINX_CONF..."
    sed -i 's+include conf.d+include /etc/nginx/conf.d+g' "$NGINX_CONF"
  done

  echo "[INFO] Creating necessary directories and copying files..."
  mkdir -p /var/www/html /etc/nginx/logs
  cp -r docker/rootfs/var/www/html/* /var/www/html/
  cp -r docker/rootfs/etc/nginx/* /etc/nginx/
  cp docker/rootfs/etc/letsencrypt.ini /etc/letsencrypt.ini
  cp docker/rootfs/etc/logrotate.d/nginx-proxy-manager /etc/logrotate.d/nginx-proxy-manager
  ln -sf /etc/nginx/nginx.conf /etc/nginx/conf/nginx.conf
  rm -f /etc/nginx/conf.d/dev.conf

  echo "[INFO] Setting up nginx temporary and data directories..."
  mkdir -p /tmp/nginx/body /run/nginx /data/nginx /data/custom_ssl /data/logs /data/access /data/nginx/default_host /data/nginx/default_www /data/nginx/proxy_host /data/nginx/redirection_host /data/nginx/stream /data/nginx/dead_host /data/nginx/temp /var/lib/nginx/cache/public /var/lib/nginx/cache/private /var/cache/nginx/proxy_temp
  chmod -R 777 /var/cache/nginx
  chown root /tmp/nginx

  echo "[INFO] Configuring resolvers for nginx..."
  echo resolver "$(awk 'BEGIN{ORS=" "} $1=="nameserver" {print ($2 ~ ":")? "["$2"]": $2}' /etc/resolv.conf);" >/etc/nginx/conf.d/include/resolvers.conf

  echo "[INFO] Generating dummy SSL certificates if not found..."
  if [ ! -f /data/nginx/dummycert.pem ] || [ ! -f /data/nginx/dummykey.pem ]; then
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -subj "/O=Nginx Proxy Manager/OU=Dummy Certificate/CN=localhost" -keyout /data/nginx/dummykey.pem -out /data/nginx/dummycert.pem &>/dev/null
  fi

  echo "[INFO] Preparing application directories..."
  mkdir -p /app/global /app/frontend/images
  cp -r backend/* /app
  cp -r global/* /app/global

  echo "[INFO] Checking and installing certbot-dns-cloudflare if missing..."
  if ! python3 -m pip show certbot-dns-cloudflare &>/dev/null; then
    python3 -m pip install --no-cache-dir certbot-dns-cloudflare --break-system-packages &>/dev/null
  fi
  msg_ok "Setup Environment"

  msg_info "Building Frontend"
  echo "[INFO] Installing and building frontend assets..."
  cd ./frontend
  pnpm install &>/dev/null
  pnpm upgrade &>/dev/null
  pnpm run build &>/dev/null
  cp -r dist/* /app/frontend
  cp -r app-images/* /app/frontend/images
  msg_ok "Built Frontend"

  msg_info "Initializing Backend"
  echo "[INFO] Configuring backend settings..."
  rm -rf /app/config/default.json &>/dev/null
  if [ ! -f /app/config/production.json ]; then
    echo "[INFO] Creating production.json configuration file..."
    cat <<'EOF' >/app/config/production.json
{
  "database": {
    "engine": "knex-native",
    "knex": {
      "client": "sqlite3",
      "connection": {
        "filename": "/data/database.sqlite"
      }
    }
  }
}
EOF
  fi

  echo "[INFO] Installing backend dependencies..."
  cd /app
  pnpm install &>/dev/null
  msg_ok "Initialized Backend"

  msg_info "Starting Services"
  echo "[INFO] Adjusting service configurations and starting services..."
  sed -i 's/user npm/user root/g; s/^pid/#pid/g' /usr/local/openresty/nginx/conf/nginx.conf
  sed -i 's/su npm npm/su root root/g' /etc/logrotate.d/nginx-proxy-manager
  sed -i 's/include-system-site-packages = false/include-system-site-packages = true/g' /opt/certbot/pyvenv.cfg
  systemctl enable -q --now openresty
  systemctl enable -q --now npm
  msg_ok "Started Services"

  msg_info "Cleaning up"
  echo "[INFO] Removing temporary files..."
  rm -rf ~/nginx-proxy-manager-*
  msg_ok "Cleaned"

  msg_ok "Updated Successfully"
  exit
}

echo "[INFO] Starting initial container build process..."
start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:81${CL}"
