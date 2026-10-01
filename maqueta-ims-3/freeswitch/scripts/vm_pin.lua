-- vm_pin.lua — Recuperación de buzón VMS (FEAT-02).
-- El UE llama a 0100004; se pide el PIN (4 dígitos) y se autentica contra la API
-- de la UI (vas.subscriber_pin). Si es correcto se abre el menú de mod_voicemail
-- del propio buzón (escuchar 1 / borrar 7 + confirmar). El PIN proviene de la BD
-- (no del módulo voicemail, por eso se autentica aquí y luego se usa
-- voicemail_authorized=true para saltar el prompt interno).
--
-- Uso dialplan: answer; set vm_domain=<dominio>; lua vm_pin.lua ${vm_domain} ${caller_id_number}; hangup

local domain = argv[1] or session:getVariable("vm_domain") or ""
local caller = argv[2] or session:getVariable("caller_id_number") or "-"
local ui_host = "172.32.0.14"  -- UI/API (Flask :8888)
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

local tries = 2
local pin = ""
while tries > 0 do
  tries = tries - 1
  session:execute("play_and_get_digits", "1 1 1 4000 # " .. prompt .. " " .. invalid .. " vm_pin_digits")
  pin = session:getVariable("vm_pin_digits") or ""
  freeswitch.consoleLog("notice", "VMS_PIN attempt caller=" .. caller .. " pin=" .. pin .. "\n")
  if #pin >= 4 and pin:match("^%d+$") then
    local resp = api_get("/api/pin/auth?caller=" .. caller .. "&pin=" .. pin)
    if resp:find('"ok":true') or resp:find('"ok": true') then
      freeswitch.consoleLog("notice", "VMS_PIN ok caller=" .. caller .. "\n")
      session:setVariable("voicemail_authorized", "true")
      session:execute("voicemail", "check default " .. domain .. " " .. caller)
      freeswitch.consoleLog("notice", "VMS_PIN done caller=" .. caller .. "\n")
      return
    end
  end
  session:streamFile(invalid)
end

freeswitch.consoleLog("notice", "VMS_PIN fail caller=" .. caller .. "\n")
session:streamFile(invalid)
session:hangup()