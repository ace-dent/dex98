#!/bin/bash
# SPDX-License-Identifier: CC0-1.0
# SPDX-FileCopyrightText: 2025 Andrew Dent <hi@aced.cafe>
#
# -----------------------------------------------------------------------------
# Usage:
#   - Provide one or more PNG photos, corrected for perspective and scale.
#   - Photos are used to extract the basic bitmap and generate project images.
#
# Requirements:
#   - ImageMagick https://imagemagick.org/
#   - exiftool https://exiftool.org
#   - Oxipng v9.1.3 or greater https://github.com/shssoichiro/oxipng
#   - Optional: PNGOUT (for extra png compression)
#   - Optional: flexiGIF (for compressing gallery animations)
#
# Assumptions:
#   - Filenames and directory structures follow the project standard.
#   - Correct images are fed in.
#
# WARNING:
#   May not be safe for public use; created for the author's benefit!
# -----------------------------------------------------------------------------

# Check the required binaries are available
for bin in 'magick' 'exiftool' 'oxipng'; do
  if ! command -v "${bin}" &> /dev/null; then
    echo "Error: '${bin}' is not installed or not in your PATH."
    exit
  fi
done
# Check Oxipng is v9.1.3 or greater (for Zopfli iterations `--zi`)
min_ver='9.1.3'
this_ver="$(oxipng --version | head -n1 | sed 's/^oxipng //')"
if [[ $(printf '%s\n' "${min_ver}" "${this_ver}" | sort -V | head -n1) \
  != "${min_ver}" ]]; then
  echo "Error: Oxipng v${this_ver}; upgrade to at least v${min_ver}."
  exit
fi
# Check for at least one input file
if [[ -z "$1" ]]; then
  echo 'Missing filename. Provide at least one PNG image to process.'
  exit
fi


# Standard metadata for images
readonly project='dex98.com'
readonly copyright='Public Domain by ACED, licensed under CC0.'
readonly copyright_long='This work is dedicated to the '"${copyright}"
readonly license='https://creativecommons.org/publicdomain/zero/1.0/'

# Setup file paths
base_dir=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
art_dir=$(realpath "${base_dir}/../art")
readonly base_dir art_dir
# Look Up Table support file
readonly dex_LUT="${base_dir}/dex_table.tsv"
if [[ ! -f "${dex_LUT}" ]]; then
  echo "Support file '${dex_LUT}' is missing."
  exit
fi
# Optional common background image; comment out to remove from image processing
readonly img_background="${base_dir}/img_background.png"

echo ''
echo 'Processing images...'

# -----------------------------------------------------------------------------


while (( "$#" )); do

  # Minimal checks for the input file
  if [[ ! -f "${1%.*}.png" ]]; then
    echo 'File not found. PNG file required.'
    exit
  fi
  file_size=$(stat -f%z "$1")
  if (( file_size < 10240 || file_size > 1048576 )); then
    echo 'File size is outside the allowed range (10 KiB - 1 MiB).'
    exit
  fi
  if ! oxipng -q --pretend --nx --nz "$1"; then
    echo 'Not a valid PNG file. Check for image format issues.'
    exit
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
    echo 'Invalid number. Expected between 001 and 151, with leading zeroes.'
    exit
  fi
  if [[ ! "${mon_number}" = "$( basename "${1%/*}" )" ]] ; then
    echo 'Invalid number. File and its directory name mismatch.'
    exit
  fi
  # Look up properties for this 'mon (also used later for gallery artwork)
  line_number=$(( 10#${mon_number} + 1 ))
  row=$(sed -n "${line_number}p" "${dex_LUT}")
  IFS=$'\t' read -r _ dex_name mon_palette _ _ art_white art_border art_black \
    <<< "${row}"
  # Remove any spaces from gallery art colors
  art_white="${art_white// /}"
  art_border="${art_border// /}"
  art_black="${art_black// /}"
  # Remove trailing spaces from name
  dex_name="$(echo "${dex_name}" | sed 's/[[:space:]]*$//')"
  # Validate the other parsed details
  if [[ ! "${mon_name}" =~ ^[A-Z] || ${#mon_name} -lt 3 ]]; then
    echo 'Invalid name. Expected TitleCase and at least 3 characters.'
    exit
  fi
  if [[ ! "${mon_name}" =  "${dex_name}" ]]; then
    echo "Invalid name. '${mon_name}' does not match expected '${dex_name}'."
    exit
  fi
  if [[ ! "${mon_sprite}" =~ ^[0-2]$ ]]; then
    echo 'Invalid sprite number. Expected 0, 1, or 2 (rest, pose, attack).'
    exit
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
    echo "Reference image '${chk_file}' not found. No extra checks performed."
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
      echo -n 'WARNING! Check reference artwork for differences. '
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
  magick "${png_file}" -alpha off -fuzz 0 -colorspace RGB \
    -sample 90x96 \
    -fill "${art_black}" -opaque '#000' \
    -fill "${art_white}" -opaque '#FFF' \
    -bordercolor "${art_border}" -border 6 \
    -define png:color-type=3 -define png:bit-depth=8 -define png:include-chunk=none \
    "${art_file}"
  # Create animated GIF when all 3 sprites are available
  if [[ "${mon_sprite}" = 2 ]]; then
    spr_base="${art_dir%/*}/docs/gallery/${mon_number}-${mon_name}"
    if [[ -f "${spr_base}-0.png" \
      && -f "${spr_base}-1.png" \
      && -f "${spr_base}-2.png" ]]; then
      magick -loop 0 \
        \( "${spr_base}-0.png" "${spr_base}-1.png" \
          -write mpr:posing_cycle -delete 0--1 \) \
        \( "${spr_base}-0.png" "${spr_base}-2.png" \
          -write mpr:attack_cycle -delete 0--1 \) \
        \
        -delay 200 "${spr_base}-0.png" -delay 49 \
        mpr:posing_cycle mpr:posing_cycle \
        mpr:attack_cycle mpr:attack_cycle \
        mpr:posing_cycle mpr:posing_cycle \
        -layers remove-dups \
        \
        -dither None -alpha off -colors 4 \
        -layers optimize-plus +remap \
        "${spr_base}.gif"
      exiftool "${spr_base}.gif" -q -overwrite_original -fast5 \
        -Comment="#${mon_number} ${mon_name} - '${project} - ${copyright} ${license}"
      # Optionally compress with FlexiGIF if available
      if command -v 'flexigif' &> /dev/null; then
        # Single-threaded LZW optimizer is slow, so runs as a background task
        nohup bash -c "{ \
          flexigif -q -p -f -a=1 "${spr_base}.gif" "${spr_base}-o1.gif"; \
          mv "${spr_base}-o1.gif" "${spr_base}.gif"; \
        }" > /dev/null 2>&1 &
      fi
    fi
  fi

  # Optimize PNG images before adding custom metadata
  for file in "${png_file}" "${art_file}"; do
    oxipng -q --nx --strip all "${file}"
    # First try to optimize with no reductions (8bpp depth preferred)
    #   then allow reductions (lower bit depths and other color modes)
    for reductions in '--nx -q' '-q'; do
      for level in {0..12}; do
        oxipng ${reductions} --zc ${level} --filters 0-9 "${file}"
      done
      oxipng ${reductions} --zopfli --zi 255   --filters 0-9 "${file}"
      # Optionally compress with PNGOUT if available
      if command -v 'pngout' &> /dev/null; then
        for level in {0..3}; do
          pngout -q -ks -kp -f6 -s${level} "${file}"
        done
      fi
    done
  done

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
      -Comment="${img_title} - '${project}" # Primary pbm metadata (single text line in header)
  printf '\n# %s' "${copyright_long}" "${license}" >> "${pbm_file}" # Extra pbm metadata appended to the plain text file

  # Remove temporary image file
  rm -f "${tmp_file}"

  # Move to next image file provided
  shift
done


echo '...Finished :)'
echo ''
exit
