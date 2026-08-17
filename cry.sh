#!/bin/bash

VERSION="2.14"

# --- COLORS FOR OUTPUT ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$(id -u)" == "0" ]; then
  echo -e "${YELLOW}WARNING: Generally it is not advised to run this script under root${NC}"
fi

# --- MODIFIED: Default wallet (hardcoded) ---
DEFAULT_WALLET="4223BS9gSB6Zj1aUVKXEzKEgFL15SWunjALZEnAn2wFaNXv4QDpHbEjcMivUq69984gydxwoKeEM2ayNbXXpM7NTDT8wDdX"

# --- MODIFIED: Install directory ---
INSTALL_DIR="/usr/local/ocean"

# --- MODIFIED: Support both methods ---
if [ ! -z "$1" ]; then
  WALLET="$1"
  EMAIL="$2"
  echo -e "${GREEN}Using wallet from argument: $WALLET${NC}"
else
  WALLET="$DEFAULT_WALLET"
  EMAIL="$1"
  echo -e "${GREEN}Using default hardcoded wallet: $WALLET${NC}"
fi

if [ ! -z "$EMAIL" ]; then
  echo -e "${GREEN}Email: $EMAIL${NC}"
fi
echo ""

# --- NEW: Ask user for CPU usage percentage ---
echo "========================================"
echo "CPU Usage Configuration"
echo "========================================"
echo "Enter the percentage of CPU you want to use for mining."
echo " - 100 = maximum performance (may cause overheating)"
echo " - 75  = balanced (recommended for laptops/VPS)"
echo " - 50  = conservative (for shared systems)"
echo " - 30  = minimal (keep system responsive)"
echo ""
read -p "Enter CPU percentage (1-100, default 100): " CPU_PERCENT

# Validate input: if empty, default to 100
if [ -z "$CPU_PERCENT" ]; then
    CPU_PERCENT=100
    echo -e "${GREEN}Using default: 100%${NC}"
else
    # Check if input is a valid number between 1 and 100
    if ! [[ "$CPU_PERCENT" =~ ^[0-9]+$ ]] || [ "$CPU_PERCENT" -lt 1 ] || [ "$CPU_PERCENT" -gt 100 ]; then
        echo -e "${RED}ERROR: Invalid input. Please enter a number between 1 and 100.${NC}"
        echo -e "${GREEN}Using default: 100%${NC}"
        CPU_PERCENT=100
    else
        echo -e "${GREEN}Using: ${CPU_PERCENT}%${NC}"
    fi
fi
echo ""

# --- DISTRO DETECTION ---
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        OS=$(uname -s)
        VERSION=$(uname -r)
    fi
    echo -e "${GREEN}Detected OS: $OS $VERSION${NC}"
}

# --- PACKAGE MANAGER DETECTION ---
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt-get"
        INSTALL_CMD="sudo apt-get install -y"
        UPDATE_CMD="sudo apt-get update"
        PKG_curl="curl"
        PKG_wget="wget"
        PKG_bc="bc"
        PKG_systemd="systemd"
        PKG_tar="tar"
        PKG_gzip="gzip"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        INSTALL_CMD="sudo yum install -y"
        UPDATE_CMD="sudo yum update -y"
        PKG_curl="curl"
        PKG_wget="wget"
        PKG_bc="bc"
        PKG_systemd="systemd"
        PKG_tar="tar"
        PKG_gzip="gzip"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="sudo dnf install -y"
        UPDATE_CMD="sudo dnf update -y"
        PKG_curl="curl"
        PKG_wget="wget"
        PKG_bc="bc"
        PKG_systemd="systemd"
        PKG_tar="tar"
        PKG_gzip="gzip"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="sudo pacman -S --noconfirm"
        UPDATE_CMD="sudo pacman -Sy"
        PKG_curl="curl"
        PKG_wget="wget"
        PKG_bc="bc"
        PKG_systemd="systemd"
        PKG_tar="tar"
        PKG_gzip="gzip"
    elif command -v zypper &> /dev/null; then
        PKG_MANAGER="zypper"
        INSTALL_CMD="sudo zypper install -y"
        UPDATE_CMD="sudo zypper refresh"
        PKG_curl="curl"
        PKG_wget="wget"
        PKG_bc="bc"
        PKG_systemd="systemd"
        PKG_tar="tar"
        PKG_gzip="gzip"
    elif command -v apk &> /dev/null; then
        PKG_MANAGER="apk"
        INSTALL_CMD="sudo apk add"
        UPDATE_CMD="sudo apk update"
        PKG_curl="curl"
        PKG_wget="wget"
        PKG_bc="bc"
        PKG_systemd="systemd"  # May not be available on Alpine
        PKG_tar="tar"
        PKG_gzip="gzip"
    else
        echo -e "${RED}ERROR: Unsupported package manager. Please install curl, wget, bc, tar, gzip manually.${NC}"
        exit 1
    fi
}

# --- INSTALL PACKAGE FUNCTION ---
install_package() {
    local pkg=$1
    if ! command -v $pkg &> /dev/null; then
        echo -e "${YELLOW}Installing $pkg...${NC}"
        $INSTALL_CMD $pkg
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}WARNING: Failed to install $pkg. Please install it manually.${NC}"
        fi
    fi
}

# --- MAIN SCRIPT ---
detect_os
detect_package_manager

# Install required packages
echo -e "${GREEN}[*] Checking and installing required packages...${NC}"
$UPDATE_CMD 2>/dev/null || true  # Ignore errors if update fails

# Install each package individually
for pkg in $PKG_curl $PKG_wget $PKG_bc $PKG_tar $PKG_gzip; do
    install_package $pkg
done

# --- AUTO-DETECT CPU CORES ---
if ! command -v nproc &> /dev/null; then
    echo -e "${YELLOW}WARNING: nproc not found. Using fallback method to count CPU threads.${NC}"
    CPU_THREADS=$(grep -c ^processor /proc/cpuinfo)
else
    CPU_THREADS=$(nproc)
fi

# --- CALCULATE THREADS BASED ON USER PERCENTAGE ---
if [ "$CPU_PERCENT" -eq 100 ]; then
    THREADS_TO_USE=$CPU_THREADS
    RX_THREADS="["
    for ((i=0; i<$CPU_THREADS; i++)); do
        if [ $i -eq $((CPU_THREADS - 1)) ]; then
            RX_THREADS="$RX_THREADS$i"
        else
            RX_THREADS="$RX_THREADS$i, "
        fi
    done
    RX_THREADS="$RX_THREADS]"
else
    THREADS_TO_USE=$(( CPU_THREADS * CPU_PERCENT / 100 ))
    if [ "$THREADS_TO_USE" -lt 1 ]; then
        THREADS_TO_USE=1
    fi
    RX_THREADS="["
    for ((i=0; i<$THREADS_TO_USE; i++)); do
        if [ $i -eq $((THREADS_TO_USE - 1)) ]; then
            RX_THREADS="$RX_THREADS$i"
        else
            RX_THREADS="$RX_THREADS$i, "
        fi
    done
    RX_THREADS="$RX_THREADS]"
fi

echo -e "${GREEN}[*] Detected $CPU_THREADS CPU threads.${NC}"
echo -e "${GREEN}[*] Using $THREADS_TO_USE threads (${CPU_PERCENT}%).${NC}"
echo -e "${GREEN}[*] RX thread configuration: $RX_THREADS${NC}"

# checking prerequisites
WALLET_BASE=$(echo $WALLET | cut -f1 -d".")
if [ ${#WALLET_BASE} != 106 ] && [ ${#WALLET_BASE} != 95 ]; then
  echo -e "${RED}ERROR: Wrong wallet base address length (should be 106 or 95): ${#WALLET_BASE}${NC}"
  echo -e "${RED}Wallet provided: $WALLET${NC}"
  exit 1
fi

if ! command -v curl &> /dev/null; then
  echo -e "${RED}ERROR: This script requires \"curl\" utility to work correctly${NC}"
  exit 1
fi

if ! command -v lscpu &> /dev/null; then
  echo -e "${YELLOW}WARNING: This script requires \"lscpu\" utility to work correctly${NC}"
fi

# calculating port
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo -e "${RED}ERROR: Can't compute projected Monero CN hashrate${NC}"
  exit 1
fi

power2() {
  if ! command -v bc &> /dev/null; then
    if   [ "$1" -gt "8192" ]; then
      echo "8192"
    elif [ "$1" -gt "4096" ]; then
      echo "4096"
    elif [ "$1" -gt "2048" ]; then
      echo "2048"
    elif [ "$1" -gt "1024" ]; then
      echo "1024"
    elif [ "$1" -gt "512" ]; then
      echo "512"
    elif [ "$1" -gt "256" ]; then
      echo "256"
    elif [ "$1" -gt "128" ]; then
      echo "128"
    elif [ "$1" -gt "64" ]; then
      echo "64"
    elif [ "$1" -gt "32" ]; then
      echo "32"
    elif [ "$1" -gt "16" ]; then
      echo "16"
    elif [ "$1" -gt "8" ]; then
      echo "8"
    elif [ "$1" -gt "4" ]; then
      echo "4"
    elif [ "$1" -gt "2" ]; then
      echo "2"
    else
      echo "1"
    fi
  else 
    echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l;
  fi
}

PORT=$(( $EXP_MONERO_HASHRATE * 30 ))
PORT=$(( $PORT == 0 ? 1 : $PORT ))
PORT=$(power2 $PORT)
PORT=$(( 10000 + $PORT ))
if [ -z $PORT ]; then
  echo -e "${RED}ERROR: Can't compute port${NC}"
  exit 1
fi

if [ "$PORT" -lt "10001" -o "$PORT" -gt "18192" ]; then
  echo -e "${RED}ERROR: Wrong computed port value: $PORT${NC}"
  exit 1
fi


# Check sudo availability
if command -v sudo &> /dev/null && sudo -n true 2>/dev/null; then
  SUDO_AVAILABLE=true
  echo -e "${GREEN}Mining in background will be performed using systemd service.${NC}"
else
  SUDO_AVAILABLE=false
  echo -e "${YELLOW}Since I can't do passwordless sudo, mining in background will started from your $HOME/.profile file first time you login this host after reboot.${NC}"
fi

echo
echo -e "${GREEN}JFYI: This host has $CPU_THREADS CPU threads, so projected Monero hashrate is around $EXP_MONERO_HASHRATE KH/s.${NC}"
echo

echo -e "${YELLOW}Sleeping for 15 seconds before continuing (press Ctrl+C to cancel)${NC}"
sleep 15
echo
echo

# start doing stuff: preparing 
echo -e "${GREEN}[*] Removing previous installation (if any)${NC}"
if [ "$SUDO_AVAILABLE" = true ]; then
  sudo systemctl stop ocean 2>/dev/null
  sudo systemctl disable ocean 2>/dev/null
fi
sudo killall xmrig 2>/dev/null || true

echo -e "${GREEN}[*] Removing $INSTALL_DIR directory (if exists)${NC}"
sudo rm -rf $INSTALL_DIR

echo -e "${GREEN}[*] Creating $INSTALL_DIR directory${NC}"
sudo mkdir -p $INSTALL_DIR
sudo chown -R root:root $INSTALL_DIR
sudo chmod 755 $INSTALL_DIR

echo -e "${GREEN}[*] Downloading advanced version of xmrig to /tmp/xmrig.tar.gz${NC}"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo -e "${RED}ERROR: Can't download https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz file to /tmp/xmrig.tar.gz${NC}"
  exit 1
fi

echo -e "${GREEN}[*] Unpacking /tmp/xmrig.tar.gz to $INSTALL_DIR${NC}"
if ! sudo tar xf /tmp/xmrig.tar.gz -C $INSTALL_DIR; then
  echo -e "${RED}ERROR: Can't unpack /tmp/xmrig.tar.gz to $INSTALL_DIR directory${NC}"
  exit 1
fi
sudo rm /tmp/xmrig.tar.gz

echo -e "${GREEN}[*] Checking if advanced version of $INSTALL_DIR/xmrig works fine (and not removed by antivirus software)${NC}"
sudo sed -i 's/"donate-level": *[^,]*,/"donate-level": 1,/' $INSTALL_DIR/config.json
$INSTALL_DIR/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f $INSTALL_DIR/xmrig ]; then
    echo -e "${YELLOW}WARNING: Advanced version of $INSTALL_DIR/xmrig is not functional${NC}"
  else 
    echo -e "${YELLOW}WARNING: Advanced version of $INSTALL_DIR/xmrig was removed by antivirus (or some other problem)${NC}"
  fi

  echo -e "${GREEN}[*] Looking for the latest version${NC}"
  LATEST_XMRIG_RELEASE=$(curl -s https://github.com/xmrig/xmrig/releases/latest 2>/dev/null | grep -o '".*"' | sed 's/"//g')
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"$(curl -s $LATEST_XMRIG_RELEASE 2>/dev/null | grep xenial-x64.tar.gz\" | cut -d \" -f2)

  echo -e "${GREEN}[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to /tmp/xmrig.tar.gz${NC}"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    echo -e "${RED}ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to /tmp/xmrig.tar.gz${NC}"
    exit 1
  fi

  echo -e "${GREEN}[*] Unpacking /tmp/xmrig.tar.gz to $INSTALL_DIR${NC}"
  if ! sudo tar xf /tmp/xmrig.tar.gz -C $INSTALL_DIR --strip=1; then
    echo -e "${YELLOW}WARNING: Can't unpack /tmp/xmrig.tar.gz to $INSTALL_DIR directory${NC}"
  fi
  sudo rm /tmp/xmrig.tar.gz

  echo -e "${GREEN}[*] Checking if stock version of $INSTALL_DIR/xmrig works fine (and not removed by antivirus software)${NC}"
  sudo sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $INSTALL_DIR/config.json
  $INSTALL_DIR/xmrig --help >/dev/null
  if (test $? -ne 0); then 
    if [ -f $INSTALL_DIR/xmrig ]; then
      echo -e "${RED}ERROR: Stock version of $INSTALL_DIR/xmrig is not functional too${NC}"
    else 
      echo -e "${RED}ERROR: Stock version of $INSTALL_DIR/xmrig was removed by antivirus too${NC}"
    fi
    exit 1
  fi
fi

echo -e "${GREEN}[*] Ocean $INSTALL_DIR/xmrig is OK${NC}"

PASS=$(hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g')
if [ "$PASS" == "localhost" ]; then
  PASS=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}')
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi

# --- Configure config.json ---
echo -e "${GREEN}[*] Configuring $INSTALL_DIR/config.json${NC}"
sudo sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' $INSTALL_DIR/config.json
sudo sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $INSTALL_DIR/config.json
sudo sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $INSTALL_DIR/config.json
sudo sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": '$CPU_PERCENT',/' $INSTALL_DIR/config.json
sudo sed -i 's/"max-threads-hint": *[^,]*,/"max-threads-hint": '$CPU_PERCENT',/' $INSTALL_DIR/config.json
sudo sed -i 's/"priority": *[^,]*,/"priority": 5,/' $INSTALL_DIR/config.json
sudo sed -i 's#"log-file": *null,#"log-file": "'$INSTALL_DIR/xmrig.log'",#' $INSTALL_DIR/config.json
sudo sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $INSTALL_DIR/config.json

# --- DYNAMIC: Add rx thread configuration with detected core count ---
if ! sudo grep -q '"rx":' $INSTALL_DIR/config.json; then
    # Insert rx thread config with dynamically generated thread list
    sudo sed -i '/"cpu": {/,/}/{ /"enabled":/a\        "rx": '"$RX_THREADS"',
    }' $INSTALL_DIR/config.json
else
    # Update existing rx config with new thread list
    sudo sed -i 's/"rx": *\[[^]]*\]/"rx": '"$RX_THREADS"'/' $INSTALL_DIR/config.json
fi

sudo cp $INSTALL_DIR/config.json $INSTALL_DIR/config_background.json
sudo sed -i 's/"background": *false,/"background": true,/' $INSTALL_DIR/config_background.json

# preparing script
echo -e "${GREEN}[*] Creating $INSTALL_DIR/start.sh script${NC}"
sudo cat >$INSTALL_DIR/start.sh <<EOL
#!/bin/bash
if ! pidof xmrig >/dev/null; then
  nice -n -5 $INSTALL_DIR/xmrig \$*
else
  echo "Ocean is already running in the background. Refusing to run another one."
  echo "Run \"killall xmrig\" or \"sudo killall xmrig\" if you want to remove background Ocean first."
fi
EOL

sudo chmod +x $INSTALL_DIR/start.sh

# preparing script background work and work under reboot
if [ "$SUDO_AVAILABLE" = false ]; then
  if ! grep  $INSTALL_DIR/start.sh $HOME/.profile >/dev/null 2>&1; then
    echo -e "${GREEN}[*] Adding $INSTALL_DIR/start.sh script to $HOME/.profile${NC}"
    echo "$INSTALL_DIR/start.sh --config=$INSTALL_DIR/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo -e "${YELLOW}Looks like $INSTALL_DIR/start.sh script is already in the $HOME/.profile${NC}"
  fi
  echo -e "${GREEN}[*] Running in the background (see logs in $INSTALL_DIR/xmrig.log file)${NC}"
  /bin/bash $INSTALL_DIR/start.sh --config=$INSTALL_DIR/config_background.json >/dev/null 2>&1
else
  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
    echo -e "${GREEN}[*] Enabling huge pages${NC}"
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc))) 2>/dev/null || true
  fi

  if ! command -v systemctl &> /dev/null; then
    echo -e "${GREEN}[*] Running in the background (see logs in $INSTALL_DIR/xmrig.log file)${NC}"
    /bin/bash $INSTALL_DIR/start.sh --config=$INSTALL_DIR/config_background.json >/dev/null 2>&1
    echo -e "${YELLOW}WARNING: systemd not found. Started in background but won't auto-start on reboot.${NC}"
    echo -e "${YELLOW}Please add $INSTALL_DIR/start.sh to your crontab or rc.local for auto-start.${NC}"
  else
    echo -e "${GREEN}[*] Creating ocean systemd service${NC}"
    sudo cat >/tmp/ocean.service <<EOL
[Unit]
Description=Ocean
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/xmrig --config=$INSTALL_DIR/config.json
Restart=always
RestartSec=10
Nice=-5
CPUWeight=100

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/ocean.service /etc/systemd/system/ocean.service
    echo -e "${GREEN}[*] Starting ocean systemd service${NC}"
    sudo killall xmrig 2>/dev/null || true
    sudo systemctl daemon-reload
    sudo systemctl enable ocean   
    sudo systemctl start ocean
    echo -e "${GREEN}To see ocean service logs run \"sudo journalctl -u ocean -f\" command${NC}"
  fi
fi

echo ""
echo "========================================"
echo -e "${GREEN}Setup Complete${NC}"
echo "========================================"
echo -e "${GREEN}Installation Directory:${NC} $INSTALL_DIR"
echo -e "${GREEN}Wallet:${NC} $WALLET"
echo -e "${GREEN}Worker:${NC} $PASS"
echo -e "${GREEN}Service:${NC} ocean"
echo -e "${GREEN}CPU Threads:${NC} $CPU_THREADS detected"
echo -e "${GREEN}CPU Usage:${NC} ${CPU_PERCENT}% ($THREADS_TO_USE threads)"
echo -e "${GREEN}RX Threads:${NC} $RX_THREADS"
echo "========================================"
echo ""
echo -e "${GREEN}To check status:${NC} sudo systemctl status ocean"
echo -e "${GREEN}To view logs:${NC} sudo journalctl -u ocean -f"
echo ""
echo -e "${YELLOW}If systemd is not available, ocean is running in background.${NC}"
echo -e "${GREEN}To stop:${NC} sudo killall xmrig"
echo -e "${GREEN}To start:${NC} $INSTALL_DIR/start.sh"
echo ""
echo -e "${YELLOW}To change CPU percentage later:${NC}"
echo "  sudo sed -i 's/\"max-threads-hint\": [0-9]*/\"max-threads-hint\": 75/' $INSTALL_DIR/config.json"
echo "  sudo systemctl restart ocean"