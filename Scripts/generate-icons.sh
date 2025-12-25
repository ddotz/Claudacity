#!/bin/bash
#
# Icon Generation Script for Claudacity
# Generates PDF icons for menu bar from SVG sources
#
# Requirements:
#   - Inkscape or rsvg-convert (librsvg)
#   - Install: brew install librsvg
#
# Usage:
#   ./Scripts/generate-icons.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$PROJECT_DIR/Claudacity/Resources/Assets.xcassets"
ICONS_DIR="$SCRIPT_DIR/icons"

echo "Generating Claudacity icons..."

# Check for conversion tool
if command -v rsvg-convert &> /dev/null; then
    CONVERTER="rsvg-convert"
elif command -v inkscape &> /dev/null; then
    CONVERTER="inkscape"
else
    echo "Error: No SVG to PDF converter found."
    echo "Install librsvg: brew install librsvg"
    echo "Or install Inkscape: brew install --cask inkscape"
    exit 1
fi

# Create icons directory if not exists
mkdir -p "$ICONS_DIR"

# Generate MenuBar icon (template image - 18x18 for menu bar)
cat > "$ICONS_DIR/menubar-icon.svg" << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
  <path fill="#000000" d="M9 1C4.58 1 1 4.58 1 9s3.58 8 8 8 8-3.58 8-8-3.58-8-8-8zm0 14.5c-3.59 0-6.5-2.91-6.5-6.5S5.41 2.5 9 2.5s6.5 2.91 6.5 6.5-2.91 6.5-6.5 6.5z"/>
  <path fill="#000000" d="M9 4.5c-.55 0-1 .45-1 1v4l3.5 2.1c.46.28 1.06.13 1.34-.33.28-.46.13-1.06-.33-1.34L10 8.5V5.5c0-.55-.45-1-1-1z"/>
</svg>
SVGEOF

# Generate status icons (colored, 16x16)
cat > "$ICONS_DIR/status-normal.svg" << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <circle cx="8" cy="8" r="6" fill="#34C759"/>
</svg>
SVGEOF

cat > "$ICONS_DIR/status-warning.svg" << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <circle cx="8" cy="8" r="6" fill="#FF9500"/>
</svg>
SVGEOF

cat > "$ICONS_DIR/status-critical.svg" << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <circle cx="8" cy="8" r="6" fill="#FF3B30"/>
</svg>
SVGEOF

# Convert SVGs to PDFs
echo "Converting SVGs to PDFs using $CONVERTER..."

convert_svg_to_pdf() {
    local svg_file="$1"
    local pdf_file="$2"

    if [ "$CONVERTER" = "rsvg-convert" ]; then
        rsvg-convert -f pdf -o "$pdf_file" "$svg_file"
    else
        inkscape --export-type=pdf --export-filename="$pdf_file" "$svg_file" 2>/dev/null
    fi

    echo "  Created: $pdf_file"
}

# Convert each icon
convert_svg_to_pdf "$ICONS_DIR/menubar-icon.svg" "$ASSETS_DIR/MenuBarIcon.imageset/menubar-icon.pdf"
convert_svg_to_pdf "$ICONS_DIR/status-normal.svg" "$ASSETS_DIR/StatusNormal.imageset/status-normal.pdf"
convert_svg_to_pdf "$ICONS_DIR/status-warning.svg" "$ASSETS_DIR/StatusWarning.imageset/status-warning.pdf"
convert_svg_to_pdf "$ICONS_DIR/status-critical.svg" "$ASSETS_DIR/StatusCritical.imageset/status-critical.pdf"

echo ""
echo "Icon generation complete!"
echo "Generated icons are in: $ASSETS_DIR"
