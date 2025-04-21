#!/bin/bash

# --- Default Configuration ---
DEFAULT_DIRECTION="left"       # Default if -d is not specified (content moves left)
GAP=10                     # Default gap between image repetitions in pixels
DEFAULT_DELAY=4            # Default animation delay in centiseconds (1/100s). 4 = 25fps
DEFAULT_FORMAT="gif"       # Default output format
SPEED_PPS=""               # Pixels Per Second speed (alternative to delay)
VERBOSE=0
MIN_DELAY=1                # Minimum allowed delay in centiseconds
# VP9_CRF=20               # Not used now
PRORES_ALPHA_BITS=16       # Alpha quality for ProRes (16 or 8)
VIDEO_THREADS=0            # Number of threads for ffmpeg (0 = auto)

# --- Usage Function ---
usage() {
  echo "Usage: $0 -i <input_image> [options]"
  echo ""
  echo "Options:"
  echo "  -i <file>    : Input image file (required)."
  echo "  -o <file>    : Output base filename (without extension). Extension (.gif/.mov) will be added."
  echo "                 (default: <input_name>_<direction_abbr>Scroll)"
  echo "  -F <format>  : Output format: 'gif', 'video' (MOV w/ ProRes+transparency), or 'both'."
  echo "                 (default: ${DEFAULT_FORMAT})"
  echo "  -d <dir>     : Scroll direction (direction the content appears to move)."
  echo "                 left (default, abbr: l), right (r), up (u), down (d)," # Added right, down
  echo "                 up-left (ul), up-right (ur),"
  echo "                 down-left (dl), down-right (dr)."
  echo "  -g <pixels>  : Gap between image repetitions (default: ${GAP}). Must be >= 0."
  echo "  -t <delay>   : Delay between frames in 1/100s (e.g., 4 = 25fps). Mutually exclusive with -s."
  echo "  -s <speed>   : Speed in Pixels Per Second (e.g., 25). Mutually exclusive with -t."
  echo "  -v           : Verbose output."
  echo "  -h           : Show this help message."
  exit 1
}

# --- Argument Parsing ---
# Initialize variables
INPUT_IMAGE=""
OUTPUT_BASE_NAME="" # Store base name from -o
DIRECTION_INPUT=""
DELAY_INPUT=""
SPEED_INPUT=""
OUTPUT_FORMAT="$DEFAULT_FORMAT"
output_option_provided=0

while getopts "i:o:F:d:g:t:s:vh" opt; do
  case $opt in
    i) INPUT_IMAGE="$OPTARG" ;;
    o)
      OUTPUT_BASE_NAME="$OPTARG"
      output_option_provided=1
      ;;
    F) OUTPUT_FORMAT="$OPTARG" ;;
    d) DIRECTION_INPUT="$OPTARG" ;;
    g) GAP="$OPTARG" ;;
    t) DELAY_INPUT="$OPTARG" ;;
    s) SPEED_INPUT="$OPTARG" ;;
    v) VERBOSE=1 ;;
    h) usage ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done

# --- Input Validation ---
if [ -z "$INPUT_IMAGE" ]; then
  echo "Error: Input image (-i) is required." >&2; usage
fi
if [ ! -f "$INPUT_IMAGE" ]; then
  echo "Error: Input file not found: $INPUT_IMAGE" >&2; exit 1
fi
if ! command -v convert &> /dev/null || ! command -v identify &> /dev/null; then
    echo "Error: ImageMagick (commands 'convert', 'identify') not found. Please install it." >&2; exit 1
fi
if ! [[ "$GAP" =~ ^[0-9]+$ ]]; then
  echo "Error: Gap (-g) must be a non-negative integer." >&2; usage
fi

# Validate Output Format
case "$OUTPUT_FORMAT" in
  gif|video|both) ;; # Valid formats
  *) echo "Error: Invalid format (-F) specified: '$OUTPUT_FORMAT'. Use 'gif', 'video', or 'both'." >&2; usage ;;
esac

# Check for ffmpeg if video output is requested
if [[ "$OUTPUT_FORMAT" == "video" || "$OUTPUT_FORMAT" == "both" ]]; then
  if ! command -v ffmpeg &> /dev/null; then
    echo "Error: 'ffmpeg' command not found. Please install a static build or ensure it's in your PATH." >&2
    exit 1
  fi
  # Optional: Verify prores_ks support in the installed ffmpeg
  # if ! ffmpeg -h encoder=prores_ks &> /dev/null; then
  #   echo "Warning: The installed ffmpeg does not seem to support the 'prores_ks' encoder needed for video output." >&2
  #   # Decide whether to exit or just warn
  # fi
fi

# --- Validate and Normalize Direction ---
DIRECTION_TO_PROCESS="${DIRECTION_INPUT:-$DEFAULT_DIRECTION}"
# Map user-facing direction (content movement) to internal direction (window movement)
# and set the user-facing abbreviation for filenames.
case "$DIRECTION_TO_PROCESS" in
    l | left)       DIRECTION="horizontal";     DIR_ABBR="l" ;;  # Content left = Window right
    r | right)      DIRECTION="horizontal-rev"; DIR_ABBR="r" ;;  # Content right = Window left
    u | up)         DIRECTION="vertical";       DIR_ABBR="u" ;;  # Content up = Window down
    d | down)       DIRECTION="vertical-rev";   DIR_ABBR="d" ;;  # Content down = Window up
    ul | up-left)   DIRECTION="diagonal-dr";    DIR_ABBR="ul" ;; # Content up-left = Window down-right
    ur | up-right)  DIRECTION="diagonal-dl";    DIR_ABBR="ur" ;; # Content up-right = Window down-left
    dl | down-left) DIRECTION="diagonal-ur";    DIR_ABBR="dl" ;; # Content down-left = Window up-right
    dr | down-right)DIRECTION="diagonal-ul";    DIR_ABBR="dr" ;; # Content down-right = Window up-left
    *) echo "Error: Invalid direction '$DIRECTION_TO_PROCESS'." >&2; exit 1 ;;
esac
if [ "$VERBOSE" -eq 1 ]; then echo "User direction: $DIRECTION_TO_PROCESS (Abbr: $DIR_ABBR). Internal processing direction: $DIRECTION"; fi

# --- Determine Default Output Base Filename (if -o not provided) ---
if [ "$output_option_provided" -eq 0 ]; then
  input_basename=$(basename "$INPUT_IMAGE")
  input_name_noext="${input_basename%.*}"
  OUTPUT_BASE_NAME="${input_name_noext}_${DIR_ABBR}Scroll" # Uses the new DIR_ABBR
  if [ "$VERBOSE" -eq 1 ]; then echo "No output base name specified (-o), defaulting to: $OUTPUT_BASE_NAME"; fi
fi

# --- Speed/Delay Validation and Calculation ---
# Check for mutual exclusivity *first*
if [ -n "$DELAY_INPUT" ] && [ -n "$SPEED_INPUT" ]; then
  echo "Error: Cannot specify both delay (-t) and speed (-s). Please choose one." >&2; usage
fi

# Check for bc if needed for speed OR video framerate calculation
if [ -n "$SPEED_INPUT" ] || [[ "$OUTPUT_FORMAT" == "video" || "$OUTPUT_FORMAT" == "both" ]]; then
    if ! command -v bc &> /dev/null; then
        echo "Error: 'bc' command is required for speed calculation (-s) or video framerate calculation. Please install it." >&2
        exit 1
    fi
fi

# Process speed (-s) if provided
if [ -n "$SPEED_INPUT" ]; then
  if ! [[ "$SPEED_INPUT" =~ ^[0-9]+(\.[0-9]+)?$ ]] || (( $(echo "$SPEED_INPUT <= 0" | bc -l 2>/dev/null) )); then
      echo "Error: Speed (-s) must be a positive number." >&2; usage
  fi
  DELAY_FLOAT=$(echo "scale=10; 100 / $SPEED_INPUT" | bc)
  DELAY=$(printf "%.0f" "$DELAY_FLOAT") # Round to nearest integer
  if [ "$DELAY" -lt "$MIN_DELAY" ]; then
    if [ "$VERBOSE" -eq 1 ]; then echo "Warning: Calculated delay (${DELAY}cs) from speed ${SPEED_INPUT} PPS below minimum (${MIN_DELAY}cs). Setting delay to ${MIN_DELAY}cs."; fi
    DELAY=$MIN_DELAY
  elif [ "$VERBOSE" -eq 1 ]; then echo "Using speed ${SPEED_INPUT} PPS, calculated delay: ${DELAY}cs"; fi
  SPEED_PPS=$SPEED_INPUT
# Process delay (-t) if provided
elif [ -n "$DELAY_INPUT" ]; then
  if ! [[ "$DELAY_INPUT" =~ ^[0-9]+$ ]] || [ "$DELAY_INPUT" -le 0 ]; then
    echo "Error: Delay (-t) must be a positive integer." >&2; usage
  fi
  DELAY="$DELAY_INPUT"
  if [ "$DELAY" -lt "$MIN_DELAY" ]; then
      echo "Warning: Specified delay (${DELAY}cs) below recommended minimum (${MIN_DELAY}cs)." >&2
  fi
  if [ "$VERBOSE" -eq 1 ]; then echo "Using specified delay: ${DELAY}cs"; fi
# Neither -t nor -s provided, use default DELAY
else
  DELAY=$DEFAULT_DELAY
  if [ "$VERBOSE" -eq 1 ]; then echo "Using default delay: ${DELAY}cs"; fi
fi
# --- End Speed/Delay Validation ---

# --- Calculate Framerate for Video ---
FRAMERATE=""
if [[ "$OUTPUT_FORMAT" == "video" || "$OUTPUT_FORMAT" == "both" ]]; then
    # Calculate framerate from delay. Use bc for precision.
    FRAMERATE=$(echo "scale=4; 100 / $DELAY" | bc)
    if [ "$VERBOSE" -eq 1 ]; then echo "Calculated video framerate: $FRAMERATE fps"; fi
fi

# --- Construct Final Output Filenames ---
OUTPUT_FILE_GIF=""
OUTPUT_FILE_MOV=""
if [[ "$OUTPUT_FORMAT" == "gif" || "$OUTPUT_FORMAT" == "both" ]]; then
    OUTPUT_FILE_GIF="${OUTPUT_BASE_NAME}.gif"
fi
if [[ "$OUTPUT_FORMAT" == "video" || "$OUTPUT_FORMAT" == "both" ]]; then
    # ProRes uses MOV container
    OUTPUT_FILE_MOV="${OUTPUT_BASE_NAME}.mov"
fi

# --- Check for Output File Overwrite ---
# Check all potential output files based on selected format
files_to_check=()
[[ -n "$OUTPUT_FILE_GIF" ]] && files_to_check+=("$OUTPUT_FILE_GIF")
[[ -n "$OUTPUT_FILE_MOV" ]] && files_to_check+=("$OUTPUT_FILE_MOV")

for outfile in "${files_to_check[@]}"; do
    if [ -e "$outfile" ]; then
        read -p "Output file '$outfile' already exists. Overwrite? [y/N]: " -n 1 -r REPLY
        echo
        REPLY=${REPLY:-N}
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled by user (file exists: $outfile)."
            exit 0
        fi
        if [ "$VERBOSE" -eq 1 ]; then echo "Overwriting existing file: $outfile"; fi
    fi
done

# --- Get Image Dimensions ---
IMG_INFO=$(identify -format "%w %h" "$INPUT_IMAGE")
if [ $? -ne 0 ]; then echo "Error: Failed to get dimensions of '$INPUT_IMAGE'." >&2; exit 1; fi
read -r W H <<< "$IMG_INFO"
if [ "$VERBOSE" -eq 1 ]; then echo "Input dimensions: ${W}x${H}"; fi

# --- Calculate Step Size ---
STEP_W=$((W + GAP))
STEP_H=$((H + GAP))

# --- Create Temporary Directory ---
TMP_DIR=$(mktemp -d)
if [ "$VERBOSE" -eq 1 ]; then echo "Using temporary directory: $TMP_DIR"; fi

# --- Cleanup Function ---
cleanup() {
  if [ -d "$TMP_DIR" ]; then
      if [ "$VERBOSE" -eq 1 ]; then echo "Cleaning up temporary directory: $TMP_DIR"; fi
      rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

# --- Prepare Base Tiled Image ---
# Using MIFF for the base tile is still fine, as it's only read by ImageMagick
BASE_IMAGE="$TMP_DIR/base_tile.miff"
echo "Creating base tiled image..."
# This case statement uses the INTERNAL direction names
case "$DIRECTION" in
  horizontal|horizontal-rev) montage "$INPUT_IMAGE" "$INPUT_IMAGE" -tile 2x1 -geometry "+${GAP}+0" -alpha set -background none "$BASE_IMAGE"; NUM_FRAMES=$STEP_W ;; # Handles l, r
  vertical|vertical-rev) montage "$INPUT_IMAGE" "$INPUT_IMAGE" -tile 1x2 -geometry "+0+${GAP}" -alpha set -background none "$BASE_IMAGE"; NUM_FRAMES=$STEP_H ;;     # Handles u, d
  diagonal-*) montage "$INPUT_IMAGE" "$INPUT_IMAGE" "$INPUT_IMAGE" "$INPUT_IMAGE" -tile 2x2 -geometry "+${GAP}+${GAP}" -alpha set -background none "$BASE_IMAGE"; NUM_FRAMES=$(( STEP_W > STEP_H ? STEP_W : STEP_H )) ;;
  *) echo "Error: Internal logic error - invalid direction '$DIRECTION'." >&2; exit 1 ;;
esac
if [ $? -ne 0 ]; then echo "Error: Failed to create base tiled image." >&2; exit 1; fi
if [ "$VERBOSE" -eq 1 ]; then echo "Base image created. Number of frames to generate: $NUM_FRAMES"; fi

# --- Generate Frames ---
echo "Generating animation frames (this may take a while)..."
FRAME_COUNT=0
for i in $(seq 0 $((NUM_FRAMES - 1))); do
  OFFSET_X=0; OFFSET_Y=0
  # This case statement uses the INTERNAL direction names
  case "$DIRECTION" in
    horizontal) OFFSET_X=$i ;;
    horizontal-rev) OFFSET_X=$(( STEP_W - 1 - i )) ;; # Window moves left
    vertical) OFFSET_Y=$i ;;
    vertical-rev) OFFSET_Y=$(( STEP_H - 1 - i )) ;;   # Window moves up
    diagonal-dr) OFFSET_X=$(( i % STEP_W )); OFFSET_Y=$(( i % STEP_H )) ;;
    diagonal-dl) OFFSET_X=$(( (STEP_W - (i % STEP_W)) % STEP_W )); OFFSET_Y=$(( i % STEP_H )) ;;
    diagonal-ur) OFFSET_X=$(( i % STEP_W )); OFFSET_Y=$(( (STEP_H - (i % STEP_H)) % STEP_H )) ;;
    diagonal-ul) OFFSET_X=$(( (STEP_W - (i % STEP_W)) % STEP_W )); OFFSET_Y=$(( (STEP_H - (i % STEP_H)) % STEP_H )) ;;
    *) echo "Error: Internal logic error - invalid direction '$DIRECTION'." >&2; exit 1 ;;
  esac
  # Using PNG for intermediate frames for better ffmpeg compatibility
  convert "$BASE_IMAGE" -alpha set -crop "${W}x${H}+${OFFSET_X}+${OFFSET_Y}" +repage "$TMP_DIR/frame_$(printf "%05d" $i).png"
  if [ $? -ne 0 ]; then echo "Error: Failed to create frame $i." >&2; exit 1; fi
  FRAME_COUNT=$((FRAME_COUNT + 1))
  if (( i > 0 && i % 50 == 0 )) && [ "$VERBOSE" -eq 0 ]; then printf "."; fi
done
if [ "$VERBOSE" -eq 0 ]; then printf "\n"; fi
if [ "$VERBOSE" -eq 1 ]; then echo "Generated $FRAME_COUNT frames."; fi

# --- Assemble Output File(s) ---
SUCCESS_GIF=0
SUCCESS_VIDEO=0

# Assemble GIF if requested
if [[ "$OUTPUT_FORMAT" == "gif" || "$OUTPUT_FORMAT" == "both" ]]; then
    echo "Assembling GIF: $OUTPUT_FILE_GIF"
    # Use PNG frames as input
    convert -delay "$DELAY" -loop 0 -dispose Background -alpha set "$TMP_DIR"/frame_*.png -layers Optimize "$OUTPUT_FILE_GIF"
    if [ $? -eq 0 ]; then
        echo "Successfully created scrolling GIF: $OUTPUT_FILE_GIF"
        SUCCESS_GIF=1
    else
        echo "Error: Failed to assemble GIF." >&2
        # Don't exit yet if 'both' was requested, try video next
    fi
fi

# Assemble Video (MOV using ProRes 4444) if requested
if [[ "$OUTPUT_FORMAT" == "video" || "$OUTPUT_FORMAT" == "both" ]]; then
    echo "Assembling Video (MOV) using ProRes 4444 (prores_ks): $OUTPUT_FILE_MOV"
    # Use ffmpeg: -framerate, input pattern (PNG), video codec prores_ks,
    # pixel format yuva444p (input), profile 4444 (enables alpha), alpha_bits for quality
    # threads, -y to overwrite.
    ffmpeg -framerate "$FRAMERATE" \
           -i "$TMP_DIR/frame_%05d.png" \
           -c:v prores_ks \
           -pix_fmt yuva444p \
           -profile:v 4444 \
           -alpha_bits "$PRORES_ALPHA_BITS" \
           -threads "$VIDEO_THREADS" \
           -y \
           "$OUTPUT_FILE_MOV" # Output to .mov file

    if [ $? -eq 0 ]; then
        echo "Successfully created scrolling Video (MOV): $OUTPUT_FILE_MOV"
        SUCCESS_VIDEO=1
    else
        echo "Error: Failed to assemble video (MOV with ProRes)." >&2
        SUCCESS_VIDEO=0 # Explicitly mark as failed
    fi
fi

# --- Final Exit Status ---
# Exit with error if *any* requested output failed
# Note: SUCCESS_VIDEO will be 0 if video wasn't requested or if it failed
if [[ "$OUTPUT_FORMAT" == "gif" && $SUCCESS_GIF -eq 0 ]] || \
   [[ "$OUTPUT_FORMAT" == "video" && $SUCCESS_VIDEO -eq 0 ]] || \
   [[ "$OUTPUT_FORMAT" == "both" && ($SUCCESS_GIF -eq 0 || $SUCCESS_VIDEO -eq 0) ]]; then
  exit 1
fi

# Cleanup happens automatically via trap EXIT
exit 0
