# Image Scroll Generator

A little Bash script to generate a scrolling GIF or `.mov` from a static PNG. tested most directions, we're fingers crossed on the others. open an issue if a direction doesnt work right
Requires **ImageMagick** and **FFmpeg**. Works in **WSL**. Could probably be converted to PowerShell, but... ya know...

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
./imagescroll.sh -i <input_image> [options]
```

### Options

| Option | Description |
|:------|:------------|
| `-i <file>` | Input image file (required). |
| `-o <file>` | Output base filename (without extension). Extension (`.gif`/`.mov`) will be added. <br> _(Default: `<input_name>_<direction_abbr>Scroll`)_. |
| `-F <format>` | Output format: `gif`, `video` (MOV w/ ProRes + transparency), or `both`. <br> _(Default: gif)_. |
| `-d <dir>` | Scroll direction (direction the content appears to move). <br> Options: `left (l)` _(default)_, `right (r)`, `up (u)`, `down (d)`, `up-left (ul)`, `up-right (ur)`, `down-left (dl)`, `down-right (dr)`. |
| `-g <pixels>` | Gap between image repetitions. _(Default: 10 pixels)_. Must be ≥ 0. |
| `-t <delay>` | Delay between frames (1/100s, e.g., `4` = 25fps). Mutually exclusive with `-s`. |
| `-s <speed>` | Speed in Pixels Per Second (e.g., `25`). Mutually exclusive with `-t`. |
| `-v` | Verbose output. |

---

## 📋 Example

```bash
./imagescroll.sh -i mybanner.png -d left -F both
```
