-- lib/pattern_persistence.lua
-- Disk persistence for pattern banks (16 slots) with checksum guard

local pattern_persistence = {}

local tab = rawget(_G, "tab") -- norns utility (may be nil on seamstress)

local ADLER_MOD = 65521

local data_dir_override = nil

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

local function ensure_dir(path)
  local ok = os.execute('mkdir -p "' .. path .. '"')
  -- os.execute returns true/nil or status code
  if ok == true or ok == 0 then return true end
  return false
end

local function write_file_atomic(path, contents)
  local dir, name = path:match("^(.*)/([^/]+)$")
  if dir and dir ~= "" then
    if not ensure_dir(dir) then
      return nil, "mkpath_failed"
    end
  end
  local tmp = dir .. "/." .. name .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then return nil, "tmp_open_failed" end
  f:write(contents)
  f:flush()
  f:close()
  local mv_ok = os.execute('mv "' .. tmp .. '" "' .. path .. '"')
  if mv_ok ~= true and mv_ok ~= 0 then
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

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local function encode_payload(payload)
  return "return " .. serialize(payload, "")
end

local function decode_payload(path)
  if tab and tab.load then
    local ok, data = pcall(tab.load, path)
    if ok and data then return data end
  end
  local data = read_file(path)
  if not data then return nil, "read_error" end
  local chunk, err = load(data, "pattern_persistence", "t", {})
  if not chunk then return nil, "parse_error:" .. tostring(err) end
  local ok, tbl = pcall(chunk)
  if not ok then return nil, "load_error:" .. tostring(tbl) end
  return tbl
end

local function sanitized_path(name)
  local sanitized, err = pattern_persistence.sanitize_name(name)
  if not sanitized then return nil, err end
  local dir = compute_data_dir()
  if not ensure_dir(dir) then return nil, "mkpath_failed" end
  return dir .. "/" .. sanitized .. ".krp", nil, sanitized
end

function pattern_persistence.save(ctx, name)
  local path, err, sanitized = sanitized_path(name)
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

  local ok, write_err = pcall(write_file_atomic, path, final_serialized)
  if not ok then return nil, "write_error:" .. tostring(write_err) end
  if write_err == false then return nil, "write_error" end

  return true, path, sanitized
end

function pattern_persistence.load(ctx, name)
  local path, err = sanitized_path(name)
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

  local slots = data.slots
  ctx.patterns = deep_copy(slots)

  -- restore tracks from saved_slot if populated
  local slot_num = data.saved_slot or 1
  if slots[slot_num] and slots[slot_num].populated and slots[slot_num].tracks then
    ctx.tracks = deep_copy(slots[slot_num].tracks)
  end

  return true
end

function pattern_persistence.list()
  local dir = compute_data_dir()
  ensure_dir(dir)
  local cmd = 'ls "' .. dir .. '"'
  local p = io.popen(cmd)
  if not p then return {} end
  local names = {}
  for file in p:lines() do
    local name = file:match("^(.*)%.krp$")
    if name and name ~= "" then
      table.insert(names, name)
    end
  end
  p:close()
  table.sort(names)
  return names
end

function pattern_persistence.delete(name)
  local path, err = sanitized_path(name)
  if not path then return nil, err end
  if not file_exists(path) then return nil, "not_found" end
  os.remove(path)
  return true
end

-- Testing hook to keep specs hermetic
function pattern_persistence._test_set_data_dir(path)
  data_dir_override = path
end

return pattern_persistence
