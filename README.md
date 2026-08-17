# One-Click Setup

## 📖 Overview

This is a fully automated bash script that downloads, configures, and runs the on your Linux system. It's designed to work on **any major Linux distribution** with systemd.

**Version:** 2.13

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| **One-Command Setup** | Runs entirely with a single command |
| **Interactive CPU Configuration** | Asks for CPU usage percentage (1-100%) |
| **Auto-Detection** | Automatically detects CPU threads and optimizes performance |
| **Cross-Distro Support** | Works on Debian, Ubuntu, RHEL, CentOS, Fedora, Rocky, AlmaLinux, Arch, openSUSE, Alpine |
| **Systemd Service** | Installs as a background service that auto-starts on reboot |
| **Huge Pages** | Enables huge pages automatically for better performance |
| **Smart Port Selection** | Dynamically calculates optimal pool port based on CPU |
| **Dual Wallet Support** | Use hardcoded wallet OR pass one as argument |
| **Error Recovery** | Falls back to stock XMRig if MoneroOcean version fails |
| **Maximum Priority** | Runs at highest CPU priority (Nice=-5) for maximum performance |

---

## 📋 Prerequisites

| Requirement | Details |
|-------------|---------|
| **OS** | Any modern Linux distribution (Debian, Ubuntu, RHEL, CentOS, Fedora, Rocky, AlmaLinux, Arch, openSUSE, Alpine) |
| **Packages** | `curl`, `wget`, `bc`, `tar`, `gzip` (auto-installed if missing) |
| **Permissions** | `sudo` access (for systemd service and huge pages) |
| **Internet** | Active connection to download and connect to pool |

---

## 🚀 Quick Start

### Method 1: Hardcoded Wallet (Default)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/janak0ff/script-forest/cry/cry.sh)"
```

### Method 2: Pass Wallet as Argument

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/janak0ff/script-forest/cry/cry.sh)" YOUR_WALLET_ADDRESS
```

### Method 3: Wallet + Email (for pool management)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/janak0ff/script-forest/cry/cry.sh)" YOUR_WALLET_ADDRESS youremail@example.com
```

---

## ⚙️ CPU Percentage Configuration

When you run the script, you'll be prompted to choose CPU usage:

```
CPU Usage Configuration
========================================
Enter the percentage of CPU you want to use for mining.
 - 100 = maximum performance (may cause overheating)
 - 75  = balanced (recommended for laptops/VPS)
 - 50  = conservative (for shared systems)
 - 30  = minimal (keep system responsive)

Enter CPU percentage (1-100, default 100): 
```

| Input | Result |
|-------|--------|
| `100` or Enter | Uses 100% of all CPU threads (maximum performance) |
| `75` | Uses 75% of CPU threads (balanced) |
| `50` | Uses 50% of CPU threads (conservative) |
| `30` | Uses 30% of CPU threads (minimal impact) |

---

## 📊 What the Script Does

| Step | Action |
|------|--------|
| **1** | Asks for CPU percentage to use (1-100%) |
| **2** | Validates wallet address format |
| **3** | Detects Linux distribution and package manager |
| **4** | Installs required packages if missing |
| **5** | Auto-detects CPU threads and calculates usage |
| **6** | Downloads MoneroOcean XMRig from official repository |
| **7** | Extracts to `/usr/local/ocean/` |
| **8** | Configures `config.json` with your settings |
| **9** | Enables huge pages for performance |
| **10** | Creates systemd service `ocean` with maximum priority |
| **11** | Starts and enables auto-restart |

---

## 🛠️ Management Commands

| Action | Command |
|--------|---------|
| **Check status** | `sudo systemctl status ocean` |
| **View live logs** | `sudo journalctl -u ocean -f` |
| **View recent logs** | `sudo journalctl -u ocean -n 50` |
| **Stop** | `sudo systemctl stop ocean` |
| **Start** | `sudo systemctl start ocean` |
| **Restart** | `sudo systemctl restart ocean` |
| **Disable auto-start** | `sudo systemctl disable ocean` |
| **Enable auto-start** | `sudo systemctl enable ocean` |


---

## ⚙️ Configuration Details

### CPU Configuration

The script dynamically configures CPU usage based on your input:

| Setting | Value | Purpose |
|---------|-------|---------|
| `max-cpu-usage` | User-defined (1-100) | Limits CPU time percentage |
| `max-threads-hint` | User-defined (1-100) | Limits thread usage percentage |
| `priority` | 5 | Maximum CPU priority |
| `rx` | Auto-generated thread list | Forces specific threads for RandomX |

### Worker Name

The script automatically sets the worker name to your system's hostname:

```
PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
```

### Pool Port Calculation

The script dynamically calculates the optimal port based on your CPU threads:

```bash
CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000))
PORT=$(( EXP_MONERO_HASHRATE * 30 ))
PORT=`power2 $PORT`
PORT=$(( 10000 + $PORT ))
```

### Key Config Settings

| Setting | Value | Purpose |
|---------|-------|---------|
| `url` | `gulf.moneroocean.stream:<PORT>` | MoneroOcean pool address |
| `user` | Your wallet address | Where to send mining rewards |
| `pass` | Hostname[:email] | Identifies your worker |
| `donate-level` | 1% | Optional donation to MoneroOcean |
| `max-cpu-usage` | User-defined | Limits CPU usage |
| `max-threads-hint` | User-defined | Limits thread usage |
| `priority` | 5 | Highest CPU priority |
| `huge-pages` | Enabled via sysctl | Performance boost |
| `background` | true | Runs in background |

---

## 🛡️ Security Considerations

| Aspect | Recommendation |
|--------|----------------|
| **Run as non-root** | Script warns if run as root (not recommended) |
| **Wallet security** | Never share your seed phrase; wallet address is public |
| **Antivirus exclusions** | Add `/usr/local/ocean/` to antivirus exclusions to prevent false positives |
| **VPS TOS** | Check your VPS provider's Terms of Service; some prohibit crypto mining |


---

## 📊 Monitoring

### Check Stats

Visit: `https://moneroocean.stream/#YOUR_WALLET_ADDRESS`

### View Local Stats

```bash
# Hashrate from logs
grep -i "hashrate" /usr/local/ocean/xmrig.log

# Accepted shares
grep "accepted" /usr/local/ocean/xmrig.log | wc -l


---

## 🗑️ Uninstalling

```bash
# Stop and disable service
sudo systemctl stop ocean
sudo systemctl disable ocean

# Remove service file
sudo rm /etc/systemd/system/ocean.service

# Remove files
rm -rf /usr/local/ocean

# (Optional) Remove sysctl changes
sudo sed -i '/vm.nr_hugepages/d' /etc/sysctl.conf
```

---

## 📝 Script Customization

### Change Default Wallet

Edit this line in the script:

```bash
DEFAULT_WALLET="YOUR_NEW_WALLET_ADDRESS"
```

### Change Pool

Modify this line:

```bash
sed -i 's/"url": *"[^"]*",/"url": "your.pool.address:PORT",/' /usr/local/ocean/config.json
```