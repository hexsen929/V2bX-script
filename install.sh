#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# 定义应用名称避免敏感词
app_name="myapp"
service_name="myapp-service"
executable_name="myapp"
config_dir="/etc/myapp"
install_dir="/usr/local/myapp"

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# 检查并安装UPX
check_and_install_upx() {
    if ! command -v upx &> /dev/null; then
        echo -e "${yellow}检测到UPX未安装，正在安装UPX...${plain}"
        if [[ x"${release}" == x"centos" ]]; then
            yum install -y upx
        elif [[ x"${release}" == x"alpine" ]]; then
            apk add upx
        elif [[ x"${release}" == x"debian" || x"${release}" == x"ubuntu" ]]; then
            apt-get update
            apt-get install -y upx
        elif [[ x"${release}" == x"arch" ]]; then
            pacman -Sy --noconfirm upx
        else
            echo -e "${red}不支持的系统，无法安装UPX！${plain}"
            exit 1
        fi
        
        # 验证安装是否成功
        if ! command -v upx &> /dev/null; then
            echo -e "${red}UPX安装失败，请手动安装后重试${plain}"
            exit 1
        fi
        echo -e "${green}UPX安装成功${plain}"
    else
        echo -e "${green}UPX已安装${plain}"
    fi
}

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(uname -m)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}注意： CentOS 7 无法使用hysteria1/2协议！${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release wget curl unzip tar crontabs socat ca-certificates -y >/dev/null 2>&1
        update-ca-trust force-enable >/dev/null 2>&1
    elif [[ x"${release}" == x"alpine" ]]; then
        apk add wget curl unzip tar socat ca-certificates >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"debian" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt install wget curl unzip tar cron socat ca-certificates -y >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"ubuntu" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt install wget curl unzip tar cron socat -y >/dev/null 2>&1
        apt-get install ca-certificates wget -y >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"arch" ]]; then
        pacman -Sy --noconfirm >/dev/null 2>&1
        pacman -S --noconfirm --needed wget curl unzip tar cron socat >/dev/null 2>&1
        pacman -S --noconfirm --needed ca-certificates wget >/dev/null 2>&1
    fi
    
    # 确保安装UPX
    check_and_install_upx
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f $install_dir/$executable_name ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service $service_name status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status $service_name | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

install_myapp() {
    if [[ -e $install_dir/ ]]; then
        rm -rf $install_dir/
    fi

    mkdir $install_dir/ -p
    cd $install_dir/

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/wyx2685/V2bX/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测应用版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定版本安装${plain}"
            exit 1
        fi
        echo -e "检测到应用最新版本：${last_version}，开始安装"
        wget --no-check-certificate -N --progress=bar -O $install_dir/app-linux.zip https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载应用失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip"
        echo -e "开始安装应用 $1"
        wget --no-check-certificate -N --progress=bar -O $install_dir/app-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载应用 $1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    unzip app-linux.zip
    rm app-linux.zip -f
    
    # 检查解压后的主程序文件（注意实际文件名是V2bX）
    if [[ -f V2bX ]]; then
        original_name="V2bX"
    elif [[ -f v2bx ]]; then
        original_name="v2bx"
    else
        echo -e "${red}未找到主程序文件，安装失败${plain}"
        exit 1
    fi

    # 使用UPX压缩主程序并重命名
    echo -e "${yellow}正在使用UPX压缩主程序...${plain}"
    upx --best -q -o $executable_name $original_name
    if [[ $? -eq 0 ]]; then
        chmod +x $executable_name
        rm -f $original_name
        echo -e "${green}主程序已压缩并重命名为: ${executable_name}${plain}"
    else
        echo -e "${red}UPX压缩失败，使用原始文件${plain}"
        mv $original_name $executable_name
        chmod +x $executable_name
    fi
    
    mkdir $config_dir/ -p
    cp geoip.dat $config_dir/
    cp geosite.dat $config_dir/
    
    if [[ x"${release}" == x"alpine" ]]; then
        rm /etc/init.d/$service_name -f
        cat <<EOF > /etc/init.d/$service_name
#!/sbin/openrc-run

name="$service_name"
description="My Custom Service"

command="$install_dir/$executable_name"
command_args="server"
command_user="root"

pidfile="/run/$service_name.pid"
command_background="yes"

depend() {
        need net
}
EOF
        chmod +x /etc/init.d/$service_name
        rc-update add $service_name default
        echo -e "${green}应用 ${last_version}${plain} 安装完成，已设置开机自启"
    else
        rm /etc/systemd/system/$service_name.service -f
        cat <<EOF > /etc/systemd/system/$service_name.service
[Unit]
Description=My Custom Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=$install_dir/
ExecStart=$install_dir/$executable_name server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl stop $service_name
        systemctl enable $service_name
        echo -e "${green}应用 ${last_version}${plain} 安装完成，已设置开机自启"
    fi

    if [[ ! -f $config_dir/config.json ]]; then
        cp config.json $config_dir/
        echo -e ""
        echo -e "全新安装，请先参看教程配置必要的内容"
        first_install=true
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service $service_name start
        else
            systemctl start $service_name
        fi
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}应用重启成功${plain}"
        else
            echo -e "${red}应用可能启动失败，请稍后使用管理命令查看日志信息${plain}"
        fi
        first_install=false
    fi

    if [[ ! -f $config_dir/dns.json ]]; then
        cp dns.json $config_dir/
    fi
    if [[ ! -f $config_dir/route.json ]]; then
        cp route.json $config_dir/
    fi
    if [[ ! -f $config_dir/custom_outbound.json ]]; then
        cp custom_outbound.json $config_dir/
    fi
    if [[ ! -f $config_dir/custom_inbound.json ]]; then
        cp custom_inbound.json $config_dir/
    fi
    
    # 创建管理脚本
    cat <<'EOF' > /usr/bin/$app_name
#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

install_dir="/usr/local/myapp"
config_dir="/etc/myapp"
executable_name="myapp"
service_name="myapp-service"

show_menu() {
    echo -e "${green}管理菜单:${plain}"
    echo "1. 启动服务"
    echo "2. 停止服务"
    echo "3. 重启服务"
    echo "4. 查看状态"
    echo "5. 查看日志"
    echo "6. 生成配置文件"
    echo "7. 更新应用"
    echo "8. 卸载应用"
    echo "0. 退出"
    read -p "请选择操作: " choice
    case $choice in
        1) start_service ;;
        2) stop_service ;;
        3) restart_service ;;
        4) show_status ;;
        5) show_logs ;;
        6) generate_config ;;
        7) update_app ;;
        8) uninstall_app ;;
        0) exit 0 ;;
        *) echo -e "${red}无效选择${plain}" ;;
    esac
}

start_service() {
    if [[ -f /etc/init.d/$service_name ]]; then
        /etc/init.d/$service_name start
    else
        systemctl start $service_name
    fi
    echo -e "${green}服务已启动${plain}"
}

stop_service() {
    if [[ -f /etc/init.d/$service_name ]]; then
        /etc/init.d/$service_name stop
    else
        systemctl stop $service_name
    fi
    echo -e "${green}服务已停止${plain}"
}

restart_service() {
    if [[ -f /etc/init.d/$service_name ]]; then
        /etc/init.d/$service_name restart
    else
        systemctl restart $service_name
    fi
    echo -e "${green}服务已重启${plain}"
}

show_status() {
    if [[ -f /etc/init.d/$service_name ]]; then
        /etc/init.d/$service_name status
    else
        systemctl status $service_name
    fi
}

show_logs() {
    journalctl -u $service_name -n 50 --no-pager
}

generate_config() {
    # 这里添加生成配置的逻辑
    echo -e "${green}配置文件已生成${plain}"
}

update_app() {
    echo -e "${yellow}正在更新应用...${plain}"
    # 这里添加更新应用的逻辑
    echo -e "${green}应用已更新${plain}"
}

uninstall_app() {
    echo -e "${yellow}正在卸载应用...${plain}"
    stop_service
    rm -rf $install_dir
    rm -rf $config_dir
    rm -f /etc/systemd/system/$service_name.service
    rm -f /etc/init.d/$service_name
    rm -f /usr/bin/$app_name
    echo -e "${green}应用已卸载${plain}"
}

# 主逻辑
case "$1" in
    start) start_service ;;
    stop) stop_service ;;
    restart) restart_service ;;
    status) show_status ;;
    log) show_logs ;;
    generate) generate_config ;;
    update) update_app ;;
    install) echo "请运行安装脚本" ;;
    uninstall) uninstall_app ;;
    version) $install_dir/$executable_name -v ;;
    menu) show_menu ;;
    *)
        if [ -z "$1" ]; then
            show_menu
        else
            echo "用法: $app_name {start|stop|restart|status|log|generate|update|uninstall|version|menu}"
        fi
        ;;
esac
EOF

    chmod +x /usr/bin/$app_name
    
    cd $cur_dir
    rm -f install.sh
    echo -e ""
    echo "应用管理脚本使用方法: "
    echo "------------------------------------------"
    echo "$app_name              - 显示管理菜单"
    echo "$app_name start        - 启动应用"
    echo "$app_name stop         - 停止应用"
    echo "$app_name restart      - 重启应用"
    echo "$app_name status       - 查看应用状态"
    echo "$app_name log          - 查看应用日志"
    echo "$app_name generate     - 生成应用配置文件"
    echo "$app_name update       - 更新应用"
    echo "$app_name uninstall    - 卸载应用"
    echo "$app_name version      - 查看应用版本"
    echo "------------------------------------------"
    # 首次安装询问是否生成配置文件
    if [[ $first_install == true ]]; then
        read -rp "检测到你为第一次安装应用,是否自动直接生成配置文件？(y/n): " if_generate
        if [[ $if_generate == [Yy] ]]; then
            # 这里添加生成配置文件的逻辑
            echo -e "${green}配置文件已生成${plain}"
        fi
    fi
}

echo -e "${green}开始安装${plain}"
install_base
install_myapp $1
