-- ivr_flow.lua — Motor de IVR con menú DTMF (FEAT-01)
-- Lee flujos JSON por país desde /mnt/freeswitch/flows/<pais>.json y ejecuta:
--   saludo -> menú (playAndGetDigits) -> acción por dígito -> repetir/colgar.
-- Persiste la elección en /mnt/freeswitch/logs/ivr_cdr.jsonl (CDR de la opción)
-- y registra "IVR_ACTION" (check de los tests E2E).
-- Uso en dialplan:  answer; set ivr_flow=<pais>; lua ivr_flow.lua ${ivr_flow}; hangup

----------------------------------- JSON (subconjunto) -----------------------------------
local ijson = {}

function ijson.skipws(s, i)
  while i <= #s and (s:sub(i, i):find("%s")) do i = i + 1 end
  return i
end

function ijson.parsestring(s, i)
  -- s[i] == '"' ; returns (value, next_index)
  assert(s:sub(i, i) == '"', "expected string")
  i = i + 1
  local out = {}
  while i <= #s do
    local c = s:sub(i, i)
    if c == '"' then return table.concat(out), i + 1 end
    if c == "\\" then
      local n = s:sub(i + 1, i + 1)
      if n == "n" then table.insert(out, "\n") elseif n == "t" then table.insert(out, "\t")
      elseif n == "\"" then table.insert(out, "\"") else table.insert(out, n) end
      i = i + 2
    else
      table.insert(out, c); i = i + 1
    end
  end
  error("unterminated string")
end

function ijson.parsevalue(s, i)
  i = ijson.skipws(s, i)
  if i > #s then error("unexpected end") end
  local c = s:sub(i, i)
  if c == "{" then return ijson.parseobject(s, i) end
  if c == "[" then return ijson.parsearray(s, i) end
  if c == "\"" then return ijson.parsestring(s, i) end
  if s:sub(i, i + 3) == "true" then return true, i + 4 end
  if s:sub(i, i + 4) == "false" then return false, i + 5 end
  if s:sub(i, i + 3) == "null" then return nil, i + 4 end
  -- número
  local j = i
  while j <= #s and s:sub(j, j):find("[%-%d%.eE%+]") do j = j + 1 end
  local num = tonumber(s:sub(i, j - 1))
  if num == nil then error("bad number at " .. i) end
  return num, j
end

function ijson.parsearray(s, i)
  assert(s:sub(i, i) == "[")
  i = i + 1
  local arr = {}
  i = ijson.skipws(s, i)
  if s:sub(i, i) == "]" then return arr, i + 1 end
  while true do
    local v, ni = ijson.parsevalue(s, i)
    table.insert(arr, v)
    i = ijson.skipws(s, ni)
    local c = s:sub(i, i)
    if c == "," then i = i + 1
    elseif c == "]" then return arr, i + 1
    else error("expected , or ]") end
  end
end

function ijson.parseobject(s, i)
  assert(s:sub(i, i) == "{")
  i = i + 1
  local obj = {}
  i = ijson.skipws(s, i)
  if s:sub(i, i) == "}" then return obj, i + 1 end
  while true do
    i = ijson.skipws(s, i)
    local key, ni = ijson.parsestring(s, i)
    i = ijson.skipws(s, ni)
    assert(s:sub(i, i) == ":", "expected :")
    local v, nv = ijson.parsevalue(s, i + 1)
    obj[key] = v
    i = ijson.skipws(s, nv)
    local c = s:sub(i, i)
    if c == "," then i = i + 1
    elseif c == "}" then return obj, i + 1
    else error("expected , or }") end
  end
end

function ijson.decode(str)
  local v, i = ijson.parsevalue(str, 1)
  i = ijson.skipws(str, i)
  if i <= #str then error("trailing data") end
  return v
end
----------------------------------- fin JSON -----------------------------------

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local c = f:read("*a")
  f:close()
  return c
end

local function append_line(path, line)
  local f = io.open(path, "a")
  if f then f:write(line, "\n"); f:close() end
end

-- POST JSON a la API VAS (FEAT-01b: cambio de contraseña/PIN). El wget GNU del
-- contenedor FS segfaulta; se usa busybox + timeout.
local function http_post(url, body, timeout)
  local f = io.popen("/bin/busybox timeout " .. tostring(timeout or 5) ..
                     " /bin/busybox wget -q --post-data='" .. body .. "' --header=Content-Type:application/json -O - " ..
                     url .. " 2>/dev/null")
  if not f then return "" end
  local out = f:read("*a")
  f:close()
  return out or ""
end

-- Captura <min>-<max> dígitos DTMF reutilizando el motor de menú (session:execute).
local function collect_digits(cfg, termch, min, max, tries, prompt, varname)
  local cmd = tostring(min) .. " " .. tostring(max) .. " " .. tostring(tries) .. " 4000 " ..
              termch .. " " .. prompt .. " " .. cfg.invalid .. " " .. varname
  session:execute("play_and_get_digits", cmd)
  return session:getVariable(varname) or ""
end

-- Timestamp %Y-%m-%d %H:%M:%S
local function now()
  local t = os.date("%Y-%m-%d %H:%M:%S")
  return t
end

local country = argv[1] or "cl"
local flow_path = "/mnt/freeswitch/flows/" .. country .. ".json"
local log_dir = "/mnt/freeswitch/logs"
os.execute("mkdir -p " .. log_dir)

local flow = nil
local raw = read_file(flow_path)
if raw then
  local ok, res = pcall(ijson.decode, raw)
  if ok then flow = res end
end

session:answer()

if not flow then
  freeswitch.consoleLog("notice", "IVR_ACTION flow=" .. country .. " error=flow_not_found path=" .. flow_path .. "\n")
  session:streamFile("/mnt/freeswitch/audio/invalido.wav")
  session:hangup()
  return
end

freeswitch.consoleLog("notice", "IVR_START flow=" .. flow.name .. " country=" .. country .. "\n")
if flow.greeting then session:streamFile(flow.greeting) end

local caller = session:getVariable("caller_id_number") or "-"
local destination = session:getVariable("destination_number") or "-"
local tries_left = tonumber(flow.max_tries) or 3
local term = "#"

while tries_left > 0 do
  local pdig_cmd = "1 1 " .. tries_left .. " 3000 " .. term .. " " .. flow.menu .. " " .. flow.invalid .. " ivr_digits"
  session:execute("play_and_get_digits", pdig_cmd)
  local digit = session:getVariable("ivr_digits") or ""
  tries_left = tries_left - 1

  local chosen = nil
  if flow.options then
    for k, opt in pairs(flow.options) do
      if opt.digit == digit then chosen = opt break end
    end
  end

  local action = (chosen and chosen.action) or "invalid"
  local file = (chosen and chosen.file) or nil
  local line = '{"ts":"' .. now() .. '","country":"' .. country .. '","caller":"' .. caller ..
               '","dest":"' .. destination .. '","digit":"' .. digit .. '","action":"' .. action .. '"}'
  append_line(log_dir .. "/ivr_cdr.jsonl", line)
  freeswitch.consoleLog("notice", "IVR_ACTION flow=" .. flow.name .. " caller=" .. caller ..
                        " digit=" .. digit .. " action=" .. action .. "\n")

  if action == "bye" then
    session:hangup()
    return
  end
  if action == "invalid" then
    session:streamFile(flow.invalid)
  elseif action == "playback" and file then
    session:streamFile(file)
  elseif action == "password" then
    -- FEAT-01b: cambio de contraseña/PIN por IVR. Pide 4+4 dígitos (nuevo y
    -- confirmación) y persiste vía la API VAS (vas.subscriber_pin en MySQL).
    local p1 = collect_digits(flow, term, 4, 4, 2, flow.pin_prompt, "ivr_pin1")
    local p2 = ""
    local result = "fail"
    if #p1 == 4 then
      p2 = collect_digits(flow, term, 4, 4, 2, flow.pin_confirm, "ivr_pin2")
      if p1 == p2 then
        local resp = http_post(flow.pin_api, '{"caller":"' .. caller .. '","pin":"' .. p1 .. '"}', 5)
        if resp:find('"ok": true') or resp:find('"ok":true') then result = "ok" end
      end
    end
    session:streamFile(result == "ok" and flow.pin_ok or flow.pin_fail)
    freeswitch.consoleLog("notice", "IVR_PIN caller=" .. caller .. " result=" .. result ..
                          " digit=" .. digit .. "\n")
  end
  if chosen and chosen["then"] == "bye" then
    session:hangup()
    return
  end
end

freeswitch.consoleLog("notice", "IVR_END flow=" .. flow.name .. " cause=timeout\n")
session:hangup()