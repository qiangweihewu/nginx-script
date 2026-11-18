#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# Nginx 官方源安全加固版一键安装脚本 (含 Certbot 自动签发与续期)
# 用法 1 (交互式):
#   curl -fsSL https://raw.githubusercontent.com/qiangweihewu/nginx-script/main/install.sh -o /tmp/install.sh && sudo bash /tmp/install.sh
# 用法 2 (无交互传参):
#   sudo bash install.sh your.domain.com [mainline|stable] [certbot|custom|skip] [email]
# ==========================================

DOMAIN="${1:-}"
BRANCH="${2:-mainline}"
CERT_MODE="${3:-}"     # 可选: certbot (申请新证书) | custom (使用自备证书) | skip (忽略)
CERT_EMAIL="${4:-}"    # 可选: 申请证书使用的邮箱，不填则在交互时询问或使用 --register-unsafely-without-email

# 1. 权限检测
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 错误: 请使用 root 用户或通过 sudo 运行此脚本。"
    exit 1
fi

# 2. 获取并校验域名
while true; do
    if [ -z "$DOMAIN" ]; then
        read -r -p "👉 请输入要配置的域名 (例如 admin.clearsolitaire.com): " DOMAIN
    fi
    DOMAIN="$(echo "$DOMAIN" | xargs)"
    if [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]; then
        break
    else
        echo "⚠️ 域名格式不合法或为空，请重新输入！"
        DOMAIN=""
    fi
done

# 3. 询问 SSL 证书处理方式
if [ -z "$CERT_MODE" ]; then
    echo "------------------------------------------"
    echo "请选择 SSL 证书配置方式："
    echo "  1) 使用 Certbot 自动申请 Let's Encrypt 证书 (standalone 模式 + 自动配置定时续期)"
    echo "  2) 使用自用/已有证书 (手动放入 /etc/letsencrypt/live/${DOMAIN}/ 或自定义路径)"
    echo "  3) 暂时忽略 (仅写入配置，稍后自行处理证书)"
    read -r -p "👉 请输入选项编号 [1/2/3，默认 1]: " CERT_CHOICE
    case "${CERT_CHOICE:-1}" in
        1) CERT_MODE="certbot" ;;
        2) CERT_MODE="custom" ;;
        3) CERT_MODE="skip" ;;
        *) echo "⚠️ 输入无效，默认选择 3 (暂时忽略)"; CERT_MODE="skip" ;;
    esac
fi

echo "✅ 目标域名: ${DOMAIN} | 分支: ${BRANCH} | 证书模式: ${CERT_MODE}"

# 4. 系统类型与版本代号检测
if [ ! -f /etc/os-release ]; then
    echo "❌ 错误: 无法读取 /etc/os-release，不支持当前操作系统。"
    exit 1
fi

. /etc/os-release
OS_ID="${ID}"
OS_CODENAME="${VERSION_CODENAME:-}"

if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    echo "❌ 错误: 本脚本仅支持 Ubuntu 或 Debian，当前系统为: $OS_ID"
    exit 1
fi

# 5. 安装前置依赖
echo "📦 [1/7] 正在更新索引并安装前置依赖..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

KEYRING_PKG="debian-archive-keyring"
[ "$OS_ID" = "ubuntu" ] && KEYRING_PKG="ubuntu-keyring"

apt-get install -y -qq curl gnupg2 ca-certificates lsb-release cron "$KEYRING_PKG"

if [ -z "$OS_CODENAME" ]; then
    OS_CODENAME="$(lsb_release -cs 2>/dev/null || true)"
fi

if [ -z "$OS_CODENAME" ]; then
    echo "❌ 错误: 无法识别当前系统的版本代号 (Codename)。"
    exit 1
fi

echo "✅ 检测到系统: ${PRETTY_NAME} (${OS_ID} / ${OS_CODENAME})"

# 6. 检测并清理系统自带的旧版冲突包
if dpkg -l | grep -E '^ii\s+(nginx-common|nginx-core|nginx-full|nginx-light|nginx-extras)\s' >/dev/null 2>&1; then
    echo "🧹 检测到系统自带源安装的旧版 Nginx 组件，正在移除以避免冲突..."
    systemctl stop nginx 2>/dev/null || true
    apt-get remove -y nginx nginx-common nginx-core nginx-full nginx-light nginx-extras 2>/dev/null || true
fi

# 7. 下载、校验并导入 Nginx 官方 GPG 密钥
echo "🔑 [2/7] 正在下载并校验 Nginx 官方 GPG 密钥..."
TMP_KEY="$(mktemp)"
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor --yes -o "$TMP_KEY"

KEY_FPR="$(gpg --show-keys --with-colons "$TMP_KEY" 2>/dev/null | awk -F: '/^fpr:/ {print $10}')"
EXPECTED_FPR="573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62|8540A6F18833A80E9C1653A42FD21310B49F6B46|9E9BE90EACBCDE69FE9B204CBCDCD8A38D88A2B3"

if ! echo "$KEY_FPR" | grep -Eq "$EXPECTED_FPR"; then
    rm -f "$TMP_KEY"
    echo "❌ 错误: GPG 密钥指纹校验失败！实际指纹: $KEY_FPR"
    exit 1
fi

mv "$TMP_KEY" /usr/share/keyrings/nginx-archive-keyring.gpg
chmod 644 /usr/share/keyrings/nginx-archive-keyring.gpg
echo "✅ GPG 密钥指纹校验通过！"

# 8. 配置 HTTPS 官方源与高优先级
echo "📝 [3/7] 正在配置 Nginx 官方 HTTPS 软件源..."
[ -f /etc/apt/sources.list.d/nginx.list ] && cp /etc/apt/sources.list.d/nginx.list /etc/apt/sources.list.d/nginx.list.bak
[ -f /etc/apt/preferences.d/99nginx ] && cp /etc/apt/preferences.d/99nginx /etc/apt/preferences.d/99nginx.bak

if [ "$BRANCH" = "stable" ]; then
    REPO_URL="https://nginx.org/packages/${OS_ID}"
else
    REPO_URL="https://nginx.org/packages/mainline/${OS_ID}"
fi

echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] ${REPO_URL} ${OS_CODENAME} nginx" > /etc/apt/sources.list.d/nginx.list

cat << 'EOF' > /etc/apt/preferences.d/99nginx
Package: *
Pin: origin nginx.org
Pin: release o=nginx
Pin-Priority: 900
EOF

# 9. 安装最新 Nginx
echo "🚀 [4/7] 正在从官方源安装最新 Nginx..."
apt-get update -qq
apt-get install -y nginx

# 10. 启动默认 Nginx，按需检测并修复 PID 竞态警告
echo "🔍 [5/7] 正在启动服务并检测 Systemd PID 竞态警告..."
systemctl enable nginx >/dev/null 2>&1
systemctl restart nginx

if journalctl -u nginx -n 15 --no-pager | grep -q "Can't open PID file"; then
    echo "⚠️ 检测到 Systemd PID 竞态警告，正在自动写入 Override 修复..."
    mkdir -p /etc/systemd/system/nginx.service.d
    cat << 'EOF' > /etc/systemd/system/nginx.service.d/override.conf
[Service]
ExecStartPost=/bin/sleep 0.1
EOF
    systemctl daemon-reload
    systemctl restart nginx
    echo "✅ PID 警告已成功修复并消除！"
else
    echo "✅ 启动正常，未触发 PID 竞态警告。"
fi

# 11. 根据用户选择处理 SSL 证书
echo "🔐 [6/7] 正在处理 SSL 证书 (${CERT_MODE})..."
CERT_FILE="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
KEY_FILE="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

if [ "$CERT_MODE" = "certbot" ]; then
    echo "📦 正在安装 certbot..."
    apt-get install -y certbot

    # 询问邮箱（用于证书到期提醒，可直接回车跳过）
    if [ -z "$CERT_EMAIL" ] && [ -t 0 ]; then
        read -r -p "👉 请输入用于接收证书到期通知的邮箱 (直接回车则跳过邮箱注册): " CERT_EMAIL
        CERT_EMAIL="$(echo "$CERT_EMAIL" | xargs)"
    fi

    if [ -n "$CERT_EMAIL" ]; then
        EMAIL_ARG="-m ${CERT_EMAIL}"
    else
        EMAIL_ARG="--register-unsafely-without-email"
    fi

    echo "🛑 正在临时停止 Nginx 以释放 80 端口供 Certbot standalone 验证..."
    systemctl stop nginx

    echo "🌐 正在通过 Certbot standalone 模式为 ${DOMAIN} 申请证书..."
    # shellcheck disable=SC2086
    if certbot certonly --standalone -d "${DOMAIN}" --non-interactive --agree-tos ${EMAIL_ARG}; then
        echo "✅ Certbot 证书申请成功！"

        # 配置 root 用户的定时续期任务 (保留原有 crontab，避免覆盖清空)
        CRON_JOB='15 2 * * * certbot renew --pre-hook "systemctl stop nginx" --post-hook "systemctl start nginx"'
        CRON_TMP="$(mktemp)"
        crontab -u root -l 2>/dev/null | grep -v 'certbot renew' > "$CRON_TMP" || true
        echo "$CRON_JOB" >> "$CRON_TMP"
        crontab -u root "$CRON_TMP"
        rm -f "$CRON_TMP"
        systemctl enable --now cron 2>/dev/null || true

        echo "✅ 已写入 root 定时续期任务 (每天 02:15 自动检查续期):"
        crontab -u root -l | grep 'certbot renew'
    else
        echo "❌ Certbot 证书申请失败！请检查域名 ${DOMAIN} 是否已解析到本机 IP，且 80 端口未被防火墙拦截。"
    fi

    # 恢复启动基础 Nginx
    systemctl start nginx

elif [ "$CERT_MODE" = "custom" ]; then
    mkdir -p "/etc/letsencrypt/live/${DOMAIN}"
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        echo "📂 已创建证书目录: /etc/letsencrypt/live/${DOMAIN}/"
        if [ -t 0 ]; then
            read -r -p "👉 如果你有现成的证书路径，请输入公钥路径 (fullchain.pem，直接回车则稍后手动上传): " USER_CERT
            if [ -n "$USER_CERT" ] && [ -f "$USER_CERT" ]; then
                read -r -p "👉 请输入私钥路径 (privkey.pem): " USER_KEY
                if [ -n "$USER_KEY" ] && [ -f "$USER_KEY" ]; then
                    cp "$USER_CERT" "$CERT_FILE"
                    cp "$USER_KEY" "$KEY_FILE"
                    chmod 600 "$KEY_FILE"
                    echo "✅ 自用证书已复制到 /etc/letsencrypt/live/${DOMAIN}/"
                fi
            fi
        fi
    else
        echo "✅ 检测到 /etc/letsencrypt/live/${DOMAIN}/ 下已有证书文件，将直接使用。"
    fi
else
    echo "⏭️ 已选择跳过证书申请。"
fi

# 12. 写入自定义 /etc/nginx/conf.d/default.conf 并替换域名
echo "⚙️ [7/7] 正在写入 /etc/nginx/conf.d/default.conf 站点配置..."
[ -f /etc/nginx/conf.d/default.conf ] && cp /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak

cat << 'EOF' > /etc/nginx/conf.d/default.conf
server {
        listen       80;
        server_name  admin.clearsolitaire.com;

        #charset koi8-r;
  
        #access_log  logs/host.access.log  main;
        return      301 https://$server_name$request_uri;

        location / {
            root   html;
            index  index.html index.htm;
        }

        #error_page  404              /404.html;

        # redirect server error pages to the static page /50x.html
        #
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
}

    server {
        listen       443 ssl ;
        http2 on;
        server_name  admin.clearsolitaire.com;
        ssl_certificate    /etc/letsencrypt/live/admin.clearsolitaire.com/fullchain.pem;
        ssl_certificate_key    /etc/letsencrypt/live/admin.clearsolitaire.com/privkey.pem;

         ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
         ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;
         ssl_prefer_server_ciphers on;
         ssl_session_cache shared:SSL:10m;
         ssl_session_timeout 10m;
         add_header Strict-Transport-Security max-age=3153600;
         error_page 497  https://;

location / {
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $http_host;
        proxy_redirect off;
        proxy_pass http://127.0.0.1:42493;
}

location ^~ /newness {
    proxy_pass http://127.0.0.1:39271/newness;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

location /us {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:55536;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
        proxy_read_timeout 300s;
        # Show realip in v2ray access.log
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
}


server
{
    listen 8443 ssl ;
    listen [::]:8443 ssl ;
    #配置站点域名，多个以空格分开
    server_name  admin.clearsolitaire.com;


    #SSL-START SSL相关配置，请勿删除或修改下一行带注释的404规则
    #error_page 404/404.html;
    #HTTP_TO_HTTPS_START

    
    ssl_certificate    /etc/letsencrypt/live/admin.clearsolitaire.com/fullchain.pem;
    ssl_certificate_key    /etc/letsencrypt/live/admin.clearsolitaire.com/privkey.pem;

    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:EECDH+3DES:RSA+3DES:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    add_header Strict-Transport-Security "max-age=31536000";
    error_page 497  https://;


    location /us {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:55536;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

}
}
server
{
    listen 2083 ssl ;
    listen [::]:2083 ssl ;
    #配置站点域名，多个以空格分开
    server_name  admin.clearsolitaire.com;
    #SSL-START SSL相关配置，请勿删除或修改下一行带注释的404规则
    #error_page 404/404.html;
    #HTTP_TO_HTTPS_START

    
    ssl_certificate    /etc/letsencrypt/live/admin.clearsolitaire.com/fullchain.pem;
    ssl_certificate_key    /etc/letsencrypt/live/admin.clearsolitaire.com/privkey.pem;
    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:EECDH+3DES:RSA+3DES:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    add_header Strict-Transport-Security "max-age=31536000";
    error_page 497  https://;

    location / {
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header Host $http_host;
            proxy_redirect off;
            proxy_pass http://127.0.0.1:42493;
    }

    location /home {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:49828;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

}
}
server
{
    listen 2096 ssl ;
    listen [::]:2096 ssl ;
    #配置站点域名，多个以空格分开
    server_name  admin.clearsolitaire.com;

    #SSL-START SSL相关配置，请勿删除或修改下一行带注释的404规则
    #error_page 404/404.html;
    #HTTP_TO_HTTPS_START

    
    ssl_certificate    /etc/letsencrypt/live/admin.clearsolitaire.com/fullchain.pem;
    ssl_certificate_key    /etc/letsencrypt/live/admin.clearsolitaire.com/privkey.pem;
    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:EECDH+3DES:RSA+3DES:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    add_header Strict-Transport-Security "max-age=31536000";
    error_page 497  https://;

    location / {
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header Host $http_host;
            proxy_redirect off;
            proxy_pass http://127.0.0.1:42493;
    }
    location /home {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:49828;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

}
}
EOF

sed -i "s/admin\.clearsolitaire\.com/${DOMAIN}/g" /etc/nginx/conf.d/default.conf

# 校验 SSL 证书是否存在，决定是否立即重载新配置
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    echo "✅ 检测到 SSL 证书已就绪，正在校验并重载新站点配置..."
    nginx -t
    systemctl reload nginx
    echo "✅ 站点配置已生效！"
else
    echo "=========================================="
    echo "⚠️ 提示: 尚未检测到 ${DOMAIN} 的 SSL 证书文件:"
    echo "   - $CERT_FILE"
    echo "   - $KEY_FILE"
    echo "   /etc/nginx/conf.d/default.conf 已写入完成，但暂未 reload 以免报错。"
    echo "   请准备好证书后执行: sudo nginx -t && sudo systemctl reload nginx"
fi

echo "=========================================="
nginx -v
systemctl status nginx -n 5 --no-pager || true
echo "=========================================="
