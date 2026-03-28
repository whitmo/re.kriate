#!/usr/bin/env bash
# Helper to run busted with local lua path so mediator.lua is found.
set -e
cd "$(dirname "$0")/.."
LUA_PATH='./?.lua;./?/init.lua;/opt/homebrew/share/lua/5.4/?.lua;/opt/homebrew/share/lua/5.4/?/init.lua;/Users/whit/.luarocks/share/lua/5.4/?.lua;/Users/whit/.luarocks/share/lua/5.4/?/init.lua;;'
LUA_CPATH='/opt/homebrew/lib/lua/5.4/?.so;/Users/whit/.luarocks/lib/lua/5.4/?.so;;'
LUA_PATH="$LUA_PATH" LUA_CPATH="$LUA_CPATH" busted "$@"
