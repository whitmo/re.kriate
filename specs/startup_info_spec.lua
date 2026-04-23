-- specs/startup_info_spec.lua
-- Tests for lib/startup_info: git/branch/release introspection + banner.

package.path = package.path .. ";./?.lua"

local startup_info = require("lib/startup_info")

local TMP_ROOT = os.getenv("TMPDIR") or "/tmp"

local function mkdtemp(prefix)
  local path = string.format("%s/%s_%d_%d", TMP_ROOT, prefix,
    os.time(), math.random(1, 1e6))
  os.execute("mkdir -p '" .. path .. "'")
  return path
end

local function write_file(path, content)
  local parent = path:match("(.+)/[^/]+$")
  if parent then os.execute("mkdir -p '" .. parent .. "'") end
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:close()
end

local function rmrf(path)
  os.execute("rm -rf '" .. path .. "'")
end

describe("startup_info", function()
  describe("git_info", function()
    it("returns unknown when no .git exists", function()
      local repo = mkdtemp("rk_nogit")
      local info = startup_info.git_info(repo)
      assert.are.equal("unknown", info.branch)
      assert.are.equal("unknown", info.hash)
      assert.are.equal("unknown", info.short)
      rmrf(repo)
    end)

    it("reads branch and sha from a directory .git layout", function()
      local repo = mkdtemp("rk_gitdir")
      write_file(repo .. "/.git/HEAD", "ref: refs/heads/feature/xyz\n")
      write_file(repo .. "/.git/refs/heads/feature/xyz",
        "abcdef1234567890abcdef1234567890abcdef12\n")
      local info = startup_info.git_info(repo)
      assert.are.equal("feature/xyz", info.branch)
      assert.are.equal("abcdef1234567890abcdef1234567890abcdef12", info.hash)
      assert.are.equal("abcdef1", info.short)
      rmrf(repo)
    end)

    it("falls back to packed-refs when the loose ref is absent", function()
      local repo = mkdtemp("rk_packed")
      write_file(repo .. "/.git/HEAD", "ref: refs/heads/main\n")
      write_file(repo .. "/.git/packed-refs",
        "# pack-refs with: peeled fully-peeled sorted\n" ..
        "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef refs/heads/main\n")
      local info = startup_info.git_info(repo)
      assert.are.equal("main", info.branch)
      assert.are.equal("deadbee", info.short)
      rmrf(repo)
    end)

    it("follows gitdir: pointer in worktree .git file", function()
      local root = mkdtemp("rk_worktree")
      local common = root .. "/.repo.git"
      local wt_gitdir = common .. "/worktrees/polecat_x"
      local repo = root .. "/polecat_x"

      os.execute("mkdir -p '" .. repo .. "'")
      write_file(repo .. "/.git", "gitdir: " .. wt_gitdir .. "\n")
      write_file(wt_gitdir .. "/HEAD", "ref: refs/heads/polecat/x\n")
      write_file(wt_gitdir .. "/commondir", "../..\n")
      write_file(common .. "/refs/heads/polecat/x",
        "1234567890abcdef1234567890abcdef12345678\n")

      local info = startup_info.git_info(repo)
      assert.are.equal("polecat/x", info.branch)
      assert.are.equal("1234567", info.short)
      rmrf(root)
    end)

    it("reports detached HEAD with the hash itself", function()
      local repo = mkdtemp("rk_detached")
      write_file(repo .. "/.git/HEAD",
        "cafebabecafebabecafebabecafebabecafebabe\n")
      local info = startup_info.git_info(repo)
      assert.are.equal("(detached)", info.branch)
      assert.are.equal("cafebab", info.short)
      rmrf(repo)
    end)
  end)

  describe("release_info", function()
    it("returns unknown when the changelog is missing", function()
      local rel = startup_info.release_info("/tmp/nonexistent-re-kriate-cl.md")
      assert.are.equal("unknown", rel.current)
      assert.is_nil(rel.last_release)
    end)

    it("returns the first heading when not Unreleased", function()
      local path = mkdtemp("rk_cl") .. "/CHANGELOG.md"
      write_file(path, "# Changelog\n\n## [2026-04-03]\n- something\n")
      local rel = startup_info.release_info(path)
      assert.are.equal("2026-04-03", rel.current)
      assert.is_nil(rel.last_release)
      rmrf(path:match("(.+)/"))
    end)

    it("pairs Unreleased with the next dated heading", function()
      local path = mkdtemp("rk_cl2") .. "/CHANGELOG.md"
      write_file(path,
        "# Changelog\n\n## [Unreleased]\n- wip\n\n## [2026-04-03]\n- shipped\n")
      local rel = startup_info.release_info(path)
      assert.are.equal("Unreleased", rel.current)
      assert.are.equal("2026-04-03", rel.last_release)
      rmrf(path:match("(.+)/"))
    end)
  end)

  describe("banner_lines", function()
    it("always includes a header and release/branch/commit line", function()
      local lines = startup_info.banner_lines({
        git = { branch = "main", short = "abc1234" },
        release = { current = "2026-04-03" },
      })
      assert.are.equal(2, #lines)
      assert.are.equal("=== re.kriate ===", lines[1])
      assert.is_truthy(lines[2]:find("release: 2026-04-03", 1, true))
      assert.is_truthy(lines[2]:find("branch: main", 1, true))
      assert.is_truthy(lines[2]:find("commit: abc1234", 1, true))
    end)

    it("renders Unreleased with the last shipped date when known", function()
      local lines = startup_info.banner_lines({
        git = { branch = "polecat/x", short = "deadbee" },
        release = { current = "Unreleased", last_release = "2026-04-03" },
      })
      assert.is_truthy(lines[2]:find("Unreleased (last: 2026-04-03)", 1, true))
    end)

    it("appends sc and softcut status lines when provided", function()
      local lines = startup_info.banner_lines({
        git = { branch = "main", short = "abc1234" },
        release = { current = "2026-04-03" },
        sc = "SC 127.0.0.1:57120 ok (v1, mixer,synth)",
        softcut = "softcut: dry-mode (no audio — norns only)",
      })
      assert.are.equal(4, #lines)
      assert.is_truthy(lines[3]:find("SC 127.0.0.1:57120", 1, true))
      assert.is_truthy(lines[4]:find("softcut: dry-mode", 1, true))
    end)

    it("omits sc/softcut lines when status is nil", function()
      local lines = startup_info.banner_lines({
        git = { branch = "main", short = "abc1234" },
        release = { current = "2026-04-03" },
      })
      assert.are.equal(2, #lines)
    end)

    it("degrades to unknown when fields are missing", function()
      local lines = startup_info.banner_lines({})
      assert.are.equal(2, #lines)
      assert.is_truthy(lines[2]:find("release: unknown", 1, true))
      assert.is_truthy(lines[2]:find("branch: unknown", 1, true))
      assert.is_truthy(lines[2]:find("commit: unknown", 1, true))
    end)
  end)

  describe("announce", function()
    it("routes each banner line through the injected printer", function()
      local captured = {}
      startup_info.announce({
        git = { branch = "main", short = "abc1234" },
        release = { current = "2026-04-03" },
      }, function(line) captured[#captured + 1] = line end)
      assert.are.equal(2, #captured)
      assert.are.equal("=== re.kriate ===", captured[1])
    end)
  end)

  describe("collect", function()
    it("combines git + release lookup for a repo root", function()
      local repo = mkdtemp("rk_collect")
      write_file(repo .. "/.git/HEAD", "ref: refs/heads/main\n")
      write_file(repo .. "/.git/refs/heads/main",
        "abcdef1234567890abcdef1234567890abcdef12\n")
      write_file(repo .. "/CHANGELOG.md", "## [2026-04-03]\n- ok\n")
      local info = startup_info.collect(repo)
      assert.are.equal("main", info.git.branch)
      assert.are.equal("abcdef1", info.git.short)
      assert.are.equal("2026-04-03", info.release.current)
      rmrf(repo)
    end)
  end)
end)
