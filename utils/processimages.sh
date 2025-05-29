#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# SPDX-FileCopyrightText: 2025 Andrew C.E. Dent <hi@aced.cafe>
#
# -----------------------------------------------------------------------------
# Usage:
#   - Provide one or more PNG photos, corrected for perspective and scale.
#   - Photos are used to extract the basic bitmap and generate project images.
#
# Requirements:
#   - Bash v3.0+
#   - ImageMagick https://imagemagick.org/
#   - ExifTool https://exiftool.org
#   - Oxipng v9.1.3+ https://github.com/shssoichiro/oxipng
#   - Optional: PNGOUT (for extra png compression)
#   - Optional: flexiGIF (for compressing gallery animations)
#
# Assumptions:
#   - Filenames and directory structures follow the project standard.
#   - Correct images are fed in.
#
# WARNING:
#   May not be safe for public use; created for the author's benefit.
#   Provided "as is", without warranty of any kind; see the
#   accompanying LICENSE file for full terms. Use at your own risk!
# -----------------------------------------------------------------------------


# Message decorations - colored for terminals with NO_COLOR unset
ERR='✖ Error:' WARN='▲ Warning:'
[[ -z "${NO_COLOR-}" && -t 1 && "${TERM-}" != dumb ]] \
  && ERR=$'\e[31m'$ERR$'\e[m' WARN=$'\e[33m'$WARN$'\e[m'

# Check the required binaries are available
for bin in 'magick' 'exiftool' 'oxipng'; do
  if ! command -v "${bin}" &> /dev/null; then
    echo "${ERR} '${bin}' is not installed or not in your PATH."
    exit 1
  fi
done
# Check Oxipng is v9.1.3 or greater (for Zopfli iterations `--zi`)
min_ver='9.1.3'
this_ver="$(oxipng --version | head -n1 | sed 's/^oxipng //')"
if [[ $(printf '%s\n' "${min_ver}" "${this_ver}" | sort -V | head -n1) \
  != "${min_ver}" ]]; then
  echo "${ERR} Oxipng v${this_ver}; upgrade to at least v${min_ver}."
  exit 1
fi
# Check for at least one input file
if [[ -z "$1" ]]; then
  echo "${ERR} Missing filename. Provide at least one PNG image to process."
  exit 1
fi

# Common function for lossless png optimization
optimize_png() {
  if [[ -f "$1" ]]; then
    oxipng -q --nx --strip all "$1"
    # First try to optimize with no reductions (8bpp depth preferred)
    #   then allow reductions (lower bit depths and other color modes)
    for reductions in '--nx -q' '-q'; do
      for level in {0..12}; do
        oxipng ${reductions} --zc ${level} --filters 0-9 "$1"
      done
      oxipng ${reductions} --zopfli --zi 255 --filters 0-9 "$1"
      # Optionally compress with PNGOUT if available
      if command -v 'pngout' &> /dev/null; then
        for level in {0..3}; do
          pngout -q -ks -kp -f6 -s${level} "$1"
        done
      fi
    done
  fi
}

# Common function to remove whitespace around strings
trim_string() {
    local trimmed="${1#"${1%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    printf '%s' "${trimmed}"
}


# Standard metadata for images
readonly project='dex98.com'
readonly copyright='Public Domain by ACED, licensed under CC0.'
readonly copyright_long="This work is dedicated to the ${copyright}"
readonly license='https://creativecommons.org/publicdomain/zero/1.0/'

# Setup file paths
base_dir=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
art_dir=$(realpath "${base_dir}/../art")
readonly base_dir art_dir
# Path to supporting data file
readonly dex_LUT="${base_dir}/dex_table.tsv"
if [[ ! -f "${dex_LUT}" ]]; then
  echo "${ERR} Support file '${dex_LUT}' is missing."
  exit 1
fi
# Optional common background image; comment out to remove from image processing
readonly img_background="${base_dir}/img_background.png"

echo ''
echo 'Processing images...'

# -----------------------------------------------------------------------------


while (( "$#" )); do

  # Minimal checks for the input file
  if [[ ! -f "${1%.*}.png" || ! -r "$1" ]]; then
    echo "${ERR} File is not accessible. PNG file required."
    exit 1
  fi
  file_size=$(stat -f%z "$1" 2>/dev/null || wc -c <"$1")
  if (( file_size < 10240 || file_size > 1048576 )); then
    echo "${ERR} File size is outside the allowed range (10 KiB - 1 MiB)."
    exit 1
  fi
  if ! oxipng -q --pretend --nx --nz "$1"; then
    echo "${ERR} Not a valid PNG file. Check for image format issues."
    exit 1
  fi


  # Prepare 'mon details
  # ---------------------------------------------------------------------------

  # Get the image name, extract the details and perform validation
  img_name="$( basename -s .png "$1" )" # e.g. `006-Dragon-1`
  img_name="${img_name/_corrected/}" # Remove possible '_corrected' suffix
  # Sanitize the string, accepting edge cases: `Pin♀/♂` , `Duck'd`, `Mr. X`
  img_name="$(echo "${img_name}" | tr -c "a-zA-Z0-9♀♂'. -\n" '?')"
  # Split the hyphenated string into separate elements
  IFS='-' read -r mon_number mon_name mon_sprite <<< "${img_name}"
  # Validate the 'mon number first
  if [[ ! "${mon_number}" =~ ^[0-9]{3}$ ]] \
      || (( 10#"${mon_number}" < 1 || 10#"${mon_number}" > 151 )); then
    echo "${ERR} Invalid number. Expected between 001 and 151, with leading zeroes."
    exit 1
  fi
  if [[ ! "${mon_number}" = "$( basename "${1%/*}" )" ]] ; then
    echo "${ERR} Invalid number. File and its directory name mismatch."
    exit 1
  fi
  # Look up properties for this 'mon (and colors used later for gallery artwork)
  line_number=$(( 10#${mon_number} + 1 ))
  row=$(sed -n "${line_number}p" "${dex_LUT}")
  IFS=$'\t' read -r _ dex_name mon_palette _ _ art_white art_border art_black \
    <<< "${row}"
  # Remove any spaces from gallery art colors
  art_white="${art_white// /}"
  art_border="${art_border// /}"
  art_black="${art_black// /}"
  # Remove trailing spaces from name
  dex_name="$(trim_string "${dex_name}")"
  # Validate the other parsed details
  if [[ ! "${mon_name}" =~ ^[A-Z] || ${#mon_name} -lt 3 ]]; then
    echo "${ERR} Invalid name. Expected TitleCase and at least 3 characters."
    exit 1
  fi
  if [[ ! "${mon_name}" =  "${dex_name}" ]]; then
    echo "${ERR} Invalid name. '${mon_name}' does not match expected '${dex_name}'."
    exit 1
  fi
  if [[ ! "${mon_sprite}" =~ ^[0-2]$ ]]; then
    echo "${ERR} Invalid sprite number. Expected 0, 1, or 2 (rest, pose, attack)."
    exit 1
  fi
  img_title="${mon_number} ${mon_name} (${mon_sprite})" # e.g. `006 Dragon (1)`

  # Begin processing
  emoji=$(echo "${mon_palette:0:1}" | sed 's/❤/❤️ /') # Fix unicode for red hearts
  echo " - ${emoji} ${img_name}"


  # Produce 'mon images
  # ---------------------------------------------------------------------------

  # Preprocess 'temp' image (reused), tweaking morphology to close pixel gaps
  tmp_file="${art_dir}/png/${img_name}-temp.png"
  img_width="$(magick identify -format '%w' "$1")"
  kernel=$(( img_width > 480 ? 4 : 2 ))
  magick "$1" -negate -morphology Dilate Disk:${kernel} \
    -morphology Erode Disk:$((kernel/2)) -negate \
    -sample 480x512 "${tmp_file}"
  # Subtract a common image background (if given), to improve pixel detection
  subtract_background_operation=()
  if [[ -f "${img_background}" ]]; then
    subtract_background_operation=(
      "${img_background}"
      -compose Mathematics -define compose:args=1,-0.8,0,0.5 -composite
    )
  fi

  # Produce canonical bitmap (png), extracted from the input photograph
  png_file="${art_dir}/png/${img_name}.png"
  magick -colorspace gray -depth 8 "${tmp_file}" \
    "${subtract_background_operation[@]}" \
    -auto-threshold OTSU -alpha off -sample 30x32 \
    -define png:color-type=0 -define png:bit-depth=8 -define png:include-chunk=none \
    "${png_file}"
  optimize_png "${png_file}"

  # Create the Portable Bit Map (PBM) as an archival copy
  pbm_file="${art_dir}/pbm/${img_name}.pbm"
  magick "${png_file}" -depth 1 -compress None "${pbm_file}"

  # Create 'diff' images for manual inspection and Quality Control
  diff_file="${art_dir}/png/diff.${img_name}"
  magick \
    \( "${tmp_file}" -colorspace gray -depth 8 \) \
    \( "${png_file}" -colorspace gray -depth 8 -sample 480x512 \) \
    -alpha off -gravity center -compose difference -composite \
    -normalize -contrast-stretch 5%x5% "${diff_file}".png
  # Flicker animation for comparison
  magick -delay 50 -loop 0 \
    \( "${tmp_file}" -modulate 100,30,100 \) \
    \( "${png_file}" +level-colors '#111,#888' \) \
    -sample 480x512 -gravity center \
    -dither FloydSteinberg -colors 256 "${diff_file}".gif

  # Optionally check the extracted bitmap against another reference source
  chk_file="${base_dir}/check_sprites/xchk_${mon_number}-${mon_sprite}.png"
  if [[ ! -f "${chk_file%.*}.png" ]]; then
    echo "${WARN} Reference image '${chk_file}' not found. No extra checks performed."
  else
    # Remove any previous 'diff' files if we tested before (clean start)
    if [[ -f "${chk_file}.diff.png" ]]; then
      rm -f "${chk_file}.diff.png" "${chk_file}.diff.gif"
    fi
    # Generate Unique ID for the images; a string of 240 hexadecimal characters
    img_uid="$(magick "${png_file}" -depth 1 PBM:- | xxd -p)"
    chk_uid="$(magick "${chk_file}" -sample 30x32 \
      -auto-threshold OTSU -alpha off -depth 1 PBM:- | xxd -p)"
    if [[ "${img_uid}" != "${chk_uid}" ]]; then
      echo -n "${WARN} Check reference artwork for differences. "
      magick compare -metric AE "${png_file}" "${chk_file}" \
        "${chk_file}.diff.png"
      # Flicker animation for comparison
      magick -delay 50 -loop 0 \
        "${chk_file}".diff.png "${chk_file}" "${tmp_file}" \
        \( "${png_file}" +level-colors '#001830,#BFBCB6' \) \
        -sample 480x512 -gravity center \
        -dither None -colors 256 "${chk_file}".diff.gif
      open "${chk_file}".diff.gif
      echo ''
    fi
  fi

  # Create the gallery art
  art_file="${art_dir%/*}/docs/gallery/${img_name}.png"
  magick "${png_file}" -alpha off -colorspace RGB \
    -sample 90x96 \
    -fuzz 0 -fill "${art_black}" -opaque black \
    -fuzz 0 -fill "${art_white}" -opaque white \
    -bordercolor "${art_border}" -border 6 \
    -define png:color-type=3 -define png:bit-depth=8 -define png:include-chunk=none \
    "${art_file}"
  optimize_png "${art_file}"

  # Create 'mon spritesheet and animated GIF for all 3 frames
  if [[ "${mon_sprite}" = 2 ]]; then
    # Check all 3 sprites are present
    spr_base="${art_dir}/png/${mon_number}-${mon_name}"
    if [[ -f "${spr_base}-0.png" \
      && -f "${spr_base}-1.png" \
      && -f "${spr_base}-2.png" ]]; then
      # Spritesheet (horizontal)
      magick montage -colorspace gray -depth 8 \
        "${spr_base}-0.png" "${spr_base}-1.png" "${spr_base}-2.png" \
        -tile 3x1 -geometry +0+0 \
        -define png:color-type=0 -define png:bit-depth=8 -define png:include-chunk=none \
        "${spr_base}.png"
      optimize_png "${spr_base}.png"
      exiftool "${spr_base}.png" -q -overwrite_original -fast1 \
        -Title="#${mon_number} ${mon_name} - '${project}" \
        -Copyright="${copyright} ${license}"
    fi
    # Check all 3 gallery images are present
    art_base="${art_dir%/*}/docs/gallery/${mon_number}-${mon_name}"
    if [[ -f "${art_base}-0.png" \
      && -f "${art_base}-1.png" \
      && -f "${art_base}-2.png" ]]; then
      # Animation
      magick -loop 0 \
        \( "${art_base}-0.png" "${art_base}-1.png" \
          -write mpr:posing_cycle -delete 0--1 \) \
        \( "${art_base}-0.png" "${art_base}-2.png" \
          -write mpr:attack_cycle -delete 0--1 \) \
        \
        -delay 200 "${art_base}-0.png" -delay 49 \
        mpr:posing_cycle mpr:posing_cycle \
        mpr:attack_cycle mpr:attack_cycle \
        mpr:posing_cycle mpr:posing_cycle \
        -layers remove-dups \
        \
        -dither None -alpha off -colors 4 \
        -layers optimize-plus +remap \
        "${art_base}.gif"
      exiftool "${art_base}.gif" -q -overwrite_original -fast5 \
        -Comment="#${mon_number} ${mon_name} - '${project} - ${copyright} ${license}"
      # Optionally compress with FlexiGIF if available
      if command -v 'flexigif' &> /dev/null; then
        # Single-threaded LZW optimizer is slow, so runs as a background task
        nohup bash -c "{ \
          flexigif -q -p -f -a=1 "${art_base}.gif" "${art_base}-o1.gif"; \
          mv "${art_base}-o1.gif" "${art_base}.gif"; \
        }" > /dev/null 2>&1 &
      fi
    fi
  fi

  # Add metadata to png files first and then pbm file
  exiftool \
    "${png_file}" "${art_file}" -q -overwrite_original -fast1 \
      -Title="#${img_title} - '${project}" \
      -Copyright="${copyright} ${license}" \
      -execute \
    "${png_file}" -q -overwrite_original -fast1 \
      -PNG:PixelsPerUnitX=909 -PNG:PixelsPerUnitY=1000 \
      -xresolution=23 -yresolution=25 -resolutionunit=inches \
      -execute \
    "${pbm_file}" -q -overwrite_original -fast5 \
      -Comment="${img_title} - '${project}" # Primary metadata (single line in header)
  # Extra pbm metadata appended to the end as plain text
  printf '\n# %s' "${copyright_long}" "${license}" >> "${pbm_file}"


  # Remove temporary image file
  rm -f "${tmp_file}"

  # Move to next image file provided
  shift
done


publish_sprites=0
publish_gallery=0
# For publishing final release files, set to true (1)
#   Disabled by default (0), as image optimization steps are quite slow


if [[ "${publish_sprites:-0}" -eq 1 || "${publish_gallery:-0}" -eq 1 ]]; then
  dex=()  # Create an array for file names
  while IFS=$'\t' read -r dex_number dex_name _; do
    # Skip the first row (header)
    if [[ -z "$dex_number" ]]; then
      continue
    fi
    dex_number="$(trim_string "${dex_number}")"
    dex_name="$(trim_string "${dex_name}")"
    # Convert dex_number to decimal and use it as an index
    dex_index=$((10#$dex_number))
    # Store the formatted value in the array
    dex["${dex_index}"]="${dex_number}-${dex_name}"
  done < <(tail -n +2 "$dex_LUT")
fi


if [[ "${publish_sprites:-0}" -eq 1 ]]; then
  # Combine individual 'mon spritesheets (3x1) into main spritesheet (3x151)
  echo ' - Generating main spritesheet...'
  sprites_dir="${art_dir%}/png/"
  spritesheet_img="${sprites_dir}SPRITESHEET.png"
  sprite_files=()
  for file in "${dex[@]}"; do
      # Array of filepaths for spritesheets
      sprite_files+=("${sprites_dir}${file}.png")
  done
  magick montage -colorspace gray -depth 8 \
    "${sprite_files[@]}" \
    -tile 1x151 -geometry +0+0 \
    -define png:color-type=0 -define png:bit-depth=8 -define png:include-chunk=none \
    "${spritesheet_img}"
  optimize_png "${spritesheet_img}"
  exiftool "${spritesheet_img}" -q -overwrite_original -fast1 \
    -Title="'${project}" \
    -Copyright="${copyright} ${license}"
  open "${spritesheet_img}"
fi


if [[ "${publish_gallery:-0}" -eq 1 ]]; then
  # Produce main animated GIF gallery image
  echo ' - Generating main gallery image...'
  gallery_dir="${art_dir%/*}/docs/gallery/"
  gallery_img="${gallery_dir}GALLERY"
  # Insert placeholder images to improve 6 column alignment, minimizing
  #   row breaks between related 'mon.
  dex=( "${dex[@]:0:47}" '998-Placeholder' "${dex[@]:48}")

  # Produce one combined gallery image for each frame of animation
  for frame in {0..2}; do
    gallery_files=()
    for file in "${dex[@]:0:150}"; do
        # Array of filepaths to 'mon gallery images (exc. 150 and 151)
        gallery_files+=("${gallery_dir}${file}-${frame}.png")
    done
    magick montage "${gallery_files[@]}" \
      -tile 6x26 -geometry +0+0 \
      "${gallery_img}-${frame}.png"
    # Create footer row featuring: 150, logo (centered), 151.
    canvas_color="#D8D6D0" # Lightest yellow (border color)
    magick -size 612x108 canvas:"${canvas_color}" \
      "${gallery_dir}${dex[150]}-${frame}.png" -geometry +0+0 -composite \
      "${gallery_dir}${dex[151]}-${frame}.png" -geometry +510+0 -composite \
      "${gallery_dir}000-Logo.png" -gravity center -composite \
      -write mpr:gallery_footer +delete \
      "${gallery_img}-${frame}.png" mpr:gallery_footer -append \
      "${gallery_img}-${frame}.png"
  done

  magick -loop 0 \
    \( "${gallery_img}-0.png" "${gallery_img}-1.png" \
      -write mpr:posing_cycle -delete 0--1 \) \
    \( "${gallery_img}-0.png" "${gallery_img}-2.png" \
      -write mpr:attack_cycle -delete 0--1 \) \
    \
    -delay 1029 "${gallery_img}-0.png" -delay 49 \
    mpr:posing_cycle mpr:posing_cycle \
    mpr:attack_cycle mpr:attack_cycle \
    mpr:posing_cycle mpr:posing_cycle \
    -layers remove-dups \
    \
    -dither None -layers optimize-plus +remap \
    -fuzz 0 -layers optimize-transparency \
    "${gallery_img}.gif"
  exiftool "${gallery_img}.gif" -q -overwrite_original -fast5 \
    -Comment="'${project} - ${copyright} ${license}"
  # flexigif -p -f -a=30 "${gallery_img}.gif" "${gallery_img}-optim30.gif"
  open "${gallery_img}.gif"
  # Remove temporary image files
  rm -f "${gallery_img}-0.png" "${gallery_img}-1.png" "${gallery_img}-2.png"
fi


echo '...Finished :)'
echo ''
exit 0
