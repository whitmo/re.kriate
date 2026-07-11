#!/usr/bin/env bash
# Helper to run busted with local lua path so mediator.lua is found.
#
# LUA_PATH/LUA_CPATH are assembled from whatever is available on this
# machine (luarocks' own path resolution, then a brew --prefix lookup,
# then $HOME/.luarocks), with the original hardcoded paths this script
# shipped with appended last as a fallback -- so it still works unmodified
# on the machine it was first written for even if none of the above apply.
set -e
cd "$(dirname "$0")/.."

LUA_PATH_EXTRA=""
LUA_CPATH_EXTRA=""

# Prefer luarocks' own path resolution when it's installed and working.
if command -v luarocks >/dev/null 2>&1; then
  LR_PATH=$(luarocks path --lr-path 2>/dev/null || true)
  LR_CPATH=$(luarocks path --lr-cpath 2>/dev/null || true)
  [ -n "$LR_PATH" ] && LUA_PATH_EXTRA="$LUA_PATH_EXTRA$LR_PATH;"
  [ -n "$LR_CPATH" ] && LUA_CPATH_EXTRA="$LUA_CPATH_EXTRA$LR_CPATH;"
fi

# Homebrew's Lua 5.4 install location -- brew --prefix resolves to
# /opt/homebrew on Apple Silicon, /usr/local on Intel Mac, etc.
if command -v brew >/dev/null 2>&1; then
  BREW_PREFIX=$(brew --prefix 2>/dev/null || true)
  if [ -n "$BREW_PREFIX" ]; then
    LUA_PATH_EXTRA="$LUA_PATH_EXTRA$BREW_PREFIX/share/lua/5.4/?.lua;$BREW_PREFIX/share/lua/5.4/?/init.lua;"
    LUA_CPATH_EXTRA="$LUA_CPATH_EXTRA$BREW_PREFIX/lib/lua/5.4/?.so;"
  fi
fi

# A user-local luarocks tree (luarocks install --local), wherever $HOME is.
LUA_PATH_EXTRA="$LUA_PATH_EXTRA$HOME/.luarocks/share/lua/5.4/?.lua;$HOME/.luarocks/share/lua/5.4/?/init.lua;"
LUA_CPATH_EXTRA="$LUA_CPATH_EXTRA$HOME/.luarocks/lib/lua/5.4/?.so;"

# Last-resort fallback: the original hardcoded paths, so this keeps working
# on the machine it was first written for even if the above all come up empty.
LUA_PATH="./?.lua;./?/init.lua;$LUA_PATH_EXTRA/opt/homebrew/share/lua/5.4/?.lua;/opt/homebrew/share/lua/5.4/?/init.lua;/Users/whit/.luarocks/share/lua/5.4/?.lua;/Users/whit/.luarocks/share/lua/5.4/?/init.lua;;"
LUA_CPATH="$LUA_CPATH_EXTRA/opt/homebrew/lib/lua/5.4/?.so;/Users/whit/.luarocks/lib/lua/5.4/?.so;;"

LUA_PATH="$LUA_PATH" LUA_CPATH="$LUA_CPATH" busted "$@"
