-- vms_buzon.lua — Buzón de voz 0100003 (VMS): solo escucha y gestión.
-- Los mensajes se dejan llamando al IVR 0100002 (ivr_flow.lua, "record" del
-- flujo), que graba en este mismo INBOX. Menú:
--   1 = escuchar todos los mensajes, del más reciente al más antiguo;
--   2 = borrar todos los mensajes;
--   3 = contraseña del buzón (solo la entrada del menú: aún no implementada).
-- Tras cada opción se vuelve al menú; tres vueltas sin dígito válido cuelgan.
-- Los mensajes son INBOX/msg_<fecha>_<uuid>.wav (QA-10), los mismos que lista y
-- reproduce la pestaña VMS de la interfaz web.
--
-- Uso dialplan: lua vms_buzon.lua <dir_inbox>; hangup

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

local function delete_all()
  local msgs = list_messages()
  freeswitch.consoleLog("notice", "VMS_BUZON borrar caller=" .. caller .. " mensajes=" .. #msgs .. "\n")
  if #msgs == 0 then
    play("vms_sin_mensajes")
    return
  end
  for _, name in ipairs(msgs) do os.remove(inbox .. "/" .. name) end
  play("vms_borrados")
end

session:answer()
session:sleep(500)
local misses = 0
while session:ready() and misses < 3 do
  -- Un dígito; 5 s para marcarlo tras el menú (también durante el menú).
  local digit = session:playAndGetDigits(1, 1, 1, 5000, "#", audio .. "vms_menu.wav", "", "[123]")
  if digit == "1" then
    misses = 0; listen()
  elseif digit == "2" then
    misses = 0; delete_all()
  elseif digit == "3" then
    misses = 0
    freeswitch.consoleLog("notice", "VMS_BUZON contrasena caller=" .. caller .. " (no disponible)\n")
    play("vms_clave_no_disponible")
  else
    misses = misses + 1
  end
end
play("vms_adios")
session:hangup()
