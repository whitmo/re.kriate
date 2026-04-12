-- lib/pattern_persistence.lua
-- Disk persistence for pattern banks (16 slots) with checksum guard

local pattern_persistence = {}

local tab = rawget(_G, "tab") -- norns utility (may be nil on seamstress)

local ADLER_MOD = 65521

local data_dir_override = nil
local fs_override = nil

local function shell_quote(path)
  return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

local default_fs = {}

local function fs_op(name)
  if fs_override and fs_override[name] then
    return fs_override[name]
  end
  return default_fs[name]
end

local function deep_copy(orig)
  if type(orig) ~= "table" then return orig end
  local copy = {}
  for k, v in pairs(orig) do
    copy[k] = deep_copy(v)
  end
  return copy
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function pattern_persistence.sanitize_name(name)
  if not name then return nil, "name_required" end
  local sanitized = trim(name):lower():gsub("[^a-z0-9_-]+", "-")
  sanitized = sanitized:gsub("^%-+", ""):gsub("%-+$", "")
  if sanitized == "" then
    return nil, "name_invalid"
  end
  return sanitized, nil
end

local function is_norns()
  return _G.norns ~= nil or _G._norns ~= nil
end

local function is_seamstress()
  return _G._seamstress ~= nil or (_G.seamstress ~= nil and _G.seamstress.state ~= nil) or (_G.path ~= nil and _G.path.seamstress ~= nil)
end

local function compute_data_dir()
  if data_dir_override then return data_dir_override end
  local env_dir = os.getenv("REKRIATE_PATTERN_DIR")
  if env_dir and env_dir ~= "" then return env_dir end
  if is_norns() then
    return os.getenv("HOME") .. "/dust/data/re_kriate/patterns"
  end
  if is_seamstress() and _G.path ~= nil and _G.path.seamstress ~= nil then
    return _G.path.seamstress .. "/data/re_kriate/patterns"
  end
  local xdg = os.getenv("XDG_DATA_HOME")
  if xdg and xdg ~= "" then
    return xdg .. "/re_kriate/patterns"
  end
  return os.getenv("HOME") .. "/.local/share/re_kriate/patterns"
end

-- Adler-32 is fast enough for CI and sufficient for tamper detection here.
local function checksum(str)
  local a = 1
  local b = 0
  for i = 1, #str do
    a = (a + string.byte(str, i)) % ADLER_MOD
    b = (b + a) % ADLER_MOD
  end
  return tostring(b * 65536 + a)
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do table.insert(keys, k) end
  table.sort(keys, function(a, b)
    if type(a) == "number" and type(b) == "number" then
      return a < b
    end
    return tostring(a) < tostring(b)
  end)
  return keys
end

-- deterministic table serializer to Lua source
local function serialize(val, indent)
  indent = indent or ""
  local t = type(val)
  if t == "number" or t == "boolean" then
    return tostring(val)
  elseif t == "string" then
    return string.format("%q", val)
  elseif t == "table" then
    local next_indent = indent .. "  "
    local parts = {"{"}
    local keys = sorted_keys(val)
    for idx, k in ipairs(keys) do
      local v = val[k]
      local key_repr
      if type(k) == "string" then
        key_repr = string.format("[%q]", k)
      else
        key_repr = "[" .. tostring(k) .. "]"
      end
      table.insert(parts, "\n" .. next_indent .. key_repr .. " = " .. serialize(v, next_indent) .. ",")
    end
    table.insert(parts, "\n" .. indent .. "}")
    return table.concat(parts)
  else
    error("unsupported type in serializer: " .. t)
  end
end

default_fs.ensure_dir = function(path)
  local ok = os.execute("mkdir -p " .. shell_quote(path))
  if ok == true or ok == 0 then return true end
  return nil, "mkdir_failed"
end

default_fs.rename = function(src, dst)
  local ok, err = os.rename(src, dst)
  if ok then return true end
  return nil, err or "rename_failed"
end

default_fs.remove = function(path)
  local ok, err = os.remove(path)
  if ok then return true end
  return nil, err or "remove_failed"
end

default_fs.list = function(path)
  local p = io.popen("ls -1A " .. shell_quote(path) .. " 2>/dev/null")
  if not p then return nil, "list_open_failed" end
  local files = {}
  for file in p:lines() do
    table.insert(files, file)
  end
  local ok = p:close()
  if ok == nil or ok == false then
    return nil, "list_failed"
  end
  return files
end

local function write_file_atomic(path, contents)
  local dir, name = path:match("^(.*)/([^/]+)$")
  if dir and dir ~= "" then
    local ok = fs_op("ensure_dir")(dir)
    if not ok then
      return nil, "mkpath_failed"
    end
  end
  local tmp = dir .. "/." .. name .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then return nil, "tmp_open_failed" end

  local ok_write = f:write(contents)
  if not ok_write then
    f:close()
    fs_op("remove")(tmp)
    return nil, "tmp_write_failed"
  end

  local ok_flush = f:flush()
  if not ok_flush then
    f:close()
    fs_op("remove")(tmp)
    return nil, "tmp_flush_failed"
  end
  f:close()

  local renamed = fs_op("rename")(tmp, path)
  if not renamed then
    fs_op("remove")(tmp)
    return nil, "rename_failed"
  end
  return true
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local data = f:read("*all")
  f:close()
  return data
end

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

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local function encode_payload(payload)
  return "return " .. serialize(payload, "")
end

local function ensure_probability(track)
  if not track or not track.params then return end
  if track.params.probability then return end
  local steps = {}
  for i = 1, 16 do steps[i] = 100 end
  track.params.probability = {
    steps = steps,
    loop_start = 1,
    loop_end = 6,
    pos = 1,
  }
end

local MAX_RATCHET = 5

local function ensure_ratchet_bits(track)
  if not track or not track.params then return end
  local ratchet = track.params.ratchet
  if not ratchet then return end
  -- Clamp values to new max range
  for i = 1, 16 do
    if ratchet.steps[i] then
      ratchet.steps[i] = math.max(1, math.min(MAX_RATCHET, ratchet.steps[i]))
    end
  end
  -- Add bits array if missing
  if not ratchet.bits then
    ratchet.bits = {}
    for i = 1, 16 do
      local count = ratchet.steps[i] or 1
      ratchet.bits[i] = (1 << count) - 1  -- all subdivisions active
    end
  end
end

-- Snapshot meta-sequencer state for persistence.
-- Only durable fields are saved; runtime playback state (active, pos,
-- loop_counter, cued_slot) is intentionally omitted so a loaded bank never
-- resumes mid-playback.
local function snapshot_meta(meta)
  if type(meta) ~= "table" then return nil end
  return {
    steps = deep_copy(meta.steps),
    length = meta.length,
    selected_step = meta.selected_step,
  }
end

-- Restore meta-sequencer state from a payload snapshot. Runtime fields are
-- reset to safe defaults; existing ctx.meta is replaced in-place so external
-- references remain valid.
local function apply_meta(ctx, saved)
  if not ctx or type(saved) ~= "table" then return end
  local target = ctx.meta
  if type(target) ~= "table" then
    target = {}
    ctx.meta = target
  end
  target.steps = deep_copy(saved.steps)
  target.length = saved.length or 0
  target.selected_step = saved.selected_step or 1
  target.pos = 1
  target.loop_counter = 0
  target.active = false
  target.cued_slot = nil
end

local function ensure_slots_migrated(slots)
  if not slots then return end
  for _, slot in pairs(slots) do
    if slot.tracks then
      for _, track in pairs(slot.tracks) do
        ensure_probability(track)
        ensure_ratchet_bits(track)
      end
    end
  end
end

local function decode_payload(path)
  if tab and tab.load then
    local ok, data = pcall(tab.load, path)
    if ok and data then return data end
  end
  local data = read_file(path)
  if not data then return nil, "read_error" end
  local chunk, err = load_table_chunk(data, "pattern_persistence")
  if not chunk then return nil, "parse_error:" .. tostring(err) end
  local ok, tbl = pcall(chunk)
  if not ok then return nil, "load_error:" .. tostring(tbl) end
  return tbl
end

local function sanitized_path(name, create_dir)
  local sanitized, err = pattern_persistence.sanitize_name(name)
  if not sanitized then return nil, err end
  local dir = compute_data_dir()
  if create_dir then
    local ok = fs_op("ensure_dir")(dir)
    if not ok then return nil, "mkpath_failed" end
  end
  return dir .. "/" .. sanitized .. ".krp", nil, sanitized
end

function pattern_persistence.save(ctx, name)
  local path, err, sanitized = sanitized_path(name, true)
  if not path then return nil, err end
  if not ctx or not ctx.patterns then
    return nil, "ctx_missing"
  end

  -- Always snapshot current tracks into slot 1 so save captures live state
  if ctx.tracks then
    ctx.patterns[1] = ctx.patterns[1] or {}
    ctx.patterns[1].tracks = deep_copy(ctx.tracks)
    ctx.patterns[1].populated = true
  end

  local payload = {
    version = 1,
    saved_slot = 1,
    slots = deep_copy(ctx.patterns),
  }

  local meta_snapshot = snapshot_meta(ctx.meta)
  if meta_snapshot then
    payload.meta = meta_snapshot
  end

  -- pick first populated slot as default loaded slot
  for i = 1, #payload.slots do
    if payload.slots[i].populated then
      payload.saved_slot = i
      break
    end
  end

  local serialized = encode_payload(payload)
  payload.checksum = checksum(serialized)
  local final_serialized = encode_payload(payload)

  local call_ok, write_ok, write_err = pcall(write_file_atomic, path, final_serialized)
  if not call_ok then return nil, "write_error:" .. tostring(write_ok) end
  if not write_ok then return nil, write_err or "write_error" end

  return true, path, sanitized
end

function pattern_persistence.load(ctx, name)
  local path, err = sanitized_path(name, false)
  if not path then return nil, err end
  if not file_exists(path) then return nil, "not_found" end

  local data, derr = decode_payload(path)
  if not data then return nil, derr end

  local stored_checksum = data.checksum
  data.checksum = nil
  local serialized = encode_payload(data)
  local computed = checksum(serialized)
  if stored_checksum ~= computed then
    return nil, "checksum_mismatch"
  end

  if not data.slots then return nil, "invalid_payload" end
  ensure_slots_migrated(data.slots)

  local slots = data.slots
  ctx.patterns = deep_copy(slots)

  -- restore tracks from saved_slot if populated
  local slot_num = data.saved_slot or 1
  if slots[slot_num] and slots[slot_num].populated and slots[slot_num].tracks then
    ctx.tracks = deep_copy(slots[slot_num].tracks)
  end

  -- restore meta-sequencer state when present. Banks saved before this field
  -- existed simply leave ctx.meta untouched so in-memory chains survive load.
  if type(data.meta) == "table" then
    apply_meta(ctx, data.meta)
  end

  return true
end

function pattern_persistence.list()
  local dir = compute_data_dir()
  local files = fs_op("list")(dir)
  if not files then return {} end
  local names = {}
  for _, file in ipairs(files) do
    local name = file:match("^(.*)%.krp$")
    if name and name ~= "" then
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

function pattern_persistence.delete(name)
  local path, err = sanitized_path(name, false)
  if not path then return nil, err end
  if not file_exists(path) then return nil, "not_found" end
  local ok = fs_op("remove")(path)
  if not ok then
    return nil, "delete_failed"
  end
  return true
end

-- Testing hook to keep specs hermetic
function pattern_persistence._test_set_data_dir(path)
  data_dir_override = path
end

function pattern_persistence._test_set_fs(fs_impl)
  fs_override = fs_impl
end

return pattern_persistence
