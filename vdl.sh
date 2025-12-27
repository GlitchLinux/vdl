#!/bin/bash
# VDL - Any Video Downloader with clean UI

# Auto-install yt-dlp from GitHub (latest version)
if ! command -v yt-dlp &>/dev/null; then
    echo "Installing yt-dlp (latest)..."
    sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
    sudo chmod +x /usr/local/bin/yt-dlp
    echo "yt-dlp installed: $(yt-dlp --version)"
fi

# Auto-install borderize
if ! command -v borderize &>/dev/null; then
    echo "Installing borderize..."
    sudo curl -sL https://raw.githubusercontent.com/GlitchLinux/BORDERIZE/main/borderize -o /usr/local/bin/borderize
    sudo chmod +x /usr/local/bin/borderize
fi

TMPDIR="/tmp/videofetch"
PROGRESS_FILE="$TMPDIR/progress.txt"
mkdir -p "$TMPDIR"

# Colors (exact hex values)
C_TITLE="FF00D8"     # Pink/Magenta
C_COMPLETED="00FF0B" # Green
C_FAILED="FF0000"    # Red
C_VIDEO="FFD400"     # Gold
C_MAIN="00FFEA"      # Cyan
C_WHITE="FFFFFF"
C_YELLOW="FFD700"
C_ORANGE="FFA500"

# Nerdfont icons
ICON_VIDEO=""       # f1c8
ICON_DOWNLOAD=" "   # f0ab
ICON_FOLDER=" "     # f114
ICON_INTERNET=" "   # f0ac
ICON_TRAFFIC=" "    # f1c1

# Borderize wrappers
box()      { echo -e "$1" | borderize -${2:-$C_MAIN}; }
box_ok()   { echo -e "$1" | borderize -$C_COMPLETED -$C_WHITE; }
box_err()  { echo -e "$1" | borderize -$C_FAILED -$C_WHITE; }
box_warn() { echo -e "$1" | borderize -$C_ORANGE -$C_YELLOW; }
box_info() { echo -e "$1" | borderize -$C_MAIN -$C_WHITE; }

# Arrays for batch results
declare -a FAILED_URLS
declare -a SUCCESS_URLS

# Progress display function (runs in background)
show_progress() {
    local SOURCE="$1"
    local TOTAL="$2"
    local SAVE_DIR="$3"
    local IS_SINGLE="$4"
    
    # Hide cursor and clear screen once at start
    tput civis
    clear
    
    while [[ -f "$PROGRESS_FILE.running" ]]; do
        # Move cursor to top-left
        tput cup 0 0
        
        # Read current state
        local CURRENT=$(cat "$TMPDIR/current_num.txt" 2>/dev/null || echo "0")
        local CURRENT_URL=$(cat "$TMPDIR/current_url.txt" 2>/dev/null || echo "")
        local PROGRESS=$(tail -1 "$PROGRESS_FILE" 2>/dev/null || echo "Starting...")
        local COMPLETED=$(cat "$TMPDIR/completed.txt" 2>/dev/null || echo "0")
        local FAILED=$(cat "$TMPDIR/failed.txt" 2>/dev/null || echo "0")
        
        # Source display - show "URL" for single, path for batch
        if [[ "$IS_SINGLE" == "1" ]]; then
            SOURCE_DISP="URL"
        else
            [[ ${#SOURCE} -gt 40 ]] && SOURCE_DISP="${SOURCE:0:37}..." || SOURCE_DISP="$SOURCE"
        fi
        
        # Truncate for fixed width (80 chars)
        [[ ${#CURRENT_URL} -gt 72 ]] && CURRENT_URL="${CURRENT_URL:0:69}..."
        [[ ${#SAVE_DIR} -gt 64 ]] && SAVE_DISP="${SAVE_DIR:0:61}..." || SAVE_DISP="$SAVE_DIR"
        
        # Extract just the useful part of progress (remove [download] prefix, clean up)
        PROGRESS_CLEAN=$(echo "$PROGRESS" | sed 's/\[download\]/[Progress]/' | head -c 72)
        [[ ${#PROGRESS_CLEAN} -gt 72 ]] && PROGRESS_CLEAN="${PROGRESS_CLEAN:0:69}..."
        
        # Pad to consistent width (76 chars inner content for 80 char box)
        local LINE1=$(printf "$ICON_FOLDER Saving to: %-64s" "$SAVE_DISP")
        local LINE2=$(printf "$ICON_DOWNLOAD Downloading: %s/%s from: %-43s" "$CURRENT" "$TOTAL" "$SOURCE_DISP")
        local LINE3=$(printf "$ICON_INTERNET %-73s" "$CURRENT_URL")
        local LINE4=$(printf "$ICON_TRAFFIC %-73s" "$PROGRESS_CLEAN")
        
        # Row 1: Title + Stats (side by side with different colors)
        local TITLE_BOX=$(echo "VDL - Download Progress" | borderize -$C_TITLE -$C_WHITE)
        local COMP_BOX=$(echo "✓ Completed: $COMPLETED" | borderize -$C_COMPLETED)
        local FAIL_BOX=$(echo "✗ Failed: $FAILED" | borderize -$C_FAILED)
        local VID_BOX=$(echo "$ICON_VIDEO Video: $CURRENT/$TOTAL" | borderize -$C_VIDEO)
        paste <(echo "$TITLE_BOX") <(echo "$COMP_BOX") <(echo "$FAIL_BOX") <(echo "$VID_BOX") | tr '\t' ' '
        
        # Row 2: Main info box (cyan border)
        echo -e "$LINE1\n$LINE2\n$LINE3\n$LINE4" | borderize -$C_MAIN
        
        # Clear any leftover lines
        tput el
        tput el
        
        sleep 0.3
    done
    
    # Show cursor again
    tput cnorm
}

# Download single URL with progress output
download_with_progress() {
    local URL="$1"
    local DIR="$2"
    local NAME="$3"
    local FMT="$4"
    
    [[ -z "$URL" ]] && return 1
    
    if [[ -n "$NAME" ]]; then
        OUT="-o ${DIR}/${NAME}.%(ext)s"
    else
        OUT="-o ${DIR}/%(title)s.%(ext)s"
    fi
    
    # Run yt-dlp and capture progress
    yt-dlp $FMT $OUT --no-playlist --newline --progress "$URL" 2>&1 | while IFS= read -r line; do
        echo "$line" >> "$TMPDIR/full_log.txt"
        if [[ "$line" =~ \[download\] || "$line" =~ ETA || "$line" =~ % ]]; then
            echo "$line" > "$PROGRESS_FILE"
        elif [[ "$line" =~ Downloading || "$line" =~ Merging || "$line" =~ Extracting ]]; then
            echo "$line" > "$PROGRESS_FILE"
        fi
    done
    
    # Check result from log
    if grep -q "has already been downloaded" "$TMPDIR/full_log.txt" 2>/dev/null || \
       grep -q "Merging formats" "$TMPDIR/full_log.txt" 2>/dev/null || \
       grep -q "100%" "$TMPDIR/full_log.txt" 2>/dev/null || \
       grep -q "Destination:" "$TMPDIR/full_log.txt" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Interactive scraping fallback
scrape_fallback() {
    local URL="$1"
    local DIR="$2"
    local NAME="$3"
    local FMT="$4"
    
    clear
    box_warn "yt-dlp failed - scraping page..."
    sleep 1
    
    UA="Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0"
    
    curl -sL -A "$UA" -e "$URL" "$URL" > "$TMPDIR/page.html"
    curl -sL -A "$UA" -e "$URL" -c "$TMPDIR/cookies.txt" -b "$TMPDIR/cookies.txt" "$URL" > "$TMPDIR/page2.html"
    cat "$TMPDIR/page.html" "$TMPDIR/page2.html" > "$TMPDIR/combined.html"
    
    sed -i 's/\\u002F/\//g; s/\\u003A/:/g; s/\\u003D/=/g; s/\\u0026/\&/g; s/\\u003F/?/g' "$TMPDIR/combined.html"
    
    python3 -c "
import urllib.parse
try:
    with open('$TMPDIR/combined.html', 'r', errors='ignore') as f:
        content = f.read()
    with open('$TMPDIR/decoded.html', 'w') as f:
        f.write(urllib.parse.unquote(content))
except: pass
" 2>/dev/null
    
    [[ -f "$TMPDIR/decoded.html" ]] && cat "$TMPDIR/decoded.html" >> "$TMPDIR/combined.html"
    
    grep -oE 'https?://[^"'"'"'\s<>\)\]\\]+' "$TMPDIR/combined.html" 2>/dev/null | sort -u > "$TMPDIR/all_urls.txt"
    
    > "$TMPDIR/found_videos.txt"
    
    grep -iE '\.(mp4|webm|m3u8|mpd|mov|mkv|avi|flv|ts)(\?|$|&)' "$TMPDIR/all_urls.txt" >> "$TMPDIR/found_videos.txt"
    grep -iE '(videoplayback|googlevideo|fbcdn.*video|vod|hls|dash|manifest|playlist\.m3u8|master\.m3u8)' "$TMPDIR/all_urls.txt" >> "$TMPDIR/found_videos.txt"
    
    IFRAMES=$(grep -oE '<iframe[^>]+src=["'"'"'][^"'"'"']+["'"'"']' "$TMPDIR/combined.html" | grep -oE 'https?://[^"'"'"']+' | head -5)
    for iframe in $IFRAMES; do
        curl -sL -A "$UA" -e "$URL" "$iframe" >> "$TMPDIR/combined.html" 2>/dev/null
    done
    
    grep -oE 'https?://[^"'"'"'\s<>\)\]\\]+' "$TMPDIR/combined.html" 2>/dev/null | sort -u >> "$TMPDIR/all_urls.txt"
    grep -iE '\.(mp4|webm|m3u8|mpd|mov|mkv|avi|flv|ts)(\?|$|&)' "$TMPDIR/all_urls.txt" >> "$TMPDIR/found_videos.txt"
    grep -iE '(videoplayback|googlevideo|fbcdn.*video|vod|hls|dash|manifest)' "$TMPDIR/all_urls.txt" >> "$TMPDIR/found_videos.txt"
    
    grep -oE '(source|src|file|url|video|stream|media|mp4|hls)["'"'"']?\s*[:=]\s*["'"'"']https?://[^"'"'"']+' "$TMPDIR/combined.html" | \
        grep -oE 'https?://[^"'"'"']+' >> "$TMPDIR/found_videos.txt"
    
    grep -oE '"(source|src|file|url|video_url|stream_url|media_url|mp4_url|hls_url)":\s*"https?://[^"]+' "$TMPDIR/combined.html" | \
        grep -oE 'https?://[^"]+' >> "$TMPDIR/found_videos.txt"
    
    grep -oE 'data-[a-z-]*(src|url|video|source|file)=["'"'"']https?://[^"'"'"']+' "$TMPDIR/combined.html" | \
        grep -oE 'https?://[^"'"'"']+' >> "$TMPDIR/found_videos.txt"
    
    grep -oE '<meta[^>]*(og:video|twitter:player|video:url)[^>]*content=["'"'"']https?://[^"'"'"']+' "$TMPDIR/combined.html" | \
        grep -oE 'https?://[^"'"'"']+' >> "$TMPDIR/found_videos.txt"
    
    sort -u "$TMPDIR/found_videos.txt" | grep -v '^$' | \
        grep -v 'googlesyndication\|doubleclick\|analytics\|tracking\|pixel\|beacon\|ads\.' > "$TMPDIR/final_videos.txt"
    
    mapfile -t URL_ARRAY < "$TMPDIR/final_videos.txt"
    
    if [[ ${#URL_ARRAY[@]} -eq 0 ]]; then
        clear
        box_err "No video URLs found"
        echo ""
        read -p "Enter URL manually (or enter to quit): " MANUAL_URL
        [[ -z "$MANUAL_URL" ]] && return 1
        URL_ARRAY=("$MANUAL_URL")
    fi
    
    clear
    box_info "Found ${#URL_ARRAY[@]} video URL(s)"
    echo ""
    
    URL_LIST=""
    for i in "${!URL_ARRAY[@]}"; do
        num=$((i+1))
        vurl="${URL_ARRAY[$i]}"
        if [[ ${#vurl} -gt 70 ]]; then
            URL_LIST+="$num) ${vurl:0:67}...\n"
        else
            URL_LIST+="$num) $vurl\n"
        fi
    done
    echo -e "$URL_LIST" | borderize -$C_YELLOW
    
    echo ""
    read -p "Select [1]: " SEL
    SEL="${SEL:-1}"
    
    IDX=$((SEL-1))
    SELECTED_URL="${URL_ARRAY[$IDX]}"
    
    [[ -z "$SELECTED_URL" ]] && return 1
    
    clear
    box "Trying selected URL..." $C_TITLE
    echo ""
    
    if [[ -n "$NAME" ]]; then
        OUT="-o ${DIR}/${NAME}.%(ext)s"
    else
        OUT="-o ${DIR}/%(title)s.%(ext)s"
    fi
    
    yt-dlp $FMT $OUT --no-playlist "$SELECTED_URL" 2>&1
    RESULT=$?
    
    if [[ $RESULT -ne 0 ]]; then
        clear
        box_warn "yt-dlp failed, trying direct download..."
        
        if [[ -n "$NAME" ]]; then
            OUTFILE="${DIR}/${NAME}"
        else
            BASENAME=$(basename "${SELECTED_URL%%\?*}")
            [[ -z "$BASENAME" || "$BASENAME" == "/" ]] && BASENAME="video"
            OUTFILE="${DIR}/${BASENAME}"
        fi
        
        [[ "$OUTFILE" != *.* ]] && OUTFILE="${OUTFILE}.mp4"
        
        curl -L -A "$UA" -e "$URL" --progress-bar -o "$OUTFILE" "$SELECTED_URL" && return 0
        return 1
    fi
    
    return 0
}

# Cleanup on exit
cleanup() {
    tput cnorm
    rm -f "$PROGRESS_FILE.running"
    rm -f "$TMPDIR"/*.txt 2>/dev/null
}
trap cleanup EXIT

# ============ MAIN ============

# Screen 1: Header
clear
box "VDL - Any Video Downloader" $C_TITLE
echo ""
read -p "URL or path to URL list: " INPUT
[[ -z "$INPUT" ]] && { clear; box_err "No input"; exit 1; }

# Check if it's a file (batch mode)
if [[ -f "$INPUT" ]]; then
    IS_SINGLE=0
    SOURCE_NAME=$(realpath "$INPUT")
    
    # Screen 2: Batch info
    clear
    URL_COUNT=$(grep -cE '^https?://' "$INPUT")
    box_info "Batch mode: $URL_COUNT URLs"
    echo ""
    read -p "Directory [.]: " DIR
    DIR="${DIR:-.}"
    DIR="${DIR/#\~/$HOME}"
    mkdir -p "$DIR"
    DIR=$(realpath "$DIR")
    
    # Screen 3: Quality
    clear
    echo -e "1) Best quality\n2) Audio only (mp3)\n3) 1080p\n4) 720p\n5) Custom" | borderize -$C_VIDEO
    echo ""
    read -p "Quality [1]: " Q
    
    case "${Q:-1}" in
        1) FMT="-f bestvideo+bestaudio/best --merge-output-format mp4" ;;
        2) FMT="-x --audio-format mp3 --audio-quality 0" ;;
        3) FMT="-f bestvideo[height<=1080]+bestaudio/best[height<=1080] --merge-output-format mp4" ;;
        4) FMT="-f bestvideo[height<=720]+bestaudio/best[height<=720] --merge-output-format mp4" ;;
        5) read -p "Format: " FC; FMT="-f $FC" ;;
        *) FMT="-f bestvideo+bestaudio/best --merge-output-format mp4" ;;
    esac
    
    # Screen 4: Starting
    clear
    box_ok "Starting batch download"
    sleep 2
    
    # Initialize progress tracking
    echo "0" > "$TMPDIR/completed.txt"
    echo "0" > "$TMPDIR/failed.txt"
    echo "0" > "$TMPDIR/current_num.txt"
    echo "" > "$TMPDIR/current_url.txt"
    echo "Initializing..." > "$PROGRESS_FILE"
    touch "$PROGRESS_FILE.running"
    
    # Start progress display in background
    show_progress "$SOURCE_NAME" "$URL_COUNT" "$DIR" "$IS_SINGLE" &
    PROGRESS_PID=$!
    
    # Process URLs
    CURRENT=0
    COMPLETED=0
    FAILED_COUNT=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        
        URL=$(echo "$line" | grep -oE 'https?://[^\s]+' | head -1)
        [[ -z "$URL" ]] && continue
        
        ((CURRENT++))
        echo "$CURRENT" > "$TMPDIR/current_num.txt"
        echo "$URL" > "$TMPDIR/current_url.txt"
        echo "Starting" > "$PROGRESS_FILE"
        > "$TMPDIR/full_log.txt"
        
        if download_with_progress "$URL" "$DIR" "" "$FMT"; then
            SUCCESS_URLS+=("$URL")
            ((COMPLETED++))
        else
            FAILED_URLS+=("$URL")
            ((FAILED_COUNT++))
        fi
        
        echo "$COMPLETED" > "$TMPDIR/completed.txt"
        echo "$FAILED_COUNT" > "$TMPDIR/failed.txt"
        
    done < "$INPUT"
    
    # Stop progress display
    rm -f "$PROGRESS_FILE.running"
    sleep 0.5
    kill $PROGRESS_PID 2>/dev/null
    wait $PROGRESS_PID 2>/dev/null
    
    tput cnorm
    
    # Final summary screen
    clear
    box "BATCH COMPLETE" $C_TITLE
    echo ""
    box_ok "✓ Completed: ${#SUCCESS_URLS[@]}"
    echo ""
    box_err "✗ Failed: ${#FAILED_URLS[@]}"
    
    if [[ ${#FAILED_URLS[@]} -gt 0 ]]; then
        echo ""
        FAIL_LIST=""
        for url in "${FAILED_URLS[@]}"; do
            [[ ${#url} -gt 60 ]] && url="${url:0:57}..."
            FAIL_LIST+="• $url\n"
        done
        echo -e "Failed URLs:\n$FAIL_LIST" | borderize -$C_FAILED
        
        FAILED_FILE="${DIR}/failed_urls.txt"
        printf '%s\n' "${FAILED_URLS[@]}" > "$FAILED_FILE"
        echo ""
        box_warn "Failed list saved: $FAILED_FILE"
    fi

else
    # ============ SINGLE URL MODE ============
    IS_SINGLE=1
    URL="$INPUT"
    
    clear
    box "Single URL Mode" $C_MAIN
    echo ""
    read -p "Directory [.]: " DIR
    DIR="${DIR:-.}"
    DIR="${DIR/#\~/$HOME}"
    mkdir -p "$DIR"
    DIR=$(realpath "$DIR")
    
    clear
    box_info "URL: ${URL:0:50}..."
    echo ""
    read -p "Filename [default]: " NAME
    
    clear
    read -p "List formats? [y/N]: " LIST
    if [[ "${LIST,,}" == "y" ]]; then
        yt-dlp -F "$URL" 2>/dev/null | head -30
        echo ""
        read -p "Press enter to continue..."
    fi
    
    clear
    echo -e "1) Best quality\n2) Audio only (mp3)\n3) 1080p\n4) 720p\n5) Custom" | borderize -$C_VIDEO
    echo ""
    read -p "Quality [1]: " Q
    
    case "${Q:-1}" in
        1) FMT="-f bestvideo+bestaudio/best --merge-output-format mp4" ;;
        2) FMT="-x --audio-format mp3 --audio-quality 0" ;;
        3) FMT="-f bestvideo[height<=1080]+bestaudio/best[height<=1080] --merge-output-format mp4" ;;
        4) FMT="-f bestvideo[height<=720]+bestaudio/best[height<=720] --merge-output-format mp4" ;;
        5) read -p "Format: " FC; FMT="-f $FC" ;;
        *) FMT="-f bestvideo+bestaudio/best --merge-output-format mp4" ;;
    esac
    
    # Initialize progress tracking for single URL
    echo "0" > "$TMPDIR/completed.txt"
    echo "0" > "$TMPDIR/failed.txt"
    echo "1" > "$TMPDIR/current_num.txt"
    echo "$URL" > "$TMPDIR/current_url.txt"
    echo "Starting..." > "$PROGRESS_FILE"
    touch "$PROGRESS_FILE.running"
    > "$TMPDIR/full_log.txt"
    
    # Start progress display in background
    show_progress "$URL" "1" "$DIR" "$IS_SINGLE" &
    PROGRESS_PID=$!
    
    # Download
    if download_with_progress "$URL" "$DIR" "$NAME" "$FMT"; then
        echo "1" > "$TMPDIR/completed.txt"
        DOWNLOAD_SUCCESS=1
    else
        echo "1" > "$TMPDIR/failed.txt"
        DOWNLOAD_SUCCESS=0
    fi
    
    # Stop progress display
    rm -f "$PROGRESS_FILE.running"
    sleep 0.5
    kill $PROGRESS_PID 2>/dev/null
    wait $PROGRESS_PID 2>/dev/null
    tput cnorm
    
    if [[ $DOWNLOAD_SUCCESS -eq 1 ]]; then
        clear
        box_ok "✓ Download complete!"
    else
        # Try scraping fallback
        scrape_fallback "$URL" "$DIR" "$NAME" "$FMT"
        if [[ $? -eq 0 ]]; then
            clear
            box_ok "✓ Download complete!"
        else
            clear
            box_err "✗ Download failed"
        fi
    fi
fi