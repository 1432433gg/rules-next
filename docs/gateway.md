# Debian 12 旁路由（Mihomo）

在 Debian 12 上装 Mihomo 当旁路由：局域网里的设备把网关和 DNS 指向这台机器就能上网。虚拟机（比如 VMware）网卡要用桥接模式，IP 要固定（在主路由里做 DHCP 绑定，或者在 Debian 里设静态 IP）。

以下命令都用 root 运行。

## 1. 基础软件

```bash
apt update && apt install -y wget curl vim git chrony
```

## 2. 时间同步

和 mihomo-next 一样：注释掉系统自带的时间服务器，只用谷歌的，时区设成上海。

```bash
C=/etc/chrony/chrony.conf
sed -i '/^# BEGIN google$/,/^# END google$/d' $C
sed -i -E 's/^((pool|server|sourcedir)[[:space:]].*)$/# \1/' $C
cat >>$C <<'EOF'
# BEGIN google
server time1.google.com iburst
server time2.google.com iburst
server time3.google.com iburst
server time4.google.com iburst
# END google
EOF
timedatectl set-timezone Asia/Shanghai
systemctl enable chrony
systemctl restart chrony
timedatectl set-ntp true
chronyc waitsync 15 0 0 2 && chronyc makestep
```

检查：`chronyc tracking`，`Leap status` 是 `Normal` 就是同步好了。

## 3. 开启转发

```bash
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf 2>/dev/null || cat >>/etc/sysctl.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
sysctl -p
```

## 4. 安装 Mihomo

版本号换成 [Releases](https://github.com/MetaCubeX/mihomo/releases) 里的最新版，配置要求 v1.19.31 以上。`compatible` 版本老 CPU 也能跑。

```bash
VER=v1.19.32
mkdir -p /usr/local/bin/mihomo /etc/mihomo
wget -O /usr/local/bin/mihomo/mihomo.gz "https://github.com/MetaCubeX/mihomo/releases/download/$VER/mihomo-linux-amd64-compatible-$VER.gz" &&
  gzip -df /usr/local/bin/mihomo/mihomo.gz &&
  chmod +x /usr/local/bin/mihomo/mihomo
/usr/local/bin/mihomo/mihomo -v
```

以后更新：改 `VER` 再跑一遍这段，然后 `systemctl restart mihomo`。

## 5. 面板（metacubexd）

```bash
git clone https://github.com/metacubex/metacubexd.git -b gh-pages /etc/mihomo/ui
```

更新：`git -C /etc/mihomo/ui pull -r`

## 6. 配置

```bash
[ -f /etc/mihomo/config.yaml ] || wget -O /etc/mihomo/config.yaml https://github.com/1432433gg/rules-next/raw/main/mihomo/config.yaml
vim /etc/mihomo/config.yaml
```

已经有配置时不会重新下载，免得把填好的内容覆盖掉。

把 `proxies` 里带「填」的换成自己的：服务器地址、端口、UUID、Reality 公钥和 short-id、SS 密码。`secret` 是面板密码，可以留空。

检查：`/usr/local/bin/mihomo/mihomo -t -d /etc/mihomo`

## 7. 开机自启

```bash
cat >/etc/systemd/system/mihomo.service <<'EOF'
[Unit]
Description=mihomo Daemon, Another Clash Kernel.
After=network.target NetworkManager.service systemd-networkd.service iwd.service

[Service]
Type=simple
LimitNPROC=500
LimitNOFILE=1000000
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
Restart=always
ExecStartPre=/usr/bin/sleep 1s
ExecStart=/usr/local/bin/mihomo/mihomo -d /etc/mihomo
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now mihomo
systemctl status mihomo
```

改了配置：先 `/usr/local/bin/mihomo/mihomo -t -d /etc/mihomo` 检查，再 `systemctl restart mihomo`。

面板地址：`http://这台机器的IP:9090/ui`

## 8. 新内核和 BBR（可选）

和 mihomo-next 的「更新 Linux 内核」「安装 BBR 加速」一样：从 backports 装最新内核，重启后清掉旧内核，再用 ylx2016 的脚本开 BBR。

```bash
echo "deb https://deb.debian.org/debian bookworm-backports main" >/etc/apt/sources.list.d/backports.list
apt update
apt -t bookworm-backports install -y linux-image-amd64   # 完整内核；云内核换成 linux-image-cloud-amd64
reboot
```

重启后删掉旧内核（和对应的 headers）。还没用上最新内核时什么都不删，只提示先重启：

```bash
K=$(uname -r)
NEW=$(dpkg-query -W -f='${binary:Package} ${db:Status-Abbrev}\n' 'linux-image-[0-9]*' | awk '$2 ~ /^ii/ {sub(/^linux-image-/, "", $1); print $1}' | sort -V | tail -n1)
if [ "$K" != "$NEW" ]; then
  echo "现在运行的是 $K，新内核 $NEW 还没用上，先重启"
else
  OLD=$(dpkg-query -W -f='${binary:Package} ${db:Status-Abbrev}\n' 'linux-image-[0-9]*' 'linux-headers-[0-9]*' 2>/dev/null | awk -v k="$K" '$2 ~ /^ii/ && $1 != "linux-image-" k && $1 != "linux-headers-" k && $1 !~ /-common$/ {print $1}')
  echo "要删除：${OLD:-无}"
  [ -n "$OLD" ] && apt purge -y $OLD
fi
```

开 BBR（脚本跑完就删，不留文件）：

```bash
cd /tmp && wget -O tcp.sh https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh && bash tcp.sh; rm -f /tmp/tcp.sh
```

检查：`sysctl net.ipv4.tcp_congestion_control` 是 `bbr`。

## 9. 设备接入

在主路由的 DHCP 设置里，把网关和 DNS 都改成这台机器的 IP；或者只在需要的设备上手动设置。这台机器关机时，这些设备会上不了网，把网关改回主路由就能恢复。
