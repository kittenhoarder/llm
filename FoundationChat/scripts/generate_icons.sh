#!/bin/bash
# Generate app icons for FoundationChat
# Requires: ImageMagick (brew install imagemagick)

ICON_DIR="../FoundationChat/Assets.xcassets/AppIcon.appiconset"

# Create a minimal dark chat bubble icon
# Dark background (#1a1a1a) with a subtle chat bubble

create_icon() {
    local size=$1
    local filename=$2
    
    convert -size ${size}x${size} xc:'#1a1a1a' \
        -fill '#3366cc' \
        -draw "roundrectangle $((size/5)),$((size/4)) $((size*4/5)),$((size*3/4)) $((size/10)),$((size/10))" \
        -fill '#1a1a1a' \
        -draw "polygon $((size/4)),$((size*3/4)) $((size/3)),$((size*3/4)) $((size/5)),$((size*17/20))" \
        "$ICON_DIR/$filename"
}

# Generate all required sizes
create_icon 16 "icon_16x16.png"
create_icon 32 "icon_16x16@2x.png"
create_icon 32 "icon_32x32.png"
create_icon 64 "icon_32x32@2x.png"
create_icon 128 "icon_128x128.png"
create_icon 256 "icon_128x128@2x.png"
create_icon 256 "icon_256x256.png"
create_icon 512 "icon_256x256@2x.png"
create_icon 512 "icon_512x512.png"
create_icon 1024 "icon_512x512@2x.png"

echo "Icons generated in $ICON_DIR"





