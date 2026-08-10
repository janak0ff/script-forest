#!/bin/bash
# master_migration.sh - Reusable IMAP/Zimbra Migration Management Tool
# Combines: Single migration, Batch migration, Status check, Verify sync, Resume failed
#
# Nothing is hardcoded. On first run it interviews you for connection details
# and saves a config profile (creds go in a separate, chmod 600, gitignore-able
# secrets file — never on the imapsync command line, never in plaintext logs).
#
# Usage:
#   ./master_migration.sh                 # interactive menu, prompts for/reuses a profile
#   ./master_migration.sh --profile NAME  # load a specific saved profile directly

set -o pipefail

# ============================================
# COLOR CODES
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${WHITE}  $1${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
}
print_subheader() { echo -e "${MAGENTA}─── $1 ───${NC}"; }
print_error()      { echo -e "${RED}[ERROR]${NC} $1"; }
print_success()    { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_info()       { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warning()    { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_result()     { echo -e "${CYAN}[RESULT]${NC} $1"; }

get_timestamp()   { date +%Y%m%d_%H%M%S; }
generate_logname(){ echo "$LOG_DIR/$(date +%Y_%m_%d_%H_%M_%S)_${1}.log"; }

pause() { read -r -p "Press Enter to continue..." _; }

# ============================================
# PRE-FLIGHT
# ============================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root (needed for zmprov / mailbox access)."
        exit 1
    fi
}

check_dependencies() {
    local missing=()
    command -v imapsync >/dev/null 2>&1 || missing+=("imapsync")
    command -v bc       >/dev/null 2>&1 || missing+=("bc")
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required tool(s): ${missing[*]}"
        print_info  "Install them first (e.g. apt install ${missing[*]})."
        exit 1
    fi
    IMAPSYNC_BIN="$(command -v imapsync)"
}

# ============================================
# VALIDATION HELPERS
# ============================================
validate_email() {
    [[ "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validate_host() {
    # accepts hostnames or IPv4 — good enough as a sanity check, not exhaustive
    [[ -n "$1" ]]
}

is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }

prompt_required() {
    # prompt_required "Prompt text" VARNAME [validator_fn]
    local prompt="$1" varname="$2" validator="$3" value
    while true; do
        read -r -p "$prompt: " value
        if [ -z "$value" ]; then
            print_error "This field is required."
            continue
        fi
        if [ -n "$validator" ] && ! "$validator" "$value"; then
            print_error "Invalid value for this field."
            continue
        fi
        printf -v "$varname" '%s' "$value"
        break
    done
}

prompt_optional() {
    # prompt_optional "Prompt text" VARNAME "default"
    local prompt="$1" varname="$2" default="$3" value
    read -r -p "$prompt [$default]: " value
    value="${value:-$default}"
    printf -v "$varname" '%s' "$value"
}

prompt_password() {
    # prompt_password "Prompt text" VARNAME
    # Typed in plain view (no -s) and taken as a single entry — no confirmation step.
    local prompt="$1" varname="$2" value
    while true; do
        read -r -p "$prompt: " value
        if [ -z "$value" ]; then
            print_error "Password cannot be empty."
            continue
        fi
        printf -v "$varname" '%s' "$value"
        break
    done
}

# ============================================
# PROFILE MANAGEMENT (connection config, no secrets)
# ============================================
# A "profile" stores source/destination/dir settings under $CONFIG_DIR/<name>.conf
# Passwords are NEVER stored in the profile file. They either live in a
# chmod-600 secrets file you point to, or are typed fresh each run.

WORK_ROOT_DEFAULT="$HOME/migration_tool"

select_or_create_profile() {
    print_header "MIGRATION PROFILE SETUP"
    echo ""
    prompt_optional "Base working directory (logs/reports/lists live here)" WORK_ROOT "$WORK_ROOT_DEFAULT"

    BASE_DIR="$WORK_ROOT"
    CONFIG_DIR="$BASE_DIR/profiles"
    LOG_DIR="$BASE_DIR/LOGS"
    REPORT_DIR="$BASE_DIR/reports"
    USER_LISTS_DIR="$BASE_DIR/user_lists"
    SECRETS_DIR="$BASE_DIR/.secrets"
    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$REPORT_DIR" "$USER_LISTS_DIR" "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"

    local profiles=()
    while IFS= read -r -d '' f; do
        profiles+=("$(basename "$f" .conf)")
    done < <(find "$CONFIG_DIR" -maxdepth 1 -name "*.conf" -print0 2>/dev/null)

    if [ ${#profiles[@]} -gt 0 ]; then
        echo ""
        echo "Existing profiles:"
        local i=1
        for p in "${profiles[@]}"; do
            echo "  $i) $p"
            ((i++))
        done
        echo "  n) Create a new profile"
        echo ""
        read -r -p "Select a profile number, or 'n' for new: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#profiles[@]} ]; then
            PROFILE_NAME="${profiles[$((choice-1))]}"
            load_profile "$PROFILE_NAME"
            return
        fi
    fi

    create_profile
}

create_profile() {
    echo ""
    print_subheader "New Profile"
    prompt_required "Profile name (e.g. clientname)" PROFILE_NAME
    PROFILE_NAME="${PROFILE_NAME// /_}"

    prompt_required "Source host (migrating FROM)" SOURCE_HOST validate_host
    prompt_required "Source auth user (admin/migration account on source)" SOURCE_AUTHUSER
    prompt_required "Destination host (migrating TO)" DEST_HOST validate_host
    prompt_required "Destination auth user (admin account on destination)" DEST_AUTHUSER

    echo ""
    print_info "Passwords are never written into the profile or passed on the"
    print_info "command line. Choose how imapsync should get them:"
    echo "  1) Store encrypted-at-rest in a chmod 600 secrets file (recommended)"
    echo "  2) Prompt me fresh every time I run a migration"
    read -r -p "Select option (1-2): " pw_mode

    if [ "$pw_mode" = "1" ]; then
        PASS_MODE="file"
        prompt_password "Password for $SOURCE_AUTHUSER (source)" SOURCE_PASS
        prompt_password "Password for $DEST_AUTHUSER (destination)" DEST_PASS
        SOURCE_PASS_FILE="$SECRETS_DIR/${PROFILE_NAME}_source.pass"
        DEST_PASS_FILE="$SECRETS_DIR/${PROFILE_NAME}_destination.pass"
        printf '%s' "$SOURCE_PASS" > "$SOURCE_PASS_FILE"
        printf '%s' "$DEST_PASS" > "$DEST_PASS_FILE"
        chmod 600 "$SOURCE_PASS_FILE" "$DEST_PASS_FILE"
        unset SOURCE_PASS DEST_PASS
    else
        PASS_MODE="prompt"
        SOURCE_PASS_FILE=""
        DEST_PASS_FILE=""
    fi

    cat > "$CONFIG_DIR/${PROFILE_NAME}.conf" <<EOF
# Migration profile: $PROFILE_NAME
# Generated $(date)
SOURCE_HOST="$SOURCE_HOST"
SOURCE_AUTHUSER="$SOURCE_AUTHUSER"
DEST_HOST="$DEST_HOST"
DEST_AUTHUSER="$DEST_AUTHUSER"
PASS_MODE="$PASS_MODE"
SOURCE_PASS_FILE="$SOURCE_PASS_FILE"
DEST_PASS_FILE="$DEST_PASS_FILE"
EOF
    chmod 600 "$CONFIG_DIR/${PROFILE_NAME}.conf"
    print_success "Profile saved: $CONFIG_DIR/${PROFILE_NAME}.conf"
    pause
}

load_profile() {
    local name="$1"
    local conf="$CONFIG_DIR/${name}.conf"
    if [ ! -f "$conf" ]; then
        print_error "Profile not found: $name"
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$conf"
    PROFILE_NAME="$name"

    if [ "$PASS_MODE" = "prompt" ]; then
        echo ""
        print_info "Profile '$PROFILE_NAME' is set to prompt for passwords each run."
        prompt_password "Password for $SOURCE_AUTHUSER (source, $SOURCE_HOST)" SOURCE_PASS
        prompt_password "Password for $DEST_AUTHUSER (destination, $DEST_HOST)" DEST_PASS
        SESSION_SOURCE_PASS_FILE="$(mktemp)"
        SESSION_DEST_PASS_FILE="$(mktemp)"
        printf '%s' "$SOURCE_PASS" > "$SESSION_SOURCE_PASS_FILE"
        printf '%s' "$DEST_PASS" > "$SESSION_DEST_PASS_FILE"
        chmod 600 "$SESSION_SOURCE_PASS_FILE" "$SESSION_DEST_PASS_FILE"
        unset SOURCE_PASS DEST_PASS
        SOURCE_PASS_FILE="$SESSION_SOURCE_PASS_FILE"
        DEST_PASS_FILE="$SESSION_DEST_PASS_FILE"
        USING_TEMP_PASS_FILES=1
    else
        if [ ! -f "$SOURCE_PASS_FILE" ] || [ ! -f "$DEST_PASS_FILE" ]; then
            print_error "Saved secrets file missing for this profile. Re-run and choose 'n' to recreate it."
            exit 1
        fi
        USING_TEMP_PASS_FILES=0
    fi
}

cleanup_session_secrets() {
    if [ "${USING_TEMP_PASS_FILES:-0}" = "1" ]; then
        shred -u "$SESSION_SOURCE_PASS_FILE" "$SESSION_DEST_PASS_FILE" 2>/dev/null || rm -f "$SESSION_SOURCE_PASS_FILE" "$SESSION_DEST_PASS_FILE"
    fi
}
trap cleanup_session_secrets EXIT

# ============================================
# IMAPSYNC WRAPPER
# ============================================
# Note: imapsync's own CLI flags (--host1/--host2/--passfile1/--passfile2 etc.)
# are fixed by imapsync itself and can't be renamed — only our internal
# variable names and prompts use "source/destination" terminology.
run_imapsync() {
    local user_email="$1" log_file="$2"; shift 2
    "$IMAPSYNC_BIN" \
        --nosyncacls \
        --subscribe \
        --syncinternaldates \
        --host1 "$SOURCE_HOST" \
        --user1 "$user_email" \
        --authuser1 "$SOURCE_AUTHUSER" \
        --passfile1 "$SOURCE_PASS_FILE" \
        --host2 "$DEST_HOST" \
        --user2 "$user_email" \
        --authuser2 "$DEST_AUTHUSER" \
        --passfile2 "$DEST_PASS_FILE" \
        "$@" \
        2>&1 | tee "$log_file"
    return "${PIPESTATUS[0]}"
}

# ============================================
# ZIMBRA (zmprov) HELPERS — optional, only used if zmprov is present
# ============================================
have_zmprov() { command -v zmprov >/dev/null 2>&1; }

check_user_exists() {
    have_zmprov && zmprov -l ga "$1" &>/dev/null
}

get_mailbox_size() {
    have_zmprov || { echo 0; return; }
    zmprov -l ga "$1" 2>/dev/null | grep "zimbraMailTotalSize:" | cut -d' ' -f2
}

human_readable_size() {
    local bytes="${1:-0}"
    if [ "$bytes" -gt 1073741824 ] 2>/dev/null; then
        echo "$(echo "scale=2; $bytes/1073741824" | bc) GB"
    elif [ "$bytes" -gt 1048576 ] 2>/dev/null; then
        echo "$(echo "scale=2; $bytes/1048576" | bc) MB"
    elif [ "$bytes" -gt 1024 ] 2>/dev/null; then
        echo "$(echo "scale=2; $bytes/1024" | bc) KB"
    else
        echo "${bytes:-0} bytes"
    fi
}

# ============================================
# 1. SINGLE USER MIGRATION
# ============================================
migrate_single_user() {
    clear
    print_header "SINGLE USER MIGRATION — Profile: $PROFILE_NAME"
    echo ""

    prompt_required "Enter user email to migrate" USER_EMAIL validate_email

    echo ""
    print_info "Migrating: $USER_EMAIL"
    print_info "Source: $SOURCE_HOST  ->  Destination: $DEST_HOST"
    echo ""
    read -r -p "Continue with migration? (y/n): " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { print_info "Cancelled"; pause; return; }

    local timeout_secs
    prompt_optional "Timeout in seconds (0 = no timeout)" timeout_secs "0"

    LOG_FILE=$(generate_logname "single_${USER_EMAIL}")
    echo ""
    print_info "Running imapsync... (this may take a while)"
    echo ""

    if [ "$timeout_secs" != "0" ] && is_number "$timeout_secs"; then
        timeout "$timeout_secs" "$IMAPSYNC_BIN" \
            --nosyncacls --subscribe --syncinternaldates \
            --host1 "$SOURCE_HOST" --user1 "$USER_EMAIL" --authuser1 "$SOURCE_AUTHUSER" --passfile1 "$SOURCE_PASS_FILE" \
            --host2 "$DEST_HOST" --user2 "$USER_EMAIL" --authuser2 "$DEST_AUTHUSER" --passfile2 "$DEST_PASS_FILE" \
            2>&1 | tee "$LOG_FILE"
        EXIT_CODE=${PIPESTATUS[0]}
    else
        run_imapsync "$USER_EMAIL" "$LOG_FILE"
        EXIT_CODE=$?
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ "$EXIT_CODE" -eq 0 ]; then
        print_success "Migration completed for $USER_EMAIL"
        echo "Log saved to: $LOG_FILE"
        echo ""
        print_subheader "Migration Summary"
        grep -E "Messages transferred|Messages skipped|Total bytes transferred" "$LOG_FILE" | tail -3
    elif [ "$EXIT_CODE" -eq 124 ]; then
        print_error "Migration TIMED OUT for $USER_EMAIL after ${timeout_secs}s"
        echo "Partial log: $LOG_FILE"
    else
        print_error "Migration failed for $USER_EMAIL (Exit code: $EXIT_CODE)"
        echo "Check log: $LOG_FILE"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    pause
}

# ============================================
# 2. BATCH MIGRATION
# ============================================
batch_migrate() {
    clear
    print_header "BATCH MIGRATION — Profile: $PROFILE_NAME"
    echo ""
    echo "Available user list files:"
    echo "─────────────────────────"
    find "$USER_LISTS_DIR" -maxdepth 1 -name "*.txt" -type f 2>/dev/null | while read -r file; do
        local count
        count=$(grep -vc '^#\|^$' "$file")
        echo "  $(basename "$file") - $count users"
    done
    echo ""
    echo "Options:"
    echo "  1) Use existing user list file"
    echo "  2) Create new user list file"
    echo "  3) Enter users manually (this run only)"
    echo "  0) Cancel"
    echo ""
    read -r -p "Select option (0-3): " BATCH_OPTION

    local USER_FILE=""
    case $BATCH_OPTION in
        0) print_info "Cancelled"; pause; return ;;
        1)
            read -r -p "Enter filename (from $USER_LISTS_DIR/): " uf
            USER_FILE="$USER_LISTS_DIR/$uf"
            [ -f "$USER_FILE" ] || { print_error "File not found: $USER_FILE"; pause; return; }
            ;;
        2)
            read -r -p "Enter new filename (without .txt): " nf
            USER_FILE="$USER_LISTS_DIR/${nf}.txt"
            echo "Enter users one per line (blank line to finish):"
            : > "$USER_FILE"
            while true; do
                read -r -p "> " line
                [ -z "$line" ] && break
                if validate_email "$line"; then
                    echo "$line" >> "$USER_FILE"
                else
                    print_warning "Skipped invalid email: $line"
                fi
            done
            [ -s "$USER_FILE" ] || { print_error "No valid users added"; rm -f "$USER_FILE"; pause; return; }
            print_success "Created: $USER_FILE"
            ;;
        3)
            USER_FILE="/tmp/users_manual_$(get_timestamp).txt"
            echo "Enter users one per line (blank line to finish):"
            : > "$USER_FILE"
            while true; do
                read -r -p "> " line
                [ -z "$line" ] && break
                if validate_email "$line"; then
                    echo "$line" >> "$USER_FILE"
                else
                    print_warning "Skipped invalid email: $line"
                fi
            done
            [ -s "$USER_FILE" ] || { print_error "No valid users added"; rm -f "$USER_FILE"; pause; return; }
            ;;
        *) print_error "Invalid option"; pause; return ;;
    esac

    # Filter to only valid, non-comment lines
    local VALID_FILE
    VALID_FILE="$(mktemp)"
    grep -v '^#\|^$' "$USER_FILE" | while read -r line; do
        if validate_email "$line"; then
            echo "$line"
        else
            print_warning "Skipping invalid entry in list: $line" >&2
        fi
    done > "$VALID_FILE"

    TOTAL_USERS=$(wc -l < "$VALID_FILE")
    if [ "$TOTAL_USERS" -eq 0 ]; then
        print_error "No valid users found in file"
        rm -f "$VALID_FILE"
        pause
        return
    fi

    echo ""
    print_info "Found $TOTAL_USERS valid users to migrate"
    echo ""
    echo "First 10:"
    head -10 "$VALID_FILE" | sed 's/^/  /'
    [ "$TOTAL_USERS" -gt 10 ] && echo "  ... and $((TOTAL_USERS - 10)) more"
    echo ""

    read -r -p "Continue with batch migration? (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Cancelled"; rm -f "$VALID_FILE"; pause; return
    fi

    local timeout_secs
    prompt_optional "Per-user timeout in seconds (0 = no timeout)" timeout_secs "0"

    REPORT_FILE="$REPORT_DIR/batch_report_$(get_timestamp).txt"
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    FAILED_USERS=()

    {
        echo "Batch Migration Report - $(date)"
        echo "Profile: $PROFILE_NAME"
        echo "=============================="
        echo "User File: $USER_FILE"
        echo "Total Users: $TOTAL_USERS"
        echo "Started: $(date)"
        echo ""
        echo "RESULTS:"
        echo "────────"
    } > "$REPORT_FILE"

    echo ""
    print_info "Starting batch migration..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    while IFS= read -r USER_EMAIL || [ -n "$USER_EMAIL" ]; do
        [ -z "$USER_EMAIL" ] && continue
        echo ""
        print_info "Migrating: $USER_EMAIL"
        LOG_FILE=$(generate_logname "batch_${USER_EMAIL}")

        if [ "$timeout_secs" != "0" ] && is_number "$timeout_secs"; then
            timeout "$timeout_secs" "$IMAPSYNC_BIN" \
                --nosyncacls --subscribe --syncinternaldates \
                --host1 "$SOURCE_HOST" --user1 "$USER_EMAIL" --authuser1 "$SOURCE_AUTHUSER" --passfile1 "$SOURCE_PASS_FILE" \
                --host2 "$DEST_HOST" --user2 "$USER_EMAIL" --authuser2 "$DEST_AUTHUSER" --passfile2 "$DEST_PASS_FILE" \
                > "$LOG_FILE" 2>&1
        else
            "$IMAPSYNC_BIN" \
                --nosyncacls --subscribe --syncinternaldates \
                --host1 "$SOURCE_HOST" --user1 "$USER_EMAIL" --authuser1 "$SOURCE_AUTHUSER" --passfile1 "$SOURCE_PASS_FILE" \
                --host2 "$DEST_HOST" --user2 "$USER_EMAIL" --authuser2 "$DEST_AUTHUSER" --passfile2 "$DEST_PASS_FILE" \
                > "$LOG_FILE" 2>&1
        fi
        EXIT_CODE=$?

        if [ "$EXIT_CODE" -eq 0 ]; then
            print_success "✓ $USER_EMAIL - SUCCESS"
            echo "SUCCESS: $USER_EMAIL" >> "$REPORT_FILE"
            ((SUCCESS_COUNT++))
        else
            print_error "✗ $USER_EMAIL - FAILED (Exit: $EXIT_CODE)"
            echo "FAILED: $USER_EMAIL (Exit: $EXIT_CODE)" >> "$REPORT_FILE"
            FAILED_USERS+=("$USER_EMAIL")
            ((FAIL_COUNT++))
        fi
        echo "Progress: $((SUCCESS_COUNT + FAIL_COUNT))/$TOTAL_USERS"
    done < "$VALID_FILE"

    {
        echo ""
        echo "SUMMARY:"
        echo "────────────────"
        echo "Total Users: $TOTAL_USERS"
        echo "Successful: $SUCCESS_COUNT"
        echo "Failed: $FAIL_COUNT"
        echo "Completion: $(date)"
    } >> "$REPORT_FILE"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_subheader "Batch Migration Complete"
    print_success "Successful: $SUCCESS_COUNT"
    print_error "Failed: $FAIL_COUNT"
    if [ "$FAIL_COUNT" -gt 0 ]; then
        echo ""
        print_warning "Failed users:"
        printf '  %s\n' "${FAILED_USERS[@]}"
        echo ""
        print_info "Use 'Resume Failed' option to retry"
    fi
    print_info "Report saved to: $REPORT_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    rm -f "$VALID_FILE"
    pause
}

# ============================================
# 3. CHECK MIGRATION STATUS
# ============================================
check_status() {
    clear
    print_header "MIGRATION STATUS CHECK — Profile: $PROFILE_NAME"
    echo ""
    prompt_required "Enter user email to check" USER_EMAIL validate_email
    echo ""
    print_subheader "Checking: $USER_EMAIL"
    echo ""

    if have_zmprov; then
        if check_user_exists "$USER_EMAIL"; then
            print_success "✓ User exists on destination server"
            echo ""
            print_subheader "User Details"
            SIZE=$(get_mailbox_size "$USER_EMAIL")
            echo "Mailbox Size: $(human_readable_size "$SIZE")"
            LAST_LOGIN=$(zmprov -l ga "$USER_EMAIL" 2>/dev/null | grep "zimbraLastLogonTimestamp:" | cut -d' ' -f2)
            echo "Last Login: ${LAST_LOGIN:-Never}"
            STATUS=$(zmprov -l ga "$USER_EMAIL" 2>/dev/null | grep "zimbraAccountStatus:" | cut -d' ' -f2)
            echo "Account Status: ${STATUS:-unknown}"
            PWD_CHANGE=$(zmprov -l ga "$USER_EMAIL" 2>/dev/null | grep "zimbraPasswordMustChange:" | cut -d' ' -f2)
            echo "Password Must Change: ${PWD_CHANGE:-unset}"
            QUOTA=$(zmprov -l ga "$USER_EMAIL" 2>/dev/null | grep "zimbraMailQuota:" | cut -d' ' -f2)
            echo "Mail Quota: $([ -n "$QUOTA" ] && human_readable_size "$QUOTA" || echo Unlimited)"
        else
            print_error "✗ User NOT found on destination server"
        fi
    else
        print_warning "zmprov not found on this host — skipping Zimbra-specific lookup."
        print_info "(This still works for plain IMAP-to-IMAP migrations; the log check below still applies.)"
    fi

    echo ""
    print_subheader "Migration Logs"
    LOG_FILES=$(find "$BASE_DIR" -name "*${USER_EMAIL}*.log" -type f 2>/dev/null | sort -r)
    if [ -n "$LOG_FILES" ]; then
        echo "Found logs for this user:"
        echo ""
        echo "$LOG_FILES" | head -5 | while read -r file; do
            local status
            status=$(grep "return value" "$file" 2>/dev/null | head -1)
            echo "  📁 $(basename "$file")"
            echo "     Status: ${status:-No result}"
        done
        echo ""
        read -r -p "View latest log? (y/n): " VIEW_LOG
        if [[ "$VIEW_LOG" =~ ^[Yy]$ ]]; then
            LATEST_LOG=$(echo "$LOG_FILES" | head -1)
            echo ""
            print_subheader "Latest Log: $(basename "$LATEST_LOG")"
            echo "─────────────────────────────────────────────────"
            tail -30 "$LATEST_LOG"
        fi
    else
        print_warning "No migration logs found for this user"
    fi
    pause
}

# ============================================
# 4. VERIFY SYNC (dry run diff)
# ============================================
verify_sync() {
    clear
    print_header "VERIFY SYNC (Source vs Destination) — Profile: $PROFILE_NAME"
    echo ""
    prompt_required "Enter user email to verify" USER_EMAIL validate_email

    if have_zmprov && ! check_user_exists "$USER_EMAIL"; then
        print_error "User does not exist on destination server"
        pause
        return
    fi

    print_info "Verifying: $USER_EMAIL"
    echo ""
    echo "Running verification (dry run, this may take a moment)..."
    echo ""
    VERIFY_LOG=$(generate_logname "verify_${USER_EMAIL}")
    run_imapsync "$USER_EMAIL" "$VERIFY_LOG" --dry
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_subheader "Verification Results"
    echo ""
    grep -E "Nb messages|Total size|Biggest message|Messages transferred|Messages skipped|duplicate" "$VERIFY_LOG" | head -20
    echo ""
    echo "Detailed log: $VERIFY_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    pause
}

# ============================================
# 5. RESUME FAILED MIGRATIONS
# ============================================
resume_failed() {
    clear
    print_header "RESUME FAILED MIGRATIONS — Profile: $PROFILE_NAME"
    echo ""
    REPORTS=$(find "$REPORT_DIR" -name "batch_report_*.txt" -type f 2>/dev/null | sort -r)
    if [ -z "$REPORTS" ]; then
        print_error "No migration reports found"
        pause
        return
    fi

    echo "Available reports:"
    echo "──────────────────"
    local i=1
    declare -A REPORT_MAP
    while IFS= read -r report; do
        local total failed
        total=$(grep -c "^SUCCESS:" "$report" 2>/dev/null)
        failed=$(grep -c "^FAILED:" "$report" 2>/dev/null)
        echo "  $i) $(basename "$report") (Success: $total, Failed: $failed)"
        REPORT_MAP[$i]="$report"
        ((i++))
    done <<< "$REPORTS"

    echo ""
    read -r -p "Select report (1-$((i-1))): " SELECTION
    if [ -z "${REPORT_MAP[$SELECTION]:-}" ]; then
        print_error "Invalid selection"
        pause
        return
    fi
    REPORT_FILE="${REPORT_MAP[$SELECTION]}"
    print_info "Using report: $(basename "$REPORT_FILE")"

    mapfile -t FAILED_USERS < <(grep "^FAILED:" "$REPORT_FILE" | awk '{print $2}')
    if [ ${#FAILED_USERS[@]} -eq 0 ]; then
        print_success "No failed users in this report"
        pause
        return
    fi

    echo ""
    print_warning "Found ${#FAILED_USERS[@]} failed users:"
    printf '  %s\n' "${FAILED_USERS[@]:0:20}"
    [ ${#FAILED_USERS[@]} -gt 20 ] && echo "... and $((${#FAILED_USERS[@]} - 20)) more"
    echo ""

    read -r -p "Resume these migrations? (y/n): " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { print_info "Cancelled"; pause; return; }

    RESUME_REPORT="$REPORT_DIR/resume_report_$(get_timestamp).txt"
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    {
        echo "Resume Migration Report - $(date)"
        echo "Profile: $PROFILE_NAME"
        echo "================================"
        echo "Original Report: $(basename "$REPORT_FILE")"
        echo ""
    } > "$RESUME_REPORT"

    echo ""
    print_info "Resuming migrations..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for USER_EMAIL in "${FAILED_USERS[@]}"; do
        echo ""
        print_info "Retrying: $USER_EMAIL"
        LOG_FILE=$(generate_logname "resume_${USER_EMAIL}")
        run_imapsync "$USER_EMAIL" "$LOG_FILE" >/dev/null
        if [ $? -eq 0 ]; then
            print_success "✓ $USER_EMAIL - SUCCESS"
            echo "SUCCESS: $USER_EMAIL" >> "$RESUME_REPORT"
            ((SUCCESS_COUNT++))
        else
            print_error "✗ $USER_EMAIL - FAILED AGAIN"
            echo "FAILED: $USER_EMAIL" >> "$RESUME_REPORT"
            ((FAIL_COUNT++))
        fi
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_subheader "Resume Complete"
    print_success "Successful: $SUCCESS_COUNT"
    print_error "Failed: $FAIL_COUNT"
    print_info "Report: $RESUME_REPORT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    pause
}

# ============================================
# USER LIST MANAGEMENT
# ============================================
manage_user_lists() {
    clear
    print_header "USER LIST MANAGEMENT — Profile: $PROFILE_NAME"
    echo ""
    echo "Current user lists:"
    echo "───────────────────"
    if [ -n "$(ls -A "$USER_LISTS_DIR" 2>/dev/null)" ]; then
        find "$USER_LISTS_DIR" -maxdepth 1 -name "*.txt" -type f 2>/dev/null | while read -r file; do
            local count
            count=$(grep -vc '^#\|^$' "$file")
            echo "  📄 $(basename "$file") - $count users"
        done
    else
        echo "  No user lists found"
    fi
    echo ""
    echo "Options:"
    echo "  1) Create new user list"
    echo "  2) View user list contents"
    echo "  3) Delete user list"
    echo "  4) Import users from a file path"
    echo "  0) Back to main menu"
    echo ""
    read -r -p "Select option (0-4): " LIST_OPTION

    case $LIST_OPTION in
        0) return ;;
        1)
            read -r -p "Enter filename (without .txt): " nl
            local USER_FILE="$USER_LISTS_DIR/${nl}.txt"
            echo "Enter users one per line (blank line to finish):"
            : > "$USER_FILE"
            while true; do
                read -r -p "> " line
                [ -z "$line" ] && break
                validate_email "$line" && echo "$line" >> "$USER_FILE" || print_warning "Skipped invalid email: $line"
            done
            if [ -s "$USER_FILE" ]; then
                print_success "Created list with $(wc -l < "$USER_FILE") users"
            else
                print_error "No users added"; rm -f "$USER_FILE"
            fi
            ;;
        2)
            read -r -p "Enter filename to view: " vf
            local VIEW_FILE="$USER_LISTS_DIR/$vf"
            if [ -f "$VIEW_FILE" ]; then
                echo ""
                echo "─────────────────────────────────────────────────"
                cat -n "$VIEW_FILE"
                echo "─────────────────────────────────────────────────"
                print_info "Total users: $(grep -vc '^#\|^$' "$VIEW_FILE")"
            else
                print_error "File not found"
            fi
            ;;
        3)
            read -r -p "Enter filename to delete: " df
            local DEL_FILE="$USER_LISTS_DIR/$df"
            if [ -f "$DEL_FILE" ]; then
                read -r -p "Confirm delete? (y/n): " CONFIRM
                if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                    rm -f "$DEL_FILE"; print_success "Deleted: $DEL_FILE"
                else
                    print_info "Cancelled"
                fi
            else
                print_error "File not found"
            fi
            ;;
        4)
            read -r -p "Enter source file path: " IMPORT_FILE
            if [ ! -f "$IMPORT_FILE" ]; then
                print_error "Source file not found"
            else
                read -r -p "Enter target filename (without .txt): " tn
                cp "$IMPORT_FILE" "$USER_LISTS_DIR/${tn}.txt"
                print_success "Imported $(grep -vc '^#\|^$' "$USER_LISTS_DIR/${tn}.txt") users"
            fi
            ;;
        *) print_error "Invalid option" ;;
    esac
    pause
}

# ============================================
# VIEW REPORTS
# ============================================
view_reports() {
    clear
    print_header "VIEW REPORTS — Profile: $PROFILE_NAME"
    echo ""
    REPORTS=$(find "$REPORT_DIR" -name "*.txt" -type f 2>/dev/null | sort -r)
    if [ -z "$REPORTS" ]; then
        echo "  No reports found"
        pause
        return
    fi

    echo "Available reports:"
    echo "──────────────────"
    local i=1
    declare -A REPORT_MAP
    while IFS= read -r report; do
        echo "  $i) $(basename "$report") ($(wc -l < "$report") lines)"
        REPORT_MAP[$i]="$report"
        ((i++))
    done <<< "$REPORTS"

    echo ""
    read -r -p "Select report to view (0 to cancel): " SEL
    [[ "$SEL" =~ ^[0-9]+$ ]] || { print_error "Invalid input"; pause; return; }
    [ "$SEL" -eq 0 ] && return
    if [ -z "${REPORT_MAP[$SEL]:-}" ]; then
        print_error "Invalid selection"
        pause
        return
    fi
    REPORT_FILE="${REPORT_MAP[$SEL]}"
    echo ""
    echo "─────────────────────────────────────────────────"
    echo "File: $(basename "$REPORT_FILE")"
    echo "─────────────────────────────────────────────────"
    cat "$REPORT_FILE"
    echo "─────────────────────────────────────────────────"
    pause
}

# ============================================
# SWITCH PROFILE
# ============================================
switch_profile() {
    cleanup_session_secrets
    select_or_create_profile
}

# ============================================
# MAIN MENU
# ============================================
show_menu() {
    clear
    print_header "IMAP / ZIMBRA MIGRATION TOOL"
    echo ""
    echo "  ┌─────────────────────────────────────────────────┐"
    echo "  │  1.  Migrate Single User                         │"
    echo "  │  2.  Batch Migration (from user list)            │"
    echo "  │  3.  Check Migration Status                      │"
    echo "  │  4.  Verify Sync (Source vs Destination)         │"
    echo "  │  5.  Resume Failed Migrations                    │"
    echo "  │  6.  Manage User Lists                           │"
    echo "  │  7.  View Reports                                │"
    echo "  │  8.  Switch / Create Profile                     │"
    echo "  │                                                   │"
    echo "  │  0.  Exit                                        │"
    echo "  └─────────────────────────────────────────────────┘"
    echo ""
    echo "📊 Status:"
    echo "  • Profile: $PROFILE_NAME  ($SOURCE_AUTHUSER@$SOURCE_HOST -> $DEST_AUTHUSER@$DEST_HOST)"
    echo "  • Base Directory: $BASE_DIR"
    echo ""
    read -r -p "Select option (0-8): " MENU_OPTION

    case $MENU_OPTION in
        1) migrate_single_user ;;
        2) batch_migrate ;;
        3) check_status ;;
        4) verify_sync ;;
        5) resume_failed ;;
        6) manage_user_lists ;;
        7) view_reports ;;
        8) switch_profile ;;
        0) echo ""; print_info "Exiting..."; cleanup_session_secrets; exit 0 ;;
        *) print_error "Invalid option"; sleep 1 ;;
    esac
}

# ============================================
# MAIN EXECUTION
# ============================================
check_root
check_dependencies

# --profile NAME flag support for non-interactive profile load
if [ "$1" = "--profile" ] && [ -n "$2" ]; then
    WORK_ROOT="${WORK_ROOT:-$WORK_ROOT_DEFAULT}"
    BASE_DIR="$WORK_ROOT"
    CONFIG_DIR="$BASE_DIR/profiles"
    LOG_DIR="$BASE_DIR/LOGS"
    REPORT_DIR="$BASE_DIR/reports"
    USER_LISTS_DIR="$BASE_DIR/user_lists"
    SECRETS_DIR="$BASE_DIR/.secrets"
    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$REPORT_DIR" "$USER_LISTS_DIR" "$SECRETS_DIR"
    load_profile "$2"
else
    select_or_create_profile
fi

while true; do
    show_menu
done