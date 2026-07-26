#!/bin/bash

SRC_DIR="/mnt/c/Users/Jack/Documents/HandBrake-CLI/source"
OUT_DIR="$SRC_DIR/output"

mkdir -p "$OUT_DIR"

shopt -s nullglob nocaseglob

TOTAL_ORIGINAL=0
TOTAL_COMPRESSED=0

for file in "$SRC_DIR"/*.webm "$SRC_DIR"/*.mp4 "$SRC_DIR"/*.mkv "$SRC_DIR"/*.mov "$SRC_DIR"/*.avi; do
    filename=$(basename -- "$file")
    name="${filename%.*}"
    output_file="$OUT_DIR/${name}.mp4"

    echo "Processing: $filename"

    start_time=$(date +%s)

    HandBrakeCLI -i "$file" -o "$output_file" \
      --encoder x265 \
      --quality 28 \
      --encoder-preset faster \
      --all-audio \
      --aencoder aac \
      --ab 96 \
      --mixdown stereo \
      --optimize \
      2>> "$OUT_DIR/handbrake.log"

    status=$?
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    if [ $status -eq 0 ] && [ -f "$output_file" ]; then
        original_size=$(stat -c%s "$file")
        compressed_size=$(stat -c%s "$output_file")
        TOTAL_ORIGINAL=$((TOTAL_ORIGINAL + original_size))
        TOTAL_COMPRESSED=$((TOTAL_COMPRESSED + compressed_size))

        original_mb=$(echo "scale=2; $original_size / 1048576" | bc)
        compressed_mb=$(echo "scale=2; $compressed_size / 1048576" | bc)
        saved_pct=$(echo "scale=1; (1 - $compressed_size / $original_size) * 100" | bc)

        echo "✓ Done: $filename (${elapsed}s) — ${original_mb}MB → ${compressed_mb}MB (saved ${saved_pct}%)"
    else
        echo "✗ Failed: $filename (check handbrake.log)" | tee -a "$OUT_DIR/handbrake.log"
    fi
done

echo ""
echo "==================================="
echo "All videos processed. Output in: $OUT_DIR"

if [ $TOTAL_ORIGINAL -gt 0 ] && [ $TOTAL_COMPRESSED -gt 0 ]; then
    total_original_mb=$(echo "scale=2; $TOTAL_ORIGINAL / 1048576" | bc)
    total_compressed_mb=$(echo "scale=2; $TOTAL_COMPRESSED / 1048576" | bc)
    total_saved_pct=$(echo "scale=1; (1 - $TOTAL_COMPRESSED / $TOTAL_ORIGINAL) * 100" | bc)
    echo "Total: ${total_original_mb}MB → ${total_compressed_mb}MB (saved ${total_saved_pct}%)"
fi
echo "==================================="


/mnt/c/Users/Jack/Documents/HandBrake-CLI/source