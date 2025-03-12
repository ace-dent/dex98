#!/bin/bash

# WARNING: Not safe for public use! Created for the author's benefit.
# Assumes:
# - Filenames and directory structure follows the project standard.
# - Correct images are fed in
# - ImageMagick, exiftool and Oxipng executables are required.


# Check the required binaries are available
for bin in 'magick' 'exiftool' 'oxipng'; do
  if ! command -v "${bin}" &> /dev/null; then
    echo "Error: '${bin}' is not installed or not in your PATH."
    exit
  fi
done
min_version="9.1.3" # Check Oxipng v9.1.3 or greater is available (for --zi)
this_version=$(oxipng --version | head -n1 | awk '{print $NF}')
if [[ $(printf '%s\n' "${min_version}" "${this_version}" \
    | sort -V | head -n1) != "${min_version}" ]]; then
  echo "Error: Oxipng v${this_version}; upgrade to at least v${min_version}."
  exit
fi
# Check for at least one input file
if [[ -z "$1" ]]; then
  echo 'Missing filename. Provide at least one image to process.'
  exit
fi


# Standard metadata for images
readonly project='dex98.com'
readonly copyright='This work is dedicated to the Public Domain by ACED, licensed under CC0.'
readonly copyright_short='Public Domain by ACED, licensed under CC0.'
readonly license='https://creativecommons.org/publicdomain/zero/1.0/'

# Setup file paths
base_dir=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
art_dir=$(realpath "${base_dir}/../art")
background_img="${base_dir}/background_img.png"

echo ''
echo 'Processing images...'


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
  if ! oxipng -q --pretend --opt 0 "$1"; then
    echo 'Not a valid PNG file. Check for image format issues.'
    exit
  fi

  # Get the image name and details from the filename
  img_name="$( basename -s .png "$1" )" # e.g. `006-Dragon-1`
  img_name="${img_name/_corrected/}" # Remove possible '_corrected' suffix
  # Sanitize the string but accept edge cases, e.g. "Mr. Mime", "Farfetch'd"
  img_name="$(echo "$img_name" | tr -c "a-zA-Z0-9'. -\n" '?')"
  echo " > ${img_name}"

  # Split the hyphenated string into separate elements
  IFS='-' read -r mon_number mon_name mon_sprite <<< "${img_name}"
  # Validate the parsed details
  if ! [[ "$mon_number" =~ ^[0-9]{3}$ ]] \
      || (( 10#"${mon_number}" < 1 || 10#"${mon_number}" > 151 )); then
    echo 'Invalid number. Expected between 001 and 151, with leading zeroes.'
    exit
  fi
  if [[ ! "$mon_name" =~ ^[A-Z] || ${#mon_name} -lt 3 ]]; then
    echo 'Invalid name. Expected TitleCase and at least 3 characters.'
    exit
  fi
  if [[ ! "$mon_sprite" =~ ^[0-2]$ ]]; then
    echo 'Invalid sprite number. Expected 0, 1, or 2 (rest, pose, attack).'
    exit
  fi
  img_title="${mon_number} ${mon_name} (${mon_sprite})" # e.g. `006 Dragon (1)`


  # Produce images
  # --------------

  png_file="${art_dir}/png/${img_name}.png"
  tmp_file="${art_dir}/png/${img_name}-temp.png"
  magick "$1" -negate -morphology Dilate Disk:4 -morphology Erode Disk:2 \
      -negate -sample 480x512 "${tmp_file}"
  magick -colorspace gray -depth 8 "${tmp_file}" "${background_img}" \
    -compose Mathematics -define compose:args=1,-0.8,0,0.5 -composite \
    -auto-threshold OTSU -alpha off -sample 30x32 \
    -define png:color-type=0 -define png:bit-depth=8 -define png:include-chunk=none \
    "${png_file}"


  # Create 'diff' images, for ultimate visual Quality Assurance
  diff_file="${art_dir}/png/diff.${img_name}"
  magick \
    \( "${tmp_file}" -colorspace gray -depth 8 \) \
    \( "${png_file}" -colorspace gray -depth 8 -sample 480x512 \) \
    -alpha off -gravity center -compose difference -composite \
    -normalize -contrast-stretch 5%x5% "${diff_file}".png
  # Flicker animation for comparison
  magick -delay 50 -loop 0 \
    \( "${tmp_file}" -modulate 100,30,100 \) \
    \( "${png_file}" +level-colors '#111','#888' \) \
    -sample 480x512 -gravity center \
    -dither FloydSteinberg -colors 256 -layers Optimize "${diff_file}".gif

  # Create the gallery 'art' image
  #  This is likely to be changed in the future
  art_file="${art_dir%/*}/docs/gallery/${img_name}.png"
  magick "${png_file}" -alpha off -sample 90x96 \
    +level-colors "#001830,#BFBCB6" \
    -bordercolor "#CFCDC7" -border 3 \
    -define png:bit-depth=8 -define png:include-chunk=none \
    "${art_file}"

  # Optimize PNG image compression, before adding custom metadata
  for file in "${png_file}" "${art_file}"; do
    oxipng -q --nx --strip all "${file}"
    # First try to optimize with no reductions (8bpp, grayscale preferred)
    #   then allow reductions (other bit depths and color formats)
    for reductions in '-q --nx' '-q'; do
      for zc_level in {0..12}; do
        oxipng ${reductions} --zc ${zc_level} --filters 0-9 "${file}"
      done
      oxipng ${reductions} --zopfli --zi 200 --filters 0-9 "${file}"
    done
  done

  # Create the Portable Bit Map (PBM) file
  pbm_file="${art_dir}/pbm/${img_name}.pbm"
  magick "${png_file}" -depth 1 -compress None "${pbm_file}"


  # Add metadata to png files first and then pbm file
  exiftool \
    "${png_file}" "${art_file}" -q -overwrite_original -fast1 \
      -Title="#${img_title} - '${project}" \
      -Copyright="${copyright_short} ${license}" \
    -execute \
    "${png_file}" -q -overwrite_original -fast1 \
      -PNG:PixelsPerUnitX=909 -PNG:PixelsPerUnitY=1000 \
      -xresolution=23 -yresolution=25 -resolutionunit=inches \
    -execute \
    "${pbm_file}" -q -overwrite_original -fast5 \
      -Comment="${img_title} - '${project}" # Primary pbm metadata (single text line in header)
  printf '\n# %s' "${copyright}" "${license}" >> "${pbm_file}" # Extra pbm metadata appended to the plain text file

  # Remove temporary file
  rm -f "${tmp_file}"

  # Move to next image file provided
  shift
done


echo '...Finished :)'
echo ''
exit
