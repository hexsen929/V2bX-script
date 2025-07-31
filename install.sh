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

# 检测并安装 UPX
check_and_install_upx() {
    echo -e "${yellow}检测 UPX 是否已安装...${plain}"
    
    if command -v upx >/dev/null 2>&1; then
        echo -e "${green}UPX 已安装${plain}"
        return 0
    fi
    
    echo -e "${yellow}UPX 未安装，开始安装...${plain}"
    
    if [[ x"${release}" == x"centos" ]]; then
        yum install upx -y >/dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            # 尝试从 EPEL 安装
            yum install epel-release -y >/dev/null 2>&1
            yum install upx -y >/dev/null 2>&1
        fi
    elif [[ x"${release}" == x"alpine" ]]; then
        apk add upx >/dev/null 2>&1
    elif [[ x"${release}" == x"debian" ]] || [[ x"${release}" == x"ubuntu" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt install upx -y >/dev/null 2>&1
    elif [[ x"${release}" == x"arch" ]]; then
        pacman -S --noconfirm upx >/dev/null 2>&1
    fi
    
    # 检查安装是否成功
    if command -v upx >/dev/null 2>&1; then
        echo -e "${green}UPX 安装成功${plain}"
        return 0
    else
        echo -e "${red}UPX 安装失败，将跳过压缩步骤${plain}"
        return 1
    fi
}

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
        wget --no-check-certificate -N --progress=bar -O /usr/local/myapp/package-linux.zip https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip"
        echo -e "开始安装版本 $1"
        wget --no-check-certificate -N --progress=bar -O /usr/local/myapp/package-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载版本 $1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi
    
    unzip package-linux.zip
    rm package-linux.zip -f
    
    # 检查 UPX 是否可用，如果可用则压缩主程序
    if command -v upx >/dev/null 2>&1; then
        echo -e "${yellow}使用 UPX 压缩程序...${plain}"
        upx --fast V2bX
        if [[ $? -eq 0 ]]; then
            echo -e "${green}程序压缩成功${plain}"
        else
            echo -e "${yellow}程序压缩失败，继续安装${plain}"
        fi
    fi
    
    # 重命名主程序
    mv V2bX myapp
    chmod +x myapp
    
    mkdir /etc/myapp/ -p
    cp geoip.dat /etc/myapp/
    cp geosite.dat /etc/myapp/
    
    if [[ x"${release}" == x"alpine" ]]; then
        rm /etc/init.d/myapp -f
        cat <<EOF > /etc/init.d/myapp
#!/sbin/openrc-run
name="myapp"
description="MyApp Service"
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
        echo -e "${green}MyApp ${last_version}${plain} 安装完成，已设置开机自启"
    else
        rm /etc/systemd/system/myapp.service -f
        cat <<EOF > /etc/systemd/system/myapp.service
[Unit]
Description=MyApp Service
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
        echo -e "${green}MyApp ${last_version}${plain} 安装完成，已设置开机自启"
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
            echo -e "${green}MyApp 重启成功${plain}"
        else
            echo -e "${red}MyApp 可能启动失败，请稍后检查日志信息${plain}"
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
    
    # 下载管理脚本（修改其中的敏感字样）
    curl -o /usr/bin/V2bX -Ls https://raw.githubusercontent.com/wyx2685/V2bX-script/master/V2bX.sh
    if [[ $? -eq 0 ]]; then
        # 替换管理脚本中的敏感字样
        sed -i 's/V2bX/myapp/g' /usr/bin/V2bX
        sed -i 's/v2bx/myapp/g' /usr/bin/V2bX
        sed -i 's/\/usr\/local\/V2bX\//\/usr\/local\/myapp\//g' /usr/bin/V2bX
        sed -i 's/\/etc\/V2bX\//\/etc\/myapp\//g' /usr/bin/V2bX
        chmod +x /usr/bin/V2bX
        
        # 创建软链接（先删除已存在的文件）
        rm -f /usr/bin/myapp
        ln -s /usr/bin/V2bX /usr/bin/myapp
        chmod +x /usr/bin/myapp
    else
        echo -e "${yellow}管理脚本下载失败，创建简单管理脚本${plain}"
        # 创建简单的管理脚本作为备用
        cat <<EOF > /usr/bin/myapp
#!/bin/bash
case "\$1" in
    start)
        if [[ x"\$(uname -s)" == x"Linux" ]]; then
            if [[ -f /etc/alpine-release ]]; then
                service myapp start
            else
                systemctl start myapp
            fi
        fi
        ;;
    stop)
        if [[ x"\$(uname -s)" == x"Linux" ]]; then
            if [[ -f /etc/alpine-release ]]; then
                service myapp stop
            else
                systemctl stop myapp
            fi
        fi
        ;;
    restart)
        if [[ x"\$(uname -s)" == x"Linux" ]]; then
            if [[ -f /etc/alpine-release ]]; then
                service myapp restart
            else
                systemctl restart myapp
            fi
        fi
        ;;
    status)
        if [[ x"\$(uname -s)" == x"Linux" ]]; then
            if [[ -f /etc/alpine-release ]]; then
                service myapp status
            else
                systemctl status myapp
            fi
        fi
        ;;
    log)
        if [[ x"\$(uname -s)" == x"Linux" ]]; then
            if [[ -f /etc/alpine-release ]]; then
                tail -f /var/log/messages | grep myapp
            else
                journalctl -f -u myapp
            fi
        fi
        ;;
    *)
        echo "使用方法: myapp {start|stop|restart|status|log}"
        ;;
esac
EOF
        chmod +x /usr/bin/myapp
    fi
    
    cd $cur_dir
    rm -f install.sh
    
    echo "MyApp 管理脚本使用方法 (兼容使用myapp执行，大小写不敏感): "
    echo "------------------------------------------"
    echo "myapp              - 显示管理菜单 (功能更多)"
    echo "myapp start        - 启动 MyApp"
    echo "myapp stop         - 停止 MyApp"
    echo "myapp restart      - 重启 MyApp"
    echo "myapp status       - 查看 MyApp 状态"
    echo "myapp enable       - 设置 MyApp 开机自启"
    echo "myapp disable      - 取消 MyApp 开机自启"
    echo "myapp log          - 查看 MyApp 日志"
    echo "myapp x25519       - 生成 x25519 密钥"
    echo "myapp generate     - 生成 MyApp 配置文件"
    echo "myapp update       - 更新 MyApp"
    echo "myapp update x.x.x - 更新 MyApp 指定版本"
    echo "myapp install      - 安装 MyApp"
    echo "myapp uninstall    - 卸载 MyApp"
    echo "myapp version      - 查看 MyApp 版本"
    echo "------------------------------------------"
    
    # 首次安装询问是否生成配置文件
    if [[ $first_install == true ]]; then
        read -rp "检测到你为第一次安装MyApp,是否自动直接生成配置文件？(y/n): " if_generate
        if [[ $if_generate == [Yy] ]]; then
            curl -o ./initconfig.sh -Ls https://raw.githubusercontent.com/wyx2685/V2bX-script/master/initconfig.sh
            if [[ $? -eq 0 ]]; then
                # 只替换路径相关的敏感字样，保持函数名和变量名不变
                sed -i 's/\/usr\/local\/V2bX\//\/usr\/local\/myapp\//g' initconfig.sh
                sed -i 's/\/etc\/V2bX\//\/etc\/myapp\//g' initconfig.sh
                # 替换服务名
                sed -i 's/systemctl restart V2bX/systemctl restart myapp/g' initconfig.sh
                sed -i 's/systemctl start V2bX/systemctl start myapp/g' initconfig.sh
                sed -i 's/service V2bX restart/service myapp restart/g' initconfig.sh
                sed -i 's/service V2bX start/service myapp start/g' initconfig.sh
                source initconfig.sh
                rm initconfig.sh -f
                generate_config_file
            else
                echo -e "${yellow}配置脚本下载失败，请手动配置 /etc/myapp/config.json 文件${plain}"
            fi
        fi
    fi
}

echo -e "${green}开始安装${plain}"

# 检测并安装 UPX
check_and_install_upx

# 安装基础包
install_base

# 安装主程序
install_V2bX $1
