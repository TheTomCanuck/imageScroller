#!/bin/bash

# --- Version ---
VERSION="1.1.0"

# --- Default Configuration ---
DEFAULT_DIRECTION="left"       # Default if -d is not specified (content moves left)
GAP=10                         # Default gap between image repetitions in pixels
DEFAULT_DELAY=4                # Default animation delay in centiseconds (1/100s). 4 = 25fps
DEFAULT_FORMAT="gif"           # Default output format
SPEED_PPS=""                   # Pixels Per Second speed (alternative to delay)
VERBOSE=0
MIN_DELAY=1                    # Minimum allowed delay in centiseconds
PRORES_ALPHA_BITS=16           # Alpha quality for ProRes (16 or 8)
VIDEO_THREADS=0                # Number of threads for ffmpeg (0 = auto)
FORCE_OVERWRITE=0              # Skip overwrite prompts if set to 1
BACKGROUND_COLOR=""            # Background color (empty = transparent/ProRes, set = flatten/H.264)
VIDEO_CODEC=""                 # Video codec (auto-detected based on background, or explicit)
USE_GPU=""                     # GPU acceleration: auto, nvidia, amd, intel, off

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
  echo "                 left (default, abbr: l), right (r), up (u), down (d),"
  echo "                 up-left (ul), up-right (ur),"
  echo "                 down-left (dl), down-right (dr)."
  echo "  -g <pixels>  : Gap between image repetitions (default: ${GAP}). Must be >= 0."
  echo "  -t <delay>   : Delay between frames in 1/100s (e.g., 4 = 25fps). Mutually exclusive with -s."
  echo "  -s <speed>   : Speed in Pixels Per Second (e.g., 25). Mutually exclusive with -t."
  echo "  -b <color>   : Background color (e.g., 'white', 'black', '#FF0000'). Flattens transparency"
  echo "                 and uses H.264 by default (much smaller files). Omit for transparency (ProRes)."
  echo "  -c <codec>   : Video codec: 'h264', 'h265', 'prores'. Default: 'h264' if -b set, 'prores' otherwise."
  echo "  -G <gpu>     : GPU acceleration: 'auto' (detect), 'nvidia', 'amd', 'intel', 'off'. Default: 'auto'."
  echo "  -a <bits>    : Alpha quality for ProRes video: 8 or 16 (default: ${PRORES_ALPHA_BITS})."
  echo "  -y           : Force overwrite without prompting."
  echo "  -v           : Verbose output."
  echo "  -V           : Show version."
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
ALPHA_BITS_INPUT=""
CODEC_INPUT=""
OUTPUT_FORMAT="$DEFAULT_FORMAT"
output_option_provided=0

while getopts "i:o:F:d:g:t:s:b:c:G:a:yvVh" opt; do
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
    b) BACKGROUND_COLOR="$OPTARG" ;;
    c) CODEC_INPUT="$OPTARG" ;;
    G) USE_GPU="$OPTARG" ;;
    a) ALPHA_BITS_INPUT="$OPTARG" ;;
    y) FORCE_OVERWRITE=1 ;;
    v) VERBOSE=1 ;;
    V) echo "imageScroller version $VERSION"; exit 0 ;;
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
# Detect ImageMagick version and set commands accordingly
if command -v magick &> /dev/null; then
    # ImageMagick 7+
    IM_CONVERT="magick"
    IM_IDENTIFY="magick identify"
    IM_MONTAGE="magick montage"
elif command -v convert &> /dev/null && command -v identify &> /dev/null && command -v montage &> /dev/null; then
    # ImageMagick 6
    IM_CONVERT="convert"
    IM_IDENTIFY="identify"
    IM_MONTAGE="montage"
else
    echo "Error: ImageMagick not found. Please install it." >&2; exit 1
fi
if ! [[ "$GAP" =~ ^[0-9]+$ ]]; then
  echo "Error: Gap (-g) must be a non-negative integer." >&2; usage
fi

# Validate alpha bits if provided
if [ -n "$ALPHA_BITS_INPUT" ]; then
  if [[ "$ALPHA_BITS_INPUT" != "8" && "$ALPHA_BITS_INPUT" != "16" ]]; then
    echo "Error: Alpha bits (-a) must be 8 or 16." >&2; usage
  fi
  PRORES_ALPHA_BITS="$ALPHA_BITS_INPUT"
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
fi

# --- Validate and Set Video Codec ---
# Logic: background color set → default to h264 (no alpha needed)
#        no background color → default to prores (preserve alpha)
if [[ "$OUTPUT_FORMAT" == "video" || "$OUTPUT_FORMAT" == "both" ]]; then
  # Validate codec if explicitly provided
  if [ -n "$CODEC_INPUT" ]; then
    case "$CODEC_INPUT" in
      h264|h265|prores) VIDEO_CODEC="$CODEC_INPUT" ;;
      *) echo "Error: Invalid codec (-c) '$CODEC_INPUT'. Use 'h264', 'h265', or 'prores'." >&2; usage ;;
    esac
  else
    # Auto-select codec based on background color
    if [ -n "$BACKGROUND_COLOR" ]; then
      VIDEO_CODEC="h264"
    else
      VIDEO_CODEC="prores"
    fi
  fi

  # Warn if using h264/h265 without background color (will have black background)
  if [[ "$VIDEO_CODEC" == "h264" || "$VIDEO_CODEC" == "h265" ]] && [ -z "$BACKGROUND_COLOR" ]; then
    echo "Warning: Using $VIDEO_CODEC without -b (background color). Transparent areas will be black." >&2
    echo "         Use -b to specify a background color, or -c prores for transparency." >&2
  fi

  # Warn if using prores with background color (unnecessary, wastes space)
  if [[ "$VIDEO_CODEC" == "prores" ]] && [ -n "$BACKGROUND_COLOR" ]; then
    echo "Note: Using ProRes with background color. Consider -c h264 for smaller files." >&2
  fi

  if [ "$VERBOSE" -eq 1 ]; then
    if [ -n "$BACKGROUND_COLOR" ]; then
      echo "Video codec: $VIDEO_CODEC (background: $BACKGROUND_COLOR)"
    else
      echo "Video codec: $VIDEO_CODEC (preserving transparency)"
    fi
  fi

  # --- GPU Acceleration Detection ---
  # Only for h264/h265, ProRes doesn't have GPU encoders
  GPU_ENCODER=""
  if [[ "$VIDEO_CODEC" == "h264" || "$VIDEO_CODEC" == "h265" ]]; then
    # Default to auto if not specified
    USE_GPU="${USE_GPU:-auto}"

    # Validate GPU option
    case "$USE_GPU" in
      auto|nvidia|amd|intel|off) ;;
      *) echo "Error: Invalid GPU option (-G) '$USE_GPU'. Use 'auto', 'nvidia', 'amd', 'intel', or 'off'." >&2; usage ;;
    esac

    # Detect available GPU encoders
    detect_gpu_encoder() {
      local codec=$1
      # Check NVIDIA (nvenc)
      if [[ "$USE_GPU" == "auto" || "$USE_GPU" == "nvidia" ]]; then
        local nvenc_name="${codec}_nvenc"
        if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "$nvenc_name"; then
          echo "$nvenc_name"
          return 0
        fi
      fi
      # Check AMD (amf)
      if [[ "$USE_GPU" == "auto" || "$USE_GPU" == "amd" ]]; then
        local amf_name="${codec}_amf"
        if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "$amf_name"; then
          echo "$amf_name"
          return 0
        fi
      fi
      # Check Intel (qsv)
      if [[ "$USE_GPU" == "auto" || "$USE_GPU" == "intel" ]]; then
        local qsv_name="${codec}_qsv"
        if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "$qsv_name"; then
          echo "$qsv_name"
          return 0
        fi
      fi
      return 1
    }

    if [[ "$USE_GPU" != "off" ]]; then
      if [[ "$VIDEO_CODEC" == "h264" ]]; then
        GPU_ENCODER=$(detect_gpu_encoder "h264")
      elif [[ "$VIDEO_CODEC" == "h265" ]]; then
        GPU_ENCODER=$(detect_gpu_encoder "hevc")
      fi
    fi

    if [ -n "$GPU_ENCODER" ]; then
      if [ "$VERBOSE" -eq 1 ]; then echo "GPU encoder: $GPU_ENCODER"; fi
    elif [[ "$USE_GPU" != "off" && "$USE_GPU" != "auto" ]]; then
      echo "Warning: Requested GPU '$USE_GPU' not available. Falling back to software encoding." >&2
    fi
  fi
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
OUTPUT_FILE_VIDEO=""
if [[ "$OUTPUT_FORMAT" == "gif" || "$OUTPUT_FORMAT" == "both" ]]; then
    OUTPUT_FILE_GIF="${OUTPUT_BASE_NAME}.gif"
fi
if [[ "$OUTPUT_FORMAT" == "video" || "$OUTPUT_FORMAT" == "both" ]]; then
    # Choose extension based on codec
    case "$VIDEO_CODEC" in
        h264|h265) OUTPUT_FILE_VIDEO="${OUTPUT_BASE_NAME}.mp4" ;;
        prores)    OUTPUT_FILE_VIDEO="${OUTPUT_BASE_NAME}.mov" ;;
    esac
fi

# --- Check for Output File Overwrite ---
# Check all potential output files based on selected format
files_to_check=()
[[ -n "$OUTPUT_FILE_GIF" ]] && files_to_check+=("$OUTPUT_FILE_GIF")
[[ -n "$OUTPUT_FILE_VIDEO" ]] && files_to_check+=("$OUTPUT_FILE_VIDEO")

for outfile in "${files_to_check[@]}"; do
    if [ -e "$outfile" ]; then
        if [ "$FORCE_OVERWRITE" -eq 1 ]; then
            if [ "$VERBOSE" -eq 1 ]; then echo "Force overwriting existing file: $outfile"; fi
        else
            read -p "Output file '$outfile' already exists. Overwrite? [y/N]: " -n 1 -r REPLY
            echo
            REPLY=${REPLY:-N}
            if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
                echo "Operation cancelled by user (file exists: $outfile)."
                exit 0
            fi
            if [ "$VERBOSE" -eq 1 ]; then echo "Overwriting existing file: $outfile"; fi
        fi
    fi
done

# --- Get Image Dimensions ---
IMG_INFO=$($IM_IDENTIFY -format "%w %h" "$INPUT_IMAGE" 2>/dev/null)
if [ $? -ne 0 ]; then echo "Error: Failed to get dimensions of '$INPUT_IMAGE'." >&2; exit 1; fi
read -r W H <<< "$IMG_INFO"
# Validate that W and H are positive integers
if ! [[ "$W" =~ ^[0-9]+$ ]] || ! [[ "$H" =~ ^[0-9]+$ ]] || [ "$W" -le 0 ] || [ "$H" -le 0 ]; then
    echo "Error: Invalid image dimensions (${W}x${H}). Is the file a valid image?" >&2; exit 1
fi
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

# --- Helper Function: GCD (Greatest Common Divisor) using Euclidean algorithm ---
gcd() {
    local a=$1 b=$2
    while [ "$b" -ne 0 ]; do
        local temp=$b
        b=$((a % b))
        a=$temp
    done
    echo "$a"
}

# --- Helper Function: LCM (Least Common Multiple) ---
lcm() {
    local a=$1 b=$2
    local g
    g=$(gcd "$a" "$b")
    echo $(( (a / g) * b ))
}

# --- Prepare Base Tiled Image ---
# Using MIFF for the base tile is still fine, as it's only read by ImageMagick
BASE_IMAGE="$TMP_DIR/base_tile.miff"
echo "Creating base tiled image..."
# This case statement uses the INTERNAL direction names
MONTAGE_SUCCESS=0
case "$DIRECTION" in
  horizontal|horizontal-rev)
    if $IM_MONTAGE "$INPUT_IMAGE" "$INPUT_IMAGE" -tile 2x1 -geometry "+${GAP}+0" -alpha set -background none "$BASE_IMAGE"; then
        MONTAGE_SUCCESS=1
    fi
    NUM_FRAMES=$STEP_W
    ;;
  vertical|vertical-rev)
    if $IM_MONTAGE "$INPUT_IMAGE" "$INPUT_IMAGE" -tile 1x2 -geometry "+0+${GAP}" -alpha set -background none "$BASE_IMAGE"; then
        MONTAGE_SUCCESS=1
    fi
    NUM_FRAMES=$STEP_H
    ;;
  diagonal-*)
    if $IM_MONTAGE "$INPUT_IMAGE" "$INPUT_IMAGE" "$INPUT_IMAGE" "$INPUT_IMAGE" -tile 2x2 -geometry "+${GAP}+${GAP}" -alpha set -background none "$BASE_IMAGE"; then
        MONTAGE_SUCCESS=1
    fi
    # Use LCM to ensure seamless looping for diagonal scrolling
    NUM_FRAMES=$(lcm "$STEP_W" "$STEP_H")
    # Cap at a reasonable maximum to prevent excessive frame counts
    MAX_DIAGONAL_FRAMES=10000
    if [ "$NUM_FRAMES" -gt "$MAX_DIAGONAL_FRAMES" ]; then
        if [ "$VERBOSE" -eq 1 ]; then echo "Warning: LCM($STEP_W, $STEP_H) = $NUM_FRAMES exceeds maximum. Using max($STEP_W, $STEP_H) instead."; fi
        NUM_FRAMES=$(( STEP_W > STEP_H ? STEP_W : STEP_H ))
    fi
    ;;
  *)
    echo "Error: Internal logic error - invalid direction '$DIRECTION'." >&2
    exit 1
    ;;
esac
if [ "$MONTAGE_SUCCESS" -ne 1 ]; then echo "Error: Failed to create base tiled image." >&2; exit 1; fi
if [ "$VERBOSE" -eq 1 ]; then echo "Base image created. Number of frames to generate: $NUM_FRAMES"; fi

# --- Generate Frames ---
echo "Generating $NUM_FRAMES animation frames..."
FRAME_COUNT=0
# Calculate progress interval: show ~20 updates for any frame count, minimum every frame for small counts
PROGRESS_INTERVAL=$(( NUM_FRAMES / 20 ))
[ "$PROGRESS_INTERVAL" -lt 1 ] && PROGRESS_INTERVAL=1

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
  if ! $IM_CONVERT "$BASE_IMAGE" -alpha set -crop "${W}x${H}+${OFFSET_X}+${OFFSET_Y}" +repage "$TMP_DIR/frame_$(printf "%05d" $i).png"; then
    echo "Error: Failed to create frame $i." >&2; exit 1
  fi
  FRAME_COUNT=$((FRAME_COUNT + 1))
  # Show progress: percentage-based updates
  if [ "$VERBOSE" -eq 0 ] && (( (i + 1) % PROGRESS_INTERVAL == 0 || i == NUM_FRAMES - 1 )); then
    PERCENT=$(( (i + 1) * 100 / NUM_FRAMES ))
    printf "\rGenerating frames: %3d%% (%d/%d)" "$PERCENT" "$((i + 1))" "$NUM_FRAMES"
  fi
done
if [ "$VERBOSE" -eq 0 ]; then printf "\n"; fi
if [ "$VERBOSE" -eq 1 ]; then echo "Generated $FRAME_COUNT frames."; fi

# --- Flatten Frames to Background Color (if specified) ---
if [ -n "$BACKGROUND_COLOR" ]; then
    echo "Flattening frames to background color: $BACKGROUND_COLOR"
    FLATTEN_COUNT=0
    for frame in "$TMP_DIR"/frame_*.png; do
        if ! $IM_CONVERT "$frame" -background "$BACKGROUND_COLOR" -flatten "$frame"; then
            echo "Error: Failed to flatten frame to background color." >&2; exit 1
        fi
        FLATTEN_COUNT=$((FLATTEN_COUNT + 1))
        if [ "$VERBOSE" -eq 0 ] && (( FLATTEN_COUNT % PROGRESS_INTERVAL == 0 || FLATTEN_COUNT == FRAME_COUNT )); then
            PERCENT=$(( FLATTEN_COUNT * 100 / FRAME_COUNT ))
            printf "\rFlattening frames: %3d%% (%d/%d)" "$PERCENT" "$FLATTEN_COUNT" "$FRAME_COUNT"
        fi
    done
    if [ "$VERBOSE" -eq 0 ]; then printf "\n"; fi
    if [ "$VERBOSE" -eq 1 ]; then echo "Flattened $FLATTEN_COUNT frames to $BACKGROUND_COLOR."; fi
fi

# --- Assemble Output File(s) ---
SUCCESS_GIF=0
SUCCESS_VIDEO=0

# Assemble GIF if requested
if [[ "$OUTPUT_FORMAT" == "gif" || "$OUTPUT_FORMAT" == "both" ]]; then
    echo "Assembling GIF: $OUTPUT_FILE_GIF"
    # Use PNG frames as input
    $IM_CONVERT -delay "$DELAY" -loop 0 -dispose Background -alpha set "$TMP_DIR"/frame_*.png -layers Optimize "$OUTPUT_FILE_GIF"
    if [ $? -eq 0 ]; then
        echo "Successfully created scrolling GIF: $OUTPUT_FILE_GIF"
        SUCCESS_GIF=1
    else
        echo "Error: Failed to assemble GIF." >&2
        # Don't exit yet if 'both' was requested, try video next
    fi
fi

# Assemble Video if requested
if [[ "$OUTPUT_FORMAT" == "video" || "$OUTPUT_FORMAT" == "both" ]]; then
    case "$VIDEO_CODEC" in
        h264)
            if [ -n "$GPU_ENCODER" ]; then
                echo "Assembling Video (MP4) using H.264 [$GPU_ENCODER]: $OUTPUT_FILE_VIDEO"
                ffmpeg -framerate "$FRAMERATE" \
                       -i "$TMP_DIR/frame_%05d.png" \
                       -c:v "$GPU_ENCODER" \
                       -pix_fmt yuv420p \
                       -preset medium \
                       -movflags +faststart \
                       -y \
                       "$OUTPUT_FILE_VIDEO"
            else
                echo "Assembling Video (MP4) using H.264 [libx264]: $OUTPUT_FILE_VIDEO"
                ffmpeg -framerate "$FRAMERATE" \
                       -i "$TMP_DIR/frame_%05d.png" \
                       -c:v libx264 \
                       -pix_fmt yuv420p \
                       -crf 18 \
                       -preset medium \
                       -movflags +faststart \
                       -threads "$VIDEO_THREADS" \
                       -y \
                       "$OUTPUT_FILE_VIDEO"
            fi
            ;;
        h265)
            if [ -n "$GPU_ENCODER" ]; then
                echo "Assembling Video (MP4) using H.265/HEVC [$GPU_ENCODER]: $OUTPUT_FILE_VIDEO"
                ffmpeg -framerate "$FRAMERATE" \
                       -i "$TMP_DIR/frame_%05d.png" \
                       -c:v "$GPU_ENCODER" \
                       -pix_fmt yuv420p \
                       -tag:v hvc1 \
                       -y \
                       "$OUTPUT_FILE_VIDEO"
            else
                echo "Assembling Video (MP4) using H.265/HEVC [libx265]: $OUTPUT_FILE_VIDEO"
                ffmpeg -framerate "$FRAMERATE" \
                       -i "$TMP_DIR/frame_%05d.png" \
                       -c:v libx265 \
                       -pix_fmt yuv420p \
                       -crf 20 \
                       -preset medium \
                       -tag:v hvc1 \
                       -threads "$VIDEO_THREADS" \
                       -y \
                       "$OUTPUT_FILE_VIDEO"
            fi
            ;;
        prores)
            echo "Assembling Video (MOV) using ProRes 4444: $OUTPUT_FILE_VIDEO"
            ffmpeg -framerate "$FRAMERATE" \
                   -i "$TMP_DIR/frame_%05d.png" \
                   -c:v prores_ks \
                   -pix_fmt yuva444p \
                   -profile:v 4444 \
                   -alpha_bits "$PRORES_ALPHA_BITS" \
                   -threads "$VIDEO_THREADS" \
                   -y \
                   "$OUTPUT_FILE_VIDEO"
            ;;
    esac

    if [ $? -eq 0 ]; then
        echo "Successfully created scrolling video: $OUTPUT_FILE_VIDEO"
        SUCCESS_VIDEO=1
    else
        echo "Error: Failed to assemble video." >&2
        SUCCESS_VIDEO=0
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
