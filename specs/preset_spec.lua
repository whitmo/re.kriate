-- specs/preset_spec.lua
-- Tests for lib/preset.lua (full session preset persistence)

package.path = "./?.lua;./?/init.lua;" .. package.path

-- Minimal params mock so the module under test can snapshot/apply values.
local param_store = {}
local param_lookup = {}
rawset(_G, "params", {
  lookup = param_lookup,
  add = function(self, id, default)
    param_store[id] = default
    param_lookup[id] = { id = id }
  end,
  get = function(self, id) return param_store[id] end,
  set = function(self, id, val) param_store[id] = val end,
})

-- Minimal clock mock (track.lua doesn't need it but some transitive deps do).
rawset(_G, "clock", {
  run = function() end,
  sync = function() end,
  cancel = function() end,
  get_beats = function() return 0 end,
})

local track_mod = require("lib/track")
local pattern = require("lib/pattern")
local meta_pattern = require("lib/meta_pattern")
local preset = require("lib/preset")

local tmp_root = "specs/tmp/preset"

local function reset_tmp()
  os.execute("rm -rf " .. tmp_root)
  os.execute("mkdir -p " .. tmp_root)
  preset._test_set_data_dir(tmp_root)
  preset._test_set_fs(nil)
  -- reset params
  for k in pairs(param_store) do param_store[k] = nil end
  for k in pairs(param_lookup) do param_lookup[k] = nil end
end

local function add_param(id, default)
  param_store[id] = default
  param_lookup[id] = { id = id }
end

local function add_all_preset_params()
  -- globals
  add_param("root_note", 60)
  add_param("scale_type", 1)
  add_param("osc_host", 1)
  add_param("osc_port", 57120)
  add_param("clock_source_mode", 1)
  add_param("clock_output", 1)
  add_param("pattern_bank_name", "default")
  -- per-track
  for t = 1, 4 do
    add_param("voice_" .. t, 1)
    add_param("midi_ch_" .. t, t)
    add_param("sc_synthdef_" .. t, 1)
    add_param("sample_path_" .. t, "")
    add_param("sample_root_" .. t, 60)
    add_param("sample_start_" .. t, 0)
    add_param("sample_end_" .. t, 1)
    add_param("sample_loop_" .. t, 1)
    add_param("division_" .. t, 1)
    add_param("direction_" .. t, 1)
    add_param("swing_" .. t, 0)
  end
end

local function make_ctx()
  return {
    tracks = track_mod.new_tracks(),
    patterns = pattern.new_slots(),
    meta = meta_pattern.new(),
    pattern_slot = 1,
    active_track = 1,
    active_page = "trigger",
  }
end

local function fill_ctx(ctx)
  for t = 1, 4 do
    ctx.tracks[t].division = t + 1
    ctx.tracks[t].muted = (t % 2 == 0)
    ctx.tracks[t].direction = ({"forward", "reverse", "pendulum", "drunk"})[t]
    for _, pname in ipairs(track_mod.PARAM_NAMES) do
      local p = ctx.tracks[t].params[pname]
      for step = 1, 16 do
        p.steps[step] = (t * 10 + step) % 8
      end
      p.loop_start = math.min(t, 16)
      p.loop_end = math.min(t + 8, 16)
      p.pos = math.min(t + 2, p.loop_end)
    end
  end
  pattern.save(ctx, 1)
  pattern.save(ctx, 4)
  meta_pattern.set_step(ctx.meta, 1, 1, 2)
  meta_pattern.set_step(ctx.meta, 2, 4, 3)
  ctx.pattern_slot = 4
  ctx.active_track = 3
  ctx.active_page = "note"
end

describe("preset", function()

  before_each(reset_tmp)

  describe("sanitize_name", function()
    it("lowercases and trims to safe characters", function()
      local sanitized, err = preset.sanitize_name(" My Jam!* ")
      assert.is_nil(err)
      assert.are.equal("my-jam", sanitized)
    end)

    it("rejects empty names", function()
      local sanitized, err = preset.sanitize_name("   ")
      assert.is_nil(sanitized)
      assert.is_not_nil(err)
    end)

    it("rejects invalid save names", function()
      local ctx = make_ctx()
      fill_ctx(ctx)
      local ok, err = preset.save(ctx, "!!!")
      assert.is_nil(ok)
      assert.are.equal("name_invalid", err)
    end)
  end)

  describe("save + load roundtrip", function()
    it("round-trips track data, patterns, meta, and position state", function()
      add_all_preset_params()
      local ctx = make_ctx()
      fill_ctx(ctx)

      param_store.root_note = 63
      param_store.scale_type = 5
      param_store.division_2 = 4
      param_store.swing_3 = 42

      local ok, path = preset.save(ctx, "my-jam")
      assert.is_true(ok)
      assert.is_truthy(path)

      -- Reset ctx + params to defaults to prove load restores everything.
      local fresh = make_ctx()
      param_store.root_note = 60
      param_store.scale_type = 1
      param_store.division_2 = 1
      param_store.swing_3 = 0

      local ok_load = preset.load(fresh, "my-jam")
      assert.is_true(ok_load)

      assert.are.equal(3, fresh.tracks[2].division)
      assert.are.equal(true, fresh.tracks[2].muted)
      assert.are.equal("reverse", fresh.tracks[2].direction)
      assert.are.equal((2 * 10 + 5) % 8, fresh.tracks[2].params.note.steps[5])
      assert.are.equal(1, fresh.tracks[1].params.trigger.loop_start)
      assert.are.equal(9, fresh.tracks[1].params.trigger.loop_end)

      assert.is_true(pattern.is_populated(fresh.patterns, 1))
      assert.is_true(pattern.is_populated(fresh.patterns, 4))
      assert.is_false(pattern.is_populated(fresh.patterns, 2))

      assert.are.equal(1, fresh.meta.steps[1].slot)
      assert.are.equal(2, fresh.meta.steps[1].loops)
      assert.are.equal(4, fresh.meta.steps[2].slot)
      assert.are.equal(3, fresh.meta.steps[2].loops)

      assert.are.equal(4, fresh.pattern_slot)
      assert.are.equal(3, fresh.active_track)
      assert.are.equal("note", fresh.active_page)

      assert.are.equal(63, param_store.root_note)
      assert.are.equal(5, param_store.scale_type)
      assert.are.equal(4, param_store.division_2)
      assert.are.equal(42, param_store.swing_3)
    end)

    it("skips params that do not exist and ignores unknown keys", function()
      -- Only a couple of params exist; missing ones must not crash apply.
      add_param("root_note", 60)
      add_param("scale_type", 1)

      local ctx = make_ctx()
      fill_ctx(ctx)
      param_store.root_note = 72

      local ok = preset.save(ctx, "sparse")
      assert.is_true(ok)

      param_store.root_note = 60
      local fresh = make_ctx()
      local ok_load = preset.load(fresh, "sparse")
      assert.is_true(ok_load)
      assert.are.equal(72, param_store.root_note)
    end)
  end)

  describe("forward-compat load", function()
    it("loads an old preset without meta/patterns without crashing", function()
      add_all_preset_params()
      local ctx = make_ctx()
      fill_ctx(ctx)
      assert.is_true(preset.save(ctx, "skinny"))

      -- Hand-craft a stripped preset file simulating an older schema
      -- (tracks + version only; no patterns, meta, params, saved fields).
      local f = assert(io.open(tmp_root .. "/skinny.krs", "r"))
      f:close()
      -- rewrite with minimal payload
      local tracks = track_mod.new_tracks()
      local function serialize_simple(t, ind)
        ind = ind or ""
        if type(t) == "number" or type(t) == "boolean" then return tostring(t) end
        if type(t) == "string" then return string.format("%q", t) end
        local parts = {"{"}
        local keys = {}
        for k in pairs(t) do table.insert(keys, k) end
        table.sort(keys, function(a, b)
          if type(a) == "number" and type(b) == "number" then return a < b end
          return tostring(a) < tostring(b)
        end)
        local next_ind = ind .. "  "
        for _, k in ipairs(keys) do
          local v = t[k]
          local kr = type(k) == "string" and string.format("[%q]", k) or "[" .. tostring(k) .. "]"
          table.insert(parts, "\n" .. next_ind .. kr .. " = " .. serialize_simple(v, next_ind) .. ",")
        end
        table.insert(parts, "\n" .. ind .. "}")
        return table.concat(parts)
      end

      local payload = { version = 1, tracks = tracks }
      local body = "return " .. serialize_simple(payload, "")
      -- Inject a matching checksum
      local cs
      do
        local a, b = 1, 0
        local serialized = "return " .. serialize_simple(payload, "")
        for i = 1, #serialized do
          a = (a + string.byte(serialized, i)) % 65521
          b = (b + a) % 65521
        end
        cs = tostring(b * 65536 + a)
      end
      payload.checksum = cs
      body = "return " .. serialize_simple(payload, "")
      local wf = assert(io.open(tmp_root .. "/skinny.krs", "w"))
      wf:write(body)
      wf:close()

      local fresh = make_ctx()
      local ok = preset.load(fresh, "skinny")
      assert.is_true(ok)
    end)
  end)

  describe("checksum guard", function()
    it("rejects tampered files and leaves ctx untouched", function()
      add_all_preset_params()
      local ctx = make_ctx()
      fill_ctx(ctx)
      assert.is_true(preset.save(ctx, "guarded"))

      local path = tmp_root .. "/guarded.krs"
      local f = assert(io.open(path, "r"))
      local data = f:read("*all")
      f:close()
      data = data:gsub("return", "returx", 1)
      local wf = assert(io.open(path, "w"))
      wf:write(data)
      wf:close()

      local fresh = make_ctx()
      fresh.tracks[1].division = 42 -- sentinel
      local ok, err = preset.load(fresh, "guarded")
      assert.is_nil(ok)
      assert.is_not_nil(err)
      assert.are.equal(42, fresh.tracks[1].division)
    end)

    it("detects payload tampering with intact file structure", function()
      add_all_preset_params()
      local ctx = make_ctx()
      fill_ctx(ctx)
      assert.is_true(preset.save(ctx, "tampered"))

      local path = tmp_root .. "/tampered.krs"
      local f = assert(io.open(path, "r"))
      local data = f:read("*all")
      f:close()
      -- Flip one step value somewhere in tracks.
      data = data:gsub('%["division"%] = 2', '["division"] = 7', 1)
      local wf = assert(io.open(path, "w"))
      wf:write(data)
      wf:close()

      local fresh = make_ctx()
      local ok, err = preset.load(fresh, "tampered")
      assert.is_nil(ok)
      assert.are.equal("checksum_mismatch", err)
    end)
  end)

  describe("atomic overwrite", function()
    it("overwrites in place and updates the checksum", function()
      add_all_preset_params()
      local ctx = make_ctx()
      fill_ctx(ctx)
      local ok, path = preset.save(ctx, "overwrite")
      assert.is_true(ok)

      local function read_pl(p)
        local fh = assert(io.open(p, "r"))
        local body = fh:read("*all")
        fh:close()
        local chunk = assert(load(body, "chk", "t", {}))
        return chunk()
      end

      local first = read_pl(path)
      assert.is_truthy(first.checksum)

      ctx.tracks[1].division = 99
      local ok2 = preset.save(ctx, "overwrite")
      assert.is_true(ok2)

      local second = read_pl(path)
      assert.are_not.equal(first.checksum, second.checksum)
      assert.are.equal(99, second.tracks[1].division)
    end)
  end)

  describe("path handling", function()
    it("creates data dir when missing", function()
      os.execute("rm -rf " .. tmp_root)
      add_all_preset_params()
      local ctx = make_ctx()
      fill_ctx(ctx)
      assert.is_true(preset.save(ctx, "fresh"))
      local fh = io.open(tmp_root .. "/fresh.krs", "r")
      assert.is_not_nil(fh)
      fh:close()
    end)
  end)

  describe("failure hardening", function()
    it("returns mkpath_failed when directory creation fails", function()
      add_all_preset_params()
      local ctx = make_ctx()
      fill_ctx(ctx)
      preset._test_set_fs({
        ensure_dir = function() return nil, "disk_full" end,
      })
      local ok, err = preset.save(ctx, "nope")
      assert.is_nil(ok)
      assert.are.equal("mkpath_failed", err)
    end)

    it("cleans up temp file and preserves existing preset when rename fails", function()
      add_all_preset_params()
      local ctx = make_ctx()
      fill_ctx(ctx)
      local ok, path = preset.save(ctx, "rename-guard")
      assert.is_true(ok)

      local function read_body(p)
        local fh = assert(io.open(p, "r"))
        local body = fh:read("*all")
        fh:close()
        return body
      end
      local original = read_body(path)

      ctx.tracks[1].division = 99

      preset._test_set_fs({
        ensure_dir = function() return true end,
        rename = function() return nil, "busy" end,
      })
      local ok2, err = preset.save(ctx, "rename-guard")
      assert.is_nil(ok2)
      assert.are.equal("rename_failed", err)
      assert.is_nil(io.open(tmp_root .. "/.rename-guard.krs.tmp", "r"))

      preset._test_set_fs(nil)
      assert.are.equal(original, read_body(path))
    end)
  end)

  describe("list and delete", function()
    it("lists saved presets sorted and hides autosave + temp files", function()
      add_all_preset_params()
      local ctx = make_ctx()
      fill_ctx(ctx)
      assert.is_true(preset.save(ctx, "beta"))
      assert.is_true(preset.save(ctx, "alpha"))
      assert.is_true(preset.save(ctx, "gamma"))
      assert.is_true(preset.save_autosave(ctx))

      local temp = assert(io.open(tmp_root .. "/.alpha.krs.tmp", "w"))
      temp:write("x"); temp:close()
      local noise = assert(io.open(tmp_root .. "/notes.txt", "w"))
      noise:write("x"); noise:close()

      local names = preset.list()
      assert.are.same({"alpha", "beta", "gamma"}, names)

      assert.is_true(preset.delete("beta"))
      local names2 = preset.list()
      assert.are.same({"alpha", "gamma"}, names2)
    end)

    it("returns not_found when deleting a missing preset", function()
      local ok, err = preset.delete("ghost")
      assert.is_nil(ok)
      assert.are.equal("not_found", err)
    end)
  end)

  describe("autosave", function()
    it("save_autosave writes the reserved slot", function()
      add_all_preset_params()
      local ctx = make_ctx()
      fill_ctx(ctx)
      assert.is_true(preset.save_autosave(ctx))
      assert.is_true(preset.exists(preset.AUTOSAVE_NAME))
    end)

    it("load_autosave restores from the reserved slot", function()
      add_all_preset_params()
      local ctx = make_ctx()
      fill_ctx(ctx)
      ctx.tracks[1].division = 6
      assert.is_true(preset.save_autosave(ctx))

      local fresh = make_ctx()
      local ok = preset.load_autosave(fresh)
      assert.is_true(ok)
      assert.are.equal(6, fresh.tracks[1].division)
    end)

    it("load_autosave returns not_found when no autosave exists", function()
      local fresh = make_ctx()
      local ok, err = preset.load_autosave(fresh)
      assert.is_nil(ok)
      assert.are.equal("not_found", err)
    end)
  end)

  describe("invalid payload", function()
    it("rejects presets missing tracks table", function()
      add_all_preset_params()
      local path = tmp_root .. "/broken.krs"
      os.execute("mkdir -p " .. tmp_root)
      local body = 'return {["version"] = 1,}'
      -- compute matching checksum for {version = 1}
      local function cs(s)
        local a, b = 1, 0
        for i = 1, #s do
          a = (a + string.byte(s, i)) % 65521
          b = (b + a) % 65521
        end
        return tostring(b * 65536 + a)
      end
      local inner = 'return {\n  ["version"] = 1,\n}'
      local computed = cs(inner)
      body = 'return {\n  ["checksum"] = "' .. computed .. '",\n  ["version"] = 1,\n}'
      local f = assert(io.open(path, "w"))
      f:write(body); f:close()

      local fresh = make_ctx()
      local ok, err = preset.load(fresh, "broken")
      assert.is_nil(ok)
      assert.are.equal("invalid_payload", err)
    end)
  end)
end)
