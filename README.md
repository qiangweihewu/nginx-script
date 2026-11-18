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
