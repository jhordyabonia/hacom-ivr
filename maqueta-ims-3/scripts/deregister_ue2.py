#!/usr/bin/env python3
"""deregister_ue2.py — Desregistra a UE2 enviando REGISTER con Expires: 0.

El P-CSCF requiere autenticación Digest para el deregistro. Este script:
1. Envía un REGISTER sin autorización al P-CSCF
2. Recibe el 401 con el nonce
3. Calcula la respuesta Digest (AKA con MD5)
4. Envía el REGISTER con Authorization y Expires: 0

Uso: python3 deregister_ue2.py
"""
import socket
import hashlib
import time
import sys

# Configuración
PCSCF_IP = "172.32.0.8"
PCSCF_PORT = 5060
DOMAIN = "ims.mnc001.mcc001.3gppnetwork.org"
UE2_MSISDN = "0010100002"
UE2_KI = "2a6ab8297e0d15c7a12eef0d8a12b143"
LOCAL_IP = "172.32.0.10"
LOCAL_PORT = 5062

def md5_hex(data: str) -> str:
    return hashlib.md5(data.encode()).hexdigest()

def build_register(call_id: str, cseq: int, nonce: str = "", nc: str = "00000000", 
                   response: str = "", expires: int = 0) -> str:
    """Construye un mensaje REGISTER SIP."""
    branch = f"z9hG4bK-dereg-{int(time.time())}-{cseq}"
    
    # URI de registro
    request_uri = f"sip:{DOMAIN}"
    
    # Cabeceras base
    msg = f"REGISTER {request_uri} SIP/2.0\r\n"
    msg += f"Via: SIP/2.0/UDP {LOCAL_IP}:{LOCAL_PORT};branch={branch}\r\n"
    msg += f"Max-Forwards: 70\r\n"
    msg += f"From: <sip:{UE2_MSISDN}@{DOMAIN}>;tag=dereg\r\n"
    msg += f"To: <sip:{UE2_MSISDN}@{DOMAIN}>\r\n"
    msg += f"Call-ID: {call_id}\r\n"
    msg += f"CSeq: {cseq} REGISTER\r\n"
    msg += f"Contact: <sip:{UE2_MSISDN}@{LOCAL_IP}:{LOCAL_PORT}>\r\n"
    msg += f"Expires: {expires}\r\n"
    
    # Authorization (si hay nonce)
    if nonce:
        # Digest response
        # HA1 = MD5(username:realm:password)
        # HA2 = MD5(method:uri)
        # response = MD5(HA1:nonce:nc:cnonce:qop:HA2)
        username = UE2_MSISDN
        realm = DOMAIN
        password = UE2_KI
        method = "REGISTER"
        uri = request_uri
        cnonce = "deregister"
        qop = "auth"
        
        ha1 = md5_hex(f"{username}:{realm}:{password}")
        ha2 = md5_hex(f"{method}:{uri}")
        resp = md5_hex(f"{ha1}:{nonce}:{nc}:{cnonce}:{qop}:{ha2}")
        
        msg += f'Authorization: Digest username="{username}", realm="{realm}", '
        msg += f'nonce="{nonce}", uri="{uri}", response="{resp}", '
        msg += f'algorithm=MD5, nc={nc}, cnonce="{cnonce}", qop={qop}\r\n'
    
    msg += "Content-Length: 0\r\n"
    msg += "\r\n"
    
    return msg

def send_and_receive(sock: socket.socket, msg: str, timeout: float = 5.0) -> str:
    """Envía un mensaje SIP y recibe la respuesta."""
    sock.sendall(msg.encode())
    sock.settimeout(timeout)
    try:
        data = sock.recv(4096)
        return data.decode()
    except socket.timeout:
        return ""

def main():
    call_id = f"dereg-{UE2_MSISDN}-{int(time.time())}"
    
    # Crear socket UDP
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((LOCAL_IP, LOCAL_PORT))
    
    print(f"[INFO] Desregistrando {UE2_MSISDN} en {PCSCF_IP}:{PCSCF_PORT}")
    
    # Paso 1: Enviar REGISTER sin autorización
    print("[INFO] Paso 1: Enviando REGISTER sin autorización...")
    msg1 = build_register(call_id, 1, expires=0)
    resp1 = send_and_receive(sock, msg1)
    
    if "401" not in resp1:
        print(f"[ERROR] No se recibió 401. Respuesta: {resp1[:200]}")
        sock.close()
        sys.exit(1)
    
    print("[INFO] Recibido 401 Unauthorized")
    
    # Extraer nonce de la respuesta
    nonce = ""
    for line in resp1.split("\r\n"):
        if "WWW-Authenticate" in line and "nonce=" in line:
            # Extraer nonce
            start = line.find('nonce="') + 7
            end = line.find('"', start)
            nonce = line[start:end]
            break
    
    if not nonce:
        print("[ERROR] No se encontró nonce en la respuesta 401")
        sock.close()
        sys.exit(1)
    
    print(f"[INFO] Nonce: {nonce}")
    
    # Paso 2: Enviar REGISTER con Authorization y Expires: 0
    print("[INFO] Paso 2: Enviando REGISTER con Authorization y Expires: 0...")
    msg2 = build_register(call_id, 2, nonce=nonce, expires=0)
    resp2 = send_and_receive(sock, msg2)
    
    if "200" in resp2:
        print("[OK] UE2 desregistrado correctamente (200 OK)")
        sock.close()
        sys.exit(0)
    else:
        print(f"[ERROR] No se recibió 200 OK. Respuesta: {resp2[:200]}")
        sock.close()
        sys.exit(1)

if __name__ == "__main__":
    main()
