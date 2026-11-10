#!/bin/bash
# Double-click to create "Dynamic Island.dmg" and "Dynamic Island.zip" that you can
# AirDrop, email or upload. Works on Apple silicon and Intel Macs.
cd "$(dirname "$0")"
echo "Making a shareable copy of Dynamic Island... about 2-3 minutes."
echo
if ./build.sh --share 2>&1 | tee build-log.txt; [ "${PIPESTATUS[0]}" -eq 0 ]; then
  echo
  echo "DONE! \"Dynamic Island.dmg\" is in this folder. Share it with anyone."
  open -R "Dynamic Island.dmg"
else
  echo
  echo "Something went wrong. The details were saved to build-log.txt."
  echo "Just tell Claude 'try again' - it can read the log."
fi
