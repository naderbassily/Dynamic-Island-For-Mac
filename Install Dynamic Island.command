#!/bin/bash
# Double-click this file in Finder to build and install Dynamic Island from source.
cd "$(dirname "$0")"
echo "Installing Dynamic Island... please wait 1-2 minutes."
echo
if ./build.sh --install 2>&1 | tee build-log.txt; [ "${PIPESTATUS[0]}" -eq 0 ]; then
  echo
  echo "DONE! Look at the top of your screen."
  echo "You can close this window."
else
  echo
  echo "Something went wrong. The details were saved to build-log.txt in this folder."
  echo "Just tell Claude 'try again' - it can read the log."
fi
