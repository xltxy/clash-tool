#!/bin/bash

API="http://127.0.0.1:9090"
CONFIG_DIR="$HOME/.config/clash"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SUB_CONF="$SCRIPT_DIR/sub_url.conf"

echo "======================================"
echo "       更新订阅配置"
echo "======================================"

if [ ! -f "$SUB_CONF" ]; then
    echo "错误: 找不到订阅配置文件"
    echo ""
    echo "请创建文件并设置订阅链接:"
    echo "  $SUB_CONF"
    echo ""
    echo "文件内容示例:"
    echo '  SUB_URL="https://api.dler.io/sub?target=clash&url=YOUR_SUBSCRIPTION_URL"'
    exit 1
fi

source "$SUB_CONF"

if [ -z "$SUB_URL" ] || [ "$SUB_URL" = "https://api.dler.io/sub?target=clash&url=YOUR_SUBSCRIPTION_URL" ]; then
    echo "错误: 请先配置订阅链接"
    echo ""
    echo "编辑文件设置你的订阅:"
    echo "  $SUB_CONF"
    echo ""
    echo "或直接将配置文件放到:"
    echo "  $CONFIG_FILE"
    exit 1
fi

TEMP_FILE=$(mktemp)

echo "正在下载配置..."
http_code=$(curl -s -L -w "%{http_code}" -o "$TEMP_FILE" "$SUB_URL")

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

mv "$TEMP_FILE" "$CONFIG_FILE"

node_count=$(grep -c "^  - {name:" "$CONFIG_FILE" 2>/dev/null || echo "?")
echo "下载成功，共 $node_count 个节点"

echo "正在重启 Clash..."
systemctl --user restart clash
sleep 2

if systemctl --user is-active clash >/dev/null 2>&1; then
    echo "重启成功"
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
node=$(curl -s "$API/proxies/GLOBAL" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('now','?'))" 2>/dev/null)
echo "代理模式: $mode"
echo "当前节点: $node"
echo ""
echo "更新完成!"