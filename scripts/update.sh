#!/usr/bin/env bash
# 按 sources.txt 下载最新规则到 rules/，再把 custom/ 里同名文件的规则追加进去。
# 先全部下载到临时目录并逐个检查，有任何一个下载失败或内容不像规则，就整体放弃，rules/ 保持原样。
# 加参数 qx：按 quantumultx/sources.txt 生成 quantumultx/rules/，custom/ 里的规则自动转成 Quantumult X 格式。
set -euo pipefail

cd "$(dirname "$0")/.."
FORMAT=${1:-mihomo}
case $FORMAT in
  mihomo) SOURCES=${SOURCES:-sources.txt} RULES_DIR=${RULES_DIR:-rules} ;;
  qx) SOURCES=${SOURCES:-quantumultx/sources.txt} RULES_DIR=${RULES_DIR:-quantumultx/rules} ;;
  *) echo "用法：$0 [mihomo|qx]" >&2; exit 1 ;;
esac
CUSTOM_DIR=${CUSTOM_DIR:-custom}

RULE_LINE='^[A-Z][A-Z0-9-]*,'
OK_LINE='^[[:space:]]*$|^[[:space:]]*#|^[A-Z][A-Z0-9-]*,'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 每一行只能是空行、注释或规则（大写类型开头，比如 DOMAIN-SUFFIX,xxx），至少要有一条规则
check_rules() {
  local file=$1 label=$2
  if grep -vqE "$OK_LINE" "$file"; then
    echo "内容不像规则文件：$label" >&2
    grep -vnE "$OK_LINE" "$file" | head -3 >&2
    return 1
  fi
  if ! grep -qE "$RULE_LINE" "$file"; then
    echo "没有任何规则：$label" >&2
    return 1
  fi
}

# Mihomo 格式转 Quantumult X 格式：DOMAIN-SUFFIX,a.com → HOST-SUFFIX,a.com,名称；QX 不支持的类型（PROCESS-NAME 等）去掉
to_qx() {
  awk -F, -v name="$2" '
    { sub(/\r$/, "") }
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { print; next }
    {
      t = $1; v = $2
      if (t == "DOMAIN") t = "HOST"
      else if (t == "DOMAIN-SUFFIX") t = "HOST-SUFFIX"
      else if (t == "DOMAIN-KEYWORD") t = "HOST-KEYWORD"
      else if (t == "DOMAIN-WILDCARD") t = "HOST-WILDCARD"
      else if (t == "IP-CIDR6") t = "IP6-CIDR"
      else if (t != "IP-CIDR" && t != "IP-ASN") next
      print t "," v "," name
    }' "$1"
}

# 最后一行没有换行也要读到；在 Windows 上编辑过的 \r 去掉
while read -r name url _ || [[ -n ${name:-} ]]; do
  name=${name%$'\r'}
  url=${url%$'\r'}
  [[ -z ${name:-} || $name == \#* ]] && continue
  if [[ ! $name =~ ^[A-Za-z0-9_-]+$ || -z ${url:-} ]]; then
    echo "$SOURCES 格式不对：$name $url" >&2
    exit 1
  fi
  if ! curl -fsSL --retry 3 --retry-delay 5 --max-time 120 -o "$tmp/$name.list" "$url"; then
    echo "下载失败：$name  $url" >&2
    exit 1
  fi
  check_rules "$tmp/$name.list" "$name  $url" || exit 1
done <"$SOURCES"

# custom/名称.list：追加到同名规则后面；sources.txt 里没有这个名称的，就单独作为一个规则文件
shopt -s nullglob
for file in "$CUSTOM_DIR"/*.list; do
  name=$(basename "$file" .list)
  if [[ ! $name =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "custom 文件名只能用字母、数字、_ 和 -：$file" >&2
    exit 1
  fi
  check_rules "$file" "$file" || exit 1
  {
    if [[ -f $tmp/$name.list ]]; then
      cat "$tmp/$name.list"
      echo
    fi
    if [[ $FORMAT == qx ]]; then
      to_qx "$file" "$name"
    else
      cat "$file"
    fi
  } >"$tmp/$name.merged"
  mv "$tmp/$name.merged" "$tmp/$name.list"
done

count=0
for file in "$tmp"/*.list; do
  # 上游以后自己加上了同样的规则时，去掉重复的那条（保留第一次出现的）
  awk -v re="$RULE_LINE" '$0 !~ re || !seen[$0]++' "$file" >"$file.dedup"
  mv "$file.dedup" "$file"
  echo "$(basename "$file" .list)：$(grep -cE "$RULE_LINE" "$file") 条"
  count=$((count + 1))
done

if [[ $count -eq 0 ]]; then
  echo "没有任何规则文件" >&2
  exit 1
fi

# 全部通过才替换；sources.txt 和 custom/ 里都没有的规则，文件也一起删掉
mkdir -p "$RULES_DIR"
rm -f "$RULES_DIR"/*.list
cp "$tmp"/*.list "$RULES_DIR"/
echo "共 $count 个规则文件"
