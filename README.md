A reusable, interactive terminal tool for migrating mailboxes between two
IMAP servers (Zimbra, Dovecot, or anything IMAP-compliant) using
[imapsync](https://imapsync.lamiral.info/). Supports single-user migration,
batch migration from a list, status checks, dry-run verification, and
resuming failed batches — all driven by prompts, with no server details or
credentials hardcoded in the script.

---

## Features

- **Single user migration** — migrate one mailbox, with an optional timeout.
- **Batch migration** — migrate a list of users from a file, pasted inline,
  or entered manually. Invalid email addresses are filtered out and reported
  instead of silently breaking the run.
- **Status check** — confirm a user exists on the destination, see mailbox
  size / quota / last login (via `zmprov`, if available), and pull up past
  migration logs for that user.
- **Verify sync** — runs imapsync in `--dry` mode to compare source and
  destination without changing anything.
- **Resume failed migrations** — re-reads a batch report and retries only
  the users that failed.
- **User list management** — create, view, delete, or import `.txt` lists of
  users to migrate.
- **Report viewer** — browse past batch/resume reports from the menu.
- **Multiple profiles** — save connection details for more than one
  client/environment and switch between them without re-typing anything.

## What's different from a "just works once" script

This version has no hardcoded hosts, usernames, passwords, or paths.
Everything is either:
- entered once and saved to a **profile** (hosts, auth users, working
  directory — no passwords), or
- entered fresh every run (passwords, if you choose "prompt" mode).

Passwords are **never** passed on the imapsync command line and are never
written into a log. They go into imapsync's `--passfile1` / `--passfile2`
option, backed by a file that's `chmod 600` and only readable by root.

---

## Requirements

| Tool      | Purpose                                   | Required? |
|-----------|--------------------------------------------|-----------|
| `bash`    | runs the script                            | yes |
| `imapsync`| does the actual mailbox migration          | yes |
| `bc`      | formats byte counts into KB/MB/GB          | yes |
| `zmprov`  | Zimbra account lookups (status/quota/size) | optional — status-check features degrade gracefully without it |
| root      | mailbox/account access                     | yes — the script refuses to run as a non-root user |

Install imapsync (Debian/Ubuntu example):
```bash
apt update && apt install imapsync bc
```

---

## Quick start

### Option A — run directly from GitHub (one-liner)

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/janak0ff/script-forest/imapsync/sync.sh)"
```

This downloads the script straight from your repo's raw URL and pipes it
into `bash`, so there's nothing to `chmod` or clean up afterward — useful
for one-off runs on a fresh server. Replace `<user>/<repo>/<branch>` with
wherever you've published `master_migration.sh`.

> **Before you rely on this in production:** double-check the raw URL
> actually resolves to `master_migration.sh` (not a different branch or
> file) before running it — `curl | bash` executes whatever that URL
> returns, with no chance to review it first. It's worth pinning to a
> specific commit or tag rather than a branch name once the script is
> stable, so a later push can't silently change what gets executed.
> Since this script requires root and handles mailbox credentials, treat
> the source repo as sensitive: keep it private, or at minimum keep the
> `profiles/`/`.secrets/` output directories (created on the *server*
> you run it on, not in the repo) out of it entirely — see
> [Security notes](#security-notes).

### Option B — download and run locally (recommended for repeat use)

```bash
curl -fsSL -o master_migration.sh https://raw.githubusercontent.com/<user>/<repo>/<branch>/master_migration.sh
chmod +x master_migration.sh
sudo ./master_migration.sh
```

Downloading first lets you read the script and keep a local copy before
running it as root — more predictable than the one-liner if you'll be
using it regularly, since you're always invoking the exact file you
already reviewed.

On first run you'll be walked through:

1. **Working directory** — where logs, reports, user lists, and the
   encrypted-at-rest secrets file live. Defaults to `~/migration_tool`.
2. **Profile name** — a short label for this source/destination pair, e.g.
   `nea`, `client-acme`.
3. **Source (host1)** — hostname/IP and the admin/migration auth user used
   to read mailboxes there.
4. **Destination (host2)** — hostname/IP and the admin auth user used to
   write mailboxes there.
5. **Password handling** — pick one:
   - `1) Store in a chmod 600 secrets file` — type each password once now;
     it's saved for future runs of this profile.
   - `2) Prompt me fresh every time` — nothing is stored; you type both
     passwords (masked, confirmed) at the start of every session.

After setup you land on the main menu.

### Re-using a saved profile

Next time you run the script it lists any saved profiles and lets you pick
one instead of re-entering host/user details. To skip the picker entirely:

```bash
sudo ./master_migration.sh --profile nea
```

To add a new client/environment later, choose **"Switch / Create Profile"**
(option 8) from the menu, or select `n` (new) at the profile picker.

---

## Menu reference

```
1. Migrate Single User          — one email address, optional timeout
2. Batch Migration               — from a saved list, a new list, or manual entry
3. Check Migration Status        — destination lookup + past logs for a user
4. Verify Sync                   — dry-run diff between source and destination
5. Resume Failed Migrations      — retry only the failures from a past batch report
6. Manage User Lists             — create / view / delete / import .txt lists
7. View Reports                  — browse past batch and resume reports
8. Switch / Create Profile       — change which source/destination you're working against
0. Exit
```

### 1. Migrate Single User
Prompts for the destination email, confirms, optionally asks for a timeout
(seconds; `0` = no timeout), then runs imapsync and prints a summary
(messages transferred/skipped, bytes transferred) pulled from the log.

### 2. Batch Migration
Choose an existing list, create a new one (paste emails, blank line to
finish — invalid addresses are rejected on the spot), or enter a one-off
list for this run only. Every address is re-validated before the batch
starts. Produces a timestamped report in `reports/` you can revisit later
or feed into "Resume Failed Migrations."

### 3. Check Migration Status
Looks the user up on the destination server (via `zmprov`, if installed)
and shows mailbox size, quota, last login, and account status. Also
searches `LOGS/` for any past migration log mentioning that address and
offers to show the most recent one.

### 4. Verify Sync
Runs imapsync with `--dry` so nothing is written — useful for a pre-flight
check or a post-migration diff. Prints message counts, sizes, and any
duplicate/skip notes.

### 5. Resume Failed Migrations
Lists past batch reports with their success/fail counts, lets you pick one,
then retries every address marked `FAILED` in that report. Writes its own
resume report.

### 6. Manage User Lists
Create, inspect, delete, or import `.txt` files of email addresses used by
batch migration. One address per line; blank lines and `#`-prefixed lines
are ignored.

### 7. View Reports
Browse and open any report generated by batch or resume runs.

### 8. Switch / Create Profile
Jump to a different saved profile, or create a new one, without restarting
the script.

---

## File layout

Everything lives under the working directory you chose at setup (default
`~/migration_tool`):

```
migration_tool/
├── profiles/           # saved connection profiles (*.conf) — hosts/users only, no passwords
├── .secrets/           # chmod 700 dir; per-profile chmod 600 password files (only if you chose "store" mode)
├── LOGS/                # one timestamped log per migration/verify/resume run
├── reports/             # batch and resume run reports
└── user_lists/          # saved .txt lists of addresses for batch migration
```

A profile file (`profiles/<name>.conf`) looks like this — note there is
**no password in it**:

```bash
HOST1="192.168.8.140"
AUTHUSER1="migration@example.org"
HOST2="192.168.1.107"
AUTHUSER2="admin@ldap.example.org"
PASS_MODE="file"
PASS1_FILE="/root/migration_tool/.secrets/example_host1.pass"
PASS2_FILE="/root/migration_tool/.secrets/example_host2.pass"
```

---

## Security notes

- Run as root is required (for `zmprov` and mailbox-level access), so treat
  the whole `migration_tool/` directory as sensitive — it's created with
  restrictive permissions on the secrets subfolder, but back it up and
  transfer it carefully.
- Passwords are supplied to imapsync via `--passfile1`/`--passfile2`, never
  `--password1`/`--password2` — this keeps them out of `ps aux` and
  `/proc/<pid>/cmdline` output, which any local user could otherwise read
  while a sync is running.
- If you choose "prompt every time" mode, the password is written to a
  `mktemp`, `chmod 600` file for the duration of the session only, and
  shredded (`shred -u`, falling back to `rm -f`) when the script exits.
- `profiles/*.conf` and any stored password files are excluded from source
  control by convention — if you put `migration_tool/` under git, add a
  `.gitignore` for `profiles/` and `.secrets/`.
- Logs and reports may contain email addresses and mailbox metadata; treat
  `LOGS/` and `reports/` as containing PII.

---

## Troubleshooting

**"Please run as root"**
Run with `sudo` — the script needs it for Zimbra account lookups and
consistent mailbox access.

**"Missing required tool(s): imapsync bc"**
Install them (`apt install imapsync bc` on Debian/Ubuntu, or the
equivalent for your distro) and re-run.

**"Saved secrets file missing for this profile"**
The profile's `.conf` points at a password file under `.secrets/` that no
longer exists. Re-run the script, pick "new profile" with the same name
to recreate it, or switch that profile's password mode to "prompt" by
editing the `.conf` file's `PASS_MODE` line to `prompt`.

**zmprov-based status checks return nothing**
`zmprov` isn't installed or isn't on `$PATH` on this host — status checks
that rely on it are skipped with a warning, but migration, batch, verify,
and log-lookup features all still work normally.

**A migration seems stuck**
Use the timeout prompt in "Migrate Single User" or "Batch Migration" next
time, or `Ctrl+C` the current run — imapsync is safe to interrupt and
resume; just re-run the same migration and it will pick up where it left
off.