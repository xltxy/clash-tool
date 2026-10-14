#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
API="http://127.0.0.1:9090"

is_clash_running() {
    systemctl --user is-active clash >/dev/null 2>&1
}

start_clash() {
    if is_clash_running; then
        echo "Clash 已在运行中" >&2
    else
        echo "正在启动 Clash..." >&2
        systemctl --user start clash
        sleep 1
        if is_clash_running; then
            echo "Clash 启动成功" >&2
        else
            echo "Clash 启动失败" >&2
            return 1
        fi
    fi
}

stop_clash() {
    if is_clash_running; then
        echo "正在停止 Clash..." >&2
        systemctl --user stop clash
        echo "Clash 已停止" >&2
    else
        echo "Clash 未在运行" >&2
    fi
}

restart_clash() {
    echo "正在重启 Clash..." >&2
    systemctl --user restart clash
    sleep 1
    if is_clash_running; then
        echo "Clash 重启成功" >&2
    else
        echo "Clash 重启失败" >&2
        return 1
    fi
}

check_clash() {
    if ! curl -s "$API" >/dev/null 2>&1; then
        echo "错误: Clash 未运行或 API 不可访问"
        echo "请先启动 Clash: clash-tool start 或 systemctl --user start clash"
        exit 1
    fi
}

check_clash_soft() {
    if ! curl -s "$API" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

show_groups() {
    curl -s "$API/proxies" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)['proxies']
    for name, p in d.items():
        if name != 'GLOBAL' and 'all' in p:
            print(name + ': ' + p.get('now', '?'))
except:
    pass
"
}

show_status() {
    echo "======================================"
    echo "       Clash 状态信息"
    echo "======================================"

    mode=$(curl -s "$API/configs" 2>/dev/null | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('mode', 'Unknown'))
except:
    print('Unknown')
")

    echo "代理模式: $mode"
    echo ""
    echo "各代理组当前节点:"
    show_groups
    echo ""
    
    echo "测试连接..."
    ip=$(curl -x http://127.0.0.1:7890 -s --connect-timeout 5 http://ip.sb 2>/dev/null)
    if [ -n "$ip" ]; then
        echo "出口 IP: $ip"
        echo -e "状态: \033[32m正常\033[0m"
    else
        echo -e "状态: \033[31m连接失败\033[0m"
    fi
}

PROXY_HOST="127.0.0.1"
PROXY_PORT="7890"
SOCKS_PORT="7891"
PROXY_STATUS_FILE="$HOME/.config/clash/proxy_status"

set_proxy() {
    if ! is_clash_running; then
        start_clash || return 1
        for i in {1..10}; do
            if check_clash_soft; then
                break
            fi
            sleep 0.5
        done
    fi
    echo "on" > "$PROXY_STATUS_FILE"
    echo "export http_proxy=\"http://$PROXY_HOST:$PROXY_PORT\""
    echo "export https_proxy=\"http://$PROXY_HOST:$PROXY_PORT\""
    echo "export all_proxy=\"socks5://$PROXY_HOST:$SOCKS_PORT\""
    echo "export no_proxy=\"localhost,127.0.0.1,::1\""
    echo "系统代理已开启" >&2
}

unset_proxy() {
    rm -f "$PROXY_STATUS_FILE"
    echo "unset http_proxy https_proxy all_proxy"
    echo "系统代理已关闭" >&2
}

unset_proxy_all() {
    rm -f "$PROXY_STATUS_FILE"
    echo "unset http_proxy https_proxy all_proxy"
    stop_clash
}

show_proxy_status() {
    if [ -n "$http_proxy" ]; then
        echo -e "系统代理: \033[32m已开启\033[0m"
    elif [ -f "$PROXY_STATUS_FILE" ]; then
        echo -e "系统代理: \033[33m已开启 (当前终端未生效)\033[0m"
        echo "  提示: 执行 'proxy on' 或重新打开终端"
    else
        echo -e "系统代理: \033[31m已关闭\033[0m"
    fi
}

show_help() {
    echo "用法: clash-tool [命令]"
    echo ""
    echo "命令:"
    echo "  start       启动 Clash 服务"
    echo "  stop        停止 Clash 服务"
    echo "  restart     重启 Clash 服务"
    echo "  test        测试所有节点延迟 (并发)"
    echo "  node        选择代理组并切换其中节点"
    echo "  mode        切换代理模式"
    echo "  sub         管理订阅 (list/add/use/del)"
    echo "  update      更新当前订阅"
    echo "  status      查看当前状态"
    echo "  proxy on    开启系统代理 (自动启动 Clash)"
    echo "  proxy off   关闭系统代理"
    echo "  proxy stop  关闭代理并停止 Clash"
    echo "  help        显示帮助信息"
    echo ""
    echo "无参数运行将进入交互菜单"
    echo ""
    echo "快捷使用 (推荐):"
    echo "  在 ~/.bashrc 添加: proxy() { eval \$(clash-tool proxy \"\$@\"); }"
    echo "  即可直接使用: proxy on / proxy off"
    echo ""
    echo "说明:"
    echo "  - 开启代理后，新终端会自动加载代理设置"
    echo "  - 使用 'proxy off' 关闭代理后，新终端将不再自动加载"
}

interactive_menu() {
    while true; do
        echo ""
        echo "======================================"
        echo "       Clash 管理工具"
        echo "======================================"
        
        if is_clash_running; then
            echo -e "Clash 服务: \033[32m运行中\033[0m"
            mode=$(curl -s "$API/configs" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('mode','?'))" 2>/dev/null)
            echo "模式: $mode"
            show_groups
        else
            echo -e "Clash 服务: \033[31m已停止\033[0m"
        fi
        show_proxy_status
        echo "--------------------------------------"
        echo ""
        echo "1. 测试节点延迟"
        echo "2. 切换代理节点"
        echo "3. 切换代理模式"
        echo "4. 查看状态信息"
        echo "5. 更新订阅配置"
        echo "6. 开启系统代理"
        echo "7. 关闭系统代理"
        echo "8. 启动/停止 Clash 服务"
        echo "9. 管理订阅 (多订阅切换)"
        echo "0. 退出"
        echo ""
        echo "--------------------------------------"
        echo "请选择:"
        read -r choice
        
        case "$choice" in
            1)
                bash "$SCRIPT_DIR/test_nodes.sh"
                ;;
            2)
                bash "$SCRIPT_DIR/switch_node.sh"
                ;;
            3)
                bash "$SCRIPT_DIR/switch_mode.sh"
                ;;
            4)
                show_status
                ;;
            5)
                bash "$SCRIPT_DIR/update_sub.sh"
                ;;
            6)
                echo "提示: 在终端执行 'proxy on' 开启代理"
                echo "       新终端会自动加载代理设置"
                ;;
            7)
                echo "提示: 在终端执行 'proxy off' 关闭代理"
                echo "       执行 'proxy stop' 可同时停止 Clash 服务"
                ;;
            8)
                if is_clash_running; then
                    stop_clash
                else
                    start_clash
                fi
                ;;
            9)
                bash "$SCRIPT_DIR/subs.sh"
                ;;
            0|q|Q)
                echo "再见!"
                exit 0
                ;;
            *)
                echo "无效选择"
                ;;
        esac
    done
}

case "${1:-}" in
    start)
        start_clash
        ;;
    stop)
        stop_clash
        ;;
    restart)
        restart_clash
        ;;
    test)
        check_clash
        bash "$SCRIPT_DIR/test_nodes.sh"
        ;;
    node)
        check_clash
        bash "$SCRIPT_DIR/switch_node.sh"
        ;;
    mode)
        check_clash
        bash "$SCRIPT_DIR/switch_mode.sh"
        ;;
    sub)
        shift
        bash "$SCRIPT_DIR/subs.sh" "$@"
        ;;
    update)
        bash "$SCRIPT_DIR/update_sub.sh"
        ;;
    status)
        check_clash
        show_status
        ;;
    proxy)
        case "${2:-}" in
            on)
                set_proxy
                ;;
            off)
                unset_proxy
                ;;
            stop)
                unset_proxy_all
                ;;
            *)
                show_proxy_status
                ;;
        esac
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        interactive_menu
        ;;
esac