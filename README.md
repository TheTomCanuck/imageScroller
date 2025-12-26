# Image Scroll Generator

A Bash script to generate a scrolling GIF or video from a static PNG. Supports 8 scroll directions. Open an issue if something doesn't work right!

Requires **ImageMagick** and **FFmpeg**. Works in **WSL**. Could probably be converted to PowerShell, but... ya know...

**Video codecs:**
- **H.264** (default with `-b`): Small files, universal playback, no transparency
- **H.265/HEVC**: ~50% smaller than H.264, good compatibility
- **ProRes 4444** (default without `-b`): Large files, preserves transparency 

---

## ⚡ Important Setup

You will likely have to **increase ImageMagick's limits** in `/etc/ImageMagick-6/policy.xml` by a lot.

Example working settings:

```xml
<policy domain="resource" name="memory" value="6GiB"/>
<policy domain="resource" name="map" value="6GiB"/>
<policy domain="resource" name="width" value="16KP"/>
<policy domain="resource" name="height" value="16KP"/>
<!-- <policy domain="resource" name="list-length" value="128"/> -->
<policy domain="resource" name="area" value="128MP"/>
<policy domain="resource" name="disk" value="12GiB"/>
```

---

## 🛠 Usage

```bash
./imageScroller.sh -i <input_image> [options]
```

### Options

| Option | Description |
|:------|:------------|
| `-i <file>` | Input image file (required). |
| `-o <file>` | Output base filename (without extension). Extension added automatically. <br> _(Default: `<input_name>_<direction_abbr>Scroll`)_. |
| `-F <format>` | Output format: `gif`, `video`, or `both`. _(Default: gif)_. |
| `-d <dir>` | Scroll direction (direction the content appears to move). <br> Options: `left (l)` _(default)_, `right (r)`, `up (u)`, `down (d)`, `up-left (ul)`, `up-right (ur)`, `down-left (dl)`, `down-right (dr)`. |
| `-g <pixels>` | Gap between image repetitions. _(Default: 10 pixels)_. Must be ≥ 0. |
| `-t <delay>` | Delay between frames (1/100s, e.g., `4` = 25fps). Mutually exclusive with `-s`. |
| `-s <speed>` | Speed in Pixels Per Second (e.g., `25`). Mutually exclusive with `-t`. |
| `-b <color>` | Background color (e.g., `white`, `black`, `#FF0000`). Flattens transparency and defaults to H.264. Omit for transparency (ProRes). |
| `-c <codec>` | Video codec: `h264`, `h265`, `prores`. _(Default: `h264` if `-b` set, `prores` otherwise)_. |
| `-G <gpu>` | GPU acceleration: `auto` (detect), `nvidia`, `amd`, `intel`, `off`. _(Default: auto)_. |
| `-j <jobs>` | Parallel jobs for frame generation. `auto` _(default)_ = cores-1, `max` = all cores, `off` = sequential, or a number. |
| `-T <dir>` | Temp directory for frames. Use disk path for large images (e.g., `-T ~/tmp`). Default: system temp (often RAM). |
| `-a <bits>` | Alpha quality for ProRes video: `8` or `16`. _(Default: 16)_. |
| `-y` | Force overwrite without prompting. |
| `-v` | Verbose output. |
| `-V` | Show version. |

---

## 📋 Examples

```bash
# GIF with transparency (default)
./imageScroller.sh -i mybanner.png -d left

# Video with transparency (ProRes, large file)
./imageScroller.sh -i mybanner.png -F video

# Video with solid background (H.264, small file ~2-10MB for 720p)
./imageScroller.sh -i mybanner.png -F video -b white

# Both GIF and small H.264 video
./imageScroller.sh -i mybanner.png -F both -b '#1a1a2e'

# H.265 for even smaller files
./imageScroller.sh -i mybanner.png -F video -b black -c h265

# Fastest processing (all cores, may slow system)
./imageScroller.sh -i mybanner.png -j max

# Limit to 4 cores
./imageScroller.sh -i mybanner.png -j 4

# Sequential processing (slowest, minimal system impact)
./imageScroller.sh -i mybanner.png -j off
```
