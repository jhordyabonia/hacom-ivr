-- vm_pin.lua — Recuperación de buzón VMS (FEAT-02).
-- El UE llama a 0100004; se pide el PIN (4 dígitos) y se autentica contra la API
-- de la UI (vas.subscriber_pin). Si es correcto se abre el menú de mod_voicemail
-- del propio buzón (escuchar 1 / borrar 7 + confirmar). El PIN proviene de la BD
-- (no del módulo voicemail, por eso se autentica aquí) y el menú de escucha /
-- borrado usa la API de mod_voicemail (ver retrieve()).
--
-- Uso dialplan: answer; set vm_domain=<dominio>; lua vm_pin.lua ${vm_domain} ${caller_id_number}; hangup

local domain = argv[1] or session:getVariable("vm_domain") or ""
local caller = argv[2] or session:getVariable("caller_id_number") or "-"
local ui_host = "172.32.0.14:8888"  -- UI/API (Flask :8888)
local prompt = "/mnt/freeswitch/audio/pin_prompt.wav"
local invalid = "/mnt/freeswitch/audio/pin_invalido.wav"

freeswitch.consoleLog("notice", "VMS_PIN start caller=" .. caller .. " domain=" .. domain .. "\n")

-- busybox wget (el wget GNU del contenedor segfallea con HTTPS/DNS interno).
local function api_get(query)
  local cmd = "/bin/busybox wget -q -O - --timeout=3 'http://" .. ui_host .. query .. "' 2>/dev/null"
  local f = io.popen(cmd, "r")
  if not f then return "" end
  local out = f:read("*a")
  f:close()
  return out or ""
end

-- Menú de recuperación sobre la API de mod_voicemail (el buzón y su índice son
-- los de mod_voicemail; vm_read/vm_delete actualizan el MWI del suscriptor).
-- La imagen de FreeSWITCH no trae los prompts de voz del menú nativo
-- ("voicemail check" cuelga al no encontrar vm-you_have.wav), por eso el menú
-- se implementa aquí:  1 = escuchar el siguiente mensaje ; tras escucharlo:
-- 7 = borrar, 2 = guardar, # = siguiente sin cambios.
local api = freeswitch.API()
local menu_prompt = "/mnt/freeswitch/audio/menu.wav"

local function list_messages(user, dom)
  local out = api:executeString("vm_list " .. user .. "@" .. dom) or ""
  local msgs = {}
  for line in out:gmatch("[^\r\n]+") do
    -- creado:leído:usuario:dominio:carpeta:fichero:uuid:cid_nombre:cid_num:duración
    local f = {}
    for field in (line .. ":"):gmatch("([^:]*):") do f[#f + 1] = field end
    if #f >= 7 and f[7]:match("^[%x%-]+$") then
      msgs[#msgs + 1] = { file = f[6], uuid = f[7], from = f[9] or "" }
    end
  end
  return msgs
end

-- MWI (TS 24.606 / RFC 3842): tras escuchar o borrar se publica el estado del
-- buzón; mod_sofia lo entrega como NOTIFY message-summary a las suscripciones
-- vigentes (la API vm_delete/vm_read no emite el evento por sí misma).
local function update_mwi(user, dom)
  local c = api:executeString("vm_boxcount default/" .. user .. "@" .. dom .. "|all") or "0:0:0:0"
  local new, saved = c:match("^(%d+):(%d+)")
  new, saved = tonumber(new) or 0, tonumber(saved) or 0
  local e = freeswitch.Event("message_waiting")
  e:addHeader("MWI-Messages-Waiting", new > 0 and "yes" or "no")
  e:addHeader("MWI-Message-Account", "sip:" .. user .. "@" .. dom)
  e:addHeader("MWI-Voice-Message", new .. "/" .. saved .. " (0/0)")
  e:addHeader("Sofia-Profile", "external")
  e:fire()
  freeswitch.consoleLog("notice", "VMS_MWI user=" .. user .. " new=" .. new .. " saved=" .. saved .. "\n")
end

function retrieve(user, dom)
  local msgs = list_messages(user, dom)
  freeswitch.consoleLog("notice", "VMS_RETRIEVE start caller=" .. user .. " mensajes=" .. #msgs .. "\n")
  for _, m in ipairs(msgs) do
    if not session:ready() then return end
    session:execute("play_and_get_digits", "1 1 2 10000 # " .. menu_prompt .. " silence_stream://250 vm_menu_digit [1#]")
    local d = session:getVariable("vm_menu_digit") or ""
    if d ~= "1" then return end
    freeswitch.consoleLog("notice", "VMS_PLAY uuid=" .. m.uuid .. " from=" .. m.from .. "\n")
    session:streamFile(m.file)
    api:executeString("vm_read " .. user .. "@" .. dom .. " read " .. m.uuid)
    session:execute("play_and_get_digits", "1 1 2 10000 # silence_stream://250 silence_stream://250 vm_act_digit [27#]")
    local a = session:getVariable("vm_act_digit") or ""
    if a == "7" then
      api:executeString("vm_delete " .. user .. "@" .. dom .. " " .. m.uuid)
      freeswitch.consoleLog("notice", "VMS_DELETE uuid=" .. m.uuid .. " caller=" .. user .. "\n")
      update_mwi(user, dom)
    elseif a == "2" then
      freeswitch.consoleLog("notice", "VMS_SAVE uuid=" .. m.uuid .. " caller=" .. user .. "\n")
      update_mwi(user, dom)
    end
  end
end

local tries = 2
local pin = ""
while tries > 0 do
  tries = tries - 1
  -- PIN de 4 dígitos (min=max=4), terminador '#', 6 s entre dígitos.
  session:execute("play_and_get_digits", "4 4 1 6000 # " .. prompt .. " " .. invalid .. " vm_pin_digits \\d+")
  pin = session:getVariable("vm_pin_digits") or ""
  freeswitch.consoleLog("notice", "VMS_PIN attempt caller=" .. caller .. " pin=" .. pin .. "\n")
  if #pin >= 4 and pin:match("^%d+$") then
    local resp = api_get("/api/pin/auth?caller=" .. caller .. "&pin=" .. pin)
    if resp:find('"ok":true') or resp:find('"ok": true') then
      freeswitch.consoleLog("notice", "VMS_PIN ok caller=" .. caller .. "\n")
      retrieve(caller, domain)
      freeswitch.consoleLog("notice", "VMS_RETRIEVE end caller=" .. caller .. "\n")
      freeswitch.consoleLog("notice", "VMS_PIN done caller=" .. caller .. "\n")
      return
    end
  end
  session:streamFile(invalid)
end

freeswitch.consoleLog("notice", "VMS_PIN fail caller=" .. caller .. "\n")
session:streamFile(invalid)
session:hangup()