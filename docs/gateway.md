# Mihomo 旁路由

在 Debian / Ubuntu 上装 Mihomo 当旁路由：局域网里的设备把网关和 DNS 指向这台机器就能上网。虚拟机（比如 VMware）网卡要用桥接模式，IP 要固定（在主路由里做 DHCP 绑定，或者在系统里设静态 IP）。

## 安装

```bash
wget -N https://raw.githubusercontent.com/1432433gg/rules-next/main/gateway.sh && chmod +x gateway.sh && ./gateway.sh
```

如果提示 `wget: command not found`，先运行 `apt update && apt install -y wget`。

1. 选「1. 安装 Mihomo 旁路由」。装完就能用：默认配置没有节点、没有分流，所有流量直连。
2. 局域网设备把网关和 DNS 设成这台机器的 IP。
3. 换成自己的配置：直接改 `/etc/mihomo/config.yaml`（带分流的完整模板见 [mihomo/config.yaml](../mihomo/config.yaml)），改完先检查再重启：

```bash
/usr/local/bin/mihomo/mihomo -t -d /etc/mihomo
systemctl restart mihomo
```

## 要求

- Debian 12+ 或 Ubuntu 22.04+，amd64 / arm64，root 用户
- 有 `/dev/net/tun`（虚拟机和实体机都有；LXC 容器要在宿主机上开启）

## 菜单

```
—————— 安装 ——————
1.  安装 Mihomo 旁路由
2.  升级 脚本
—————— 查看信息 ——————
3.  查看服务运行状态
—————— 其他 ——————
4.  更新 / 指定版本 Mihomo
5.  更新 / 指定版本 面板
6.  更新 Linux 内核
7.  安装 BBR 加速
0.  退出
```

时间同步、更新内核、安装 BBR 和 [mihomo-next](https://github.com/1432433gg/mihomo-next) 的做法一样。

## 安装做了什么

- 时间同步：chrony 只用谷歌时间服务器，时区 Asia/Shanghai
- 开启 IP 转发
- 安装最新版 Mihomo 和面板（metacubexd），设为开机自启
- 没有配置时写入默认配置（只有直连），已有配置不动

面板从 metacubexd 的 [Releases](https://github.com/MetaCubeX/metacubexd/releases) 下载，「5. 更新 / 指定版本 面板」可以换成任意版本。面板地址 `http://这台机器的IP:9090/ui`，「3. 查看服务运行状态」里也会显示。换成自己的配置后，里面要有一行 `external-ui: /etc/mihomo/ui` 才有面板。

## 设备接入

在主路由的 DHCP 设置里，把网关和 DNS 都改成这台机器的 IP；或者只在需要的设备上手动设置。这台机器关机时，这些设备会上不了网，把网关改回主路由就能恢复。

## 文件位置

| 路径 | 内容 |
| --- | --- |
| `/etc/mihomo/config.yaml` | Mihomo 配置 |
| `/etc/mihomo/ui` | 面板 |
| `/usr/local/bin/mihomo/mihomo` | Mihomo 程序 |
| `/etc/systemd/system/mihomo.service` | Mihomo 服务 |
| `/etc/sysctl.d/99-mihomo-gateway.conf` | IP 转发设置 |
