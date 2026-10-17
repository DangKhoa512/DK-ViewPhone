#!/bin/bash

if [ -z "${THEOS:-}" ]; then
  THEOS="$HOME/theos-roothide"
  if [ ! -d "$THEOS" ] && [ -n "${GITHUB_WORKSPACE:-}" ]; then
    THEOS="$GITHUB_WORKSPACE/theos-roothide"
  fi
fi
if [ ! -f "$THEOS/vendor/mod/roothide/package/deb.mk" ]; then
  echo "Missing roothide/theos checkout at $THEOS (including submodules)." >&2
  return 1
fi

export THEOS
export THEOS_PACKAGE_SCHEME=roothide
export THEOS_DEVICE_IP=127.0.0.1
export THEOS_DEVICE_PORT=58422
export THEOS_DEVICE_SIMULATOR=
export THEBOOTSTRAP=
