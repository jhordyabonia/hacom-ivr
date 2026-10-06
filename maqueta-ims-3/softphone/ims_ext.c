/*
 * ims_ext.c — Extensiones IMS para pjsua (maqueta-ims-3, softphone UE).
 *
 * Se incluye desde pjsua_app.c (ver softphone/Dockerfile). Se configura por
 * variables de entorno para no tocar el parser de opciones de pjsua:
 *
 *   IMS_AKA_K, IMS_AKA_OPC, IMS_AKA_AMF   USIM/ISIM (hex). Activa IMS-AKA
 *                                         (Digest-AKAv1-MD5, RFC 3310 / TS 33.203).
 *   IMS_SECAGREE=1                        sec-agree + IPsec ESP en Gm (RFC 3329,
 *                                         TS 33.203 §7, TS 24.229 §5.1.1.2).
 *   IMS_PORT_C / IMS_PORT_S               port_uc / port_us del UE (port_us = --local-port).
 *   IMS_SPI_C / IMS_SPI_S                 spi_uc / spi_us del UE.
 *   IMS_PANI                              P-Access-Network-Info del UE (TS 24.229 §7.2A.4).
 *   IMS_IPSEC_SCRIPT                      script que instala las SA (ip xfrm) y el
 *                                         mapeo de puertos protegidos.
 *
 * Qué hace:
 *  - Credenciales AKA reales: RES = f2(K, RAND, OPc), verificación de AUTN (MAC),
 *    IMPI en el Authorization desde el primer REGISTER (initial_auth, --use-ims).
 *  - REGISTER: Security-Client (ipsec-3gpp), Require/Proxy-Require: sec-agree,
 *    Supported: path.
 *  - 401 con Security-Server: calcula CK/IK (Milenage f2345) e instala las 4 SA
 *    ESP (UE<->P-CSCF) antes de que el 2º REGISTER salga; desde ahí toda petición
 *    lleva Security-Verify (= Security-Server recibido) y viaja protegida.
 *  - Peticiones fuera de diálogo: P-Access-Network-Info; INVITE inicial:
 *    P-Preferred-Identity, P-Preferred-Service y Accept-Contact (MMTEL, TS 24.173).
 */
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <pjlib-util/base64.h>
#include "../../../third_party/milenage/milenage.h"

#define IMS_THIS_FILE "ims_ext.c"

static struct ims_ext_state {
    pj_bool_t   aka;
    pj_bool_t   secagree;
    pj_uint8_t  k[16], opc[16], amf[2];
    unsigned    port_c, port_s;
    unsigned    spi_c, spi_s;
    char        pani[160];
    char        script[128];
    char        sec_client[200];
    char        sec_verify[400];      /* Security-Server recibido en el 401 */
    pj_bool_t   sa_up;
    unsigned    spi_base, gen;        /* generación del juego de SA (TS 33.203 §7.4) */
    unsigned    last_reg_cseq;
    pj_bool_t   auth_resend_pending;  /* el próximo REGISTER responde a un 401 */
} ims;

static void ims_build_sec_client(void)
{
    pj_ansi_snprintf(ims.sec_client, sizeof(ims.sec_client),
        "ipsec-3gpp;alg=hmac-sha-1-96;ealg=null;spi-c=%u;spi-s=%u;port-c=%u;port-s=%u",
        ims.spi_c, ims.spi_s, ims.port_c, ims.port_s);
}

static const char *ims_env(const char *name, const char *def)
{
    const char *v = getenv(name);
    return (v && *v) ? v : def;
}

static int ims_hex2bin(const char *hex, pj_uint8_t *out, int len)
{
    int i;
    if (!hex || (int)strlen(hex) != len * 2) return -1;
    for (i = 0; i < len; ++i) {
        unsigned b;
        if (sscanf(hex + 2*i, "%2x", &b) != 1) return -1;
        out[i] = (pj_uint8_t)b;
    }
    return 0;
}

static void ims_bin2hex(const pj_uint8_t *in, int len, char *out)
{
    int i;
    for (i = 0; i < len; ++i) sprintf(out + 2*i, "%02x", in[i]);
    out[2*len] = '\0';
}

/* Valor de un parámetro "name=value" dentro de un header sec-agree. */
static int ims_param(const char *hdr, const char *name, char *out, int outlen)
{
    char key[32];
    const char *p, *e;
    int n;
    snprintf(key, sizeof(key), "%s=", name);
    p = strstr(hdr, key);
    while (p && p != hdr && p[-1] != ';' && p[-1] != ' ')
        p = strstr(p + 1, key);
    if (!p) return -1;
    p += strlen(key);
    e = p;
    while (*e && *e != ';' && *e != ',' && *e != ' ' && *e != '\r') ++e;
    n = (int)(e - p);
    if (n >= outlen) n = outlen - 1;
    memcpy(out, p, n);
    out[n] = '\0';
    return 0;
}

static void ims_add_hdr(pjsip_tx_data *tdata, const char *name, const char *value)
{
    pj_str_t hname = pj_str((char*)name);
    pj_str_t hval;
    pjsip_generic_string_hdr *h;
    if (pjsip_msg_find_hdr_by_name(tdata->msg, &hname, NULL))
        return;                             /* idempotente (retransmisiones) */
    pj_strdup2(tdata->pool, &hval, value);
    h = pjsip_generic_string_hdr_create(tdata->pool, &hname, &hval);
    pjsip_msg_add_hdr(tdata->msg, (pjsip_hdr*)h);
}

static pj_bool_t ims_has_totag(pjsip_msg *msg)
{
    pjsip_to_hdr *to = PJSIP_MSG_TO_HDR(msg);
    return to && to->tag.slen > 0;
}

static pj_status_t ims_on_tx_request(pjsip_tx_data *tdata)
{
    pjsip_msg *msg = tdata->msg;
    const pjsip_method *m = &msg->line.req.method;
    pj_bool_t is_ack = (m->id == PJSIP_ACK_METHOD);
    pj_bool_t is_cancel = (m->id == PJSIP_CANCEL_METHOD);
    pj_bool_t changed = PJ_FALSE;

    /* TS 24.229 §5.1.1.2.1/§5.1.2A: con IMS-AKA solo el REGISTER lleva
     * Authorization (initial_auth de pjsip la añadiría a toda petición). */
    if (ims.aka && m->id != PJSIP_REGISTER_METHOD) {
        pjsip_msg_find_remove_hdr(msg, PJSIP_H_AUTHORIZATION, NULL);
        pjsip_msg_find_remove_hdr(msg, PJSIP_H_PROXY_AUTHORIZATION, NULL);
        changed = PJ_TRUE;
    }

    if (ims.secagree && !is_ack && !is_cancel) {
        if (m->id == PJSIP_REGISTER_METHOD) {
            pjsip_cseq_hdr *cs = PJSIP_MSG_CSEQ_HDR(msg);
            pj_str_t sc = pj_str("Security-Client");
            pjsip_hdr *old;
            if (cs && cs->cseq != ims.last_reg_cseq) {      /* no es retransmisión */
                ims.last_reg_cseq = cs->cseq;
                if (ims.auth_resend_pending) {
                    /* 2º REGISTER: mismo Security-Client que el 1º (RFC 3329). */
                    ims.auth_resend_pending = PJ_FALSE;
                } else if (ims.sa_up) {
                    /* TS 33.203 §7.4: una nueva autenticación negocia un juego
                     * de SA nuevo (spi_uc/spi_us y port_uc nuevos; port_us se
                     * mantiene) mientras el anterior sigue vivo. */
                    ims.gen = (ims.gen + 1) % 64;
                    ims.spi_c = ims.spi_base + 2 * ims.gen;
                    ims.spi_s = ims.spi_c + 1;
                    ims.port_c = ims.port_s + 1 + 2 * ims.gen;
                    ims_build_sec_client();
                }
            }
            while ((old = (pjsip_hdr*)pjsip_msg_find_hdr_by_name(msg, &sc, NULL)) != NULL)
                pj_list_erase(old);
            ims_add_hdr(tdata, "Security-Client", ims.sec_client);
            ims_add_hdr(tdata, "Supported", "path");
        }
        if (m->id == PJSIP_REGISTER_METHOD || ims.sa_up) {
            ims_add_hdr(tdata, "Require", "sec-agree");
            ims_add_hdr(tdata, "Proxy-Require", "sec-agree");
        }
        if (ims.sa_up) {
            /* RFC 3329 §2.3.1: Security-Verify refleja el Security-Server
             * vigente; un reenvío autenticado clona la petición anterior. */
            pj_str_t sv = pj_str("Security-Verify");
            pjsip_hdr *old;
            while ((old = (pjsip_hdr*)pjsip_msg_find_hdr_by_name(msg, &sv, NULL)) != NULL)
                pj_list_erase(old);
            ims_add_hdr(tdata, "Security-Verify", ims.sec_verify);
        }
        changed = PJ_TRUE;
    }

    if (ims.pani[0] && !is_ack && !is_cancel) {
        ims_add_hdr(tdata, "P-Access-Network-Info", ims.pani);
        changed = PJ_TRUE;
    }

    if (m->id == PJSIP_INVITE_METHOD && !ims_has_totag(msg)) {
        char ppi[256];
        pjsip_sip_uri *fu = (pjsip_sip_uri*)
            pjsip_uri_get_uri(PJSIP_MSG_FROM_HDR(msg)->uri);
        if (PJSIP_URI_SCHEME_IS_SIP(fu)) {
            snprintf(ppi, sizeof(ppi), "<sip:%.*s@%.*s>",
                     (int)fu->user.slen, fu->user.ptr,
                     (int)fu->host.slen, fu->host.ptr);
            ims_add_hdr(tdata, "P-Preferred-Identity", ppi);
        }
        ims_add_hdr(tdata, "P-Preferred-Service",
                    "urn:urn-7:3gpp-service.ims.icsi.mmtel");
        ims_add_hdr(tdata, "Accept-Contact",
                    "*;+g.3gpp.icsi-ref=\"urn%3Aurn-7%3A3gpp-service.ims.icsi.mmtel\"");
        changed = PJ_TRUE;
    }

    if (changed)
        pjsip_tx_data_invalidate_msg(tdata);
    return PJ_SUCCESS;
}

/* 401 al REGISTER con Security-Server: instala las SA antes del 2º REGISTER. */
static pj_bool_t ims_on_rx_response(pjsip_rx_data *rdata)
{
    pjsip_msg *msg = rdata->msg_info.msg;
    pj_str_t ss_name = pj_str("Security-Server");
    pjsip_generic_string_hdr *ss;
    pjsip_www_authenticate_hdr *wa;
    char ss_val[400], best[400], alg[32], ealg[32], spi_c[16], spi_s[16],
         port_c[8], port_s[8], ik_hex[33], ck_hex[33], cmd[1024];
    pj_uint8_t nonce[64], res[8], ck[16], ik[16], ak[6];
    int nonce_len = sizeof(nonce);
    float best_q = -1;
    char *tok, *save = NULL;
    const char *local_ip;
    pj_str_t local_ip_str;
    int rc;

    if (!ims.secagree || msg->line.status.code != 401 ||
        rdata->msg_info.cseq->method.id != PJSIP_REGISTER_METHOD)
        return PJ_FALSE;

    ss = (pjsip_generic_string_hdr*)
         pjsip_msg_find_hdr_by_name(msg, &ss_name, NULL);
    wa = (pjsip_www_authenticate_hdr*)
         pjsip_msg_find_hdr(msg, PJSIP_H_WWW_AUTHENTICATE, NULL);
    if (!ss || !wa) {
        PJ_LOG(2,(IMS_THIS_FILE, "sec-agree: 401 sin Security-Server/WWW-Authenticate"));
        return PJ_FALSE;
    }

    /* Mecanismo ipsec-3gpp de mayor q (RFC 3329 §2.2). */
    pj_ansi_snprintf(ss_val, sizeof(ss_val), "%.*s",
                     (int)ss->hvalue.slen, ss->hvalue.ptr);
    best[0] = '\0';
    {
        char tmp[400];
        pj_ansi_strncpy(tmp, ss_val, sizeof(tmp));
        for (tok = strtok_r(tmp, ",", &save); tok; tok = strtok_r(NULL, ",", &save)) {
            char q[16];
            float qv = 0.1f;
            while (*tok == ' ') ++tok;
            if (strncmp(tok, "ipsec-3gpp", 10) != 0) continue;
            if (ims_param(tok, "q", q, sizeof(q)) == 0) qv = (float)atof(q);
            if (qv > best_q) { best_q = qv; pj_ansi_strncpy(best, tok, sizeof(best)); }
        }
    }
    if (!best[0] ||
        ims_param(best, "alg", alg, sizeof(alg)) ||
        ims_param(best, "spi-c", spi_c, sizeof(spi_c)) ||
        ims_param(best, "spi-s", spi_s, sizeof(spi_s)) ||
        ims_param(best, "port-c", port_c, sizeof(port_c)) ||
        ims_param(best, "port-s", port_s, sizeof(port_s))) {
        PJ_LOG(1,(IMS_THIS_FILE, "sec-agree: Security-Server inválido: %s", ss_val));
        return PJ_FALSE;
    }
    if (ims_param(best, "ealg", ealg, sizeof(ealg)))
        pj_ansi_strncpy(ealg, "null", sizeof(ealg));

    /* CK/IK a partir de RAND (nonce = base64(RAND||AUTN||...)). */
    if (pj_base64_decode(&wa->challenge.digest.nonce, nonce, &nonce_len) != PJ_SUCCESS ||
        nonce_len < 32) {
        PJ_LOG(1,(IMS_THIS_FILE, "sec-agree: nonce AKA inválido"));
        return PJ_FALSE;
    }
    f2345(ims.k, nonce, res, ck, ik, ak, ims.opc);
    ims_bin2hex(ik, 16, ik_hex);
    ims_bin2hex(ck, 16, ck_hex);

    local_ip_str = rdata->tp_info.transport->local_name.host;
    local_ip = pj_strbuf(&local_ip_str);

    pj_ansi_snprintf(cmd, sizeof(cmd),
        "%s setup %.*s %s %u %u %u %u %s %s %s %s %s %s %s %s",
        ims.script, (int)local_ip_str.slen, local_ip, rdata->pkt_info.src_name,
        ims.port_c, ims.port_s, ims.spi_c, ims.spi_s,
        port_c, port_s, spi_c, spi_s, alg, ealg, ik_hex, ck_hex);
    rc = system(cmd);
    if (rc != 0) {
        PJ_LOG(1,(IMS_THIS_FILE, "sec-agree: fallo instalando SA (rc=%d)", rc));
        return PJ_FALSE;
    }
    pj_ansi_strncpy(ims.sec_verify, ss_val, sizeof(ims.sec_verify));
    ims.sa_up = PJ_TRUE;
    ims.auth_resend_pending = PJ_TRUE;
    PJ_LOG(3,(IMS_THIS_FILE,
              "sec-agree: SA IPsec ESP establecidas (alg=%s ealg=%s, P-CSCF port-c=%s port-s=%s)",
              alg, ealg, port_c, port_s));
    return PJ_FALSE;        /* el 401 sigue su curso: pjsip responde con AKA */
}

static pjsip_module ims_ext_mod = {
    NULL, NULL,
    { "mod-ims-ext", 11 },
    -1,
    PJSIP_MOD_PRIORITY_TRANSPORT_LAYER + 2,     /* antes de la capa de transacción */
    NULL, NULL, NULL, NULL,
    NULL,                                       /* on_rx_request */
    &ims_on_rx_response,
    &ims_on_tx_request,
    NULL,                                       /* on_tx_response */
    NULL,
};

/* Ajusta las cuentas (credenciales AKA) y registra el módulo. */
static pj_status_t ims_ext_init(pjsua_app_config *cfg)
{
    unsigned a, c;
    const char *k = getenv("IMS_AKA_K");

    pj_bzero(&ims, sizeof(ims));
    if (k && *k) {
        if (ims_hex2bin(k, ims.k, 16) ||
            ims_hex2bin(ims_env("IMS_AKA_OPC", ""), ims.opc, 16) ||
            ims_hex2bin(ims_env("IMS_AKA_AMF", "8000"), ims.amf, 2)) {
            PJ_LOG(1,(IMS_THIS_FILE, "IMS_AKA_K/IMS_AKA_OPC/IMS_AKA_AMF inválidos"));
            return PJ_EINVAL;
        }
        ims.aka = PJ_TRUE;
        for (a = 0; a < cfg->acc_cnt; ++a) {
            pjsua_acc_config *acc = &cfg->acc_cfg[a];
            acc->auth_pref.initial_auth = PJ_TRUE;      /* IMPI desde el 1er REGISTER */
            acc->auth_pref.algorithm = pj_str("AKAv1-MD5");
            for (c = 0; c < acc->cred_count; ++c) {
                pjsip_cred_info *ci = &acc->cred_info[c];
                ci->data_type = PJSIP_CRED_DATA_EXT_AKA;
                ci->ext.aka.k.ptr = (char*)ims.k;   ci->ext.aka.k.slen = 16;
                ci->ext.aka.op.ptr = (char*)ims.opc; ci->ext.aka.op.slen = 16;
                ci->ext.aka.amf.ptr = (char*)ims.amf; ci->ext.aka.amf.slen = 2;
                ci->ext.aka.cb = &pjsip_auth_create_aka_response;
            }
        }
        PJ_LOG(3,(IMS_THIS_FILE, "IMS-AKA activo (Digest-AKAv1-MD5, Milenage con OPc)"));
    } else {
        /* Modo SIP Digest (perfil no-3GPP): pjsua, compilado con AKA, marca
         * --password como credencial AKA (K en ASCII) y aborta; se deja plana. */
        for (a = 0; a < cfg->acc_cnt; ++a)
            for (c = 0; c < cfg->acc_cfg[a].cred_count; ++c)
                cfg->acc_cfg[a].cred_info[c].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
    }

    ims.secagree = (atoi(ims_env("IMS_SECAGREE", "0")) == 1) && ims.aka;
    if (ims.secagree) {
        /* TS 24.229 §5.1.1.2.1: Contact y Via llevan el puerto protegido port-s.
         * Las peticiones salen desde port-c (SNAT local), así que el rport que
         * devuelve el P-CSCF no debe provocar reescrituras ni re-registros. */
        for (a = 0; a < cfg->acc_cnt; ++a) {
            cfg->acc_cfg[a].allow_contact_rewrite = PJ_FALSE;
            cfg->acc_cfg[a].allow_via_rewrite = PJ_FALSE;
            cfg->acc_cfg[a].allow_sdp_nat_rewrite = PJ_FALSE;
        }
    }
    ims.port_c = (unsigned)atoi(ims_env("IMS_PORT_C", "5063"));
    ims.port_s = (unsigned)atoi(ims_env("IMS_PORT_S", "5061"));
    ims.spi_c = (unsigned)strtoul(ims_env("IMS_SPI_C", "0"), NULL, 10);
    ims.spi_s = (unsigned)strtoul(ims_env("IMS_SPI_S", "0"), NULL, 10);
    if (!ims.spi_c) ims.spi_c = 10000 + (unsigned)(pj_rand() % 50000) * 256;
    if (!ims.spi_s) ims.spi_s = ims.spi_c + 1;
    ims.spi_base = ims.spi_c;
    pj_ansi_strncpy(ims.pani, ims_env("IMS_PANI", ""), sizeof(ims.pani));
    pj_ansi_strncpy(ims.script, ims_env("IMS_IPSEC_SCRIPT", "/usr/local/bin/ims-ipsec.sh"),
                    sizeof(ims.script));
    ims_build_sec_client();
    if (ims.secagree)
        PJ_LOG(3,(IMS_THIS_FILE, "sec-agree activo: Security-Client: %s", ims.sec_client));

    return pjsip_endpt_register_module(pjsua_get_pjsip_endpt(), &ims_ext_mod);
}
