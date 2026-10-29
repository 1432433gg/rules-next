#!/usr/bin/env bash
#
# Mihomo 旁路由一键安装脚本
# https://github.com/1432433gg/rules-next
#
# 用法：
#   wget -N https://raw.githubusercontent.com/1432433gg/rules-next/main/gateway.sh && chmod +x gateway.sh && ./gateway.sh
#

SCRIPT_VERSION="1.0.0"

# ─── 路径 ───
MIHOMO_REPO=MetaCubeX/mihomo
MIHOMO_BIN_DIR=/usr/local/bin/mihomo
MIHOMO_BIN=$MIHOMO_BIN_DIR/mihomo
MIHOMO_CONF_DIR=/etc/mihomo
MIHOMO_CONF=$MIHOMO_CONF_DIR/config.yaml
MIHOMO_SERVICE=/etc/systemd/system/mihomo.service
UI_DIR=$MIHOMO_CONF_DIR/ui
UI_REPO=MetaCubeX/metacubexd
# 记录装的是哪个版本
UI_VERSION_FILE=.mihomo-gateway-version

CHRONY_CONF=/etc/chrony/chrony.conf
SYSCTL_FILE=/etc/sysctl.d/99-mihomo-gateway.conf
BBR_SCRIPT_URL=https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh
OS_RELEASE_FILE=/etc/os-release
APT_SOURCES_LIST=/etc/apt/sources.list
APT_SOURCES_DIR=/etc/apt/sources.list.d

# 简单配置和升级脚本都从本仓库下载
REPO_RAW=https://raw.githubusercontent.com/1432433gg/rules-next/main
SCRIPT_NAME=gateway.sh
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)

# ─── 输出 ───
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Blue="\033[36m"
Font="\033[0m"
OK="${Green}[OK]${Font}"
ERROR="${Red}[错误]${Font}"
WARN="${Yellow}[注意]${Font}"

print_ok() { echo -e "${OK} ${Blue}$1${Font}"; }
print_error() { echo -e "${ERROR} ${Red}$1${Font}"; }
print_warn() { echo -e "${WARN} ${Yellow}$1${Font}"; }
print_info() { echo -e "${Green}==>${Font} $1"; }

# 检查上一条命令的结果，失败就退出
judge() {
  if [[ $? -eq 0 ]]; then
    print_ok "$1 完成"
    sleep 1
  else
    print_error "$1 失败"
    exit 1
  fi
}

# ─── 系统检查 ───
is_root() {
  if [[ $EUID -ne 0 ]]; then
    print_error "请用 root 运行"
    exit 1
  fi
}

detect_system() {
  if [[ ! -f $OS_RELEASE_FILE ]]; then
    print_error "无法识别系统"
    exit 1
  fi
  # shellcheck disable=SC1090
  OS_ID=$(. "$OS_RELEASE_FILE" && echo "$ID")
  # shellcheck disable=SC1090
  OS_VERSION=$(. "$OS_RELEASE_FILE" && echo "${VERSION_ID:-0}")
  # shellcheck disable=SC1090
  OS_CODENAME=$(. "$OS_RELEASE_FILE" && echo "${VERSION_CODENAME:-}")
  case "$OS_ID" in
    debian)
      if [[ ${OS_VERSION%%.*} -lt 12 ]]; then
        print_error "仅支持 Debian 12 及以上"
        exit 1
      fi
      ;;
    ubuntu)
      if [[ ${OS_VERSION%%.*} -lt 22 ]]; then
        print_error "仅支持 Ubuntu 22.04 及以上"
        exit 1
      fi
      ;;
    *)
      print_error "仅支持 Debian / Ubuntu"
      exit 1
      ;;
  esac

  case "$(uname -m)" in
    x86_64 | amd64)
      ARCH=amd64
      MIHOMO_ARCH=amd64-compatible
      ;;
    aarch64 | arm64)
      ARCH=arm64
      MIHOMO_ARCH=arm64
      ;;
    *)
      print_error "不支持的架构：$(uname -m)"
      exit 1
      ;;
  esac
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 -y -qq install "$@" >/dev/null
}

# 新开的机器上系统可能正在自动更新，占着 apt，等它结束
wait_for_apt() {
  local i
  for i in $(seq 1 60); do
    pgrep -x 'apt|apt-get|dpkg|unattended-upgr' >/dev/null 2>&1 || return 0
    [[ $i -eq 1 ]] && print_info "系统正在自动更新，等待完成（最多 5 分钟）"
    sleep 5
  done
  print_warn "等待超时，继续执行"
}

apt_update() {
  wait_for_apt
  if ! apt-get -qq update; then
    print_error "apt update 失败，请检查软件源"
    return 1
  fi
}

install_deps() {
  print_info "安装依赖"
  apt_update || exit 1
  apt_install wget curl vim gzip tar ca-certificates chrony iproute2
  judge "安装依赖"
}

# 旁路由要用 TUN；有些容器（比如 LXC）默认没有
check_tun() {
  if [[ ! -c /dev/net/tun ]]; then
    print_error "没有 /dev/net/tun，这台机器用不了 TUN 模式（容器的话要在宿主机上开启 TUN）"
    return 1
  fi
}

# ─── 时间同步 ───
# 注释掉原有的时间服务器，只用谷歌的；重复运行只保留一份（和 mihomo-next 一样）
configure_chrony_file() {
  local conf=$1
  sed -i '/^# BEGIN mihomo-gateway$/,/^# END mihomo-gateway$/d' "$conf"
  sed -i -E 's/^((pool|server|sourcedir)[[:space:]].*)$/# \1/' "$conf"
  if [[ -s $conf && -n $(tail -c1 "$conf") ]]; then
    echo >>"$conf"
  fi
  cat >>"$conf" <<'EOF'
# BEGIN mihomo-gateway
server time1.google.com iburst
server time2.google.com iburst
server time3.google.com iburst
server time4.google.com iburst
# END mihomo-gateway
EOF
}

configure_chrony() {
  local conf=$CHRONY_CONF
  [[ -f $conf ]] || conf=/etc/chrony.conf
  if [[ ! -f $conf ]]; then
    print_error "找不到 chrony 配置文件"
    return 1
  fi
  configure_chrony_file "$conf" || return 1
  timedatectl set-timezone Asia/Shanghai >/dev/null 2>&1
  systemctl enable chrony >/dev/null 2>&1
  systemctl restart chrony
  timedatectl set-ntp true >/dev/null 2>&1
  print_ok "时间同步已设置（谷歌时间服务器，时区 Asia/Shanghai）"
  wait_time_sync
}

now_time() {
  date '+%Y-%m-%d %H:%M:%S %Z'
}

# 等 chrony 连上时间服务器，立即校准一次，再显示同步后的时间
wait_time_sync() {
  local server
  print_info "等待时间同步（最多 30 秒）"
  if ! chronyc waitsync 15 0 0 2 >/dev/null 2>&1; then
    print_warn "30 秒内没有同步上，当前时间 $(now_time)，chrony 会在后台继续同步"
    return 0
  fi
  chronyc makestep >/dev/null 2>&1
  server=$(chronyc tracking 2>/dev/null | awk -F'[()]' '/^Reference ID/ {print $2; exit}')
  print_ok "时间已同步：$(now_time)（时间服务器 ${server:-未知}）"
}

time_sync_state() {
  if chronyc tracking 2>/dev/null | grep -qE '^Leap status +: Normal'; then
    echo -e "${Green}已同步${Font}"
  else
    echo -e "${Red}未同步${Font}"
  fi
}

# ─── IP 转发 ───
# 旁路由要帮局域网设备转发流量，必须打开
enable_forwarding() {
  cat >"$SYSCTL_FILE" <<'EOF'
# Mihomo 旁路由：转发局域网设备的流量
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
  if ! sysctl -q -p "$SYSCTL_FILE" >/dev/null; then
    print_error "开启 IP 转发失败"
    return 1
  fi
  print_ok "已开启 IP 转发"
}

forwarding_state() {
  if [[ $(sysctl -n net.ipv4.ip_forward 2>/dev/null) == 1 ]]; then
    echo -e "${Green}已开启${Font}"
  else
    echo -e "${Red}未开启${Font}"
  fi
}

# ─── GitHub 版本 ───
github_latest_tag() {
  local api
  api=$(wget -qO- --timeout=15 --tries=2 "https://api.github.com/repos/$1/releases/latest") || return 1
  if [[ $api =~ \"tag_name\":[[:space:]]*\"([^\"]+)\" ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    return 1
  fi
}

# ─── Mihomo ───
mihomo_current_version() {
  [[ -x $MIHOMO_BIN ]] || return 0
  "$MIHOMO_BIN" -v 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1
}

# 安装或更新到指定版本（不传就是最新版）；有变化时 CHANGED=1
install_mihomo() {
  local version=${1:-} current tmp file
  CHANGED=0
  if [[ -z $version ]]; then
    print_info "获取 Mihomo 最新版本"
    version=$(github_latest_tag "$MIHOMO_REPO") || {
      print_error "无法访问 GitHub API，可以手动指定版本号"
      return 1
    }
  fi
  version="v${version#v}"
  current=$(mihomo_current_version)
  if [[ $current == "$version" ]]; then
    print_ok "Mihomo 已是 $version"
    return 0
  fi
  print_info "安装 Mihomo ${version}（当前：${current:-未安装}）"

  tmp=$(mktemp -d)
  file="mihomo-linux-${MIHOMO_ARCH}-${version}.gz"
  if ! wget -q --show-progress --timeout=30 --tries=2 -O "$tmp/mihomo.gz" \
    "https://github.com/${MIHOMO_REPO}/releases/download/${version}/${file}"; then
    rm -rf "$tmp"
    print_error "下载失败：${file}，请检查版本号或网络"
    return 1
  fi
  if ! gzip -d "$tmp/mihomo.gz" || ! chmod +x "$tmp/mihomo" || ! "$tmp/mihomo" -v >/dev/null 2>&1; then
    rm -rf "$tmp"
    print_error "下载的文件无法运行"
    return 1
  fi

  # 别的安装方式可能把 /usr/local/bin/mihomo 装成了文件，直接换掉
  if [[ -f $MIHOMO_BIN_DIR ]]; then
    rm -f "$MIHOMO_BIN_DIR"
  fi
  mkdir -p "$MIHOMO_BIN_DIR"
  install -m 755 -o root -g root "$tmp/mihomo" "$MIHOMO_BIN"
  rm -rf "$tmp"
  CHANGED=1
  print_ok "Mihomo $version 安装完成"
}

write_mihomo_service() {
  cat >"$MIHOMO_SERVICE" <<EOF
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
ExecStartPre=/bin/sleep 1s
ExecStart=$MIHOMO_BIN -d $MIHOMO_CONF_DIR
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable mihomo >/dev/null 2>&1
}

# 检查配置；第一个参数是要检查的文件（默认 config.yaml）
check_mihomo_config() {
  local file=${1:-$MIHOMO_CONF} out
  if ! out=$("$MIHOMO_BIN" -t -d "$MIHOMO_CONF_DIR" -f "$file" 2>&1); then
    # 只显示出错的原因（临时文件名之类的不显示）
    echo "$out" | grep -E 'level=(error|fatal)' | sed -E 's/^.*msg="(.*)"$/  \1/' | tail -n 5
    return 1
  fi
}

restart_mihomo() {
  if ! check_mihomo_config; then
    print_error "Mihomo 配置检查未通过，没有重启"
    return 1
  fi
  systemctl enable mihomo >/dev/null 2>&1
  systemctl restart mihomo
  sleep 2
  if systemctl is-active --quiet mihomo; then
    print_ok "Mihomo 运行中"
  else
    print_error "Mihomo 启动失败，可以运行 journalctl -u mihomo -n 30 查看原因"
    return 1
  fi
}

DEFAULT_MARK="# Mihomo 简单配置"

# 没有配置时用仓库里的 mihomo/simple.yaml（没有节点、没有分流，全部直连，只为了装好就能跑）
# 在克隆下来的仓库里运行就用本地的，否则从 GitHub 下载；已有配置不动
write_default_config() {
  local tmp
  [[ -f $MIHOMO_CONF ]] && return 0
  mkdir -p "$MIHOMO_CONF_DIR"
  tmp=$(mktemp "$MIHOMO_CONF_DIR/.config.XXXXXX") || return 1
  if [[ -n $SCRIPT_DIR && -f $SCRIPT_DIR/mihomo/simple.yaml ]]; then
    cp "$SCRIPT_DIR/mihomo/simple.yaml" "$tmp"
  elif ! wget -q --timeout=15 --tries=2 -O "$tmp" "$REPO_RAW/mihomo/simple.yaml"; then
    rm -f "$tmp"
    print_error "下载简单配置失败：$REPO_RAW/mihomo/simple.yaml"
    return 1
  fi
  if ! head -n1 "$tmp" | grep -qF "$DEFAULT_MARK"; then
    rm -f "$tmp"
    print_error "简单配置文件不完整，请稍后再试"
    return 1
  fi
  chmod 600 "$tmp"
  mv -f "$tmp" "$MIHOMO_CONF"
  print_ok "已写入简单配置（全部直连）：$MIHOMO_CONF"
}

is_default_config() {
  head -n1 "$MIHOMO_CONF" 2>/dev/null | grep -qF "$DEFAULT_MARK"
}

# ─── 5. 面板 ───
ui_current_version() {
  [[ -f $UI_DIR/$UI_VERSION_FILE ]] && head -n1 "$UI_DIR/$UI_VERSION_FILE"
}

ui_installed() {
  [[ -n $(ui_current_version) ]]
}

# 从 Releases 下载 metacubexd，安装或更新到指定版本（不传就是最新版）
# 下载、解压、检查都通过才替换，失败时原来的面板不动
install_ui() {
  local version=${1:-} current tmp
  if [[ -z $version ]]; then
    print_info "获取面板最新版本"
    version=$(github_latest_tag "$UI_REPO") || {
      print_error "无法访问 GitHub API，可以手动指定版本号"
      return 1
    }
  fi
  version="v${version#v}"
  current=$(ui_current_version)
  if [[ $current == "$version" ]]; then
    print_ok "面板已是 $version"
    return 0
  fi
  print_info "安装面板 metacubexd ${version}（当前：${current:-未安装}）"

  mkdir -p "$MIHOMO_CONF_DIR"
  tmp=$(mktemp -d "$MIHOMO_CONF_DIR/.ui.XXXXXX") || return 1
  if ! wget -q --show-progress --timeout=30 --tries=2 -O "$tmp/ui.tgz" \
    "https://github.com/${UI_REPO}/releases/download/${version}/compressed-dist.tgz"; then
    rm -rf "$tmp"
    print_error "下载失败：面板 ${version}，请检查版本号或网络"
    return 1
  fi
  mkdir "$tmp/ui"
  if ! tar -xzf "$tmp/ui.tgz" -C "$tmp/ui" || [[ ! -f $tmp/ui/index.html ]]; then
    rm -rf "$tmp"
    print_error "下载的面板文件不完整"
    return 1
  fi
  echo "$version" >"$tmp/ui/$UI_VERSION_FILE"

  # 旧面板直接换掉
  if [[ -e $UI_DIR ]]; then
    mv "$UI_DIR" "$tmp/old"
  fi
  mv "$tmp/ui" "$UI_DIR"
  rm -rf "$tmp"
  print_ok "面板 $version 安装完成"
}

update_ui() {
  local version
  read -rp "请输入面板版本号 [回车=最新版]：" version
  install_ui "$(echo "$version" | tr -d '[:space:]')"
}

ui_state() {
  if ui_installed; then
    echo -e "${Green}已安装${Font}  $(ui_current_version)"
  else
    echo -e "${Yellow}未安装${Font}"
  fi
}

# 本机局域网 IP（默认路由出去的那张网卡）
lan_ip() {
  ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") {print $(i + 1); exit}}'
}

# 配置里 external-controller 的端口，比如 0.0.0.0:9090 → 9090
controller_port() {
  [[ -f $MIHOMO_CONF ]] || return 0
  sed -n -E 's/^external-controller:[[:space:]]*"?[^"#]*:([0-9]+)"?.*$/\1/p' "$MIHOMO_CONF" | head -n1
}

panel_url() {
  local ip port
  ui_installed || return 0
  ip=$(lan_ip)
  port=$(controller_port)
  [[ -n $ip && -n $port ]] || return 0
  echo "http://$ip:$port/ui"
}

# ─── 1. 安装 ───
install_gateway() {
  check_tun || exit 1
  install_deps
  configure_chrony || exit 1
  enable_forwarding || exit 1
  install_mihomo || exit 1
  # 面板不是必需的，下载失败也接着装
  install_ui || print_warn "面板没装上，之后可以选「5. 更新 / 指定版本 面板」再试"
  write_default_config || exit 1
  write_mihomo_service
  echo
  if check_mihomo_config >/dev/null 2>&1; then
    restart_mihomo || exit 1
    show_status
  else
    print_warn "$MIHOMO_CONF 检查没通过，Mihomo 没有启动"
    echo
  fi
  if is_default_config; then
    print_warn "现在是简单配置：没有节点、没有分流，所有流量直连"
  fi
  show_config_help
  show_usage
}

show_config_help() {
  echo -e "改配置：直接改 ${Green}$MIHOMO_CONF${Font}，改完先检查再重启"
  echo -e "  检查：${Green}$MIHOMO_BIN -t -d $MIHOMO_CONF_DIR${Font}"
  echo -e "  重启：${Green}systemctl restart mihomo${Font}"
  echo
}

show_usage() {
  local ip
  ip=$(lan_ip)
  echo -e "局域网设备把${Green}网关${Font}和 ${Green}DNS${Font} 都设成 ${Green}${ip:-这台机器的 IP}${Font} 就能上网"
  show_panel_url
}

show_panel_url() {
  local url
  url=$(panel_url)
  if [[ -n $url ]]; then
    echo -e "面板：${Green}$url${Font}"
  elif ! ui_installed; then
    echo -e "面板：没装上，可以选「5. 更新 / 指定版本 面板」再试"
  fi
  echo
}

# ─── 3. 服务状态 ───
service_state() {
  if systemctl is-active --quiet "$1"; then
    echo -e "${Green}运行中${Font}"
  elif [[ -f /etc/systemd/system/$1.service || -f /lib/systemd/system/$1.service ]]; then
    echo -e "${Red}未运行${Font}"
  else
    echo -e "${Yellow}未安装${Font}"
  fi
}

config_state() {
  if [[ ! -f $MIHOMO_CONF ]]; then
    echo -e "${Yellow}未创建${Font}"
  elif [[ ! -x $MIHOMO_BIN ]]; then
    echo -e "${Yellow}未检查${Font}"
  elif check_mihomo_config >/dev/null 2>&1; then
    if is_default_config; then
      echo -e "${Green}检查通过${Font}  简单配置（全部直连）"
    else
      echo -e "${Green}检查通过${Font}"
    fi
  else
    echo -e "${Red}有错误${Font}  运行 $MIHOMO_BIN -t -d $MIHOMO_CONF_DIR 查看原因"
  fi
}

# 当前的 TCP 拥塞控制算法，并说明 BBR 有没有开
congestion_state() {
  local cc
  cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
  case "$cc" in
    "") echo -e "${Yellow}未知${Font}" ;;
    bbr*) echo -e "${cc}  ${Green}已开启${Font}" ;;
    *) echo -e "${cc}  ${Yellow}未开启${Font}" ;;
  esac
}

show_status() {
  local url
  url=$(panel_url)
  echo
  echo -e "Mihomo：$(service_state mihomo)  $(mihomo_current_version)"
  echo -e "配置：$(config_state)"
  echo -e "面板：$(ui_state)  ${url}"
  echo -e "本机 IP：$(lan_ip)"
  echo -e "IP 转发：$(forwarding_state)"
  echo -e "时间同步：$(service_state chrony)  $(time_sync_state)"
  echo -e "当前时间：$(now_time)"
  echo -e "Linux 内核：$(uname -r)"
  echo -e "拥塞控制：$(congestion_state)"
  echo
}

# ─── 4. 更新 Mihomo ───
update_mihomo() {
  local version
  read -rp "请输入 Mihomo 版本号 [回车=最新版]：" version
  install_mihomo "$(echo "$version" | tr -d '[:space:]')" || return 1
  if [[ $CHANGED -eq 1 && -f $MIHOMO_SERVICE ]]; then
    restart_mihomo
  fi
}

# ─── 6. 更新 Linux 内核（和 mihomo-next 一样） ───
# 已安装的具体版本内核包里，除了新内核和正在运行的内核，其余都删掉
kernel_packages_to_remove() {
  local new_ver=$1 running=$2 pkg ver
  dpkg-query -W -f='${binary:Package} ${db:Status-Abbrev}\n' 'linux-image-[0-9]*' 2>/dev/null |
    awk '$2 ~ /^ii/ {print $1}' |
    while read -r pkg; do
      ver=${pkg#linux-image-}
      [[ $ver == "$new_ver" || $ver == "$running" ]] && continue
      echo "$pkg"
      if dpkg-query -W -f='${db:Status-Abbrev}' "linux-headers-$ver" 2>/dev/null | grep -q '^ii'; then
        echo "linux-headers-$ver"
      fi
    done
}

backports_enabled() {
  grep -rhs -- "${OS_CODENAME}-backports" "$APT_SOURCES_LIST" "$APT_SOURCES_DIR" |
    grep -qv '^[[:space:]]*#'
}

update_kernel() {
  local choice flavor meta other_meta new_pkg new_ver running yn
  local -a remove
  if [[ $OS_ID != debian ]]; then
    print_error "更新 Linux 内核仅支持 Debian"
    return 1
  fi
  echo "1. 安装最新完整内核"
  echo "2. 安装最新云内核"
  read -rp "请选择 [1]：" choice
  case "${choice:-1}" in
    1)
      flavor=$ARCH
      other_meta=linux-image-cloud-$ARCH
      ;;
    2)
      flavor=cloud-$ARCH
      other_meta=linux-image-$ARCH
      ;;
    *)
      print_error "请输入正确的数字"
      return 1
      ;;
  esac
  meta=linux-image-$flavor

  if ! backports_enabled; then
    echo "deb https://deb.debian.org/debian ${OS_CODENAME}-backports main" >"$APT_SOURCES_DIR/backports.list"
    print_ok "已添加 ${OS_CODENAME}-backports 源"
  fi
  print_info "安装 $meta（${OS_CODENAME}-backports）"
  apt_update || return 1
  DEBIAN_FRONTEND=noninteractive apt-get -y -t "${OS_CODENAME}-backports" install "$meta"
  judge "安装内核"

  # 先确认新内核真的装好了，才删旧内核
  new_pkg=$(dpkg-query -W -f='${Depends}' "$meta" 2>/dev/null | grep -oE 'linux-image-[0-9][^ ,|]*' | head -n1)
  new_ver=${new_pkg#linux-image-}
  if [[ -z $new_ver || ! -f /boot/vmlinuz-$new_ver || ! -f /boot/initrd.img-$new_ver ]]; then
    print_error "没有找到新内核文件，已停止，不会删除任何内核"
    return 1
  fi

  running=$(uname -r)
  mapfile -t remove < <(kernel_packages_to_remove "$new_ver" "$running")
  if dpkg-query -W -f='${db:Status-Abbrev}' "$other_meta" 2>/dev/null | grep -q '^ii'; then
    remove+=("$other_meta")
  fi
  if [[ ${#remove[@]} -gt 0 ]]; then
    print_info "卸载旧内核：${remove[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get -y purge "${remove[@]}"
  fi
  if [[ ! -f /boot/vmlinuz-$new_ver ]]; then
    print_error "新内核文件不见了，千万别重启！"
    return 1
  fi
  command -v update-grub >/dev/null 2>&1 && update-grub >/dev/null 2>&1

  print_ok "新内核：$new_ver（当前运行：$running）"
  if [[ $running == "$new_ver" ]]; then
    print_ok "已经在使用最新内核"
    return 0
  fi
  print_warn "重启后才会使用新内核；重启后再运行一次「更新 Linux 内核」会清理现在这个旧内核"
  read -rp "是否现在重启？[Y/n]：" yn
  if [[ -z $yn || $yn == [Yy] ]]; then
    print_info "正在重启"
    reboot
  fi
}

# ─── 7. BBR ───
install_bbr() {
  local dir
  dir=$(mktemp -d)
  if ! wget -q --connect-timeout=5 --timeout=30 -O "$dir/tcp.sh" "$BBR_SCRIPT_URL"; then
    rm -rf "$dir"
    print_error "BBR 脚本下载失败：$BBR_SCRIPT_URL"
    return 1
  fi
  chmod +x "$dir/tcp.sh"
  (cd "$dir" && bash ./tcp.sh)
  rm -rf "$dir"
}

# ─── 2. 升级脚本 ───
# $1 比 $2 新时返回成功
version_gt() {
  [[ $1 != "$2" && $(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1) == "$1" ]]
}

update_script() {
  local self tmp latest
  if [[ -d $SCRIPT_DIR/.git ]]; then
    print_warn "这是克隆下来的仓库，请在 $SCRIPT_DIR 里用 git pull 更新"
    return 0
  fi
  self=$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")
  if [[ ! -f $self ]]; then
    print_error "找不到脚本文件，请重新下载：wget -N $REPO_RAW/$SCRIPT_NAME"
    return 1
  fi
  print_info "检查最新版本"
  # 下载到同一目录再改名替换，正在运行的脚本不受影响
  tmp=$(mktemp "$SCRIPT_DIR/.$SCRIPT_NAME.XXXXXX") || return 1
  if ! wget -q --timeout=15 --tries=2 -O "$tmp" "$REPO_RAW/$SCRIPT_NAME"; then
    rm -f "$tmp"
    print_error "下载失败，请检查网络"
    return 1
  fi
  latest=$(sed -n 's/^SCRIPT_VERSION="\([^"]*\)".*/\1/p' "$tmp" | head -n1)
  if [[ -z $latest ]] || ! bash -n "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    print_error "下载的脚本不完整，请稍后再试"
    return 1
  fi
  if ! version_gt "$latest" "$SCRIPT_VERSION"; then
    rm -f "$tmp"
    print_ok "已是最新版本 $SCRIPT_VERSION"
    return 0
  fi
  chmod 755 "$tmp"
  mv -f "$tmp" "$self"
  print_ok "已从 $SCRIPT_VERSION 升级到 $latest"
  sleep 1
  exec bash "$self"
}

# ─── 菜单 ───
menu() {
  is_root
  detect_system

  # 标题缩进 3 格
  echo -e "   Mihomo 旁路由一键安装脚本 ${Red}[${SCRIPT_VERSION}]${Font}"
  echo -e "   https://github.com/1432433gg/rules-next"
  echo
  echo -e "—————— 安装 ——————"
  echo -e "${Green}1.${Font}  安装 Mihomo 旁路由"
  echo -e "${Green}2.${Font}  升级 脚本"
  echo -e "—————— 查看信息 ——————"
  echo -e "${Green}3.${Font}  查看服务运行状态"
  echo -e "—————— 其他 ——————"
  echo -e "${Green}4.${Font}  更新 / 指定版本 Mihomo"
  echo -e "${Green}5.${Font}  更新 / 指定版本 面板"
  if [[ $OS_ID == debian ]]; then
    echo -e "${Green}6.${Font}  更新 Linux 内核"
  else
    echo -e "${Green}6.${Font}  更新 Linux 内核（仅 Debian）"
  fi
  echo -e "${Green}7.${Font}  安装 BBR 加速"
  echo -e "${Green}0.${Font}  退出"
  read -rp "请输入数字：" menu_num
  case "$menu_num" in
    1) install_gateway ;;
    2) update_script ;;
    3) show_status ;;
    4) update_mihomo ;;
    5) update_ui ;;
    6) update_kernel ;;
    7) install_bbr ;;
    0) exit 0 ;;
    *) print_error "请输入正确的数字" ;;
  esac
}

# 被 source 时（测试用）不执行菜单
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  menu "$@"
fi
