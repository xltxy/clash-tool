#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SUBS_DIR="$SCRIPT_DIR/subs"
CURRENT_FLAG="$SUBS_DIR/.current"
LEGACY_CONF="$SCRIPT_DIR/sub_url.conf"
API="http://127.0.0.1:9090"

mkdir -p "$SUBS_DIR"

die() {
    echo "错误: $1" >&2
    exit 1
}

current_name() {
    if [ -f "$CURRENT_FLAG" ]; then
        cat "$CURRENT_FLAG"
    fi
}

sub_file() {
    echo "$SUBS_DIR/$1.conf"
}

get_url() {
    grep -E '^SUB_URL=' "$1" 2>/dev/null | tail -1 | cut -d'"' -f2
}

# 按固定顺序输出所有订阅名称（序号与此顺序一致）
list_names() {
    for f in "$SUBS_DIR"/*.conf; do
        [ -f "$f" ] && basename "$f" .conf
    done
}

# 把输入解析为订阅名称：直接匹配名称，或按 list 显示的序号匹配
resolve_sub() {
    local input=$1
    if [ -f "$(sub_file "$input")" ]; then
        echo "$input"
        return 0
    fi
    if echo "$input" | grep -qE '^[0-9]+$'; then
        local names total
        names=$(list_names)
        total=$(echo "$names" | grep -c .)
        if [ "$input" -ge 1 ] && [ "$input" -le "$total" ]; then
            echo "$names" | sed -n "${input}p"
            return 0
        fi
    fi
    return 1
}

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

# 切换到某订阅后，恢复它上次的节点选择（组和新节点都存在才恢复）
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

# 旧版单订阅配置(sub_url.conf)自动迁移到 subs/ 目录
migrate_legacy() {
    if [ ! -f "$CURRENT_FLAG" ] && [ -f "$LEGACY_CONF" ]; then
        local url
        url=$(get_url "$LEGACY_CONF")
        if [ -z "$url" ] || [ "$url" = "https://api.dler.io/sub?target=clash&url=YOUR_SUBSCRIPTION_URL" ]; then
            return
        fi
        # 从链接路径推导名称，如 .../sabusuku?token=xx -> sabusuku
        local name
        name=$(echo "$url" | sed -E 's#.*://[^/]+/([^/?]+).*#\1#')
        if ! echo "$name" | grep -qE '^[A-Za-z0-9._-]{1,32}$' || [ "$name" = "sub" ]; then
            name="default"
        fi
        if [ ! -f "$(sub_file "$name")" ]; then
            echo "SUB_URL=\"$url\"" > "$(sub_file "$name")"
        fi
        echo "$name" > "$CURRENT_FLAG"
        echo "已迁移旧订阅配置: sub_url.conf -> subs/$name.conf"
    fi
}

list_subs() {
    local cur
    cur=$(current_name)
    local i=0 found=0 name
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        found=1
        i=$((i+1))
        local mark=" "
        [ "$name" = "$cur" ] && mark="*"
        printf "%s %s) %-16s %s\n" "$mark" "$i" "$name" "$(get_url "$(sub_file "$name")")"
    done < <(list_names)
    if [ "$found" -eq 0 ]; then
        echo "(暂无订阅，使用 'clash-tool sub add <名称> <链接>' 添加)"
    else
        echo ""
        echo "(带 * 为当前订阅，'更新订阅' 只更新它)"
    fi
}

add_sub() {
    local name=${1:-} url=${2:-}
    if [ -z "$name" ] || [ -z "$url" ]; then
        echo "用法: clash-tool sub add <名称> <订阅链接>" >&2
        exit 1
    fi
    echo "$name" | grep -qE '^[A-Za-z0-9._-]{1,32}$' || die "名称只能包含字母、数字、点、下划线、中划线 (最长32位)"
    [ -f "$(sub_file "$name")" ] && die "订阅 '$name' 已存在"
    echo "SUB_URL=\"$url\"" > "$(sub_file "$name")"
    if [ ! -f "$CURRENT_FLAG" ]; then
        echo "$name" > "$CURRENT_FLAG"
        echo "已添加订阅 '$name' 并设为当前订阅"
    else
        echo "已添加订阅 '$name'"
    fi
    echo "切换到该订阅: clash-tool sub use $name"
}

use_sub() {
    local input=${1:-} name old
    name=$(resolve_sub "$input") || die "找不到订阅 '$input'，用 'clash-tool sub list' 查看序号和名称"
    old=$(current_name)
    if [ -n "$old" ] && [ "$old" != "$name" ]; then
        save_selections "$old"
    fi
    echo "$name" > "$CURRENT_FLAG"
    echo "当前订阅已切换为: $name"
    echo ""
    if bash "$SCRIPT_DIR/update_sub.sh"; then
        echo "正在恢复该订阅上次的节点选择..."
        apply_selections "$name"
    else
        exit 1
    fi
}

del_sub() {
    local input=${1:-} name
    name=$(resolve_sub "$input") || die "找不到订阅 '$input'"
    rm -f "$(sub_file "$name")" "$SUBS_DIR/$name.nodes.json"
    if [ "$(current_name)" = "$name" ]; then
        local next
        next=$(list_names | head -1)
        if [ -n "$next" ]; then
            echo "$next" > "$CURRENT_FLAG"
            echo "已删除订阅 '$name'，当前订阅变为 '$next'"
        else
            rm -f "$CURRENT_FLAG"
            echo "已删除订阅 '$name'（已无剩余订阅）"
        fi
    else
        echo "已删除订阅 '$name'"
    fi
}

show_current() {
    local cur
    cur=$(current_name)
    if [ -n "$cur" ] && [ -f "$(sub_file "$cur")" ]; then
        echo "当前订阅: $cur"
        echo "链接: $(get_url "$(sub_file "$cur")")"
    else
        echo "未设置当前订阅"
        exit 1
    fi
}

interactive_menu() {
    while true; do
        echo ""
        echo "======================================"
        echo "       订阅管理"
        echo "======================================"
        list_subs
        echo "--------------------------------------"
        echo ""
        echo "1. 切换订阅 (切换后立即更新)"
        echo "2. 添加订阅"
        echo "3. 删除订阅"
        echo "4. 立即更新当前订阅"
        echo "0. 退出"
        echo ""
        echo "--------------------------------------"
        echo "请选择:"
        read -r choice

        case "$choice" in
            1)
                echo "--------------------------------------"
                list_subs
                echo "--------------------------------------"
                echo "输入序号或名称切换 (直接回车取消):"
                read -r input
                [ -n "$input" ] && use_sub "$input"
                ;;
            2)
                echo "输入订阅名称 (如 fsc-75c5):"
                read -r name
                echo "输入订阅链接:"
                read -r url
                add_sub "$name" "$url"
                ;;
            3)
                echo "输入要删除的订阅序号或名称:"
                read -r input
                [ -n "$input" ] && del_sub "$input"
                ;;
            4)
                bash "$SCRIPT_DIR/update_sub.sh"
                ;;
            0|q|Q)
                exit 0
                ;;
            *)
                echo "无效选择"
                ;;
        esac
    done
}

show_help() {
    echo "用法: clash-tool sub [子命令] [参数]"
    echo ""
    echo "子命令:"
    echo "  list               列出所有订阅 (带 * 为当前订阅)"
    echo "  add <名称> <链接>  添加订阅"
    echo "  use <序号|名称>    切换订阅并立即更新"
    echo "  del <序号|名称>    删除订阅"
    echo "  current            查看当前订阅"
    echo ""
    echo "无参数运行进入交互菜单"
}

case "${1:-}" in
    list)
        migrate_legacy
        list_subs
        ;;
    add)
        add_sub "$2" "$3"
        ;;
    use)
        migrate_legacy
        use_sub "$2"
        ;;
    del|remove)
        del_sub "$2"
        ;;
    current)
        migrate_legacy
        show_current
        ;;
    help|--help|-h)
        show_help
        ;;
    "")
        migrate_legacy
        interactive_menu
        ;;
    *)
        echo "未知子命令: $1" >&2
        show_help
        exit 1
        ;;
esac
