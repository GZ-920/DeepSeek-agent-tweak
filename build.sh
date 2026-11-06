#!/usr/bin/env bash
# GitHub Actions 用：在 macOS runner 上装 Theos，编译 DSAAgent.dylib + .deb
set -euo pipefail
export THEOS="${THEOS:-$HOME/theos}"

if [ ! -d "$THEOS" ]; then
  git clone --recursive --depth 1 https://github.com/theos/theos.git "$THEOS"
fi
if [ ! -x "$THEOS/bin/make" ] && [ -z "${THEOS_MAKE:-}" ]; then
  # Theos 自带 make 包装器；没有就退回系统 make
  echo "using system make"
fi

THEOS_MAKE_PATH="$THEOS/makefiles" make -C "$(dirname "$0")" package FINALPACKAGE=1

echo "---- artifacts ----"
ls -l "$(dirname "$0")/packages/" || true
ls -l "$(dirname "$0")/.theos/obj/debug/" 2>/dev/null || true
