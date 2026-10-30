-- ivr_flow.lua — Motor de IVR con menú DTMF (FEAT-01)
-- Lee flujos JSON por país desde /mnt/freeswitch/flows/<pais>.json y ejecuta:
--   saludo -> menú (playAndGetDigits) -> acción por dígito -> repetir/colgar.
-- Si el flujo trae "record" (0100002), el menú sin dígito no cuelga: avisa, da
-- el tono y graba un mensaje de voz en record.inbox (buzón 0100003).
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

-- Mensaje de voz tras el menú: tono de 1 kHz (0,6 s) y grabación hasta 300 s;
-- termina al colgar o tras 7 s seguidos de silencio. Mismo formato que el
-- buzón (INBOX/msg_<fecha>_<uuid>.wav, QA-10): lo lista la pestaña VMS.
local function record_message(rec)
  local inbox = rec.inbox
  os.execute("mkdir -p " .. inbox)
  local file = string.format("%s/msg_%s_%s.wav", inbox, os.date("%Y%m%d_%H%M%S"),
    session:getVariable("uuid"))
  if rec.prompt then session:streamFile(rec.prompt) end
  if not session:ready() then return end
  session:execute("playback", "tone_stream://%(600,0,1000)")
  freeswitch.consoleLog("notice", "VMS_BUZON graba caller=" .. caller .. " file=" .. file .. "\n")
  session:recordFile(file, 300, 200, 7)
  if rec.done and session:ready() then session:streamFile(rec.done) end
end

while tries_left > 0 do
  -- Con "record" el primer silencio pasa a grabar: un solo intento por vuelta.
  local tries = flow.record and 1 or tries_left
  local pdig_cmd = "1 1 " .. tries .. " 3000 " .. term .. " " .. flow.menu .. " " .. flow.invalid .. " ivr_digits"
  session:execute("play_and_get_digits", pdig_cmd)
  local digit = session:getVariable("ivr_digits") or ""
  tries_left = tries_left - 1
  -- Colgó durante el menú: sin CDR de opción (no hubo elección ni grabación).
  if not session:ready() then break end

  local chosen = nil
  if flow.options then
    for k, opt in pairs(flow.options) do
      if opt.digit == digit then chosen = opt break end
    end
  end

  local action = (chosen and chosen.action) or "invalid"
  if digit == "" and flow.record then action = "record" end
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
  if action == "record" then
    record_message(flow.record)
    session:hangup()
    return
  end
  if action == "invalid" then
    session:streamFile(flow.invalid)
  elseif action == "playback" and file then
    session:streamFile(file)
  end
  if chosen and chosen["then"] == "bye" then
    session:hangup()
    return
  end
end

freeswitch.consoleLog("notice", "IVR_END flow=" .. flow.name .. " cause=timeout\n")
session:hangup()