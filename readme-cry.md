# 🪙 MoneroOcean CPU Miner One-Click Setup

## 📖 Overview

This is a fully automated bash script that downloads, configures, and runs the MoneroOcean CPU miner on your Linux system. It's designed to work on **any major Linux distribution** with systemd.

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
| **Internet** | Active connection to download miner and connect to pool |

---

## 🚀 Quick Start

### Method 1: Hardcoded Wallet (Default)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/janak0ff/script-forest/Crypto-setup/cry.sh)"
```

### Method 2: Pass Wallet as Argument

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/janak0ff/script-forest/Crypto-setup/cry.sh)" YOUR_WALLET_ADDRESS
```

### Method 3: Wallet + Email (for pool management)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/janak0ff/script-forest/Crypto-setup/cry.sh)" YOUR_WALLET_ADDRESS youremail@example.com
```

**Default Hardcoded Wallet:**
```
4223BS9gSB6Zj1aUVKXEzKEgFL15SWunjALZEnAn2wFaNXv4QDpHbEjcMivUq69984gydxwoKeEM2ayNbXXpM7NTDT8wDdX
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
| **7** | Extracts miner to `$HOME/moneroocean/` |
| **8** | Configures `config.json` with your settings |
| **9** | Enables huge pages for performance |
| **10** | Creates systemd service `moneroocean` with maximum priority |
| **11** | Starts miner and enables auto-restart |

---

## 🛠️ Management Commands

| Action | Command |
|--------|---------|
| **Check status** | `sudo systemctl status moneroocean` |
| **View live logs** | `sudo journalctl -u moneroocean -f` |
| **View recent logs** | `sudo journalctl -u moneroocean -n 50` |
| **Stop miner** | `sudo systemctl stop moneroocean` |
| **Start miner** | `sudo systemctl start moneroocean` |
| **Restart miner** | `sudo systemctl restart moneroocean` |
| **Disable auto-start** | `sudo systemctl disable moneroocean` |
| **Enable auto-start** | `sudo systemctl enable moneroocean` |

---

## 📁 Installation Structure

```
$HOME/moneroocean/
├── xmrig                      # Miner binary
├── config.json                # Main configuration
├── config_background.json     # Background configuration
├── miner.sh                   # Manual start script
└── xmrig.log                  # Log file
```

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

**Example:**
- 4 threads → ~2.8 KH/s → port 10032
- 12 threads → ~8.4 KH/s → port 10256

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

## 🔧 Changing CPU Percentage After Installation

To adjust CPU usage after installation:

```bash
# Change to 75% permanently
sed -i 's/"max-threads-hint": [0-9]*/"max-threads-hint": 75/' $HOME/moneroocean/config.json
sed -i 's/"max-cpu-usage": [0-9]*/"max-cpu-usage": 75/' $HOME/moneroocean/config.json

# Restart the service
sudo systemctl restart moneroocean
```

### Thread Usage Examples

| CPU Percentage | 4-Core System | 8-Core System | 16-Core System |
|----------------|---------------|---------------|----------------|
| **100%** | 4 threads | 8 threads | 16 threads |
| **75%** | 3 threads | 6 threads | 12 threads |
| **50%** | 2 threads | 4 threads | 8 threads |
| **25%** | 1 thread | 2 threads | 4 threads |

---

## 🛡️ Security Considerations

| Aspect | Recommendation |
|--------|----------------|
| **Run as non-root** | Script warns if run as root (not recommended) |
| **Wallet security** | Never share your seed phrase; wallet address is public |
| **Antivirus exclusions** | Add `$HOME/moneroocean/` to antivirus exclusions to prevent false positives |
| **VPS TOS** | Check your VPS provider's Terms of Service; some prohibit crypto mining |

---

## 🐛 Troubleshooting

### Issue: "GLIBC_2.38 not found"

**Solution:** Install the compatibility build or build from source:
```bash
cd $HOME/moneroocean
./xmrig --help  # Check if works
# If not, download compat build manually
```

### Issue: "Permission denied"

**Solution:** Make the binary executable:
```bash
chmod +x $HOME/moneroocean/xmrig
```

### Issue: Miner not starting

**Solution:** Check logs:
```bash
sudo journalctl -u moneroocean -n 50
tail -f $HOME/moneroocean/xmrig.log
```

### Issue: "Failed to load ADL"

**Solution:** This is normal for CPUs without AMD GPUs. The miner will still work.

### Issue: "Huge pages unavailable"

**Solution:** Enable huge pages manually:
```bash
sudo sysctl -w vm.nr_hugepages=1280
echo "vm.nr_hugepages=1280" | sudo tee -a /etc/sysctl.conf
```

### Issue: System becomes sluggish

**Solution:** Reduce CPU percentage:
```bash
sed -i 's/"max-threads-hint": [0-9]*/"max-threads-hint": 50/' $HOME/moneroocean/config.json
sudo systemctl restart moneroocean
```

---

## 📊 Monitoring Your Miner

### Check MoneroOcean Stats

Visit: `https://moneroocean.stream/#YOUR_WALLET_ADDRESS`

### View Local Stats

```bash
# Miner hashrate from logs
grep -i "hashrate" $HOME/moneroocean/xmrig.log

# Accepted shares
grep "accepted" $HOME/moneroocean/xmrig.log | wc -l

# Recent activity
tail -20 $HOME/moneroocean/xmrig.log
```

---

## 🗑️ Uninstalling

```bash
# Stop and disable service
sudo systemctl stop moneroocean
sudo systemctl disable moneroocean

# Remove service file
sudo rm /etc/systemd/system/moneroocean.service

# Remove miner files
rm -rf $HOME/moneroocean

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

### Change Default CPU Percentage

Modify this line to set a different default:

```bash
read -p "Enter CPU percentage (1-100, default 100): " CPU_PERCENT
```

### Change Pool

Modify this line:

```bash
sed -i 's/"url": *"[^"]*",/"url": "your.pool.address:PORT",/' $HOME/moneroocean/config.json
```

---

## 📜 License & Credits

- **Script Version:** 2.13
- **Miner:** [MoneroOcean/xmrig](https://github.com/MoneroOcean/xmrig)
- **Support:** support@moneroocean.stream
- **License:** MIT (as per original MoneroOcean script)

---

## ⚠️ Disclaimer

**Crypto mining involves risks:**
- Check your VPS provider's Terms of Service
- Monitor your system temperatures
- Be aware of electricity costs
- 100% CPU usage may cause overheating on laptops
- This is a hobby, not a get-rich-quick scheme

---

## 📈 Performance Expectations

| CPU Cores | Hashrate (100%) | Daily Earnings (approx) |
|-----------|-----------------|-------------------------|
| 2 cores | ~1,000-1,500 H/s | ~$0.04-0.06 |
| 4 cores | ~2,000-3,000 H/s | ~$0.08-0.12 |
| 8 cores | ~4,000-6,000 H/s | ~$0.16-0.24 |
| 12 cores | ~6,000-9,000 H/s | ~$0.24-0.36 |
| 16 cores | ~8,000-12,000 H/s | ~$0.32-0.48 |

*Estimates based on XMR price of ~$150 and may vary significantly.*

You can also use plainraw.