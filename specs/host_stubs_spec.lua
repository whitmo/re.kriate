-- specs/host_stubs_spec.lua
-- Tests for specs/lib/host_stubs.lua: the shared save/restore helper for
-- host-runtime globals (params, clock, grid, ...) that spec files fake out.
--
-- Under --no-auto-insulate, busted runs every spec file in one Lua process,
-- so a bare `rawset(_G, "params", ...)` at module load time in one file
-- leaks into every file that runs after it (see specs/ui_spec_spec.lua's
-- mixer describe block for the hand-rolled guard this generalizes). This
-- helper exists so specs can snapshot/restore globals from a proper
-- before_each/after_each instead of leaving load-time state lying around.

package.path = package.path .. ";./?.lua"

local host_stubs = require("specs/lib/host_stubs")

describe("host_stubs", function()

  describe("save_and_clear / restore (single global)", function()

    it("returns the previous value and clears the global", function()
      rawset(_G, "_host_stubs_test_g", {marker = "original"})
      local saved = host_stubs.save_and_clear("_host_stubs_test_g")
      assert.are.same({marker = "original"}, saved)
      assert.is_nil(rawget(_G, "_host_stubs_test_g"))
      host_stubs.restore("_host_stubs_test_g", saved)
    end)

    it("restore puts the exact saved value back", function()
      local original = {marker = "restore-me"}
      rawset(_G, "_host_stubs_test_g", original)
      local saved = host_stubs.save_and_clear("_host_stubs_test_g")
      host_stubs.restore("_host_stubs_test_g", saved)
      assert.are.equal(original, rawget(_G, "_host_stubs_test_g"))
      rawset(_G, "_host_stubs_test_g", nil)
    end)

    it("round-trips a global that was absent to begin with", function()
      rawset(_G, "_host_stubs_test_absent", nil)
      local saved = host_stubs.save_and_clear("_host_stubs_test_absent")
      assert.is_nil(saved)
      rawset(_G, "_host_stubs_test_absent", {fake = true})
      host_stubs.restore("_host_stubs_test_absent", saved)
      assert.is_nil(rawget(_G, "_host_stubs_test_absent"))
    end)

  end)

  describe("snapshot / restore_all (multiple globals)", function()

    it("captures and restores several globals at once", function()
      rawset(_G, "_host_stubs_test_a", {v = 1})
      rawset(_G, "_host_stubs_test_b", nil)
      local names = {"_host_stubs_test_a", "_host_stubs_test_b"}

      local snap = host_stubs.snapshot(names)

      rawset(_G, "_host_stubs_test_a", {v = 2}) -- simulate installing a fake
      rawset(_G, "_host_stubs_test_b", {fake = true})

      host_stubs.restore_all(snap)

      assert.are.same({v = 1}, rawget(_G, "_host_stubs_test_a"))
      assert.is_nil(rawget(_G, "_host_stubs_test_b"))

      rawset(_G, "_host_stubs_test_a", nil)
    end)

    it("distinguishes a genuinely-absent global from one holding nil-like state", function()
      rawset(_G, "_host_stubs_test_c", nil)
      local snap = host_stubs.snapshot({"_host_stubs_test_c"})
      rawset(_G, "_host_stubs_test_c", {})
      host_stubs.restore_all(snap)
      assert.is_nil(rawget(_G, "_host_stubs_test_c"))
    end)

  end)

  describe("stub (install + auto-generated restorer)", function()

    it("installs fakes via the callback and returns a restorer closure", function()
      rawset(_G, "_host_stubs_test_d", {original = true})

      local restore = host_stubs.stub({"_host_stubs_test_d"}, function()
        rawset(_G, "_host_stubs_test_d", {fake = true})
      end)

      assert.are.same({fake = true}, rawget(_G, "_host_stubs_test_d"))

      restore()

      assert.are.same({original = true}, rawget(_G, "_host_stubs_test_d"))
      rawset(_G, "_host_stubs_test_d", nil)
    end)

  end)

end)
