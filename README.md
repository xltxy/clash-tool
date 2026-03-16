# Clash Tool

一个简洁高效的 Clash 代理管理工具，支持命令行和交互菜单两种使用方式。

## 功能特性

- 系统代理一键开关，新终端自动加载代理设置
- 节点延迟并发测试，快速筛选最优节点
- 交互式节点切换和代理模式切换
- 订阅配置更新，自动重载
- Clash 服务管理（启动/停止/重启）
- 多用户支持，每个用户独立配置

## 安装

```bash
# 克隆仓库
git clone https://github.com/xltxy/clash-tool.git ~/clash

# 创建软链接
ln -s ~/clash/clash.sh ~/.local/bin/clash-tool

# 添加快捷命令到 ~/.bashrc
cat >> ~/.bashrc << 'EOF'

# Clash Proxy
proxy() { eval $(clash-tool proxy "$@"); }
export PATH="$HOME/.local/bin:$PATH"

if [ -f ~/.config/clash/proxy_status ]; then
    export http_proxy="http://127.0.0.1:7890"
    export https_proxy="http://127.0.0.1:7890"
    export all_proxy="socks5://127.0.0.1:7891"
    export no_proxy="localhost,127.0.0.1,::1"
fi
EOF

source ~/.bashrc
```

### 配置 systemd 服务

创建服务文件 `~/.config/systemd/user/clash.service`：

```ini
[Unit]
Description=Clash Proxy
After=network.target

[Service]
Type=simple
ExecStart=%h/.local/bin/clash -d %h/.config/clash
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

启用服务：

```bash
systemctl --user daemon-reload
systemctl --user enable --now clash
```

## 使用方法

### 快捷命令（推荐）

```bash
proxy on      # 开启系统代理（自动启动 Clash）
proxy off     # 关闭系统代理
proxy stop    # 关闭代理并停止 Clash 服务
```

开启代理后，新打开的终端会自动加载代理设置。

### 命令行

```bash
clash-tool start       # 启动 Clash 服务
clash-tool stop        # 停止 Clash 服务
clash-tool restart     # 重启 Clash 服务
clash-tool test        # 测试所有节点延迟（并发）
clash-tool node        # 切换代理节点
clash-tool mode        # 切换代理模式
clash-tool status      # 查看当前状态
clash-tool help        # 显示帮助信息
clash-tool             # 进入交互菜单
```

### 交互菜单

运行 `clash-tool` 进入交互菜单：

```
======================================
       Clash 管理工具
======================================
Clash 服务: 运行中
模式: rule | 节点: 日本hy2-1-移动优化
系统代理: 已开启
--------------------------------------

1. 测试节点延迟
2. 切换代理节点
3. 切换代理模式
4. 查看状态信息
5. 更新订阅配置
6. 开启系统代理
7. 关闭系统代理
8. 启动/停止 Clash 服务
0. 退出
```

## 文件结构

```
~/clash/
├── clash.sh          # 主脚本
├── test_nodes.sh     # 节点延迟测试（并发）
├── switch_node.sh    # 切换代理节点
├── switch_mode.sh    # 切换代理模式
├── update_sub.sh     # 更新订阅配置
├── sub_url.conf      # 订阅链接配置（不上传）
├── .gitignore        # Git 忽略文件
└── README.md

~/.config/clash/
├── config.yaml       # Clash 配置文件
└── proxy_status      # 代理状态标记文件
```

## 配置订阅

首次使用需要配置订阅链接：

```bash
# 编辑订阅配置文件
nano ~/clash/sub_url.conf

# 设置你的订阅转换链接
SUB_URL="https://api.dler.io/sub?target=clash&url=YOUR_SUBSCRIPTION_URL"
```

然后运行 `clash-tool` 选择「更新订阅配置」或直接编辑 `~/.config/clash/config.yaml`。

> 注意：`sub_url.conf` 文件已加入 `.gitignore`，你的订阅链接不会被上传到 GitHub。

## 代理模式说明

| 模式 | 说明 |
|------|------|
| rule | 规则模式，根据规则分流（推荐） |
| global | 全局模式，所有流量走代理 |
| direct | 直连模式，所有流量直连 |

## 代理地址

| 类型 | 地址 |
|------|------|
| HTTP | `http://127.0.0.1:7890` |
| SOCKS5 | `socks5://127.0.0.1:7891` |
| API | `http://127.0.0.1:9090` |


## 服务管理

```bash
systemctl --user status clash    # 查看状态
systemctl --user start clash     # 启动
systemctl --user stop clash      # 停止
systemctl --user restart clash   # 重启
systemctl --user enable clash    # 开机自启
systemctl --user disable clash   # 禁用自启
```

## 依赖

- Bash
- Python 3
- curl
- systemctl (systemd)

## 注意事项

1. 使用前确保 Clash 服务已启动
2. 测试节点延迟需要网络连接
3. 更新订阅后自动重载配置
4. 开启代理后新终端自动加载代理设置，关闭后新终端不再加载

## License

MIT
