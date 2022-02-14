#!/usr/bin/env bash

# fatx.sh is a Bash script wrapper for fatx (fatxfs), a userspace FATX
# filesystem driver (https://github.com/mborgerson/fatx).
#
# fatx.sh written primarily because fatx doesn't automagically mount F and G
# partition's (https://github.com/mborgerson/fatx/issues/30) yet.
#
# This script uses alot of bashism. Please use latest version of Bash.
#
# Sahri Riza Umami
#   v0.1 - 13/02/2022 18:51:36
#        - Initial release
#
# LICENSE ----------------------------------------------------------------------
#
# This is free and unencumbered software released into the public domain.
#
# Anyone is free to copy, modify, publish, use, compile, sell, or
# distribute this software, either in source code form or as a compiled
# binary, for any purpose, commercial or non-commercial, and by any
# means.
#
# In jurisdictions that recognize copyright laws, the author or authors
# of this software dedicate any and all copyright interest in the
# software to the public domain. We make this dedication for the benefit
# of the public at large and to the detriment of our heirs and
# successors. We intend this dedication to be an overt act of
# relinquishment in perpetuity of all present and future rights to this
# software under copyright law.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# For more information, please refer to <http://unlicense.org>
#
# ------------------------------------------------------------------------------

THIS_DIR=$(cd "$(dirname "$0")" || exit; pwd)
cd "$THIS_DIR" || exit

text() {
  printf ':: %s\n' "$@"
}

# Print text in brown
warn() {
  printf '\e[33m:: %s\n\e[m' "$@"
}

if [ "$EUID" -ne 0 ]; then
  warn 'Please run as root.'
  exit 0
fi

# Checking dependencies:
declare -a DEPS=(hexdump)
for ((NUM=${#DEPS[@]},i=0; i<NUM;i++)); do
  if command -v "${DEPS[i]}" &>/dev/null ; then
    unset -v 'DEPS[i]'
  fi
done

# Exit if dependency not found.
if [[ "${#DEPS[@]}" -gt 0 ]]; then
  warn    'Package(s) not found'
  warn    'Install the proper distribution package for your system:'
  printf  '   - %s\n' "${DEPS[@]}"
  exit 1
fi

# VARIABLES --------------------------------------------------------------------

if command -v fatxfs &>/dev/null; then
  FATX='fatxfs -o allow_other'
elif [[ -f './build/fatxfs' ]]; then
  FATX='./build/fatxfs -o allow_other'
else
  warn 'FATXFS not found.'
  text 'Will compiling it now:'
  sudo apt install libfuse-dev cmake
  mkdir -pm 777 build && cd build || exit
  cmake ..
  make
  cd "$THIS_DIR" || exit
fi

OGXBOOTREC='ogxbootrec'
# E, C, X, Y and Z partition's are hardcoded.
declare -A XPART=( [0055f400]=E [00465400]=C [00000400]=X [00177400]=Y [002ee400]=Z )

# FUNCTIONS --------------------------------------------------------------------

# List block devices (connected disks)
lsdisk(){
  warn "Check your Xbox's disk in the list below:"
  lsblk -I 8 -do NAME,SIZE,MODEL
}

# Multiply hex value by 512
truhex() {
  printf '0x%x\n' $((0x$1 * 0x200))
}

# Mount FATX extended (not default) partitions
mount_extpart() {
  mapfile -t SECT < <(hexdump "$OGXBOOTREC" | awk '/0000 8000/{ print $5 $4" "$7 $6 }')
  $FATX "$1" "$2" --offset="$(truhex "${SECT[$3]:0:8}")" --size="$(truhex "${SECT[$3]:(-8)}")"
}

print_usage() {
  printf '%s\n' "
  ${0##*/} is a Bash script wrapper for fatxfs, a userspace FATX filesystem
  driver.

  Usage: ${0##*/} OPTION
  Usage: ${0##*/} OPTION <device>
     or: ${0##*/} OPTION <device> <mountpoint> --drive=c|e|f|g|x|y|z

  OPTION:
        lsblk   List connected disks.
    -d  dump    Dump first sector of the Xbox disk (sector 0).
    -l  list    List Xbox disk's partitions from dump.
    -m  mount   Mount Xbox disk's partition.

  Example:
    - Dump first sector of /dev/sdc.
      sudo ${0##*/} dump /dev/sdc

    - List partitions of dumped sector.
      sudo ${0##*/} list

    - Mount F partition of /dev/sdc disk to ~/ogxhdd.
      sudo ${0##*/} mount /dev/sdc ~/ogxhdd --drive=f
"
  exit
}

# MAIN -------------------------------------------------------------------------

case $1 in
  lsblk)
    lsdisk
  ;;
  -d|dump)
    if [[ "$#" -eq 1 ]]; then
      warn 'Please define which disk sector to dump.'
      text "Example: sudo ${0##*/} dump /dev/sda"
      lsdisk
    else
      dd if="$2" bs=512 count=1 > "$OGXBOOTREC"
    fi
  ;;
  -l|list)
    if [[ ! -f "$OGXBOOTREC" ]]; then
      warn 'Xbox disk first sector dump not found.'
      text 'Please dump it first.'
      text "Example: ${0##*/} dump /dev/sda"
      lsdisk
      exit 0
    fi

    # table header
    printf ' %-10s %-14s %-14s %12s %10s\n\n' PARTITION 'OFFSET (hex)' 'SIZE (hex)' 'SIZE (dec)' 'SIZE (MB)'

    n=1
    while read -r PSTART PEND; do
      # print table
      printf  ' %-10s %-14s %-12s %14d %10d\n' \
              "$n. ${XPART[$PSTART]}" \
              "$(truhex "$PSTART")" \
              "$(truhex "$PEND")" \
              "$(truhex "$PEND")" \
              "$(($(truhex "$PEND") / 0x100000))"
      n=$((n+1))
    # get active partision from boot sector dump
    done < <(hexdump "$OGXBOOTREC" | awk '/0000 8000/{ print $5 $4" "$7 $6; }')
  ;;
  -m|mount)
    if [[ "$#" -eq 4 ]]; then
      DRVLTR=${4:(-1)}

      case ${DRVLTR,,} in
        f)
          # F actually is 6th partition.
          # But we use 5 because of mapfile array in mount_extpart start from 0.
          mount_extpart "$2" "$3" 5
        ;;
        g)
          mount_extpart "$2" "$3" 6
        ;;
        *)
          $FATX "$2" "$3" "$4"
        ;;
      esac
    elif [[ "$#" -eq 3 ]]; then
      # Mount C if no drive letter specified (default behaviour).)
      $FATX "${@:2}"
    fi
  ;;
  *)
    print_usage
  ;;
esac
