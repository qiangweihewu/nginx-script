# nginx-script

适用于 **Ubuntu** 与 **Debian** 的 Nginx 官方源（`nginx.org`）一键安全安装与自动配置脚本[cite: 1]。

## ✨ 功能特性

- **双系统自动识别**：自动检测 Ubuntu / Debian 系统版本代号，匹配对应的官方 HTTPS 软件源与系统密钥环。
- **官方 GPG 指纹核验**：自动拉取 Nginx 官方签名密钥并进行指纹比对校验，配置高优先级（`Pin-Priority: 900`）防止被系统默认旧包覆盖。
- **旧版冲突包清理**：自动检测并清理系统自带源安装的旧版 `nginx-common` / `nginx-core` 等冲突组件。
- **Systemd PID 警告自愈**：自动检测 `Can't open PID file /run/nginx.pid` 竞态警告，按需注入 Systemd Override 修复。
- **站点配置自动生成**：支持交互式或命令行传参注入域名，自动生成 `/etc/nginx/conf.d/default.conf` 多端口 SSL 与反向代理配置，并智能检测 Let's Encrypt 证书状态。

---

## 🚀 一键安装指令

### 方式一：交互式安装（推荐，运行后会提示输入域名）

使用 `root` 用户或带有 `sudo` 权限的用户执行：

```bash
sudo bash <(curl -fsSL [https://raw.githubusercontent.com/qiangweihewu/nginx-script/main/install.sh](https://raw.githubusercontent.com/qiangweihewu/nginx-script/main/install.sh))

```

### 方式二：无交互直接传参安装（适合自动化部署）

将 `your.domain.com` 替换为你的实际域名，默认安装 **Mainline（主线最新版）**：

```bash
curl -fsSL [https://raw.githubusercontent.com/qiangweihewu/nginx-script/main/install.sh](https://raw.githubusercontent.com/qiangweihewu/nginx-script/main/install.sh) | sudo bash -s -- your.domain.com

```

如果需要安装 **Stable（稳定版）**，可在域名后追加 `stable` 参数：

```bash
curl -fsSL [https://raw.githubusercontent.com/qiangweihewu/nginx-script/main/install.sh](https://raw.githubusercontent.com/qiangweihewu/nginx-script/main/install.sh) | sudo bash -s -- your.domain.com stable

```

### 方式三：下载到本地后运行

```bash
curl -fsSLO [https://raw.githubusercontent.com/qiangweihewu/nginx-script/main/install.sh](https://raw.githubusercontent.com/qiangweihewu/nginx-script/main/install.sh)
chmod +x install.sh
sudo ./install.sh

```

---

## 📂 默认配置与路径说明

脚本执行完成后，核心文件路径如下：

| 路径 | 说明 |
| --- | --- |
| `/etc/nginx/nginx.conf` | Nginx 主配置文件 |
| `/etc/nginx/conf.d/default.conf` | 自动生成的站点配置文件（已替换为你输入的域名） |
| `/etc/nginx/conf.d/default.conf.bak` | 原有默认配置的自动备份 |
| `/etc/letsencrypt/live/<你的域名>/` | 默认读取的 SSL 证书目录（`fullchain.pem` & `privkey.pem`） |
| `/var/log/nginx/` | 访问日志（`access.log`）与错误日志（`error.log`） |

### ⚠️ 关于 SSL 证书的说明

脚本生成的 `default.conf` 默认监听 `80`、`443`、`8443`、`2083`、`2096` 端口并启用 SSL：

1. **如果证书已存在**（位于 `/etc/letsencrypt/live/<你的域名>/` 下）：脚本会自动执行 `nginx -t` 并平滑重载（`reload`）使配置立即生效。
2. **如果证书尚未签发**：脚本会先启动基础 Nginx 服务并完成配置文件写入，待你上传证书或使用 Certbot 签发证书后，执行以下命令即可生效：
```bash
sudo nginx -t && sudo systemctl reload nginx

```



---

## 🛠️ 常用维护命令

```bash
# 查看 Nginx 版本与编译参数
nginx -V

# 测试配置文件语法是否正确
sudo nginx -t

# 平滑重载配置（不中断现有连接）
sudo systemctl reload nginx

# 重启 Nginx 服务
sudo systemctl restart nginx

# 查看运行状态与最新日志
sudo systemctl status nginx

```

```

```
