# HandBrake Batch Video Compressor

An interactive Bash script that batch-compresses video files to MP4 using
**HandBrakeCLI**. It runs on any major Linux distribution (and on Windows
via WSL), scans nested subfolders automatically, and mirrors your source
folder structure in the output.

---

## What it does

- Accepts any video format HandBrake supports (MP4, MKV, MOV, AVI, WebM,
  WMV, FLV, TS, MTS, M2TS, VOB, OGV, 3GP, 3G2, and more)
- Always outputs `.mp4` (H.265/HEVC video + AAC audio, web-optimised)
- **Scans recursively** — finds videos in nested subfolders, not just the
  top level
- **Mirrors your folder structure** in the output — a file at
  `source/Trip/beach.mov` becomes `source/output/Trip/beach.mp4`
- Automatically excludes its own `output/` folder from re-scanning, so
  running the script again on the same source won't reprocess its own output
- Walks you through an interactive menu to configure every option
- Processes files **one at a time**, each using all available CPU cores —
  HandBrake already multi-threads a single encode across every core, so this
  gets you full throughput without the terminal output of multiple files
  scrambling together
- **Live progress** — HandBrake's own live %/fps/ETA line streams straight to
  your terminal in real time, exactly like running HandBrakeCLI directly
- **Ctrl+C cancels only the current file** — it cleans up the partial output
  and moves on to the next file instead of killing the whole batch
- Shows a per-file and total summary: original size → compressed size → %
  saved + time taken
- Logs HandBrake errors/warnings to `output/handbrake.log`
- Handles folder paths with spaces safely

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| `HandBrakeCLI` | The actual video encoder |
| `bc` | Floating-point arithmetic for size/percentage calculations |

The script checks for both on startup. If either is missing, it offers to
**auto-install them for you** (via `apt`, `dnf`+RPM Fusion, or `pacman`,
whichever it detects) — just confirm the prompt. If you decline, or if
auto-install isn't possible (unsupported package manager, or no `sudo` while
not running as root), it prints the exact manual install command instead.

---

## Installation

### Option 1: Direct from GitHub (recommended)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/janak0ff/HandBrake-CLI/main/compress.sh)"
```

### Option 2: Using wget

```bash
bash -c "$(wget -qO- https://raw.githubusercontent.com/janak0ff/HandBrake-CLI/main/compress.sh)"
```

Both of these download and run the script immediately — no separate install
step needed. Just make sure HandBrakeCLI and `bc` are installed first (see
below), and adjust the URL if you've forked this into your own repo.

### Option 3: Clone the repo

```bash
git clone https://github.com/janak0ff/HandBrake-CLI.git
cd HandBrake-CLI
chmod +x compress.sh
./compress.sh
```

---

## Installing HandBrakeCLI + bc

### Ubuntu / Debian

```bash
sudo apt-get update
sudo apt-get install -y handbrake-cli bc
```

### Fedora / RHEL / Rocky / AlmaLinux

HandBrake isn't in the default repos — you need RPM Fusion first:

```bash
sudo dnf install -y \
  "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
sudo dnf install -y HandBrake-cli bc
```

### Arch Linux / Manjaro

```bash
sudo pacman -S --noconfirm handbrake-cli bc
```

---

## Running on Windows (via WSL)

HandBrakeCLI itself doesn't run natively on Windows through this script —
you'll need **WSL (Windows Subsystem for Linux)** with a Linux distro
installed.

### 1. Install WSL (if you haven't already)

Open PowerShell as Administrator:

```powershell
wsl --install
```

This installs WSL2 with Ubuntu by default. Restart when prompted, then
finish setting up your Linux username/password on first launch.

### 2. Open your WSL terminal and install prerequisites

```bash
sudo apt-get update
sudo apt-get install -y handbrake-cli bc
```

### 3. Access your Windows files from WSL

Your Windows drives are automatically mounted under `/mnt/` inside WSL. For
example:

| Windows path | WSL path |
|---|---|
| `C:\Users\Jack\Documents` | `/mnt/c/Users/Jack/Documents` |
| `C:\Users\Jack\Videos` | `/mnt/c/Users/Jack/Videos` |
| `D:\Recordings` | `/mnt/d/Recordings` |

So when the script asks for a source folder, you'd enter something like:

```
Source folder: /mnt/c/Users/Jack/Documents/HandBrake-CLI/source
```

### 4. Run the script

```bash
chmod +x compress.sh
./compress.sh
```

> **Performance tip:** reading/writing across the Windows/WSL boundary
> (`/mnt/c/...`) is noticeably slower than working inside WSL's native
> Linux filesystem (`~/`). For large batches, consider copying your source
> videos into your WSL home folder first (`cp -r /mnt/c/Users/Jack/Videos/raw ~/videos`),
> compressing there, then copying the `output/` folder back out.

---

## Usage

```bash
./compress.sh
```

The script walks you through:

| Prompt | Options |
|--------|---------|
| **Source folder** | Any path containing video files (scanned recursively) |
| **Resolution** | HQ (source), HD (1280×720), FHD (1920×1080) |
| **Encoder preset** | `veryfast` → `faster` (default) → `slow` |
| **Frame rate** | Same as source (default), 24, or 30 fps |
| **Quality (CRF)** | High (20), Medium (24), Low (28, default), or custom 0–51 |

After answering, you'll see a summary and a confirmation prompt before any
encoding begins.

---

## Example run

If a tool is missing, you'll see this before the menu appears:

```
Checking prerequisites...
  ✗ HandBrakeCLI not found
  ✓ bc

Missing: HandBrakeCLI
Auto-install now? [Y/n]: y
Installing via apt...
...
✓ All prerequisites installed successfully.
```

Otherwise, if everything's already installed:

```
  ╔══════════════════════════════════════╗
  ║    HandBrake Batch Compressor        ║
  ╚══════════════════════════════════════╝

Checking prerequisites...
  ✓ HandBrakeCLI
  ✓ bc

Source folder: /mnt/c/Users/Jack/Documents/HandBrake-CLI/source
  Found 5 file(s) (including subfolders):
    Introduction.webm                                  55.70 MB
    The CIA Triad.webm                                 21.49 MB
    Advanced/DNS Records Deep Dive.webm               312.10 MB
    ...

Resolution:
  1) HQ  — original
  2) HD  — 1280×720
  3) FHD — 1920×1080
  [1-3, default 1]: 1

Encoder preset (fast→small file, slow→better quality):
  1) veryfast
  2) faster ← default
  3) slow
  [1-3, default 2]: 2

Frame rate:
  1) Same as source ← default
  2) 24 fps
  3) 30 fps
  [1-3, default 1]: 1

Quality (CRF):
  1) High    CRF 20
  2) Medium  CRF 24
  3) Low     CRF 28  ← default
  4) Custom
  [1-4, default 3]: 3

─────────────────  Summary  ─────────────────
  Source    : /mnt/c/Users/Jack/Documents/HandBrake-CLI/source
  Output    : /mnt/c/Users/Jack/Documents/HandBrake-CLI/source/output
  Files     : 5   (sequential)
  Resolution: HQ   Preset: faster   FPS: source   Quality: Low (28)
─────────────────────────────────────────────

Proceed? [Y/n]: y

Compressing 5 file(s) sequentially...
(Ctrl+C cancels only the current file and moves on to the next)

▶ start  Introduction.webm
Encoding: task 1 of 1, 42.87 % (98.31 fps, avg 95.02 fps, ETA 00h00m41s)
✔ done   Introduction.webm  55.70 MB → 7.22 MB  90.0% saved  ⏱ 00:58
▶ start  The CIA Triad.webm
✔ done   The CIA Triad.webm  21.49 MB → 5.36 MB  80.0% saved  ⏱ 01:00
▶ start  Advanced/DNS Records Deep Dive.webm
✔ done   Advanced/DNS Records Deep Dive.webm  312.10 MB → 41.80 MB  86.6% saved  ⏱ 04:32
...

─────────────────  Complete  ────────────────
  Files    : 5
  Input    : 704.19 MB   Output: 91.44 MB   Saved: 87.0%
  Time     : 08:41
  Output   : /mnt/c/Users/Jack/Documents/HandBrake-CLI/source/output
  Log      : /mnt/c/Users/Jack/Documents/HandBrake-CLI/source/output/handbrake.log
─────────────────────────────────────────────
```

---

## Options reference

### Resolution presets

| Name | Dimensions | Use when… |
|------|-----------|-----------|
| HQ   | Original  | Archiving; you want no quality compromise |
| HD   | 1280×720  | Web sharing, smaller storage |
| FHD  | 1920×1080 | Full HD delivery, streaming |

### Encoder preset speed

`veryfast` → `faster` → `slow`, fastest to slowest. Slower presets squeeze
more compression efficiency out of x265 at the same CRF, at the cost of
encode time. `faster` is a good default for screen-recorded/tutorial-style
content, which has low motion and compresses well even at faster presets.

### CRF values

| Label | CRF | Typical use |
|-------|-----|-------------|
| High  | 20  | Near-lossless archival |
| Medium| 24  | Balanced quality/size |
| Low   | 28  | Maximum compression, streaming (default) |

Lower CRF = better quality & bigger files. Higher CRF = smaller files & more
visible quality loss. Valid range is 0–51.

---

## Folder structure

The script scans **recursively**, including nested subfolders, and mirrors
that structure inside `output/`:

```
/your/source/folder/
├── video1.mkv
├── video2.mov
├── Trip 2024/
│   ├── beach.webm
│   └── hiking.mov
└── output/                    ← created automatically
    ├── video1.mp4
    ├── video2.mp4
    ├── Trip 2024/
    │   ├── beach.mp4
    │   └── hiking.mp4
    └── handbrake.log
```

Re-running the script on the same source folder will **not** pick up files
already inside `output/` — it's automatically excluded from the scan.

---

## Troubleshooting

### `HandBrakeCLI` or `bc` not found
The script offers to install these automatically when it detects they're
missing — just confirm the `Auto-install now? [Y/n]` prompt. If auto-install
fails or isn't available on your system (unsupported package manager, or no
`sudo` while not running as root), it prints the exact manual command for
your distro — see [Installing HandBrakeCLI + bc](#installing-handbrakecli--bc).

### Auto-install ran but the tool is still not found afterward
Open a new terminal (or run `hash -r`) so your shell picks up the newly
installed binary, then re-run the script. If it's still missing, the package
manager install likely failed silently — check the output above the error
for the actual apt/dnf/pacman error message.

### No video files found in source folder
- Check the extension is supported: `mp4, mkv, mov, avi, wmv, flv, webm,
  m4v, mpeg, mpg, ts, mts, m2ts, vob, ogv, 3gp, 3g2`
- The search is case-insensitive (`.MP4` and `.mp4` both match) and
  recursive (nested subfolders are included automatically)
- Make sure you're not pointing at the `output/` folder itself — it's
  excluded by design

### A file shows `✘ FAILED / CANCELLED`
Check `output/handbrake.log` — it contains HandBrake's error/warning output
(stderr) for every file. Note: the live progress line in your terminal is
*not* written to the log on purpose (that's stdout, kept separate so live
progress keeps working) — only warnings and errors land there. Common
causes: corrupt source file, unsupported/DRM-protected input, insufficient
disk space, or a cancelled (Ctrl+C) encode.

### Output file is larger than the input
Happens when the source is already well-compressed (e.g. a low-bitrate H.264
file) and you chose a low CRF (near-lossless, e.g. 20). Try a higher CRF
(28+) or the HQ resolution preset to avoid upscaling.

### Script exits immediately with "permission denied"
```bash
chmod +x compress.sh
```

### Paths with spaces not working
Type the path normally at the prompt — don't add extra quotes around it, the
script handles quoting internally.

### Live progress isn't showing / terminal looks frozen while encoding
Make sure you're running the script directly in an interactive terminal
(not through another pipe or redirect) — HandBrake only shows its live
progress meter when its output is connected to a real terminal.

### Ctrl+C killed the whole batch, not just one file
This shouldn't happen with the current version — Ctrl+C is designed to
cancel only the file currently encoding and move on to the next one. If
you're seeing the whole script exit, you may be running an older copy of
`compress.sh`; re-download the latest version.

### Running from WSL: script can't find my videos
Double-check you're using the WSL-style path, not the Windows one — e.g.
`/mnt/c/Users/Jack/Documents/...`, not `C:\Users\Jack\Documents\...`. See the
[Running on Windows (via WSL)](#running-on-windows-via-wsl) section above.