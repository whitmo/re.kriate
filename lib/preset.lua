-- lib/preset.lua
-- Full session preset persistence (save/restore tracks, patterns,
-- meta-sequence, and re.kriate-owned params) with checksum guard.

local preset = {}

local tab = rawget(_G, "tab") -- norns utility (may be nil on seamstress)

local ADLER_MOD = 65521

local data_dir_override = nil
local fs_override = nil

local AUTOSAVE_NAME = "_autosave"
preset.AUTOSAVE_NAME = AUTOSAVE_NAME

-- Params the preset owns (re.kriate-managed). Missing params are skipped on
-- save and defaulted on load so older presets forward-migrate cleanly.
local GLOBAL_PARAMS = {
  "root_note",
  "scale_type",
  "osc_host",
  "osc_port",
  "clock_source_mode",
  "clock_output",
  "pattern_bank_name",
}

local PER_TRACK_PARAM_TEMPLATES = {
  "voice_%d",
  "midi_ch_%d",
  "sc_synthdef_%d",
  "sample_path_%d",
  "sample_root_%d",
  "sample_start_%d",
  "sample_end_%d",
  "sample_loop_%d",
  "division_%d",
  "direction_%d",
  "swing_%d",
}

local NUM_TRACKS = 4

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

function preset.sanitize_name(name)
  if not name then return nil, "name_required" end
  local sanitized = trim(name):lower():gsub("[^a-z0-9_-]+", "-")
  sanitized = sanitized:gsub("^%-+", ""):gsub("%-+$", "")
  if sanitized == "" then
    return nil, "name_invalid"
  end
  return sanitized, nil
end

-- Allow the reserved autosave name past sanitize_name's underscore-strip rule.
local function normalize_name(name)
  if name == AUTOSAVE_NAME then
    return AUTOSAVE_NAME, nil
  end
  return preset.sanitize_name(name)
end

local function is_norns()
  return _G.norns ~= nil or _G._norns ~= nil
end

local function is_seamstress()
  return _G._seamstress ~= nil
    or (_G.seamstress ~= nil and _G.seamstress.state ~= nil)
    or (_G.path ~= nil and _G.path.seamstress ~= nil)
end

local function compute_data_dir()
  if data_dir_override then return data_dir_override end
  local env_dir = os.getenv("REKRIATE_PRESET_DIR")
  if env_dir and env_dir ~= "" then return env_dir end
  if is_norns() then
    return os.getenv("HOME") .. "/dust/data/re_kriate/presets"
  end
  if is_seamstress() and _G.path ~= nil and _G.path.seamstress ~= nil then
    return _G.path.seamstress .. "/data/re_kriate/presets"
  end
  local xdg = os.getenv("XDG_DATA_HOME")
  if xdg and xdg ~= "" then
    return xdg .. "/re_kriate/presets"
  end
  return os.getenv("HOME") .. "/.local/share/re_kriate/presets"
end

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
    for _, k in ipairs(keys) do
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

local function decode_payload(path)
  if tab and tab.load then
    local ok, data = pcall(tab.load, path)
    if ok and data then return data end
  end
  local data = read_file(path)
  if not data then return nil, "read_error" end
  local chunk, err = load_table_chunk(data, "preset")
  if not chunk then return nil, "parse_error:" .. tostring(err) end
  local ok, tbl = pcall(chunk)
  if not ok then return nil, "load_error:" .. tostring(tbl) end
  return tbl
end

local function param_exists(id)
  local p = rawget(_G, "params")
  if not p or type(p) ~= "table" then return false end
  if p.lookup and p.lookup[id] then return true end
  -- Fall back to pcall(get) if lookup isn't available.
  local ok = pcall(function() return p:get(id) end)
  return ok
end

local function param_get(id)
  local p = rawget(_G, "params")
  if not p then return nil end
  local ok, val = pcall(function() return p:get(id) end)
  if ok then return val end
  return nil
end

local function param_set(id, value)
  local p = rawget(_G, "params")
  if not p then return end
  pcall(function() p:set(id, value) end)
end

local function collect_param_ids()
  local ids = {}
  for _, id in ipairs(GLOBAL_PARAMS) do
    table.insert(ids, id)
  end
  for t = 1, NUM_TRACKS do
    for _, tpl in ipairs(PER_TRACK_PARAM_TEMPLATES) do
      table.insert(ids, string.format(tpl, t))
    end
  end
  return ids
end

local function snapshot_params()
  local snapshot = {}
  for _, id in ipairs(collect_param_ids()) do
    if param_exists(id) then
      local v = param_get(id)
      if v ~= nil then
        snapshot[id] = v
      end
    end
  end
  return snapshot
end

local function apply_params(snapshot)
  if type(snapshot) ~= "table" then return end
  -- Iterate declared ids (not raw snapshot keys) so unknown/foreign keys are
  -- ignored and we honor a stable apply order.
  for _, id in ipairs(collect_param_ids()) do
    if snapshot[id] ~= nil and param_exists(id) then
      param_set(id, snapshot[id])
    end
  end
end

local function sanitized_path(name, create_dir)
  local sanitized, err = normalize_name(name)
  if not sanitized then return nil, err end
  local dir = compute_data_dir()
  if create_dir then
    local ok = fs_op("ensure_dir")(dir)
    if not ok then return nil, "mkpath_failed" end
  end
  return dir .. "/" .. sanitized .. ".krs", nil, sanitized
end

local PRESET_VERSION = 1

local function build_payload(ctx)
  local payload = {
    version = PRESET_VERSION,
    saved_at = os.time(),
    tracks = deep_copy(ctx.tracks),
    patterns = deep_copy(ctx.patterns),
    meta = deep_copy(ctx.meta),
    pattern_slot = ctx.pattern_slot,
    active_track = ctx.active_track,
    active_page = ctx.active_page,
    params = snapshot_params(),
  }
  return payload
end

function preset.save(ctx, name)
  if not ctx then return nil, "ctx_missing" end
  local path, err = sanitized_path(name, true)
  if not path then return nil, err end

  local payload = build_payload(ctx)
  local serialized = encode_payload(payload)
  payload.checksum = checksum(serialized)
  local final_serialized = encode_payload(payload)

  local call_ok, write_ok, write_err = pcall(write_file_atomic, path, final_serialized)
  if not call_ok then return nil, "write_error:" .. tostring(write_ok) end
  if not write_ok then return nil, write_err or "write_error" end

  return true, path
end

-- Restore a preset into ctx. Failures leave ctx untouched.
function preset.load(ctx, name)
  if not ctx then return nil, "ctx_missing" end
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

  if type(data.tracks) ~= "table" then
    return nil, "invalid_payload"
  end

  -- Commit atomically after validation.
  ctx.tracks = deep_copy(data.tracks)
  if type(data.patterns) == "table" then
    ctx.patterns = deep_copy(data.patterns)
  end
  if type(data.meta) == "table" then
    ctx.meta = deep_copy(data.meta)
  end
  if data.pattern_slot ~= nil then ctx.pattern_slot = data.pattern_slot end
  if data.active_track ~= nil then ctx.active_track = data.active_track end
  if data.active_page ~= nil then ctx.active_page = data.active_page end

  apply_params(data.params)

  ctx.grid_dirty = true
  return true, path
end

function preset.list()
  local dir = compute_data_dir()
  local files = fs_op("list")(dir)
  if not files then return {} end
  local names = {}
  for _, file in ipairs(files) do
    local name = file:match("^(.*)%.krs$")
    -- Hide hidden temp files and the reserved autosave from the public list.
    if name and name ~= "" and not file:match("^%.") and name ~= AUTOSAVE_NAME then
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

function preset.delete(name)
  local path, err = sanitized_path(name, false)
  if not path then return nil, err end
  if not file_exists(path) then return nil, "not_found" end
  local ok = fs_op("remove")(path)
  if not ok then
    return nil, "delete_failed"
  end
  return true
end

function preset.exists(name)
  local path, err = sanitized_path(name, false)
  if not path then return false, err end
  return file_exists(path)
end

function preset.save_autosave(ctx)
  return preset.save(ctx, AUTOSAVE_NAME)
end

function preset.load_autosave(ctx)
  return preset.load(ctx, AUTOSAVE_NAME)
end

-- Testing hooks to keep specs hermetic.
function preset._test_set_data_dir(path)
  data_dir_override = path
end

function preset._test_set_fs(fs_impl)
  fs_override = fs_impl
end

return preset
