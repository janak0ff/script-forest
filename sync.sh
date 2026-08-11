#!/bin/bash
# Universal IMAP Email Migration Tool
# Supports: Gmail, Zimbra, Outlook/Office 365, Yahoo, and any IMAP server

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
NC='\033[0m'

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

get_timestamp()   { date +%Y%m%d_%H%M%S; }
generate_logname() {
    local safe_name=$(echo "$1" | tr '@' '_' | tr '.' '_')
    echo "$LOG_DIR/$(date +%Y_%m_%d_%H_%M_%S)_${safe_name}.log"
}
pause() { read -r -p "Press Enter to continue..." _; }

# ============================================
# PROVIDER HELPERS
# ============================================
provider_name() {
    case "$1" in
        1) echo "Gmail / Google Workspace" ;;
        2) echo "Zimbra" ;;
        3) echo "Outlook / Office 365 / Exchange" ;;
        4) echo "Yahoo Mail" ;;
        *) echo "Other IMAP Server" ;;
    esac
}

provider_auth_notice() {
    case "$1" in
        1) print_warning "Gmail/Google Workspace requires an App Password if 2FA is enabled." ;;
        3) print_warning "Office 365/Exchange often requires OAuth or an App Password." ;;
        4) print_warning "Yahoo Mail requires an App Password if 2-step verification is enabled." ;;
    esac
}

validate_mapping_line() {
    local line="$1" src dest
    [[ "$line" != *:* ]] && return 1
    src="${line%%:*}"
    dest="${line#*:}"
    validate_email "$src" && validate_email "$dest"
}

# ============================================
# PRE-FLIGHT
# ============================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root."
        exit 1
    fi
}

check_dependencies() {
    local missing=()
    command -v imapsync >/dev/null 2>&1 || missing+=("imapsync")
    command -v bc >/dev/null 2>&1 || missing+=("bc")
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing: ${missing[*]}"
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
validate_host() { [[ -n "$1" ]]; }
is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }

prompt_required() {
    local prompt="$1" varname="$2" validator="$3" value
    while true; do
        read -r -p "$prompt: " value
        if [ -z "$value" ]; then
            print_error "This field is required."
            continue
        fi
        if [ -n "$validator" ] && ! "$validator" "$value"; then
            print_error "Invalid value."
            continue
        fi
        printf -v "$varname" '%s' "$value"
        break
    done
}

prompt_optional() {
    local prompt="$1" varname="$2" default="$3" value
    read -r -p "$prompt [$default]: " value
    value="${value:-$default}"
    printf -v "$varname" '%s' "$value"
}

prompt_password() {
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
# PROFILE MANAGEMENT
# ============================================
WORK_ROOT_DEFAULT="$HOME/migration_tool"

select_or_create_profile() {
    print_header "MIGRATION PROFILE SETUP"
    echo ""
    prompt_optional "Base working directory" WORK_ROOT "$WORK_ROOT_DEFAULT"

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
        echo "  n) Create new"
        echo ""
        read -r -p "Select profile or 'n': " choice
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
    prompt_required "Profile name" PROFILE_NAME
    PROFILE_NAME="${PROFILE_NAME// /_}"

    echo ""
    print_info "Select source provider:"
    echo "  1) Gmail / Google Workspace"
    echo "  2) Zimbra"
    echo "  3) Outlook / Office 365 / Exchange"
    echo "  4) Yahoo Mail"
    echo "  5) Other IMAP Server"
    read -r -p "Select (1-5): " SOURCE_PROVIDER
    provider_auth_notice "$SOURCE_PROVIDER"

    case $SOURCE_PROVIDER in
        1)
            SOURCE_HOST="imap.gmail.com"
            SOURCE_PORT="993"
            SOURCE_SSL="--ssl1"
            SOURCE_OPTIONS="--gmail1"
            ;;
        2)
            prompt_required "Source host" SOURCE_HOST validate_host
            SOURCE_PORT="993"
            SOURCE_SSL="--ssl1"
            SOURCE_OPTIONS=""
            ;;
        3)
            SOURCE_HOST="outlook.office365.com"
            SOURCE_PORT="993"
            SOURCE_SSL="--ssl1"
            SOURCE_OPTIONS=""
            ;;
        4)
            SOURCE_HOST="imap.mail.yahoo.com"
            SOURCE_PORT="993"
            SOURCE_SSL="--ssl1"
            SOURCE_OPTIONS=""
            ;;
        *)
            prompt_required "Source host" SOURCE_HOST validate_host
            prompt_optional "Source port" SOURCE_PORT "993"
            read -r -p "Use SSL? (y/n): " use_ssl
            if [[ "$use_ssl" =~ ^[Yy]$ ]]; then
                SOURCE_SSL="--ssl1"
            else
                SOURCE_SSL=""
            fi
            SOURCE_OPTIONS=""
            ;;
    esac

    prompt_required "Source auth user" SOURCE_AUTHUSER validate_email

    echo ""
    print_info "Select destination provider:"
    echo "  1) Gmail / Google Workspace"
    echo "  2) Zimbra"
    echo "  3) Outlook / Office 365 / Exchange"
    echo "  4) Yahoo Mail"
    echo "  5) Other IMAP Server"
    read -r -p "Select (1-5): " DEST_PROVIDER
    provider_auth_notice "$DEST_PROVIDER"

    case $DEST_PROVIDER in
        1)
            DEST_HOST="imap.gmail.com"
            DEST_PORT="993"
            DEST_SSL="--ssl2"
            DEST_OPTIONS="--gmail2"
            ;;
        2)
            prompt_required "Destination host" DEST_HOST validate_host
            DEST_PORT="993"
            DEST_SSL="--ssl2"
            DEST_OPTIONS=""
            ;;
        3)
            DEST_HOST="outlook.office365.com"
            DEST_PORT="993"
            DEST_SSL="--ssl2"
            DEST_OPTIONS=""
            ;;
        4)
            DEST_HOST="imap.mail.yahoo.com"
            DEST_PORT="993"
            DEST_SSL="--ssl2"
            DEST_OPTIONS=""
            ;;
        *)
            prompt_required "Destination host" DEST_HOST validate_host
            prompt_optional "Destination port" DEST_PORT "993"
            read -r -p "Use SSL? (y/n): " use_ssl
            if [[ "$use_ssl" =~ ^[Yy]$ ]]; then
                DEST_SSL="--ssl2"
            else
                DEST_SSL=""
            fi
            DEST_OPTIONS=""
            ;;
    esac

    prompt_required "Destination auth user" DEST_AUTHUSER validate_email

    echo ""
    print_info "Password options:"
    echo "  1) Store in chmod 600 secrets file (recommended)"
    echo "  2) Prompt me each time"
    read -r -p "Select (1-2): " pw_mode

    if [ "$pw_mode" = "1" ]; then
        PASS_MODE="file"
        prompt_password "Source password" SOURCE_PASS
        prompt_password "Destination password" DEST_PASS
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
SOURCE_PROVIDER="$SOURCE_PROVIDER"
SOURCE_HOST="$SOURCE_HOST"
SOURCE_PORT="$SOURCE_PORT"
SOURCE_SSL="$SOURCE_SSL"
SOURCE_AUTHUSER="$SOURCE_AUTHUSER"
SOURCE_OPTIONS="$SOURCE_OPTIONS"
DEST_PROVIDER="$DEST_PROVIDER"
DEST_HOST="$DEST_HOST"
DEST_PORT="$DEST_PORT"
DEST_SSL="$DEST_SSL"
DEST_AUTHUSER="$DEST_AUTHUSER"
DEST_OPTIONS="$DEST_OPTIONS"
PASS_MODE="$PASS_MODE"
SOURCE_PASS_FILE="$SOURCE_PASS_FILE"
DEST_PASS_FILE="$DEST_PASS_FILE"
EOF
    chmod 600 "$CONFIG_DIR/${PROFILE_NAME}.conf"
    print_success "Profile saved"
    pause
}

load_profile() {
    local name="$1"
    local conf="$CONFIG_DIR/${name}.conf"
    if [ ! -f "$conf" ]; then
        print_error "Profile not found"
        exit 1
    fi
    source "$conf"
    PROFILE_NAME="$name"

    if [ "$PASS_MODE" = "prompt" ]; then
        echo ""
        print_info "Profile '$PROFILE_NAME' prompts for passwords."
        prompt_password "Source password" SOURCE_PASS
        prompt_password "Destination password" DEST_PASS
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
            print_error "Secrets file missing"
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
run_imapsync() {
    local user1="$1" user2="$2" log_file="$3"; shift 3
    local timeout_secs="0"
    local extra_args=()

    while [ $# -gt 0 ]; do
        if [ "$1" = "--timeout" ]; then
            timeout_secs="$2"
            shift 2
        else
            extra_args+=("$1")
            shift
        fi
    done

    local cmd=()
    [ "$timeout_secs" != "0" ] && is_number "$timeout_secs" && cmd+=("timeout" "$timeout_secs")
    cmd+=("$IMAPSYNC_BIN")

    [ -n "$SOURCE_SSL" ] && cmd+=("$SOURCE_SSL")
    cmd+=("--host1" "$SOURCE_HOST")
    [ -n "$SOURCE_PORT" ] && cmd+=("--port1" "$SOURCE_PORT")
    cmd+=("--user1" "$user1")
    cmd+=("--authuser1" "$SOURCE_AUTHUSER")
    cmd+=("--passfile1" "$SOURCE_PASS_FILE")
    [ -n "$SOURCE_OPTIONS" ] && cmd+=("$SOURCE_OPTIONS")

    [ -n "$DEST_SSL" ] && cmd+=("$DEST_SSL")
    cmd+=("--host2" "$DEST_HOST")
    [ -n "$DEST_PORT" ] && cmd+=("--port2" "$DEST_PORT")
    cmd+=("--user2" "$user2")
    cmd+=("--authuser2" "$DEST_AUTHUSER")
    cmd+=("--passfile2" "$DEST_PASS_FILE")
    [ -n "$DEST_OPTIONS" ] && cmd+=("$DEST_OPTIONS")

    cmd+=("--nosyncacls" "--subscribe" "--syncinternaldates")
    cmd+=("${extra_args[@]}")

    "${cmd[@]}" 2>&1 | tee "$log_file"
    return "${PIPESTATUS[0]}"
}

# ============================================
# ZIMBRA HELPERS (Optional)
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
    print_header "SINGLE USER MIGRATION — $PROFILE_NAME"
    echo ""
    print_info "Source: $(provider_name "$SOURCE_PROVIDER") ($SOURCE_HOST)"
    print_info "Destination: $(provider_name "$DEST_PROVIDER") ($DEST_HOST)"
    echo ""

    prompt_required "Source email (FROM)" SOURCE_EMAIL validate_email
    prompt_required "Destination email (TO)" DEST_EMAIL validate_email

    echo ""
    print_info "Migrating: $SOURCE_EMAIL -> $DEST_EMAIL"
    read -r -p "Continue? (y/n): " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { print_info "Cancelled"; pause; return; }

    local timeout_secs
    while true; do
        prompt_optional "Timeout seconds (0=no timeout)" timeout_secs "0"
        if [ "$timeout_secs" -ge 0 ] 2>/dev/null; then
            break
        else
            print_error "Timeout must be >= 0"
        fi
    done

    LOG_FILE=$(generate_logname "single_${SOURCE_EMAIL}_to_${DEST_EMAIL}")
    echo ""
    print_info "Running imapsync..."
    echo ""

    run_imapsync "$SOURCE_EMAIL" "$DEST_EMAIL" "$LOG_FILE" --timeout "$timeout_secs"
    EXIT_CODE=$?

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ "$EXIT_CODE" -eq 0 ]; then
        print_success "Migration completed!"
        echo "Log: $LOG_FILE"
        echo ""
        print_subheader "Summary"
        grep -E "Messages transferred|Messages skipped|Total bytes transferred" "$LOG_FILE" | tail -3
    else
        print_error "Migration failed (Exit: $EXIT_CODE)"
        echo "Log: $LOG_FILE"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    pause
}

# ============================================
# 2. BATCH MIGRATION
# ============================================
batch_migrate() {
    clear
    print_header "BATCH MIGRATION — $PROFILE_NAME"
    echo ""
    echo "Available user list files:"
    echo "─────────────────────────"
    find "$USER_LISTS_DIR" -maxdepth 1 -name "*.txt" -type f 2>/dev/null | while read -r file; do
        local count=$(grep -vc '^#\|^$' "$file")
        echo "  $(basename "$file") - $count users"
    done
    echo ""
    echo "Options:"
    echo "  1) Use existing source email list"
    echo "  2) Create new source email list"
    echo "  3) Use mapping file (source:dest pairs)"
    echo "  0) Cancel"
    read -r -p "Select (0-3): " BATCH_OPTION

    local USER_FILE="" MAPPING_FILE=""
    case $BATCH_OPTION in
        0) print_info "Cancelled"; pause; return ;;
        1)
            read -r -p "Enter filename: " uf
            USER_FILE="$USER_LISTS_DIR/$uf"
            [ -f "$USER_FILE" ] || { print_error "File not found"; pause; return; }
            ;;
        2)
            read -r -p "Enter new filename: " nf
            USER_FILE="$USER_LISTS_DIR/${nf}.txt"
            echo "Enter emails (blank line to finish):"
            : > "$USER_FILE"
            while true; do
                read -r -p "> " line
                [ -z "$line" ] && break
                validate_email "$line" && echo "$line" >> "$USER_FILE" || print_warning "Skipped invalid: $line"
            done
            [ -s "$USER_FILE" ] || { print_error "No valid users"; rm -f "$USER_FILE"; pause; return; }
            print_success "Created: $USER_FILE"
            ;;
        3)
            read -r -p "Enter mapping file path: " MAPPING_FILE
            [ -f "$MAPPING_FILE" ] || { print_error "File not found"; pause; return; }
            ;;
        *) print_error "Invalid"; pause; return ;;
    esac

    local LIST_FILE="$(mktemp)"
    local SKIPPED=0

    if [ -n "$MAPPING_FILE" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            if validate_mapping_line "$line"; then
                echo "$line" >> "$LIST_FILE"
            else
                print_warning "Skipped invalid: $line"
                ((SKIPPED++))
            fi
        done < "$MAPPING_FILE"
    else
        while IFS= read -r line || [ -n "$line" ]; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            if validate_email "$line"; then
                echo "$line:$line" >> "$LIST_FILE"
            else
                print_warning "Skipped invalid: $line"
                ((SKIPPED++))
            fi
        done < "$USER_FILE"
    fi

    TOTAL_USERS=$(wc -l < "$LIST_FILE")
    if [ "$TOTAL_USERS" -eq 0 ]; then
        print_error "No valid entries ($SKIPPED skipped)"
        rm -f "$LIST_FILE"
        pause
        return
    fi
    [ "$SKIPPED" -gt 0 ] && print_warning "$SKIPPED invalid entries skipped"
    print_info "Found $TOTAL_USERS valid migrations"

    read -r -p "Continue? (y/n): " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { print_info "Cancelled"; rm -f "$LIST_FILE"; pause; return; }

    local timeout_secs
    while true; do
        prompt_optional "Per-user timeout seconds" timeout_secs "0"
        [ "$timeout_secs" -ge 0 ] 2>/dev/null && break
        print_error "Timeout must be >= 0"
    done

    REPORT_FILE="$REPORT_DIR/batch_report_$(get_timestamp).txt"
    SUCCESS_COUNT=0; FAIL_COUNT=0; FAILED_USERS=()

    {
        echo "Batch Report - $(date)"
        echo "Profile: $PROFILE_NAME"
        echo "Started: $(date)"
        echo ""
        echo "RESULTS:"
        echo "────────"
    } > "$REPORT_FILE"

    echo ""
    print_info "Starting batch migration..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    while IFS=: read -r SOURCE_EMAIL DEST_EMAIL || [ -n "$SOURCE_EMAIL" ]; do
        [ -z "$SOURCE_EMAIL" ] && continue
        DEST_EMAIL="${DEST_EMAIL:-$SOURCE_EMAIL}"

        echo ""
        print_info "Migrating: $SOURCE_EMAIL -> $DEST_EMAIL"
        LOG_FILE=$(generate_logname "batch_${SOURCE_EMAIL}_to_${DEST_EMAIL}")

        run_imapsync "$SOURCE_EMAIL" "$DEST_EMAIL" "$LOG_FILE" --timeout "$timeout_secs"
        EXIT_CODE=$?

        if [ "$EXIT_CODE" -eq 0 ]; then
            print_success "✓ $SOURCE_EMAIL -> $DEST_EMAIL"
            echo "SUCCESS: $SOURCE_EMAIL -> $DEST_EMAIL" >> "$REPORT_FILE"
            ((SUCCESS_COUNT++))
        else
            print_error "✗ $SOURCE_EMAIL -> $DEST_EMAIL (Exit: $EXIT_CODE)"
            echo "FAILED: $SOURCE_EMAIL -> $DEST_EMAIL (Exit: $EXIT_CODE)" >> "$REPORT_FILE"
            FAILED_USERS+=("$SOURCE_EMAIL:$DEST_EMAIL")
            ((FAIL_COUNT++))
        fi
        echo "Progress: $((SUCCESS_COUNT + FAIL_COUNT))/$TOTAL_USERS"
    done < "$LIST_FILE"

    {
        echo ""
        echo "SUMMARY:"
        echo "────────────────"
        echo "Total: $TOTAL_USERS"
        echo "Success: $SUCCESS_COUNT"
        echo "Failed: $FAIL_COUNT"
        echo "Completed: $(date)"
    } >> "$REPORT_FILE"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_subheader "Batch Complete"
    print_success "Successful: $SUCCESS_COUNT"
    print_error "Failed: $FAIL_COUNT"
    if [ "$FAIL_COUNT" -gt 0 ]; then
        echo ""
        print_warning "Failed migrations:"
        printf '  %s\n' "${FAILED_USERS[@]}"
        echo ""
        print_info "Use option 5 to resume failed"
    fi
    print_info "Report: $REPORT_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    rm -f "$LIST_FILE"
    pause
}

# ============================================
# 3. CHECK STATUS
# ============================================
check_status() {
    clear
    print_header "MIGRATION STATUS CHECK — $PROFILE_NAME"
    
    if [ "$DEST_PROVIDER" != "2" ]; then
        print_warning "Status check works best for Zimbra destinations"
        print_info "Current destination: $(provider_name "$DEST_PROVIDER")"
        print_info "Please check your destination mailbox directly."
        echo ""
    fi

    prompt_required "Destination email to check" USER_EMAIL validate_email
    echo ""
    print_subheader "Checking: $USER_EMAIL"
    echo ""

    if have_zmprov; then
        if check_user_exists "$USER_EMAIL"; then
            print_success "✓ User exists on Zimbra"
            echo ""
            print_subheader "User Details"
            SIZE=$(get_mailbox_size "$USER_EMAIL")
            echo "Mailbox Size: $(human_readable_size "$SIZE")"
            LAST_LOGIN=$(zmprov -l ga "$USER_EMAIL" 2>/dev/null | grep "zimbraLastLogonTimestamp:" | cut -d' ' -f2)
            echo "Last Login: ${LAST_LOGIN:-Never}"
            STATUS=$(zmprov -l ga "$USER_EMAIL" 2>/dev/null | grep "zimbraAccountStatus:" | cut -d' ' -f2)
            echo "Account Status: ${STATUS:-unknown}"
            QUOTA=$(zmprov -l ga "$USER_EMAIL" 2>/dev/null | grep "zimbraMailQuota:" | cut -d' ' -f2)
            echo "Mail Quota: $([ -n "$QUOTA" ] && human_readable_size "$QUOTA" || echo Unlimited)"
        else
            print_error "✗ User NOT found"
        fi
    else
        print_warning "zmprov not found - skipping Zimbra check"
    fi

    echo ""
    print_subheader "Migration Logs"
    LOG_FILES=$(find "$BASE_DIR" -name "*${USER_EMAIL}*.log" -type f 2>/dev/null | sort -r)
    if [ -n "$LOG_FILES" ]; then
        echo "Found logs:"
        echo ""
        echo "$LOG_FILES" | head -5 | while read -r file; do
            local status=$(grep "return value" "$file" 2>/dev/null | head -1)
            echo "  📁 $(basename "$file")"
            echo "     Status: ${status:-No result}"
        done
        echo ""
        read -r -p "View latest log? (y/n): " VIEW_LOG
        if [[ "$VIEW_LOG" =~ ^[Yy]$ ]]; then
            LATEST_LOG=$(echo "$LOG_FILES" | head -1)
            echo ""
            print_subheader "Latest Log"
            echo "─────────────────────────────────────────────────"
            tail -30 "$LATEST_LOG"
        fi
    else
        print_warning "No logs found for this user"
    fi
    pause
}

# ============================================
# 4. VERIFY SYNC
# ============================================
verify_sync() {
    clear
    print_header "VERIFY SYNC — $PROFILE_NAME"
    echo ""
    prompt_required "Source email" SOURCE_EMAIL validate_email
    prompt_required "Destination email" DEST_EMAIL validate_email

    print_info "Verifying: $SOURCE_EMAIL -> $DEST_EMAIL"
    echo ""
    echo "Running dry run..."
    echo ""
    VERIFY_LOG=$(generate_logname "verify_${SOURCE_EMAIL}_to_${DEST_EMAIL}")
    run_imapsync "$SOURCE_EMAIL" "$DEST_EMAIL" "$VERIFY_LOG" --dry

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_subheader "Verification Results"
    echo ""
    grep -E "Nb messages|Total size|Biggest message|Messages transferred" "$VERIFY_LOG" | head -20
    echo ""
    echo "Log: $VERIFY_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    pause
}

# ============================================
# 5. RESUME FAILED
# ============================================
resume_failed() {
    clear
    print_header "RESUME FAILED — $PROFILE_NAME"
    echo ""
    REPORTS=$(find "$REPORT_DIR" -name "batch_report_*.txt" -type f 2>/dev/null | sort -r)
    if [ -z "$REPORTS" ]; then
        print_error "No reports found"
        pause
        return
    fi

    echo "Available reports:"
    echo "──────────────────"
    local i=1
    declare -A REPORT_MAP
    while IFS= read -r report; do
        local total=$(grep -c "^SUCCESS:" "$report" 2>/dev/null)
        local failed=$(grep -c "^FAILED:" "$report" 2>/dev/null)
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
    print_info "Using: $(basename "$REPORT_FILE")"

    mapfile -t FAILED_MIGRATIONS < <(grep "^FAILED:" "$REPORT_FILE" | sed 's/FAILED: //')
    if [ ${#FAILED_MIGRATIONS[@]} -eq 0 ]; then
        print_success "No failed migrations"
        pause
        return
    fi

    echo ""
    print_warning "Found ${#FAILED_MIGRATIONS[@]} failed migrations"
    printf '  %s\n' "${FAILED_MIGRATIONS[@]:0:20}"
    [ ${#FAILED_MIGRATIONS[@]} -gt 20 ] && echo "... and $((${#FAILED_MIGRATIONS[@]} - 20)) more"
    echo ""

    read -r -p "Resume? (y/n): " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { print_info "Cancelled"; pause; return; }

    RESUME_REPORT="$REPORT_DIR/resume_report_$(get_timestamp).txt"
    SUCCESS_COUNT=0; FAIL_COUNT=0
    {
        echo "Resume Report - $(date)"
        echo "Profile: $PROFILE_NAME"
        echo "Original: $(basename "$REPORT_FILE")"
        echo ""
    } > "$RESUME_REPORT"

    echo ""
    print_info "Resuming..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    for MIGRATION in "${FAILED_MIGRATIONS[@]}"; do
        SOURCE_EMAIL=$(echo "$MIGRATION" | sed -E 's/^[[:space:]]*([^ ]+) -> ([^ ]+).*$/\1/')
        DEST_EMAIL=$(echo "$MIGRATION" | sed -E 's/^[[:space:]]*([^ ]+) -> ([^ ]+).*$/\2/')

        echo ""
        print_info "Retrying: $SOURCE_EMAIL -> $DEST_EMAIL"
        LOG_FILE=$(generate_logname "resume_${SOURCE_EMAIL}_to_${DEST_EMAIL}")

        run_imapsync "$SOURCE_EMAIL" "$DEST_EMAIL" "$LOG_FILE"
        if [ $? -eq 0 ]; then
            print_success "✓ $SOURCE_EMAIL -> $DEST_EMAIL"
            echo "SUCCESS: $SOURCE_EMAIL -> $DEST_EMAIL" >> "$RESUME_REPORT"
            ((SUCCESS_COUNT++))
        else
            print_error "✗ $SOURCE_EMAIL -> $DEST_EMAIL - FAILED AGAIN"
            echo "FAILED: $SOURCE_EMAIL -> $DEST_EMAIL" >> "$RESUME_REPORT"
            ((FAIL_COUNT++))
        fi
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_subheader "Resume Complete"
    print_success "Success: $SUCCESS_COUNT"
    print_error "Failed: $FAIL_COUNT"
    print_info "Report: $RESUME_REPORT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    pause
}

# ============================================
# 6. MANAGE USER LISTS
# ============================================
manage_user_lists() {
    clear
    print_header "USER LIST MANAGEMENT — $PROFILE_NAME"
    echo ""
    echo "Current lists:"
    echo "───────────────────"
    if [ -n "$(ls -A "$USER_LISTS_DIR" 2>/dev/null)" ]; then
        find "$USER_LISTS_DIR" -maxdepth 1 -name "*.txt" -type f 2>/dev/null | while read -r file; do
            local count=$(grep -vc '^#\|^$' "$file")
            echo "  📄 $(basename "$file") - $count entries"
        done
    else
        echo "  No lists found"
    fi
    echo ""
    echo "Options:"
    echo "  1) Create source email list"
    echo "  2) Create mapping file (source:dest)"
    echo "  3) View file contents"
    echo "  4) Delete file"
    echo "  5) Import from file path"
    echo "  0) Back"
    read -r -p "Select (0-5): " LIST_OPTION

    case $LIST_OPTION in
        0) return ;;
        1)
            read -r -p "Filename: " nl
            local USER_FILE="$USER_LISTS_DIR/${nl}.txt"
            echo "Enter emails (blank line to finish):"
            : > "$USER_FILE"
            while true; do
                read -r -p "> " line
                [ -z "$line" ] && break
                validate_email "$line" && echo "$line" >> "$USER_FILE" || print_warning "Skipped invalid: $line"
            done
            [ -s "$USER_FILE" ] && print_success "Created $(wc -l < "$USER_FILE") entries" || { print_error "No entries"; rm -f "$USER_FILE"; }
            ;;
        2)
            read -r -p "Filename: " nl
            local MAP_FILE="$USER_LISTS_DIR/${nl}.txt"
            echo "Enter source:dest pairs (blank line to finish):"
            : > "$MAP_FILE"
            while true; do
                read -r -p "> " line
                [ -z "$line" ] && break
                if validate_mapping_line "$line"; then
                    echo "$line" >> "$MAP_FILE"
                else
                    print_warning "Skipped invalid: $line (format: email:email)"
                fi
            done
            [ -s "$MAP_FILE" ] && print_success "Created $(wc -l < "$MAP_FILE") mappings" || { print_error "No mappings"; rm -f "$MAP_FILE"; }
            ;;
        3)
            read -r -p "Filename: " vf
            local VIEW_FILE="$USER_LISTS_DIR/$vf"
            [ -f "$VIEW_FILE" ] && { echo ""; cat -n "$VIEW_FILE"; echo ""; print_info "Total: $(grep -vc '^#\|^$' "$VIEW_FILE")"; } || print_error "Not found"
            ;;
        4)
            read -r -p "Filename: " df
            local DEL_FILE="$USER_LISTS_DIR/$df"
            if [ -f "$DEL_FILE" ]; then
                read -r -p "Confirm delete? (y/n): " CONFIRM
                [[ "$CONFIRM" =~ ^[Yy]$ ]] && rm -f "$DEL_FILE" && print_success "Deleted" || print_info "Cancelled"
            else
                print_error "Not found"
            fi
            ;;
        5)
            read -r -p "Source file path: " IMPORT_FILE
            if [ ! -f "$IMPORT_FILE" ]; then
                print_error "Not found"
            else
                read -r -p "Target filename: " tn
                cp "$IMPORT_FILE" "$USER_LISTS_DIR/${tn}.txt"
                print_success "Imported $(grep -vc '^#\|^$' "$USER_LISTS_DIR/${tn}.txt") entries"
            fi
            ;;
        *) print_error "Invalid" ;;
    esac
    pause
}

# ============================================
# 7. VIEW REPORTS
# ============================================
view_reports() {
    clear
    print_header "VIEW REPORTS — $PROFILE_NAME"
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
    read -r -p "Select (0 to cancel): " SEL
    [[ "$SEL" =~ ^[0-9]+$ ]] || { print_error "Invalid"; pause; return; }
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
# 8. SWITCH PROFILE
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
    print_header "UNIVERSAL EMAIL MIGRATION TOOL"
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────┐"
    echo "  │  1.  Migrate Single User                               │"
    echo "  │  2.  Batch Migration                                   │"
    echo "  │  3.  Check Migration Status                            │"
    echo "  │  4.  Verify Sync (Dry Run)                             │"
    echo "  │  5.  Resume Failed Migrations                          │"
    echo "  │  6.  Manage User Lists                                 │"
    echo "  │  7.  View Reports                                      │"
    echo "  │  8.  Switch / Create Profile                           │"
    echo "  │  0.  Exit                                              │"
    echo "  └─────────────────────────────────────────────────────────┘"
    echo ""
    echo "📊 Status:"
    echo "  • Profile: $PROFILE_NAME"
    echo "  • Source: ${SOURCE_AUTHUSER%%@*}@$SOURCE_HOST ($(provider_name "$SOURCE_PROVIDER"))"
    echo "  • Destination: ${DEST_AUTHUSER%%@*}@$DEST_HOST ($(provider_name "$DEST_PROVIDER"))"
    echo "  • Base: $BASE_DIR"
    echo ""
    read -r -p "Select (0-8): " MENU_OPTION

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
        *) print_error "Invalid"; sleep 1 ;;
    esac
}

# ============================================
# MAIN
# ============================================
check_root
check_dependencies

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