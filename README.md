lil bash script to generate scrolling gif or .mov from a static png. requires imagemagick and ffmpeg. works in WSL. could probaby convert to powershell but ... ya know...


Usage: ./imagescroll.sh -i <input_image> [options]

Options:
  -i <file>    : Input image file (required).
  -o <file>    : Output base filename (without extension). Extension (.gif/.mov) will be added.
                 (default: <input_name>_<direction_abbr>Scroll)
  -F <format>  : Output format: 'gif', 'video' (MOV w/ ProRes+transparency), or 'both'.
                 (default: gif)
  -d <dir>     : Scroll direction (direction the content appears to move).
                 left (default, abbr: l), right (r), up (u), down (d),
                 up-left (ul), up-right (ur),
                 down-left (dl), down-right (dr).
  -g <pixels>  : Gap between image repetitions (default: 10). Must be >= 0.
  -t <delay>   : Delay between frames in 1/100s (e.g., 4 = 25fps). Mutually exclusive with -s.
  -s <speed>   : Speed in Pixels Per Second (e.g., 25). Mutually exclusive with -t.
  -v           : Verbose output.
