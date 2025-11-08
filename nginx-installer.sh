#!/bin/bash

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印欢迎信息
echo -e "${GREEN}"
echo "========================================"
echo "    Nginx 自动编译安装脚本"
echo "========================================"
echo -e "${NC}"

# 检查是否以 root 用户运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}警告: 建议使用 root 权限运行此脚本${NC}"
    read -p "是否继续? (y/N): " continue_as_user
    if [ "$continue_as_user" != "y" ] && [ "$continue_as_user" != "Y" ]; then
        echo "安装已取消"
        exit 1
    fi
fi

# 获取安装路径
echo -e "${BLUE}请输入 Nginx 的安装路径 (默认: /usr/local/nginx):${NC}"
read -r install_path

# 设置默认路径
if [ -z "$install_path" ]; then
    install_path="/usr/local/nginx"
    echo -e "${YELLOW}使用默认路径: $install_path${NC}"
else
    # 确保路径以斜杠结尾
    install_path="${install_path%/}"
    echo -e "${GREEN}使用自定义路径: $install_path${NC}"
fi

# 检查路径是否已存在
if [ -d "$install_path" ]; then
    echo -e "${RED}警告: 目录 $install_path 已存在${NC}"
    read -p "是否覆盖安装? (y/N): " overwrite
    if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
        echo "安装已取消"
        exit 1
    fi
    # 备份原有配置
    if [ -f "$install_path/conf/nginx.conf" ]; then
        backup_dir="/tmp/nginx_backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        cp -r "$install_path/conf" "$backup_dir/" 2>/dev/null
        echo -e "${YELLOW}原有配置已备份到: $backup_dir${NC}"
    fi
fi

# 显示安装信息
echo -e "${GREEN}"
echo "开始安装 Nginx..."
echo "版本: 1.28.0"
echo "安装路径: $install_path"
echo -e "${NC}"

# 创建临时工作目录
temp_dir=$(mktemp -d)
cd "$temp_dir" || exit 1

# 下载 Nginx
echo -e "${BLUE}[1/6] 下载 Nginx 源码包...${NC}"
if wget -q https://nginx.org/download/nginx-1.28.0.tar.gz; then
    echo -e "${GREEN}✓ 下载成功${NC}"
else
    echo -e "${RED}✗ 下载失败，请检查网络连接${NC}"
    exit 1
fi

# 解压
echo -e "${BLUE}[2/6] 解压源码包...${NC}"
if tar -xzf nginx-1.28.0.tar.gz; then
    echo -e "${GREEN}✓ 解压成功${NC}"
else
    echo -e "${RED}✗ 解压失败${NC}"
    exit 1
fi

cd nginx-1.28.0 || exit 1

# 检查依赖
echo -e "${BLUE}[3/6] 检查系统依赖...${NC}"

# 检查必要的编译工具
for cmd in gcc make; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${YELLOW}需要安装 $cmd${NC}"
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y build-essential
        elif command -v yum &> /dev/null; then
            yum groupinstall -y "Development Tools"
        else
            echo -e "${RED}无法自动安装依赖，请手动安装 gcc 和 make${NC}"
            exit 1
        fi
        break
    fi
done

# 检查 PCRE
if ! pkg-config --exists libpcre; then
    echo -e "${YELLOW}需要安装 PCRE 库${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get install -y libpcre3-dev
    elif command -v yum &> /dev/null; then
        yum install -y pcre-devel
    fi
fi

# 检查 zlib
if ! pkg-config --exists zlib; then
    echo -e "${YELLOW}需要安装 zlib 库${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get install -y zlib1g-dev
    elif command -v yum &> /dev/null; then
        yum install -y zlib-devel
    fi
fi

# 配置编译选项
echo -e "${BLUE}[4/6] 配置编译选项...${NC}"
./configure --prefix="$install_path" \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_gzip_static_module

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ 配置失败，请检查依赖是否安装完整${NC}"
    exit 1
fi

# 编译
echo -e "${BLUE}[5/6] 编译 Nginx...${NC}"
if make -j$(nproc); then
    echo -e "${GREEN}✓ 编译成功${NC}"
else
    echo -e "${RED}✗ 编译失败${NC}"
    exit 1
fi

# 安装
echo -e "${BLUE}[6/6] 安装到系统...${NC}"
if make install; then
    echo -e "${GREEN}✓ 安装成功${NC}"
else
    echo -e "${RED}✗ 安装失败${NC}"
    exit 1
fi

# 创建系统服务文件
echo -e "${BLUE}创建系统服务...${NC}"
cat > /etc/systemd/system/nginx.service << EOF
[Unit]
Description=nginx - high performance web server
Documentation=https://nginx.org/en/docs/
After=network.target

[Service]
Type=forking
PIDFile=$install_path/logs/nginx.pid
ExecStartPre=$install_path/sbin/nginx -t
ExecStart=$install_path/sbin/nginx
ExecReload=$install_path/sbin/nginx -s reload
ExecStop=$install_path/sbin/nginx -s quit
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# 设置环境变量
echo "export PATH=\$PATH:$install_path/sbin" >> /etc/profile
source /etc/profile

# 清理临时文件
cd /
rm -rf "$temp_dir"

# 显示安装结果
echo -e "${GREEN}"
echo "========================================"
echo "    Nginx 安装完成!"
echo "========================================"
echo -e "${NC}"
echo -e "安装路径: ${GREEN}$install_path${NC}"
echo -e "可执行文件: ${GREEN}$install_path/sbin/nginx${NC}"
echo -e "配置文件: ${GREEN}$install_path/conf/nginx.conf${NC}"
echo ""
echo -e "${YELLOW}下一步操作:${NC}"
echo "1. 启动 Nginx: $install_path/sbin/nginx"
echo "2. 或使用 systemd: systemctl start nginx"
echo "3. 设置开机启动: systemctl enable nginx"
echo ""
echo -e "测试安装: curl http://localhost/${NC}"
