#!/bin/bash

API="http://127.0.0.1:9090"
TIMEOUT=8
TEST_URL="https://www.gstatic.com/generate_204"
CONCURRENT=10

echo "======================================"
echo "       Clash 节点延迟测试"
echo "======================================"

nodes=$(curl -s "$API/proxies" 2>/dev/null)
if [ -z "$nodes" ]; then
    echo "错误: 无法连接到 Clash API"
    exit 1
fi

node_names=$(echo "$nodes" | python3 -c "
import sys, json
data = json.load(sys.stdin)
proxies = data.get('proxies', {})
for name in proxies:
    p = proxies[name]
    if p.get('type') not in ['Selector', 'URLTest', 'Fallback', 'Direct', 'Reject', 'RejectDrop', 'Pass', 'Compatible']:
        print(name)
")

total=$(echo "$node_names" | wc -l)
echo "共 $total 个节点，并发数: $CONCURRENT"
echo "正在测试..."
echo ""

RESULT_FILE=$(mktemp)

test_node() {
    local node="$1"
    local encoded=$(echo "$node" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))")
    local result=$(curl -s -m $TIMEOUT "$API/proxies/$encoded/delay?timeout=$((TIMEOUT*1000))&url=$TEST_URL" 2>/dev/null)
    
    if echo "$result" | grep -q '"delay"'; then
        local delay=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('delay', 'N/A'))")
        echo "$node:$delay" >> "$RESULT_FILE"
        printf "\033[32m%-40s %sms\033[0m\n" "$node" "$delay"
    else
        printf "\033[31m%-40s 超时\033[0m\n" "$node"
    fi
}

count=0
while IFS= read -r node; do
    [ -z "$node" ] && continue
    test_node "$node" &
    ((count++))
    if [ $count -ge $CONCURRENT ]; then
        wait -n
        ((count--))
    fi
done <<< "$node_names"

wait

echo ""
echo "======================================"
echo "可用节点列表 (按延迟排序):"
echo "======================================"

if [ -s "$RESULT_FILE" ]; then
    IFS=$'\n' sorted=($(sort -t: -k2 -n "$RESULT_FILE"))
    
    i=1
    for item in "${sorted[@]}"; do
        name=$(echo "$item" | cut -d: -f1)
        delay=$(echo "$item" | cut -d: -f2)
        printf "%2d. %-38s %sms\n" "$i" "$name" "$delay"
        ((i++))
    done
    
    echo ""
    echo "总共 ${#sorted[@]} 个可用节点"
else
    echo "没有可用节点"
fi

rm -f "$RESULT_FILE"