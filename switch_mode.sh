#!/bin/bash

API="http://127.0.0.1:9090"

get_current_mode() {
    curl -s "$API/configs" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('mode', 'Unknown'))
except:
    print('Unknown')
"
}

set_mode() {
    local mode=$1
    curl -s -X PATCH -H "Content-Type: application/json" -d "{\"mode\":\"$mode\"}" "$API/configs" >/dev/null 2>&1
}

current=$(get_current_mode)
echo "======================================"
echo "       Clash 代理模式切换"
echo "======================================"
echo "当前模式: $current"
echo "--------------------------------------"
echo ""
echo "1. rule   - 规则模式 (推荐)"
echo "2. global - 全局模式"
echo "3. direct - 直连模式"
echo ""
echo "--------------------------------------"
echo "输入序号选择模式 (q 退出):"
read -r choice

case "$choice" in
    1)
        set_mode "rule"
        echo "已切换到: 规则模式"
        ;;
    2)
        set_mode "global"
        echo "已切换到: 全局模式"
        ;;
    3)
        set_mode "direct"
        echo "已切换到: 直连模式"
        ;;
    q|Q)
        echo "已取消"
        exit 0
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

sleep 1
new_mode=$(get_current_mode)
echo "当前模式: $new_mode"