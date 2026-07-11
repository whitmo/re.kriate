-- specs/platform_spec.lua
-- Tests for lib/platform.lua: the execution-environment boundary.
--
-- re.kriate runs in three environments: norns (hardware), seamstress
-- (desktop), and standalone (plain Lua — no host runtime at all; busted
-- itself is a standalone environment). platform.lua detects which one is
-- active, reports host capabilities, and can bootstrap the minimal host
-- stubs a standalone process needs to boot the full app. The definitive
-- test here boots the REAL app.init on top of prepare_standalone().

package.path = package.path .. ";./?.lua"

local platform = require("lib/platform")

-- Snapshot/restore host globals so this spec can manipulate them freely
-- without poisoning other spec files (which run in the same process under
-- --no-auto-insulate).
local HOST_GLOBALS = {"params", "clock", "metro", "midi", "osc", "norns", "_seamstress", "grid", "screen"}
local saved

local function snapshot_globals()
  local s = {}
  for _, name in ipairs(HOST_GLOBALS) do
    s[name] = rawget(_G, name)
  end
  return s
end

local function restore_globals(s)
  for _, name in ipairs(HOST_GLOBALS) do
    rawset(_G, name, s[name])
  end
end

describe("platform", function()

  before_each(function()
    saved = snapshot_globals()
  end)

  after_each(function()
    restore_globals(saved)
  end)

  describe("detect", function()

    it("reports norns when the norns global is present", function()
      rawset(_G, "norns", {})
      rawset(_G, "_seamstress", nil)
      assert.are.equal("norns", platform.detect())
    end)

    it("reports seamstress when the _seamstress global is present", function()
      rawset(_G, "norns", nil)
      rawset(_G, "_seamstress", {})
      assert.are.equal("seamstress", platform.detect())
    end)

    it("reports standalone when neither host global is present", function()
      rawset(_G, "norns", nil)
      rawset(_G, "_seamstress", nil)
      assert.are.equal("standalone", platform.detect())
    end)

  end)

  describe("capabilities", function()

    it("probes which host services exist as globals", function()
      rawset(_G, "norns", nil)
      rawset(_G, "_seamstress", nil)
      rawset(_G, "screen", nil)
      rawset(_G, "midi", nil)
      rawset(_G, "params", {})
      rawset(_G, "clock", {})
      local caps = platform.capabilities()
      assert.are.equal("standalone", caps.env)
      assert.is_true(caps.params)
      assert.is_true(caps.clock)
      assert.is_false(caps.screen)
      assert.is_false(caps.midi)
    end)

  end)

  describe("prepare_standalone", function()

    it("installs host stubs sufficient to boot the real app.init", function()
      -- wipe the host surface entirely: this is a bare Lua process
      for _, name in ipairs(HOST_GLOBALS) do
        rawset(_G, name, nil)
      end

      platform.prepare_standalone()

      -- hermetic persistence: keep app.init's stock-preset seeding and
      -- autosave restore away from the developer's real data dir
      local preset = require("lib/preset")
      local tmp_dir = "specs/tmp/platform_presets"
      os.execute("mkdir -p " .. tmp_dir)
      preset._test_set_data_dir(tmp_dir)

      local app = require("lib/app")
      local recorder = require("lib/voices/recorder")
      local voices = {}
      for t = 1, 4 do voices[t] = recorder.new(t) end

      local ctx = app.init({ voices = voices, grid_provider = "synthetic" })
      assert.is_true(ctx.ready)

      -- the behavioral layer is live in this environment too
      ctx.events:emit("cmd:transport:play", {})
      assert.is_true(ctx.playing)
      ctx.events:emit("cmd:transport:stop", {})
      assert.is_false(ctx.playing)

      -- and notes can sound into the injected voices via commands
      ctx.events:emit("cmd:note:play", {track = 1, note = 60, vel = 0.8, dur = 0.1})
      assert.are.same({60}, voices[1]:get_notes())

      app.cleanup(ctx)
      preset._test_set_data_dir(nil)
      os.execute("rm -rf " .. tmp_dir)
    end)

    it("does not clobber an existing host (returns nil, err on norns/seamstress)", function()
      rawset(_G, "norns", {})
      local ok, err = platform.prepare_standalone()
      assert.is_nil(ok)
      assert.is_truthy(tostring(err):find("norns"))
    end)

  end)

end)
