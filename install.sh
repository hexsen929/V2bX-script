#!/bin/bash
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check and install upx
check_install_upx() {
    if ! command -v upx &> /dev/null; then
        echo -e "${yellow}UPX 未安装，正在安装...${plain}"
        if [[ x"${release}" == x"centos" ]]; then
            yum install upx -y
        elif [[ x"${release}" == x"alpine" ]]; then
            apk add upx
        elif [[ x"${release}" == x"debian" ]] || [[ x"${release}" == x"ubuntu" ]]; then
            apt-get update -y
            apt install upx-ucl -y
        elif [[ x"${release}" == x"arch" ]]; then
            pacman -S --noconfirm upx
        fi
        
        if ! command -v upx &> /dev/null; then
            echo -e "${red}UPX 安装失败！${plain}"
            exit 1
        else
            echo -e "${green}UPX 安装成功${plain}"
        fi
    else
        echo -e "${green}UPX 已安装${plain}"
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
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/myapp/myapp ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service myapp status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status myapp | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

install_V2bX() {
    if [[ -e /usr/local/myapp/ ]]; then
        rm -rf /usr/local/myapp/
    fi
    mkdir /usr/local/myapp/ -p
    cd /usr/local/myapp/
    
    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/wyx2685/V2bX/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定版本安装${plain}"
            exit 1
        fi
        echo -e "检测到最新版本：${last_version}，开始安装"
        wget --no-check-certificate -N --progress=bar -O /usr/local/myapp/app-linux.zip https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip"
        echo -e "开始安装 $1"
        wget --no-check-certificate -N --progress=bar -O /usr/local/myapp/app-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 $1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi
    
    unzip app-linux.zip
    rm app-linux.zip -f
    
    # 重命名主程序并加壳
    mv V2bX myapp
    echo -e "${yellow}正在使用UPX加壳程序...${plain}"
    
    # 使用最快的压缩方式进行加壳
    if timeout 30 upx -1 myapp >/dev/null 2>&1; then
        echo -e "${green}程序加壳成功${plain}"
    else
        echo -e "${yellow}UPX加壳失败，继续安装原程序${plain}"
        echo -e "${yellow}可能原因：架构不兼容或程序已被加壳${plain}"
    fi
    
    chmod +x myapp
    mkdir /etc/myapp/ -p
    cp geoip.dat /etc/myapp/
    cp geosite.dat /etc/myapp/
    
    if [[ x"${release}" == x"alpine" ]]; then
        rm /etc/init.d/myapp -f
        cat <<EOF > /etc/init.d/myapp
#!/sbin/openrc-run
name="myapp"
description="Network Service"
command="/usr/local/myapp/myapp"
command_args="server"
command_user="root"
pidfile="/run/myapp.pid"
command_background="yes"
depend() {
        need net
}
EOF
        chmod +x /etc/init.d/myapp
        rc-update add myapp default
        echo -e "${green}程序 ${last_version}${plain} 安装完成，已设置开机自启"
    else
        rm /etc/systemd/system/myapp.service -f
        cat <<EOF > /etc/systemd/system/myapp.service
[Unit]
Description=Network Service
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
WorkingDirectory=/usr/local/myapp/
ExecStart=/usr/local/myapp/myapp server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl stop myapp
        systemctl enable myapp
        echo -e "${green}程序 ${last_version}${plain} 安装完成，已设置开机自启"
    fi
    
    if [[ ! -f /etc/myapp/config.json ]]; then
        cp config.json /etc/myapp/
        echo -e ""
        echo -e "全新安装，请先配置必要的内容"
        first_install=true
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service myapp start
        else
            systemctl start myapp
        fi
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}程序重启成功${plain}"
        else
            echo -e "${red}程序可能启动失败，请检查日志信息${plain}"
        fi
        first_install=false
    fi
    
    if [[ ! -f /etc/myapp/dns.json ]]; then
        cp dns.json /etc/myapp/
    fi
    if [[ ! -f /etc/myapp/route.json ]]; then
        cp route.json /etc/myapp/
    fi
    if [[ ! -f /etc/myapp/custom_outbound.json ]]; then
        cp custom_outbound.json /etc/myapp/
    fi
    if [[ ! -f /etc/myapp/custom_inbound.json ]]; then
        cp custom_inbound.json /etc/myapp/
    fi
    
    # 创建管理脚本
    cat <<EOF > /usr/bin/myapp
#!/bin/bash
case "\$1" in
    start)
        systemctl start myapp
        ;;
    stop)
        systemctl stop myapp
        ;;
    restart)
        systemctl restart myapp
        ;;
    status)
        systemctl status myapp
        ;;
    enable)
        systemctl enable myapp
        ;;
    disable)
        systemctl disable myapp
        ;;
    log)
        journalctl -f -u myapp
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|enable|disable|log}"
        ;;
esac
EOF
    chmod +x /usr/bin/myapp
    
    cd $cur_dir
    rm -f install.sh
    echo -e ""
    echo "程序管理命令: "
    echo "------------------------------------------"
    echo "myapp start        - 启动服务"
    echo "myapp stop         - 停止服务"
    echo "myapp restart      - 重启服务"
    echo "myapp status       - 查看状态"
    echo "myapp enable       - 设置开机自启"
    echo "myapp disable      - 取消开机自启"
    echo "myapp log          - 查看日志"
    echo "------------------------------------------"
}

echo -e "${green}开始安装${plain}"
check_install_upx
install_base
install_V2bX $1
