#!/bin/bash

trap_main_menu() {
  clear
  echo "========================="
  echo "🌿 Drosera 一键部署脚本"
  echo "========================="
  echo "1. 创建 Trap"
  echo "2. 运行 Operator 节点"
  echo "3. 退出"
  echo "========================="
  read -p "请输入选项 (1/2/3): " option

  case $option in
    1) create_trap;;
    2) run_operator;;
    3) exit 0;;
    *) echo "无效选项"; sleep 2; trap_main_menu;;
  esac
}

create_trap() {
  read -p "请输入 GitHub 用户名: " gh_name
  read -p "请输入 GitHub 邮箱: " gh_email
  read -p "请输入钱包私钥 (带0x): " privkey

  echo "\n▶️ 安装系统依赖..."
  sudo apt-get update && sudo apt-get upgrade -y
  sudo apt install curl ufw iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev -y

  echo "\n▶️ 安装 Docker..."
  for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove $pkg; done
  sudo apt-get update
  sudo apt-get install ca-certificates curl gnupg -y
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update
  sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
  sudo docker run hello-world

  echo "\n▶️ 安装 Drosera CLI..."
  curl -L https://app.drosera.io/install | bash
  source ~/.bashrc
  droseraup

  echo "\n▶️ 安装 Foundry..."
  curl -L https://foundry.paradigm.xyz | bash
  source ~/.bashrc
  foundryup

  echo "\n▶️ 安装 Bun..."
  curl -fsSL https://bun.sh/install | bash
  source ~/.bashrc

  echo "\n▶️ 初始化 Trap 项目..."
  mkdir -p my-drosera-trap && cd my-drosera-trap
  git config --global user.email "$gh_email"
  git config --global user.name "$gh_name"
  forge init -t drosera-network/trap-foundry-template
  bun install
  forge build

  echo "\n▶️ 部署 Trap 合约..."
  DROSERA_PRIVATE_KEY=$privkey drosera apply <<< "ofc"

  echo "✅ Trap 部署完成。请登录 Drosera 面板加速 Trap。"
  read -p "是否获取区块（是/否）？: " dry
  if [[ "$dry" == "是" ]]; then
    drosera dryrun
  fi

  read -n 1 -s -r -p $'\n按任意键返回主菜单...'
  trap_main_menu
}

run_operator() {
  read -p "请输入 Operator 钱包地址: " op_address
  read -p "请输入 Operator 钱包私钥 (带0x): " op_privkey
  read -p "请输入公网 IP 或填写 localhost: " ip

  cd ~/my-drosera-trap || { echo "项目目录不存在！"; sleep 2; trap_main_menu; }
  echo "\nprivate_trap = true" >> drosera.toml
  echo "whitelist = [\"$op_address\"]" >> drosera.toml
  DROSERA_PRIVATE_KEY=$op_privkey drosera apply <<< "ofc"

  echo "\n▶️ 安装 Operator CLI..."
  cd ~
  curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
  tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
  sudo cp drosera-operator /usr/bin
  drosera-operator --version

  echo "\n▶️ 注册 Operator..."
  drosera-operator register --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com --eth-private-key $op_privkey

  echo "\n▶️ 创建 systemd 服务..."
  sudo tee /etc/systemd/system/drosera.service > /dev/null <<EOF
[Unit]
Description=Drosera Operator
After=network-online.target

[Service]
User=root
Restart=always
RestartSec=15
LimitNOFILE=65535
ExecStart=/usr/bin/drosera-operator node \\
  --db-file-path /root/.drosera.db \\
  --network-p2p-port 31313 \\
  --server-port 31314 \\
  --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com \\
  --eth-backup-rpc-url https://1rpc.io/holesky \\
  --eth-private-key $op_privkey \\
  --listen-address 0.0.0.0 \\
  --network-external-p2p-address $ip \\
  --disable-dnr-confirmation true

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable drosera
  sudo systemctl start drosera

  echo "✅ 节点已启动。使用以下命令查看日志："
  echo "journalctl -u drosera.service -f"
  read -n 1 -s -r -p $'\n按任意键返回主菜单...'
  trap_main_menu
}

# 启动脚本
trap_main_menu
