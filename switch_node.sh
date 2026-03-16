#!/bin/bash

API="http://127.0.0.1:9090"

get_current_node() {
    curl -s "$API/proxies/GLOBAL" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('now', 'Unknown'))
except:
    print('Unknown')
"
}

get_nodes() {
    curl -s "$API/proxies/GLOBAL" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for name in data.get('all', []):
        if name not in ['DIRECT', 'REJECT', 'Proxy']:
            print(name)
except:
    pass
"
}

switch_node() {
    local node="$1"
    echo "$node" | python3 -c "
import sys, json, urllib.request
node = sys.stdin.read().strip()
data = json.dumps({'name': node}).encode()
req = urllib.request.Request('$API/proxies/GLOBAL', data=data, method='PUT')
req.add_header('Content-Type', 'application/json')
try:
    urllib.request.urlopen(req, timeout=5)
except Exception as e:
    print(f'Error: {e}')
"
}

current=$(get_current_node)
echo "======================================"
echo "       Clash 节点切换"
echo "======================================"
echo "当前节点: $current"
echo "--------------------------------------"

nodes=()
i=1
while IFS= read -r node; do
    [ -z "$node" ] && continue
    if [ "$node" = "$current" ]; then
        printf "\033[32m%2d. %s (当前)\033[0m\n" "$i" "$node"
    else
        printf "%2d. %s\n" "$i" "$node"
    fi
    nodes+=("$node")
    ((i++))
done < <(get_nodes)

if [ ${#nodes[@]} -eq 0 ]; then
    echo ""
    echo "没有可用节点，请检查配置"
    exit 1
fi

echo ""
echo "--------------------------------------"
echo "输入序号选择节点 (q 退出):"
read -r choice

if [ "$choice" = "q" ] || [ -z "$choice" ]; then
    echo "已取消"
    exit 0
fi

if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#nodes[@]} ]; then
    echo "无效选择"
    exit 1
fi

selected="${nodes[$((choice-1))]}"

result=$(switch_node "$selected")

if [ -n "$result" ]; then
    echo "切换失败: $result"
    exit 1
fi

echo ""
echo "已切换到: $selected"

new_current=$(get_current_node)
echo "当前节点: $new_current"