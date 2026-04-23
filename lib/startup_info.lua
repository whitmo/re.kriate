-- lib/startup_info.lua
-- Print state information to the console at script load.
--
-- Surfaces git hash, branch, release number, and connection status for
-- SuperCollider and softcut so a fresh session makes the runtime environment
-- obvious. Works on both seamstress (development host) and norns (target
-- device), with graceful fallbacks when git metadata or changelog are absent.
--
-- Pure functions + an `announce` entrypoint, so callers can use individual
-- helpers in tests without triggering a print.

local M = {}

--- Read an entire file's contents. Returns nil if the file is absent or
--- unreadable; callers decide how to render a missing value.
function M.read_file(path)
  if not path then return nil end
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

--- Resolve the git directory for a repository root. Handles worktrees,
--- where `.git` is a file containing `gitdir: <path>` rather than a real
--- directory. Returns an absolute path or nil if no git metadata is found.
function M.resolve_gitdir(repo_dir)
  repo_dir = repo_dir or "."
  local dot_git = repo_dir .. "/.git"
  local content = M.read_file(dot_git)
  if content then
    local gitdir = content:match("gitdir:%s*(%S+)")
    if gitdir then
      return trim(gitdir)
    end
    return nil
  end
  -- Probe HEAD to confirm this is a real gitdir.
  if M.read_file(dot_git .. "/HEAD") then
    return dot_git
  end
  return nil
end

--- Look up a ref sha in a worktree-aware layout: first the worktree's own
--- ref tree, then the commondir's refs, then packed-refs in the commondir.
local function lookup_ref(gitdir, ref_path)
  local sha = M.read_file(gitdir .. "/" .. ref_path)
  if sha then return trim(sha) end

  local commondir_rel = M.read_file(gitdir .. "/commondir")
  if commondir_rel then
    commondir_rel = trim(commondir_rel)
    local commondir = commondir_rel
    if not commondir:match("^/") then
      commondir = gitdir .. "/" .. commondir
    end
    sha = M.read_file(commondir .. "/" .. ref_path)
    if sha then return trim(sha) end

    local packed = M.read_file(commondir .. "/packed-refs")
    if packed then
      for line in packed:gmatch("[^\n]+") do
        local h, r = line:match("^(%x+)%s+(%S+)$")
        if r == ref_path then return h end
      end
    end
  end

  local packed = M.read_file(gitdir .. "/packed-refs")
  if packed then
    for line in packed:gmatch("[^\n]+") do
      local h, r = line:match("^(%x+)%s+(%S+)$")
      if r == ref_path then return h end
    end
  end
  return nil
end

--- Introspect git HEAD for a repo root. Returns a table with
--- `{ branch = "...", hash = "...", short = "..." }`. Missing values are
--- reported as "unknown" so callers don't need to guard every field.
function M.git_info(repo_dir)
  local out = { branch = "unknown", hash = "unknown", short = "unknown" }
  local gitdir = M.resolve_gitdir(repo_dir)
  if not gitdir then return out end

  local head = M.read_file(gitdir .. "/HEAD")
  if not head then return out end
  head = trim(head)

  local ref = head:match("^ref:%s*(%S+)$")
  if ref then
    out.branch = ref:gsub("^refs/heads/", "")
    local sha = lookup_ref(gitdir, ref)
    if sha then
      out.hash = sha
      out.short = sha:sub(1, 7)
    end
  else
    -- Detached HEAD — HEAD itself is the sha.
    if head:match("^%x+$") then
      out.hash = head
      out.short = head:sub(1, 7)
      out.branch = "(detached)"
    end
  end
  return out
end

--- Parse the most recent release markers from a Keep-a-Changelog file.
--- Returns `{ current = "Unreleased"|"<date>", last_release = "<date>"|nil }`.
--- When the first heading is Unreleased, `last_release` is the next dated
--- heading so users can see what version their working tree is ahead of.
function M.release_info(changelog_path)
  local content = M.read_file(changelog_path)
  if not content then return { current = "unknown", last_release = nil } end
  local headings = {}
  for line in content:gmatch("[^\n]+") do
    local tag = line:match("^##%s*%[([^%]]+)%]")
    if tag then headings[#headings + 1] = tag end
    if #headings >= 2 then break end
  end
  if #headings == 0 then
    return { current = "unknown", last_release = nil }
  end
  local current = headings[1]
  local last_release = nil
  if current:lower() == "unreleased" then
    last_release = headings[2]
  end
  return { current = current, last_release = last_release }
end

local function format_release(rel)
  if not rel then return "unknown" end
  if rel.current and rel.current:lower() == "unreleased" and rel.last_release then
    return string.format("Unreleased (last: %s)", rel.last_release)
  end
  return rel.current or "unknown"
end

--- Build banner lines without printing. Lets tests assert exact formatting
--- and lets callers route output somewhere other than stdout.
---
--- @param opts table {
---   git = {branch, short, hash},
---   release = {current, last_release},
---   sc = string | nil,        -- sc_bridge:status_string() or similar
---   softcut = string | nil,   -- softcut_runtime.status_string() or similar
--- }
function M.banner_lines(opts)
  opts = opts or {}
  local git = opts.git or {}
  local lines = {}
  lines[#lines + 1] = "=== re.kriate ==="
  lines[#lines + 1] = string.format(
    "release: %s  branch: %s  commit: %s",
    format_release(opts.release),
    git.branch or "unknown",
    git.short or "unknown"
  )
  if opts.sc then
    lines[#lines + 1] = "  " .. opts.sc
  end
  if opts.softcut then
    lines[#lines + 1] = "  " .. opts.softcut
  end
  return lines
end

--- Collect git + release info for a repo root. Separated from `announce` so
--- the expensive parsing is observable in isolation.
function M.collect(repo_dir, changelog_path)
  changelog_path = changelog_path or ((repo_dir or ".") .. "/CHANGELOG.md")
  return {
    git = M.git_info(repo_dir),
    release = M.release_info(changelog_path),
  }
end

--- Print the startup banner. Accepts optional `sc` / `softcut` status
--- strings; callers inject them so this module stays dependency-free.
function M.announce(opts, printer)
  printer = printer or print
  for _, line in ipairs(M.banner_lines(opts)) do
    printer(line)
  end
end

return M
