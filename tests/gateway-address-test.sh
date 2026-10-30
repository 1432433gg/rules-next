#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$TEST_ROOT/gateway.sh"
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gateway-address.XXXXXX")
trap 'rm -rf "$TEST_TMP"' EXIT
MIHOMO_CONF=$TEST_TMP/config.yaml
declare -A LINKS=()
COUNT=0

reset_fixture() {
  unset GATEWAY_LAN_INTERFACE GATEWAY_LAN_IP
  ADDRESSES='2: eth0    inet 192.168.0.3/24 brd 192.168.0.255 scope global eth0'
  ROUTE='8.8.8.8 via 192.168.0.1 dev eth0 src 192.168.0.3 uid 0'
  DEFAULTS='default via 192.168.0.1 dev eth0 proto dhcp metric 100'
  ADDRESS_STATUS=0 ROUTE_STATUS=0 UI_PRESENT=1
  LINKS=([eth0]='2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP link/ether 02:00:00:00:00:01')
  printf 'external-controller: 0.0.0.0:9090\n' >"$MIHOMO_CONF"
  : >"$TEST_TMP/ip.calls"
}

# No network, service or filesystem operation outside the temporary test files.
ip() {
  printf '%s\n' "$*" >>"$TEST_TMP/ip.calls"
  case "$*" in
    '-o -4 addr show up scope global')
      ((ADDRESS_STATUS == 0)) || return "$ADDRESS_STATUS"
      printf '%s\n' "$ADDRESSES" ;;
    '-d -o link show dev '*)
      [[ -n ${LINKS[$6]:-} ]] || return 1
      printf '%s\n' "${LINKS[$6]}" ;;
    '-4 route get 8.8.8.8')
      ((ROUTE_STATUS == 0)) || return "$ROUTE_STATUS"
      printf '%s\n' "$ROUTE" ;;
    '-4 route show table main default') printf '%s\n' "$DEFAULTS" ;;
    *) printf 'Unexpected ip command: %s\n' "$*" >&2; return 99 ;;
  esac
}
ui_installed() { ((UI_PRESENT == 1)); }

equal() {
  local label=$1 expected=$2 actual
  shift 2
  if ! actual=$("$@"); then
    printf 'FAIL: %s (command failed)\n' "$label" >&2
    exit 1
  fi
  if [[ $actual != "$expected" ]]; then
    printf 'FAIL: %s\nExpected: %s\nActual: %s\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
  COUNT=$((COUNT + 1))
}
fails() {
  local label=$1 output
  shift
  if output=$("$@"); then
    printf 'FAIL: %s (unexpected success: %s)\n' "$label" "$output" >&2
    exit 1
  fi
  [[ -z $output ]] || { printf 'FAIL: %s leaked an address\n' "$label" >&2; exit 1; }
  COUNT=$((COUNT + 1))
}
contains() {
  local label=$1 needle=$2 output
  shift 2
  output=$("$@")
  [[ $output == *"$needle"* ]] || { printf 'FAIL: %s\n%s\n' "$label" "$output" >&2; exit 1; }
  COUNT=$((COUNT + 1))
}

reset_fixture
equal 'normal LAN address' 'eth0 192.168.0.3' lan_address
equal 'compatibility helper' '192.168.0.3' lan_ip
equal 'probe is 8.8.8.8' '-4 route get 8.8.8.8' awk '/route get/ {print; exit}' "$TEST_TMP/ip.calls"
equal 'normal panel' 'http://192.168.0.3:9090/ui' panel_url

ADDRESSES+=$'\n3: Meta inet 198.18.0.1/30 scope global Meta\n4: veth123 inet 172.18.0.2/16 scope global veth123'
LINKS[Meta]='3: Meta: <POINTOPOINT,UP,LOWER_UP> link/none tun type tun'
LINKS[veth123]='4: veth123: <UP> link/ether 02:00:00:00:00:04 veth'
ROUTE='8.8.8.8 dev Meta table 2022 src 198.18.0.1 uid 0'
equal 'TUN route falls back to main-table LAN' 'eth0 192.168.0.3' lan_address
equal 'post-start panel remains on LAN' 'http://192.168.0.3:9090/ui' panel_url
contains 'usage names actual interface' '网卡：eth0' show_usage
contains 'usage keeps actual gateway address' '192.168.0.3' show_usage
output=$(show_usage)
[[ $output != *'198.18.0.1'* && $output != *'就能上网'* ]] || exit 1
COUNT=$((COUNT + 1))

ADDRESSES=$'2: eth0 inet 192.168.0.3/24 scope global eth0\n3: customvpn inet 10.7.0.1/24 scope global customvpn'
LINKS[customvpn]='3: customvpn: <UP> link/ether 02:00:00:00:00:05 tun type tap'
ROUTE='8.8.8.8 dev customvpn src 10.7.0.1'
equal 'custom-name TAP with private IP is excluded' 'eth0 192.168.0.3' lan_address

reset_fixture
ROUTE_STATUS=1
equal 'failed probe falls back without network traffic' 'eth0 192.168.0.3' lan_address
DEFAULTS=''
equal 'single candidate works without default route' 'eth0 192.168.0.3' lan_address
ADDRESSES+=$'\n5: ens19 inet 10.0.0.3/24 scope global ens19'
LINKS[ens19]='5: ens19: <UP> link/ether 02:00:00:00:00:06'
fails 'multiple candidates without usable route are ambiguous' lan_address
contains 'ambiguous output lists first candidate' '192.168.0.3（网卡：eth0）' show_usage
contains 'ambiguous output lists second candidate' '10.0.0.3（网卡：ens19）' show_usage
output=$(show_usage)
[[ $output != *'设为'* && $output != *'http://'* ]] || exit 1
COUNT=$((COUNT + 1))
DEFAULTS=$'default via 192.168.0.1 dev eth0\ndefault via 10.0.0.1 dev ens19'
fails 'multiple main-table defaults are not guessed' lan_address
GATEWAY_LAN_INTERFACE=ens19
equal 'explicit interface selects a candidate' 'ens19 10.0.0.3' lan_address
GATEWAY_LAN_IP=192.168.0.3
fails 'mismatched explicit interface and IP do not fall back' lan_address
unset GATEWAY_LAN_INTERFACE
equal 'explicit IP selects owning interface' 'eth0 192.168.0.3' lan_address
GATEWAY_LAN_IP=192.168.0.99
fails 'unassigned explicit IP is rejected' lan_address

reset_fixture
ADDRESSES+=$'\n2: eth0 inet 192.168.0.4/24 scope global secondary eth0'
GATEWAY_LAN_INTERFACE=eth0
fails 'interface with two addresses needs an explicit IP' lan_address
GATEWAY_LAN_IP=192.168.0.4
equal 'secondary address may be explicitly selected' 'eth0 192.168.0.4' lan_address

reset_fixture
ADDRESSES='6: br0 inet 192.168.0.3/24 scope global br0'
LINKS[br0]='6: br0: <UP> link/ether 02:00:00:00:00:07 bridge forward_delay 1500'
ROUTE='8.8.8.8 dev br0 src 192.168.0.3'
equal 'LAN bridge is retained' 'br0 192.168.0.3' lan_address
ADDRESSES='7: ens18.20@ens18 inet 192.168.0.3/24 scope global ens18.20'
LINKS[ens18.20]='7: ens18.20@ens18: <UP> link/ether 02:00:00:00:00:08 vlan protocol 802.1Q id 20'
ROUTE='8.8.8.8 dev ens18.20 src 192.168.0.3'
equal 'VLAN is retained and parent suffix removed' 'ens18.20 192.168.0.3' lan_address

reset_fixture
ROUTE='8.8.8.8 dev eth0 src 10.9.9.9'
equal 'route source must actually belong to interface' 'eth0 192.168.0.3' lan_address
ADDRESSES=$'2: eth0 inet 198.19.0.1/24 scope global eth0\n2: eth0 inet 169.254.0.2/16 scope global eth0\n2: eth0 inet 127.0.0.2/8 scope global eth0'
fails 'internal and link-local addresses are excluded' lan_address
reset_fixture
LINKS=()
fails 'failed link inspection is not treated as usable' lan_address
reset_fixture
ADDRESS_STATUS=1
fails 'failed address query produces no guess' lan_address

reset_fixture
printf 'external-controller: "0.0.0.0:19090" # custom port\n' >"$MIHOMO_CONF"
equal 'quoted controller port' 'http://192.168.0.3:19090/ui' panel_url
printf "external-controller: '192.168.0.3:9091'\n" >"$MIHOMO_CONF"
equal 'explicit binding is respected' 'http://192.168.0.3:9091/ui' panel_url
printf 'external-controller: 127.0.0.1:9090\n' >"$MIHOMO_CONF"
ADDRESS_STATUS=1
equal 'loopback panel works without LAN detection' 'http://127.0.0.1:9090/ui' panel_url
contains 'loopback is clearly labeled' '仅本机' show_panel_url
printf 'external-controller: "[::1]:9090"\n' >"$MIHOMO_CONF"
equal 'IPv6 loopback formatting' 'http://[::1]:9090/ui' panel_url
printf 'external-controller: "[::]:9090"\n' >"$MIHOMO_CONF"
equal 'IPv6 wildcard does not imply IPv4 access' 'http://[::1]:9090/ui' panel_url
printf 'external-controller: 0.0.0.0:70000\n' >"$MIHOMO_CONF"
fails 'out-of-range port rejected' panel_url
printf 'external-controller: "[::]:0"\n' >"$MIHOMO_CONF"
fails 'zero port rejected' panel_url
printf 'external-controller: ::1:9090\n' >"$MIHOMO_CONF"
fails 'unbracketed IPv6 rejected' panel_url
UI_PRESENT=0
equal 'uninstalled panel has no fabricated URL' '' panel_url

reset_fixture
ADDRESSES+=$'\n3: Meta inet 198.18.0.1/30 scope global Meta'
LINKS[Meta]='3: Meta: <UP> link/none tun type tun'
ROUTE='8.8.8.8 dev Meta src 198.18.0.1'
service_state() { printf '运行中'; }
mihomo_current_version() { printf 'test-version'; }
config_state() { printf '检查通过'; }
ui_state() { printf '已安装'; }
forwarding_state() { printf '开启'; }
time_sync_state() { printf '已同步'; }
now_time() { printf 'test-time'; }
congestion_state() { printf 'test-cc'; }
contains 'status shows actual LAN interface after startup' '网卡：eth0' show_status
contains 'status panel uses LAN address after startup' 'http://192.168.0.3:9090/ui' show_status
output=$(show_status)
[[ $output != *'198.18.0.1'* ]] || exit 1
COUNT=$((COUNT + 1))

printf 'PASS: %s address and panel checks\n' "$COUNT"
