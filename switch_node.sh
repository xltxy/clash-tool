#!/bin/bash

API="http://127.0.0.1:9090"

# 列出可切换的代理组: 名称<TAB>类型<TAB>当前节点
get_groups() {
    curl -s "$API/proxies" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)['proxies']
    tag = {'Selector': '手动', 'URLTest': '自动', 'Fallback': '兜底'}
    for name, p in d.items():
        if name == 'GLOBAL' or 'all' not in p:
            continue
        print(name + '\t' + tag.get(p.get('type'), p.get('type', '?')) + '\t' + p.get('now', '?'))
except:
    pass
"
}

# 列出组内可选节点
get_group_nodes() {
    python3 - "$1" <<'PYEOF'
import sys, json, urllib.parse, urllib.request
u = "http://127.0.0.1:9090/proxies/" + urllib.parse.quote(sys.argv[1], safe="")
p = json.load(urllib.request.urlopen(u, timeout=8))
for n in p.get('all', []):
    print(n)
PYEOF
}

get_group_now() {
    python3 - "$1" <<'PYEOF'
import sys, json, urllib.parse, urllib.request
u = "http://127.0.0.1:9090/proxies/" + urllib.parse.quote(sys.argv[1], safe="")
p = json.load(urllib.request.urlopen(u, timeout=8))
print(p.get('now', '?'))
PYEOF
}

switch_group_node() {
    python3 - "$1" "$2" <<'PYEOF'
import sys, json, urllib.parse, urllib.request
r = urllib.request.Request(
    "http://127.0.0.1:9090/proxies/" + urllib.parse.quote(sys.argv[1], safe=""),
    data=json.dumps({"name": sys.argv[2]}).encode(),
    method="PUT",
    headers={"Content-Type": "application/json"})
urllib.request.urlopen(r, timeout=10)
PYEOF
}

while true; do
    echo ""
    echo "======================================"
    echo "       Clash 节点切换 (按代理组)"
    echo "======================================"

    groups=()
    i=1
    while IFS=$'\t' read -r g t n; do
        [ -z "$g" ] && continue
        printf "%2d. %-14s [%s] 当前: %s\n" "$i" "$g" "$t" "$n"
        groups+=("$g")
        ((i++))
    done < <(get_groups)

    if [ ${#groups[@]} -eq 0 ]; then
        echo "没有可切换的代理组，请检查 Clash 是否运行"
        exit 1
    fi

    echo ""
    echo "--------------------------------------"
    echo "输入序号选择代理组 (q 退出):"
    read -r choice
    case "$choice" in
        q|Q|"") exit 0 ;;
    esac
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#groups[@]} ]; then
        echo "无效选择"
        continue
    fi
    group="${groups[$((choice-1))]}"

    echo ""
    echo "代理组: $group"
    now=$(get_group_now "$group")
    nodes=()
    i=1
    while IFS= read -r n; do
        [ -z "$n" ] && continue
        if [ "$n" = "$now" ]; then
            printf "\033[32m%2d. %s (当前)\033[0m\n" "$i" "$n"
        else
            printf "%2d. %s\n" "$i" "$n"
        fi
        nodes+=("$n")
        ((i++))
    done < <(get_group_nodes "$group")

    if [ ${#nodes[@]} -eq 0 ]; then
        echo "该组没有可选节点"
        continue
    fi

    echo ""
    echo "--------------------------------------"
    echo "输入序号选择节点 (q 退出, b 返回选组):"
    read -r nchoice
    case "$nchoice" in
        q|Q|"") exit 0 ;;
        b|B) continue ;;
    esac
    if ! [[ "$nchoice" =~ ^[0-9]+$ ]] || [ "$nchoice" -lt 1 ] || [ "$nchoice" -gt ${#nodes[@]} ]; then
        echo "无效选择"
        continue
    fi
    node="${nodes[$((nchoice-1))]}"

    if switch_group_node "$group" "$node" 2>/dev/null; then
        echo "已切换: $group -> $node"
        echo "其他代理组不受影响"
    else
        echo "切换失败: $group -> $node"
    fi
done
