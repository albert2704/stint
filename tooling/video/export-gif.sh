#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
input=../../docs/media/demo.mp4
output=../../docs/media/demo.gif
ffmpeg -hide_banner -loglevel error -y -i "$input" \
  -filter_complex "fps=8,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
  -loop 0 "$output"
printf 'Wrote %s\n' "$output"
