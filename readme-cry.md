# 🪙 MoneroOcean CPU Miner One-Click Setup

## 📖 Overview

This is a fully automated bash script that downloads, configures, and runs the MoneroOcean CPU miner on your Linux system. It's designed for **Ubuntu/Debian** systems with systemd.

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| **One-Command Setup** | Runs entirely with a single command |
| **Auto-Detection** | Automatically detects CPU threads and optimizes performance |
| **Systemd Service** | Installs as a background service that auto-starts on reboot |
| **Huge Pages** | Enables huge pages automatically for better performance |
| **Smart Port Selection** | Dynamically calculates optimal pool port based on CPU |
| **Dual Wallet Support** | Use hardcoded wallet OR pass one as argument |
| **Error Recovery** | Falls back to stock XMRig if MoneroOcean version fails |
| **CPU Limiting** | Provides hints to limit CPU usage on shared VPS |

---

## 📋 Prerequisites

| Requirement | Details |
|-------------|---------|
| **OS** | Ubuntu 20.04+, Debian 10+, or any systemd-based Linux |
| **Packages** | `curl`, `wget`, `systemd` (auto-installed if missing) |
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

## 📊 What the Script Does

| Step | Action |
|------|--------|
| **1** | Validates wallet address format |
| **2** | Installs `curl` and `systemd` if missing |
| **3** | Downloads MoneroOcean XMRig from official repository |
| **4** | Extracts miner to `$HOME/moneroocean/` |
| **5** | Configures `config.json` with your wallet and hostname |
| **6** | Enables huge pages for performance |
| **7** | Creates systemd service `moneroocean` |
| **8** | Starts miner and enables auto-restart |

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

### Worker Name

The script automatically sets the worker name to your system's hostname:

```
PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
```

If you have a multi-core system, it appears as `<hostname>:<email>` (if email provided).

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
| `max-cpu-usage` | 100% | Uses all CPU (can be reduced) |
| `huge-pages` | Enabled via sysctl | Performance boost |
| `background` | true | Runs in background |

---

## 🔧 Performance Tuning

### For Shared VPS (Avoid 100% CPU)

The script provides hints to limit CPU usage to 75%:

```bash
sed -i 's/"max-threads-hint": *[^,]*,/"max-threads-hint": 75,/' $HOME/moneroocean/config.json
sudo systemctl restart moneroocean
```

### For Systems with <4 CPU Threads

The script recommends `cpulimit`:

```bash
sudo apt-get install -y cpulimit
sudo cpulimit -e xmrig -l 75 -b
```

### Manual Thread Control

Edit `config.json` to set explicit thread count:

```bash
"max-threads-hint": 75,  # 75% of CPU
# OR
"threads": 8,            # Explicit number of threads
```

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

To change the default wallet, edit this line in the script:

```bash
DEFAULT_WALLET="YOUR_NEW_WALLET_ADDRESS"
```

To change the pool, modify this line:

```bash
sed -i 's/"url": *"[^"]*",/"url": "your.pool.address:PORT",/' $HOME/moneroocean/config.json
```

---

## 📜 License & Credits

- **Script Version:** 2.11
- **Miner:** [MoneroOcean/xmrig](https://github.com/MoneroOcean/xmrig)
- **Support:** support@moneroocean.stream
- **License:** MIT (as per original MoneroOcean script)

---

## ⚠️ Disclaimer

**Crypto mining involves risks:**
- Check your VPS provider's Terms of Service
- Monitor your system temperatures
- Be aware of electricity costs
- This is a hobby, not a get-rich-quick scheme

---