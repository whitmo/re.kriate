-- specs/pattern_persistence_spec.lua
-- TDD for lib/pattern_persistence.lua (disk persistence + checksum)

-- Ensure local modules (mediator.lua, lib/...) are found
package.path = "./?.lua;./?/init.lua;" .. package.path

local track_mod = require("lib/track")
local pattern = require("lib/pattern")
local pp = require("lib/pattern_persistence")

local tmp_root = "specs/tmp/pattern_persistence"

local function load_table_chunk(source, chunkname)
  if _VERSION == "Lua 5.1" then
    local chunk, err = loadstring(source, chunkname)
    if not chunk then return nil, err end
    if setfenv then
      setfenv(chunk, {})
    end
    return chunk
  end
  return load(source, chunkname, "t", {})
end

local function read_payload(path)
  local f = assert(io.open(path, "r"))
  local data = f:read("*all")
  f:close()
  local chunk = assert(load_table_chunk(data, "pattern_persistence_spec"))
  return assert(chunk())
end

local function reset_tmp()
  os.execute("rm -rf " .. tmp_root)
  os.execute("mkdir -p " .. tmp_root)
  if pp._test_set_data_dir then
    pp._test_set_data_dir(tmp_root)
  end
end

local function make_ctx()
  return {
    tracks = track_mod.new_tracks(),
    patterns = pattern.new_slots(),
  }
end

local function fill_ctx(ctx)
  -- set distinctive values across tracks/params for roundtrip fidelity
  local params = {"trigger", "note", "octave", "duration", "velocity", "ratchet", "alt_note", "glide"}
  for t = 1, 4 do
    ctx.tracks[t].division = t + 1
    ctx.tracks[t].muted = (t % 2 == 0)
    ctx.tracks[t].direction = ({"forward", "reverse", "pendulum", "drunk"})[t]
    for _, pname in ipairs(params) do
      local p = ctx.tracks[t].params[pname]
      for step = 1, 16 do
        p.steps[step] = (t * 10 + step) % 8
      end
      p.loop_start = math.min(t, 16)
      p.loop_end = math.min(t + 8, 16)
      p.pos = math.min(t + 2, p.loop_end)
    end
  end
  -- mark some slots populated
  pattern.save(ctx, 1)
  pattern.save(ctx, 4)
end

describe("pattern_persistence", function()

  before_each(reset_tmp)

  describe("sanitize_name", function()
    it("lowercases and trims to safe characters", function()
      local sanitized, err = pp.sanitize_name(" My Jam!* ")
      assert.is_nil(err)
      assert.are.equal("my-jam", sanitized)
    end)

    it("rejects empty names", function()
      local sanitized, err = pp.sanitize_name("   ")
      assert.is_nil(sanitized)
      assert.is_not_nil(err)
    end)

    it("rejects invalid save names", function()
      local ctx = make_ctx()
      fill_ctx(ctx)

      local ok, err = pp.save(ctx, "!!!")
      assert.is_nil(ok)
      assert.are.equal("name_invalid", err)
    end)
  end)

  describe("save + load roundtrip", function()
    it("round-trips all pattern slots and track data", function()
      local ctx = make_ctx()
      fill_ctx(ctx)

      local ok, path_or_err = pp.save(ctx, "bank-a")
      assert.is_true(ok)
      assert.is_truthy(path_or_err)

      -- mutate ctx to defaults to prove load restores
      ctx.tracks = track_mod.new_tracks()
      ctx.patterns = pattern.new_slots()

      local ok_load, err = pp.load(ctx, "bank-a")
      assert.is_true(ok_load)
      assert.is_nil(err)

      -- slots 1 and 4 should be populated
      assert.is_true(pattern.is_populated(ctx.patterns, 1))
      assert.is_true(pattern.is_populated(ctx.patterns, 4))
      assert.is_false(pattern.is_populated(ctx.patterns, 2))

      -- check a handful of values for fidelity
      assert.are.equal(3, ctx.tracks[2].division)
      assert.are.equal(true, ctx.tracks[2].muted)
      assert.are.equal("reverse", ctx.tracks[2].direction)
      assert.are.equal((2 * 10 + 5) % 8, ctx.tracks[2].params.note.steps[5])
      assert.are.equal(1, ctx.tracks[1].params.trigger.loop_start)
      assert.are.equal(9, ctx.tracks[1].params.trigger.loop_end)
      assert.are.equal(math.min(1 + 2, ctx.tracks[1].params.trigger.loop_end), ctx.tracks[1].params.trigger.pos)
    end)
  end)

  describe("checksum guard", function()
    it("rejects tampered files and leaves ctx unchanged", function()
      local ctx = make_ctx()
      fill_ctx(ctx)

      local ok = pp.save(ctx, "bank-b")
      assert.is_true(ok)

      -- mutate ctx to known defaults
      ctx.tracks = track_mod.new_tracks()
      ctx.tracks[1].division = 42 -- sentinel to verify untouched on failure

      -- corrupt the file (flip a byte)
      local filename = tmp_root .. "/bank-b.krp"
      local f = assert(io.open(filename, "r"))
      local data = f:read("*all")
      f:close()
      data = data:gsub("return", "returx", 1) -- simple corruption
      local cf = assert(io.open(filename, "w"))
      cf:write(data)
      cf:close()

      local ok_load, err = pp.load(ctx, "bank-b")
      assert.is_nil(ok_load)
      assert.is_not_nil(err)
      assert.are.equal(42, ctx.tracks[1].division) -- unchanged
    end)
  end)

  describe("atomic overwrite", function()
    it("overwrites in place and updates the checksum", function()
      local ctx = make_ctx()
      fill_ctx(ctx)

      local ok, path = pp.save(ctx, "bank-overwrite")
      assert.is_true(ok)
      assert.are.equal(tmp_root .. "/bank-overwrite.krp", path)

      local first_payload = read_payload(path)
      assert.is_truthy(first_payload.checksum)

      ctx.tracks[1].division = 99
      pattern.save(ctx, 2)

      local ok2, same_path = pp.save(ctx, "bank-overwrite")
      assert.is_true(ok2)
      assert.are.equal(path, same_path)

      local second_payload = read_payload(path)
      assert.is_truthy(second_payload.checksum)
      assert.are_not.equal(first_payload.checksum, second_payload.checksum)
      assert.are.equal(99, second_payload.slots[1].tracks[1].division)

      local fh = io.open(path, "r")
      assert.is_not_nil(fh)
      fh:close()
    end)
  end)

  describe("path handling", function()
    it("creates data dir when missing", function()
      os.execute("rm -rf " .. tmp_root)
      local ctx = make_ctx()
      fill_ctx(ctx)

      local ok = pp.save(ctx, "fresh-dir")
      assert.is_true(ok)

      local st = io.open(tmp_root .. "/fresh-dir.krp", "r")
      assert.is_not_nil(st)
      st:close()
    end)
  end)

  describe("list and delete", function()
    it("lists saved banks sorted and ignores temp files", function()
      local ctx = make_ctx()
      fill_ctx(ctx)
      assert.is_true(pp.save(ctx, "beta"))
      assert.is_true(pp.save(ctx, "alpha"))
      assert.is_true(pp.save(ctx, "gamma"))

      local temp = assert(io.open(tmp_root .. "/.alpha.krp.tmp", "w"))
      temp:write("temp")
      temp:close()
      local noise = assert(io.open(tmp_root .. "/notes.txt", "w"))
      noise:write("noise")
      noise:close()

      local names = pp.list()
      assert.are.same({"alpha", "beta", "gamma"}, names)

      assert.is_true(pp.delete("beta"))
      local names2 = pp.list()
      assert.are.same({"alpha", "gamma"}, names2)
    end)
  end)
end)
