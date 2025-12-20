#!/bin/bash

# Generate app icons from SVG
# Requires: Python 3 with cairosvg or rsvg-convert

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON_DIR="$SCRIPT_DIR/../FoundationChat/FoundationChat/Assets.xcassets/AppIcon.appiconset"
SVG_FILE="$ICON_DIR/icon.svg"

if [ ! -f "$SVG_FILE" ]; then
    echo "Error: SVG file not found at $SVG_FILE"
    exit 1
fi

cd "$ICON_DIR"

# Check for available conversion tools
if command -v rsvg-convert &> /dev/null; then
    echo "Using rsvg-convert..."
    rsvg-convert -w 16 -h 16 "$SVG_FILE" -o icon_16x16.png
    rsvg-convert -w 32 -h 32 "$SVG_FILE" -o icon_16x16@2x.png
    rsvg-convert -w 32 -h 32 "$SVG_FILE" -o icon_32x32.png
    rsvg-convert -w 64 -h 64 "$SVG_FILE" -o icon_32x32@2x.png
    rsvg-convert -w 128 -h 128 "$SVG_FILE" -o icon_128x128.png
    rsvg-convert -w 256 -h 256 "$SVG_FILE" -o icon_128x128@2x.png
    rsvg-convert -w 256 -h 256 "$SVG_FILE" -o icon_256x256.png
    rsvg-convert -w 512 -h 512 "$SVG_FILE" -o icon_256x256@2x.png
    rsvg-convert -w 512 -h 512 "$SVG_FILE" -o icon_512x512.png
    rsvg-convert -w 1024 -h 1024 "$SVG_FILE" -o icon_512x512@2x.png
elif python3 -c "import cairosvg" 2>/dev/null; then
    echo "Using Python cairosvg..."
    python3 << 'PYTHON'
import cairosvg
import os

svg_file = "icon.svg"
sizes = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for size, filename in sizes:
    cairosvg.svg2png(url=svg_file, write_to=filename, output_width=size, output_height=size)
    print(f"Generated {filename}")
PYTHON
elif python3 -c "import svglib; from reportlab.graphics import renderPM" 2>/dev/null; then
    echo "Using Python svglib..."
    python3 << 'PYTHON'
from svglib.svglib import svg2rlg
from reportlab.graphics import renderPM
import os

svg_file = "icon.svg"
sizes = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

drawing = svg2rlg.svg2rlg(svg_file)
for size, filename in sizes:
    renderPM.drawToFile(drawing, filename, fmt='PNG', configPIL={'size': (size, size)})
    print(f"Generated {filename}")
PYTHON
else
    echo "No SVG conversion tool found. Installing cairosvg..."
    echo "Please run: pip3 install cairosvg"
    echo ""
    echo "Or install librsvg: brew install librsvg"
    echo ""
    echo "Alternatively, you can convert the SVG manually using an online tool or image editor."
    exit 1
fi

echo "✅ All app icons generated successfully!"



