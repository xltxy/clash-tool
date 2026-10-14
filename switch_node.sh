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
    curl -s "$API/proxies" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
proxies = data.get('proxies', {})
group_types = {'Selector', 'URLTest', 'Fallback'}
skip = ('DIRECT', 'REJECT', 'Proxy', 'COMPATIBLE', 'Compatible')
for name, info in proxies.items():
    if name in skip:
        continue
    if info.get('type') in group_types:
        continue
    if info.get('type') in ('Direct', 'Reject', 'Compatible'):
        continue
    print(name)
"
}

get_switchable_groups() {
    curl -s "$API/proxies" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for name, info in data.get('proxies', {}).items():
    if info.get('type') in ('Selector', 'URLTest', 'Fallback'):
        if 'all' in info:
            print(name)
"
}

switch_node() {
    local node="$1"
    get_switchable_groups | python3 -c "
import sys, json, urllib.request, time
node = sys.argv[1]
groups = [g for g in (line.strip() for line in sys.stdin) if g]
errors = []
ok = []
for g in groups:
    data = json.dumps({'name': node}).encode()
    req = urllib.request.Request('$API/proxies/' + urllib.parse.quote(g), data=data, method='PUT')
    req.add_header('Content-Type', 'application/json')
    def do():
        return urllib.request.urlopen(req, timeout=10)
    try:
        do()
        ok.append(g)
    except Exception as e:
        # URLTest/Fallback groups may report transient 400 right after switch;
        # retry once after a short pause
        time.sleep(0.5)
        try:
            do()
            ok.append(g)
        except Exception as e2:
            errors.append(f'{g}: {e2}')
if errors and not ok:
    print('ALL_FAILED: ' + '; '.join(errors))
elif errors:
    print('PARTIAL: ' + '; '.join(errors))
" "$node"
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

if echo "$result" | grep -q "^ALL_FAILED:"; then
    echo "切换失败: ${result#ALL_FAILED: }"
    exit 1
fi

if echo "$result" | grep -q "^PARTIAL:"; then
    echo "部分组切换失败: ${result#PARTIAL: }"
fi

echo ""
echo "已切换到: $selected"

new_current=$(get_current_node)
echo "当前节点(GLOBAL): $new_current"

groups=$(get_switchable_groups)
if [ -n "$groups" ]; then
    echo "所有组状态:"
    while IFS= read -r g; do
        [ -z "$g" ] && continue
        n=$(curl -s "$API/proxies/$g" 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin).get('now','?'))" 2>/dev/null)
        echo "  $g -> $n"
    done <<< "$groups"
fi