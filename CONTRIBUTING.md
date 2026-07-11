# Contributing to re.kriate

## Dev setup

You need Lua 5.4 and the `busted` test framework. Any of these work:

```
# Homebrew (macOS)
brew install lua@5.4
brew install luarocks
luarocks install busted

# or, if you already have luarocks set up elsewhere
luarocks install busted
```

`scripts/busted.sh` locates the Lua module path automatically (via
`luarocks path`, then `brew --prefix`, then `$HOME/.luarocks`), so no manual
`LUA_PATH`/`LUA_CPATH` setup should be needed once `busted` is on your `PATH`.

## Running the test suite

```
cd re.kriate
./scripts/busted.sh --no-auto-insulate specs/
```

This should report `0 failures / 0 errors`. One test is expected to show as
`pending`: `specs/seamstress_load_spec.lua` requires a real seamstress
runtime and only runs when `SEAMSTRESS_LOAD_TEST=1` is set (see below).

Coverage report (matches CI):

```
busted --coverage specs/ && luacov
```

## Launching each entrypoint

re.kriate has three ways to run, all sharing the same `lib/app.lua` core
(see `docs/adapters.md`):

**norns** — copy (or symlink) the repo into `~/dust/code/`:

```
cd ~/dust/code
git clone https://github.com/whitmo/re.kriate re_kriate
```

Then select **re.kriate** from the norns script menu.

**seamstress** — install [seamstress](https://github.com/ryleelyman/seamstress)
v1.4.7+ (v2 is not yet supported), then from the repo root:

```
/opt/homebrew/opt/seamstress@1/bin/seamstress -s seamstress.lua
```

(Adjust the binary path for your seamstress install; see the README's
Install & Run section.) This opens a simulated grid window with keyboard
fallback controls.

**standalone** — plain Lua, no norns or seamstress host at all. Useful for
quick smoke-testing changes to the core sequencer/params/event layers:

```
lua standalone.lua [steps]
```

Exit code 0 means the app booted, played `steps` sequencer steps (default
16), and shut down cleanly; this is also what CI runs as a real-entrypoint
smoke test.

## Before opening a PR

- This project follows test-first development: add or extend a
  `specs/*_spec.lua` file for any behavior change before implementing it.
- No custom globals beyond the norns host hooks (`init`, `redraw`, `key`,
  `enc`, `cleanup`) — application state flows through a single `ctx` table.
  See `CLAUDE.md` for the full conventions.
- Run `./scripts/busted.sh --no-auto-insulate specs/` and make sure it's
  green before pushing.
