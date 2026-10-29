-- vms_buzon.lua — Buzón de voz 0100003 (VMS).
-- Saluda y ofrece dos opciones:
--   1      = escuchar los mensajes del buzón, del más reciente al más antiguo;
--   (nada) = tras el tono, grabar un mensaje nuevo.
-- Los mensajes son INBOX/msg_<fecha>_<uuid>.wav (QA-10), los mismos que lista y
-- reproduce la pestaña VMS de la interfaz web.
--
-- Uso dialplan: answer; lua vms_buzon.lua <dir_inbox>; hangup

local inbox = argv[1] or "/var/lib/freeswitch/storage/vms/0100003/INBOX"
local audio = "/mnt/freeswitch/audio/"
local caller = session:getVariable("caller_id_number") or "-"

os.execute("mkdir -p " .. inbox)

local function play(name)
  if session:ready() then session:streamFile(audio .. name .. ".wav") end
end

-- Mensajes del buzón, del más reciente al más antiguo (el nombre empieza por la
-- fecha, así que el orden alfabético inverso es el cronológico inverso).
local function list_messages()
  local msgs = {}
  local f = io.popen("ls " .. inbox .. " 2>/dev/null")
  if f then
    for name in f:lines() do
      if name:match("^msg.*%.wav$") then msgs[#msgs + 1] = name end
    end
    f:close()
  end
  table.sort(msgs, function(a, b) return a > b end)
  return msgs
end

local function listen()
  local msgs = list_messages()
  freeswitch.consoleLog("notice", "VMS_BUZON escuchar caller=" .. caller .. " mensajes=" .. #msgs .. "\n")
  if #msgs == 0 then
    play("vms_sin_mensajes")
    return
  end
  play("vms_reproduciendo")
  for i, name in ipairs(msgs) do
    if not session:ready() then return end
    if i > 1 then play("vms_siguiente") end
    freeswitch.consoleLog("notice", "VMS_BUZON reproduce " .. name .. "\n")
    session:streamFile(inbox .. "/" .. name)
  end
  play("vms_fin_mensajes")
end

local function deposit()
  local file = string.format("%s/msg_%s_%s.wav", inbox, os.date("%Y%m%d_%H%M%S"),
    session:getVariable("uuid"))
  -- Tono de 1 kHz (0,6 s) que marca el inicio de la grabación.
  session:execute("playback", "tone_stream://%(600,0,1000)")
  freeswitch.consoleLog("notice", "VMS_BUZON graba caller=" .. caller .. " file=" .. file .. "\n")
  -- Hasta 300 s; termina al colgar o tras 7 s seguidos de silencio.
  session:recordFile(file, 300, 200, 7)
  play("vms_grabado")
end

session:answer()
session:sleep(500)
-- Saludo con opción: un dígito, 4 s para marcarlo; sin dígito se graba.
local digit = session:playAndGetDigits(1, 1, 1, 4000, "#", audio .. "vms_bienvenida.wav", "", "[1]")
if digit == "1" then
  listen()
else
  deposit()
end
session:hangup()
