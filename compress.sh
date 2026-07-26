#!/usr/bin/env bash
# =============================================================================
# compress.sh — Batch video compressor using HandBrakeCLI
# Supports Ubuntu/Debian, Fedora/RHEL (via RPM Fusion), Arch Linux
# =============================================================================
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── Supported extensions ─────────────────────────────────────────────────────
EXTS="mp4|mkv|mov|avi|wmv|flv|webm|m4v|mpeg|mpg|ts|mts|m2ts|vob|ogv|3gp|3g2"

# ── Parallel jobs (1 = sequential, one file at a time) ───────────────────────
PARALLEL_JOBS=1

# ── Helpers ───────────────────────────────────────────────────────────────────
human_size() {
    local b=$1
    if   (( b >= 1073741824 )); then echo "$(echo "scale=2;$b/1073741824"|bc) GB"
    elif (( b >= 1048576    )); then echo "$(echo "scale=2;$b/1048576"   |bc) MB"
    elif (( b >= 1024       )); then echo "$(echo "scale=2;$b/1024"      |bc) KB"
    else echo "${b} B"; fi
}

# ── Prerequisite check ────────────────────────────────────────────────────────
check_prereqs() {
    local miss=0
    local distro_hint=""

    echo -e "${BOLD}Checking prerequisites...${NC}"

    if command -v HandBrakeCLI &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} HandBrakeCLI"
    else
        echo -e "  ${RED}✗ HandBrakeCLI not found${NC}"
        if command -v apt-get &>/dev/null; then
            echo -e "    Install: ${BOLD}sudo apt-get install handbrake-cli${NC}"
        elif command -v dnf &>/dev/null; then
            echo -e "    Fedora/RHEL needs RPM Fusion (not in default repos):"
            echo -e "    ${BOLD}sudo dnf install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-\$(rpm -E %fedora).noarch.rpm${NC}"
            echo -e "    ${BOLD}sudo dnf install HandBrake-cli${NC}"
        elif command -v pacman &>/dev/null; then
            echo -e "    Install: ${BOLD}sudo pacman -S handbrake-cli${NC}"
        else
            echo -e "    Could not detect package manager — install HandBrakeCLI manually."
        fi
        (( miss++ )) || true
    fi

    if command -v bc &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} bc"
    else
        echo -e "  ${RED}✗ bc not found${NC}"
        if command -v apt-get &>/dev/null; then
            echo -e "    Install: ${BOLD}sudo apt-get install bc${NC}"
        elif command -v dnf &>/dev/null; then
            echo -e "    Install: ${BOLD}sudo dnf install bc${NC}"
        elif command -v pacman &>/dev/null; then
            echo -e "    Install: ${BOLD}sudo pacman -S bc${NC}"
        fi
        (( miss++ )) || true
    fi

    if (( miss > 0 )); then
        echo -e "\n${RED}Install the missing tool(s) above and re-run.${NC}"; exit 1
    fi
    echo ""
}

# ── Prompts ───────────────────────────────────────────────────────────────────
prompt_source() {
    while true; do
        read -rp "$(echo -e "${BOLD}Source folder:${NC} ")" SOURCE_DIR
        SOURCE_DIR="${SOURCE_DIR/#\~/$HOME}"
        SOURCE_DIR="${SOURCE_DIR%/}"
        [[ ! -d "$SOURCE_DIR" ]] && { echo -e "${RED}  Not found.${NC}"; continue; }

        OUTPUT_DIR="${SOURCE_DIR}/output"

        # Recursive: includes nested subfolders. Prunes the output/ folder itself
        # so re-running the script doesn't pick up its own previous .mp4 output.
        mapfile -d '' VIDEO_FILES < <(find "$SOURCE_DIR" -type f \
            -regextype posix-extended -iregex ".*\.($EXTS)" \
            ! -path "${OUTPUT_DIR}/*" -print0 2>/dev/null)
        FILE_COUNT=${#VIDEO_FILES[@]}

        (( FILE_COUNT == 0 )) && { echo -e "${RED}  No video files found (including subfolders).${NC}"; continue; }

        echo -e "${GREEN}  Found ${FILE_COUNT} file(s) (including subfolders):${NC}"
        for f in "${VIDEO_FILES[@]}"; do
            printf "    ${CYAN}%-50s${NC}  %s\n" "${f#$SOURCE_DIR/}" "$(human_size "$(stat -c%s "$f")")"
        done
        break
    done
}

prompt_resolution() {
    echo -e "\n${BOLD}Resolution:${NC}"
    echo "  1) HQ  — original"
    echo "  2) HD  — 1280×720"
    echo "  3) FHD — 1920×1080"
    while true; do
        read -rp "  [1-3, default 1]: " c; c="${c:-1}"
        case $c in
            1) RES="HQ";  W="";     H="";     break ;;
            2) RES="HD";  W="1280"; H="720";  break ;;
            3) RES="FHD"; W="1920"; H="1080"; break ;;
            *) echo -e "${RED}  Invalid.${NC}" ;;
        esac
    done
}

prompt_preset() {
    local presets=(veryfast faster slow)
    echo -e "\n${BOLD}Encoder preset${NC} (fast→small file, slow→better quality):"
    for i in "${!presets[@]}"; do
        local mark=""; [[ "${presets[$i]}" == "faster" ]] && mark=" ← default"
        echo -e "  $((i+1))) ${presets[$i]}${mark}"
    done
    while true; do
        read -rp "  [1-3, default 2]: " c; c="${c:-2}"
        [[ "$c" =~ ^[1-3]$ ]] && { PRESET="${presets[$((c-1))]}"; break; }
        echo -e "${RED}  Invalid.${NC}"
    done
}

prompt_fps() {
    echo -e "\n${BOLD}Frame rate:${NC}"
    echo "  1) Same as source ← default"
    echo "  2) 24 fps"
    echo "  3) 30 fps"
    while true; do
        read -rp "  [1-3, default 1]: " c; c="${c:-1}"
        case $c in
            1) FPS="";   FPS_LABEL="source"; break ;;
            2) FPS="24"; FPS_LABEL="24 fps"; break ;;
            3) FPS="30"; FPS_LABEL="30 fps"; break ;;
            *) echo -e "${RED}  Invalid.${NC}" ;;
        esac
    done
}

prompt_quality() {
    echo -e "\n${BOLD}Quality (CRF):${NC}"
    echo "  1) High    CRF 20"
    echo "  2) Medium  CRF 24"
    echo "  3) Low     CRF 28  ← default"
    echo "  4) Custom"
    while true; do
        read -rp "  [1-4, default 3]: " c; c="${c:-3}"
        case $c in
            1) CRF=20; CRF_LABEL="High (20)";   break ;;
            2) CRF=24; CRF_LABEL="Medium (24)"; break ;;
            3) CRF=28; CRF_LABEL="Low (28)";    break ;;
            4) read -rp "  CRF [0-51]: " CRF
               [[ "$CRF" =~ ^[0-9]+$ ]] && (( CRF<=51 )) && { CRF_LABEL="Custom ($CRF)"; break; }
               echo -e "${RED}  Must be 0-51.${NC}" ;;
            *) echo -e "${RED}  Invalid.${NC}" ;;
        esac
    done
}

# ── Summary + confirm ─────────────────────────────────────────────────────────
confirm() {
    echo -e "\n${CYAN}${BOLD}─────────────────  Summary  ─────────────────${NC}"
    echo -e "  Source    : $SOURCE_DIR"
    echo -e "  Output    : $OUTPUT_DIR"
    local mode_label="sequential"
    (( PARALLEL_JOBS > 1 )) && mode_label="${PARALLEL_JOBS} in parallel"
    echo -e "  Files     : $FILE_COUNT   ($mode_label)"
    echo -e "  Resolution: $RES   Preset: $PRESET   FPS: $FPS_LABEL   Quality: $CRF_LABEL"
    echo -e "${CYAN}${BOLD}─────────────────────────────────────────────${NC}"
    read -rp "$(echo -e "\n${BOLD}Proceed? [Y/n]: ${NC}")" ans
    [[ "${ans:-Y}" =~ ^[Yy]$ ]] || { echo -e "${YELLOW}Aborted.${NC}"; exit 0; }
}

# ── Compress one file ─────────────────────────────────────────────────────────
# Args: input_file  stats_file  log_file
compress_file() {
    local input="$1" stats="$2" log="$3"
    local rel="${input#$SOURCE_DIR/}"
    local rel_dir; rel_dir="$(dirname -- "$rel")"
    local name; name="$(basename -- "$input")"

    local out_dir="$OUTPUT_DIR"
    [[ "$rel_dir" != "." ]] && out_dir="${OUTPUT_DIR}/${rel_dir}"
    mkdir -p "$out_dir"
    local out="${out_dir}/${name%.*}.mp4"

    local orig; orig=$(stat -c%s "$input" 2>/dev/null || echo 0)
    local t0; t0=$(date +%s)

    local args=(
        --input "$input" --output "$out"
        --format av_mp4 --encoder x265
        --quality "$CRF" --encoder-preset "$PRESET"
        --aencoder av_aac --mixdown stereo --ab 96
        --optimize
    )
    [[ -n "$W" ]] && args+=(--width "$W" --height "$H" --keep-display-aspect)
    [[ -n "$FPS" ]] && args+=(--rate "$FPS" --cfr) || args+=(--vfr)

    echo -e "${CYAN} STARTING${NC}  ${BOLD}${rel}${NC}"

    # Run HandBrake in a subshell that resets SIGINT to its default action.
    # The parent script ignores SIGINT (see run()), so Ctrl+C here kills only
    # this one encode — the script catches the failure below and moves on to
    # the next file instead of exiting entirely.
    #
    # IMPORTANT: stdout is left completely untouched (not piped, not
    # redirected) so it stays connected to the real terminal — that's what
    # HandBrake checks to decide whether to show its live %/fps/ETA progress
    # line. Piping it (even through `tee`) makes HandBrake think it isn't
    # attached to a terminal and it stops updating live. Only stderr goes to
    # the log file.
    local hb_status=0
    if ( trap - INT; exec HandBrakeCLI "${args[@]}" ) 2>>"$log"; then
        hb_status=0
    else
        hb_status=$?
    fi

    local elapsed=$(( $(date +%s) - t0 ))
    local etime; etime=$(printf '%02d:%02d' $(( elapsed/60 )) $(( elapsed%60 )))

    if [[ $hb_status -eq 0 && -s "$out" ]]; then
        local new; new=$(stat -c%s "$out" 2>/dev/null || echo 0)
        local saved="0"
        (( orig > 0 )) && saved=$(echo "scale=1;(1-$new/$orig)*100" | bc)
        echo -e "${GREEN}✔ Done ${NC} ${BOLD}${rel}${NC}  $(human_size "$orig") → $(human_size "$new")  ${GREEN}${saved}% saved${NC}  ⏱ $etime"
        echo "$orig $new $elapsed" >> "$stats"
    else
        echo -e "${RED} FAILED / CANCELLED${NC} ${BOLD}${rel}${NC}  — check handbrake.log"
        echo "0 0 $elapsed" >> "$stats"
        echo "ERROR: $rel" >> "$log"
        rm -f "$out"   # remove partial output from an interrupted/failed encode
    fi
}

# ── Run compression (2-way parallel) ─────────────────────────────────────────
run() {
    mkdir -p "$OUTPUT_DIR"
    local log="${OUTPUT_DIR}/handbrake.log"
    local stats="${OUTPUT_DIR}/.stats"
    : > "$log"; : > "$stats"

    local total=$FILE_COUNT
    local t0; t0=$(date +%s)

    local mode_label="sequentially"
    (( PARALLEL_JOBS > 1 )) && mode_label="— ${PARALLEL_JOBS} in parallel"
    echo -e "\n${BOLD}Compressing ${total} file(s) ${mode_label}...${NC}"
    echo -e "${YELLOW}(Ctrl+C cancels only the current file and moves on to the next)${NC}\n"

    # Ignore SIGINT here so Ctrl+C doesn't kill this script — only the current
    # HandBrakeCLI job, which resets SIGINT to default inside its own subshell.
    trap '' INT

    local running=0
    for input in "${VIDEO_FILES[@]}"; do
        compress_file "$input" "$stats" "$log" &
        (( running++ )) || true
        if (( running >= PARALLEL_JOBS )); then
            wait -n || true   # `|| true` so a failed/cancelled job doesn't trip set -e
            (( running-- )) || true
        fi
    done
    wait || true

    trap - INT   # restore normal Ctrl+C behavior now that compression is done

    # ── Summary ──
    local total_orig=0 total_new=0
    while read -r o n _; do
        total_orig=$(( total_orig + o ))
        total_new=$(( total_new  + n ))
    done < "$stats"
    rm -f "$stats"

    local saved="0"
    (( total_orig > 0 )) && saved=$(echo "scale=1;(1-$total_new/$total_orig)*100" | bc)
    local total_elapsed=$(( $(date +%s) - t0 ))
    local etime; etime=$(printf '%02d:%02d' $(( total_elapsed/60 )) $(( total_elapsed%60 )))

    echo -e "\n${CYAN}${BOLD}─────────────────  Complete  ────────────────${NC}"
    echo -e "  Files    : ${total}"
    echo -e "  Input    : $(human_size "$total_orig")   Output: $(human_size "$total_new")   Saved: ${saved}%"
    echo -e "  Time     : ${etime}"
    echo -e "  Output   : ${OUTPUT_DIR}"
    echo -e "  Log      : ${log}"
    echo -e "${CYAN}${BOLD}─────────────────────────────────────────────${NC}\n"
}

# ── Entry point ───────────────────────────────────────────────────────────────
main() {
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║    HandBrake Batch Compressor        ║"
    echo "  ╚══════════════════════════════════════╝"
    echo -e "${NC}"

    check_prereqs
    prompt_source
    prompt_resolution
    prompt_preset
    prompt_fps
    prompt_quality
    confirm
    run
}

main "$@"