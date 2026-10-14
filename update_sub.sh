#!/bin/bash

API="http://127.0.0.1:9090"
CONFIG_DIR="$HOME/.config/clash"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# 多订阅：更新 subs/.current 指向的订阅；未迁移时兼容旧版 sub_url.conf
SUBS_DIR="$SCRIPT_DIR/subs"
SUB_CONF="$SCRIPT_DIR/sub_url.conf"
if [ -f "$SUBS_DIR/.current" ]; then
    _sub_name="$(cat "$SUBS_DIR/.current" 2>/dev/null)"
    if [ -n "$_sub_name" ] && [ -f "$SUBS_DIR/$_sub_name.conf" ]; then
        SUB_CONF="$SUBS_DIR/$_sub_name.conf"
    fi
fi
mkdir -p "$SUBS_DIR"
RUNNING_FILE="$SUBS_DIR/.running"

# 保存某订阅当前在 Clash 中的节点选择（组名 -> 节点名），存为 subs/<名称>.nodes.json
# API 不可达时不覆盖旧文件，避免停机时把记忆清掉
save_selections() {
    local name=$1 tmp
    tmp=$(mktemp)
    if curl -s --max-time 5 "$API/proxies" 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)['proxies']
sel = {n: p['now'] for n, p in d.items() if 'all' in p and 'now' in p}
print(json.dumps(sel, ensure_ascii=False, indent=2))
" > "$tmp" && [ -s "$tmp" ]; then
        mv "$tmp" "$SUBS_DIR/$name.nodes.json"
    fi
    rm -f "$tmp"
}

# 恢复某订阅上次的节点选择（组和新节点都存在才恢复）
apply_selections() {
    local name=$1 file
    file="$SUBS_DIR/$name.nodes.json"
    [ -f "$file" ] || return 0
    python3 - "$file" <<'PYEOF'
import sys, json, urllib.parse, urllib.request
try:
    sel = json.load(open(sys.argv[1]))
    d = json.load(urllib.request.urlopen("http://127.0.0.1:9090/proxies", timeout=8))["proxies"]
    restored = 0
    for g, node in sel.items():
        p = d.get(g)
        if not p or "all" not in p or node not in p["all"] or p.get("now") == node:
            continue
        r = urllib.request.Request(
            "http://127.0.0.1:9090/proxies/" + urllib.parse.quote(g, safe=""),
            data=json.dumps({"name": node}).encode(),
            method="PUT",
            headers={"Content-Type": "application/json"})
        urllib.request.urlopen(r, timeout=8)
        print("  已恢复: " + g + " -> " + node)
        restored += 1
    if restored == 0:
        print("  (该订阅无需要恢复的节点选择)")
except Exception as e:
    print("  (恢复节点选择失败: %s)" % e)
PYEOF
}

echo "======================================"
echo "       更新订阅配置"
echo "======================================"

if [ ! -f "$SUB_CONF" ]; then
    echo "错误: 找不到订阅配置文件"
    echo ""
    echo "可用以下任一方式配置订阅:"
    echo "  1. 添加订阅: clash-tool sub add <名称> <订阅链接>"
    echo "  2. 旧版方式: 创建 $SCRIPT_DIR/sub_url.conf"
    exit 1
fi

source "$SUB_CONF"

if [ -z "$SUB_URL" ] || [ "$SUB_URL" = "https://api.dler.io/sub?target=clash&url=YOUR_SUBSCRIPTION_URL" ]; then
    echo "错误: 当前订阅 ($SUB_CONF) 未配置订阅链接"
    echo ""
    echo "切换订阅: clash-tool sub use <名称>"
    echo "查看列表: clash-tool sub list"
    exit 1
fi

TEMP_FILE=$(mktemp)

echo "正在下载配置..."
# 部分机场根据 UA 返回格式：带 clash 的 UA 返回 Clash YAML，否则返回 base64 节点列表
UA="clash-verge/v1.7.7"
http_code=$(curl -A "$UA" -s -L -w "%{http_code}" -o "$TEMP_FILE" "$SUB_URL")

if [ "$http_code" != "200" ]; then
    # 部分订阅域名无法通过代理访问，回退为直连下载
    http_code=$(curl --noproxy '*' -A "$UA" -s -L -w "%{http_code}" -o "$TEMP_FILE" "$SUB_URL")
fi

if [ "$http_code" != "200" ]; then
    echo "下载失败: HTTP $http_code"
    rm -f "$TEMP_FILE"
    exit 1
fi

if [ ! -s "$TEMP_FILE" ]; then
    echo "下载失败: 文件为空"
    rm -f "$TEMP_FILE"
    exit 1
fi

if ! grep -q "^proxies:" "$TEMP_FILE" 2>/dev/null; then
    echo "下载失败: 不是有效的 Clash 配置文件"
    rm -f "$TEMP_FILE"
    exit 1
fi

if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
    echo "已备份旧配置到: $CONFIG_FILE.bak"
fi

# 本机 .bashrc 与 clash-tool 依赖 socks5://127.0.0.1:7891，若订阅配置缺失则补上
if ! grep -q "^socks-port:" "$TEMP_FILE"; then
    if grep -q "^mixed-port:" "$TEMP_FILE"; then
        sed -i "/^mixed-port:/a socks-port: 7891" "$TEMP_FILE"
    else
        sed -i "1i socks-port: 7891" "$TEMP_FILE"
    fi
fi

# 安全加固：仅允许回环/内网来源访问代理端口，防止公网直连 7890/7891
# 172.16.0.0/12 覆盖全部 Docker 网桥（含 new-api 的 172.21.0.0/16 和 sub2api 的 172.26.0.1，
# 显式列出仅为醒目）；10.100.0.0/24 为 WireGuard
if ! grep -q "^lan-allowed-ips:" "$TEMP_FILE"; then
    sed -i "/^socks-port:/a lan-allowed-ips:\n    - 127.0.0.1/8\n    - ::1/128\n    - 172.16.0.0/12\n    - 172.21.0.0/16\n    - 172.26.0.1/32\n    - 10.100.0.0/24" "$TEMP_FILE"
fi

# 保持节点选择：订阅配置自带 profile 时以其为准，否则补上，避免更新/重启后丢失所选节点
if ! grep -q "^profile:" "$TEMP_FILE"; then
    sed -i "/^lan-allowed-ips:/i profile:\n    store-selected: true" "$TEMP_FILE"
fi

# 自定义直连规则：插到 rules 最前，保证优先于订阅自带规则
if grep -q "^rules:" "$TEMP_FILE"; then
    sed -i "/^rules:/a\    - 'DOMAIN-SUFFIX,xltxy.top,DIRECT'\n    - 'DOMAIN-SUFFIX,cn,DIRECT'\n    - 'DOMAIN-SUFFIX,z.ai,DIRECT'" "$TEMP_FILE"
fi

# 本次更新会替换正在运行的配置：先把运行中订阅的节点选择存档
running_name="$(cat "$RUNNING_FILE" 2>/dev/null)"
if [ -n "$running_name" ] && [ -n "$_sub_name" ] && [ "$running_name" != "$_sub_name" ]; then
    save_selections "$running_name"
fi

mv "$TEMP_FILE" "$CONFIG_FILE"

node_count=$(grep -cE "^[[:space:]]*- (name:|\{ ?name:)" "$CONFIG_FILE" 2>/dev/null || echo "?")
echo "下载成功，共 $node_count 个节点"

echo "正在重启 Clash..."
systemctl --user restart clash
sleep 2

if systemctl --user is-active clash >/dev/null 2>&1; then
    echo "重启成功"
    # 记录正在运行的订阅；换了订阅则恢复它上次的节点选择
    if [ -n "$_sub_name" ]; then
        echo "$_sub_name" > "$RUNNING_FILE"
        if [ -n "$running_name" ] && [ "$running_name" != "$_sub_name" ]; then
            echo "正在恢复该订阅上次的节点选择..."
            apply_selections "$_sub_name"
        fi
    fi
else
    echo "重启失败，正在恢复旧配置..."
    if [ -f "$CONFIG_FILE.bak" ]; then
        mv "$CONFIG_FILE.bak" "$CONFIG_FILE"
        systemctl --user restart clash
        echo "已恢复旧配置"
    fi
    exit 1
fi

mode=$(curl -s "$API/configs" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('mode','?'))" 2>/dev/null)
echo "代理模式: $mode"
echo "各代理组当前节点:"
curl -s "$API/proxies" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)['proxies']
    for name, p in d.items():
        if name != 'GLOBAL' and 'all' in p:
            print('  ' + name + ': ' + p.get('now', '?'))
except:
    pass
"
echo ""
echo "更新完成!"