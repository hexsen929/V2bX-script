#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

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

# Check if UPX is installed, if not, install it
install_upx() {
    if ! command -v upx &> /dev/null; then
        echo -e "${yellow}UPX未安装，正在安装UPX...${plain}"
        if [[ x"${release}" == x"centos" ]]; then
            yum install -y upx
        elif [[ x"${release}" == x"ubuntu" || x"${release}" == x"debian" ]]; then
            apt-get update && apt-get install -y upx-ucl
        elif [[ x"${release}" == x"alpine" ]]; then
            apk add upx
        else
            echo -e "${red}不支持的系统，无法安装 UPX！${plain}"
            exit 1
        fi
    else
        echo -e "${green}UPX 已经安装，跳过安装步骤。${plain}"
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

install_myapp() {
    if [[ -e /usr/local/myapp/ ]]; then
        rm -rf /usr/local/myapp/
    fi

    mkdir /usr/local/myapp/ -p
    cd /usr/local/myapp/

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/wyx2685/V2bX/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 myapp 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定版本安装${plain}"
            exit 1
        fi
        echo -e "检测到 myapp 最新版本：${last_version}，开始安装"
        wget --no-check-certificate -N --progress=bar -O /usr/local/myapp/myapp-linux.zip https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 myapp 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip"
        echo -e "开始安装 myapp $1"
        wget --no-check-certificate -N --progress=bar -O /usr/local/myapp/myapp-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 myapp $1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    unzip myapp-linux.zip
    rm myapp-linux.zip -f
    chmod +x myapp
    install_upx
    upx /usr/local/myapp/myapp
    mv /usr/local/myapp/myapp /usr/local/myapp/myapp

    mkdir /etc/myapp/ -p
    cp geoip.dat /etc/myapp/
    cp geosite.dat /etc/myapp/

    # systemd setup and init process (same as previous)
    if [[ x"${release}" == x"alpine" ]]; then
        rm /etc/init.d/myapp -f
        cat <<EOF > /etc/init.d/myapp
#!/sbin/openrc-run

name="myapp"
description="myapp"

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
        echo -e "${green}myapp ${last_version}${plain} 安装完成，已设置开机自启"
    else
        rm /etc/systemd/system/myapp.service -f
        cat <<EOF > /etc/systemd/system/myapp.service
[Unit]
Description=myapp Service
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
        echo -e "${green}myapp ${last_version}${plain} 安装完成，已设置开机自启"
    fi

    # Further configuration steps (same as previous)
    cp config.json /etc/myapp/
    cp dns.json /etc/myapp/
    cp route.json /etc/myapp/
    cp custom_outbound.json /etc/myapp/
    cp custom_inbound.json /etc/myapp/

    echo -e "${green}myapp 安装和配置完成！${plain}"
}

echo -e "${green}开始安装${plain}"
install_base
install_myapp $1
