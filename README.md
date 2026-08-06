# Script Forest

A collection of useful Bash scripts for Linux system administration, automation, and productivity.

Each script is maintained in its own branch and can be executed directly without cloning the repository.

---

## Available Scripts

### 1. Zimbra Password Reset

Reset a Zimbra user password from the command line.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/janak0ff/script-forest/zimbra-email-pass-reset/pass-reset.sh)"
```

View source:
https://github.com/janak0ff/script-forest/tree/zimbra-email-pass-reset

---

### 2. Zsh Setup

Installs and configures Zsh with recommended settings.

Using curl:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/janak0ff/script-forest/Zsh-Setup/zsh-setup.sh)"
```

Using wget:

```bash
bash -c "$(wget -qO- https://raw.githubusercontent.com/janak0ff/script-forest/Zsh-Setup/zsh-setup.sh)"
```

View source:
https://github.com/janak0ff/script-forest/tree/Zsh-Setup

---

### 3. Batch Video Compressor 

Compress multiple video files using HandBrakeCLI. It support any linux distors. Running on Windows (via WSL) - path should be `/mnt/` formats.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/janak0ff/script-forest/Batch-Video-Compressor/compress.sh)"
```

View source:
https://github.com/janak0ff/script-forest/tree/Batch-Video-Compressor

---

### 4. MoneroOcean Setup

Installs and configures the MoneroOcean.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/janak0ff/script-forest/Crypto-setup/cry.sh)"
```

View source:
https://github.com/janak0ff/script-forest/tree/Crypto-setup


---

## Usage

Run any script directly using `curl` or `wget`.

Example:

```bash
bash -c "$(curl -fsSL <script-url>)"
```

```bash
bash -c "$(wget -qO- <script-url>)"
```

For url you can use [https://www.plainraw.com/](https://www.plainraw.com/)

> **Always review scripts before executing them**