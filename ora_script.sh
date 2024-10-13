#!/bin/bash

BLUE='\033[1;34m'
NC='\033[0m'

function show() {
    echo -e "${BLUE}$1${NC}"
}

if ! command -v curl &> /dev/null
then
    show "curl not found. Installing curl..."
    sudo apt update && sudo apt install -y curl
else
    show "curl is already installed."
fi
echo

if ! command -v docker &> /dev/null
then
    show "Docker not found. Installing Docker..."
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
    # Add Docker's official GPG key:
    sudo apt-get update
    sudo apt-get --yes --force-yes install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get --yes --force-yes install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker $USER
    sudo chmod 666 /var/run/docker.sock
else
    show "Docker is already installed."
fi
echo

mkdir -p tora && cd tora

cat << EOF > docker-compose.yml
# ora node docker-compose
services:
  confirm:
    image: oraprotocol/tora:confirm
    container_name: ora-tora
    depends_on:
      - redis
      - openlm
    command:
      - "--confirm"
    env_file:
      - .env
    environment:
      REDIS_HOST: 'redis'
      REDIS_PORT: 6379
      CONFIRM_MODEL_SERVER_13: 'http://openlm:5000/'
    networks:
      - private_network
  redis:
    image: oraprotocol/redis:latest
    container_name: ora-redis
    restart: always
    networks:
      - private_network
  openlm:
    image: oraprotocol/openlm:latest
    container_name: ora-openlm
    restart: always
    networks:
      - private_network
  diun:
    image: crazymax/diun:latest
    container_name: diun
    command: serve
    volumes:
      - "./data:/data"
      - "/var/run/docker.sock:/var/run/docker.sock"
    environment:
      - "TZ=Asia/Shanghai"
      - "LOG_LEVEL=info"
      - "LOG_JSON=false"
      - "DIUN_WATCH_WORKERS=5"
      - "DIUN_WATCH_JITTER=30"
      - "DIUN_WATCH_SCHEDULE=0 0 * * *"
      - "DIUN_PROVIDERS_DOCKER=true"
      - "DIUN_PROVIDERS_DOCKER_WATCHBYDEFAULT=true"
    restart: always

networks:
  private_network:
    driver: bridge
EOF

echo
read -p "Enter your private key: " PRIV_KEY
read -p "Do you want to run a node in Ethereum Mainnet? Yes or No: " MAINNET_CHOICE
if [[ $MAINNET_CHOICE == "Yes" || $MAINNET_CHOICE == "yes" ]]; then
    read -p "Enter your WSS URL for Ethereum Mainnet: " MAINNET_WSS
    read -p "Enter your HTTP URL for Ethereum Mainnet: " MAINNET_HTTP
fi

read -p "Enter your WSS URL for Ethereum Sepolia: " SEPOLIA_WSS
read -p "Enter your HTTP URL for Ethereum Sepolia: " SEPOLIA_HTTP

cat <<EOF > .env
############### Sensitive config ###############

PRIV_KEY="$PRIV_KEY"

############### General config ###############

TORA_ENV=production

# general - provider url
# MAINNET_WSS="$MAINNET_WSS"
# MAINNET_HTTP="$MAINNET_HTTP"
SEPOLIA_WSS="$SEPOLIA_WSS"
SEPOLIA_HTTP="$SEPOLIA_HTTP"

# redis global ttl, comment out -> no ttl limit
REDIS_TTL=86400000 # 1 day in ms 

############### App specific config ###############

# confirm - general
CONFIRM_CHAINS='["sepolia"]' # sepolia | mainnet ｜ '["sepolia","mainnet"]'
CONFIRM_MODELS='[13]' # 13: OpenLM ,now only 13 supported
# confirm - crosscheck
CONFIRM_USE_CROSSCHECK=true
CONFIRM_CC_POLLING_INTERVAL=3000 # 3 sec in ms
CONFIRM_CC_BATCH_BLOCKS_COUNT=300 # default 300 means blocks in 1 hours on eth
# confirm - store ttl
CONFIRM_TASK_TTL=2592000000
CONFIRM_TASK_DONE_TTL = 2592000000 # comment out -> no ttl limit
CONFIRM_CC_TTL=2592000000 # 1 month in ms
EOF
if [[ $MAINNET_CHOICE == "Yes" || $MAINNET_CHOICE == "yes" ]]; then
    echo "MAINNET_WSS=\"$MAINNET_WSS\"" >> .env
    echo "MAINNET_HTTP=\"$MAINNET_HTTP\"" >> .env
fi

sudo sysctl vm.overcommit_memory=1
echo
show "Starting Docker containers using docker-compose(may take 5-10 mins)..."
echo
sudo docker compose up