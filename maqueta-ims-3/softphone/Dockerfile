FROM ubuntu:22.04 AS build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get -y install --no-install-recommends build-essential autoconf python3 \
        libopencore-amrnb-dev libopencore-amrwb-dev libvo-amrwbenc-dev && \
    rm -rf /var/lib/apt/lists/*
COPY pjproject-2.14.tar.gz /tmp/pj.tar.gz
RUN tar -xzf /tmp/pj.tar.gz -C /tmp && mv /tmp/pjproject-2.14 /tmp/pjproject
COPY ims_ext.c /tmp/pjproject/pjsip-apps/src/pjsua/ims_ext.c
# IMS-AKA (TS 33.203): AKA nativo de pjsip + Milenage con OPc (la USIM de la
# maqueta se provisiona con OPc en PyHSS); extensión IMS (sec-agree/IPsec, PANI,
# MMTEL) enganchada en pjsua_app.c.
RUN cd /tmp/pjproject && \
    printf '#define PJSIP_HAS_DIGEST_AKA_AUTH 1\n' > pjlib/include/pj/config_site.h && \
    printf '/* MTU 9000 en la red del laboratorio (RFC 3261 §18.1.1) */\n#define PJSIP_UDP_SIZE_THRESHOLD 8000\n' >> pjlib/include/pj/config_site.h && \
    python3 - <<'EOF'
import re
p = 'third_party/milenage/milenage.c'
s = open(p).read()
s = s.replace('''  RijndaelEncrypt( op, op_c );
  for (i=0; i<16; i++)
    op_c[i] ^= op[i];
''', '''  /* maqueta-ims-3: el parámetro "op" ya es OPc (provisionado en el HSS) */
  for (i=0; i<16; i++)
    op_c[i] = op[i];
''')
open(p, 'w').write(s)
# Milenage/Rijndael no se enlazan por defecto: se compilan dentro de libpjsip.
p = 'pjsip/src/pjsip/sip_auth_aka.c'
s = open(p).read()
s += '\n#if PJSIP_HAS_DIGEST_AKA_AUTH\n#include "../../third_party/milenage/rijndael.c"\n#include "../../third_party/milenage/milenage.c"\n#endif\n'
open(p, 'w').write(s)
p = 'pjsip-apps/src/pjsua/pjsua_app.c'
s = open(p).read()
s = s.replace('static pjsip_module mod_default_handler =',
              '#include "ims_ext.c"\n\nstatic pjsip_module mod_default_handler =', 1)
s = s.replace('''                                         &mod_default_handler);
    if (status != PJ_SUCCESS)
        return status;
''', '''                                         &mod_default_handler);
    if (status != PJ_SUCCESS)
        return status;

    status = ims_ext_init(&app_config);
    if (status != PJ_SUCCESS)
        return status;
''', 1)
assert 'ims_ext_init(&app_config)' in s
open(p, 'w').write(s)
EOF
RUN cd /tmp/pjproject && \
    ./configure --disable-video --disable-sound --disable-libwebrtc > /tmp/configure.log && \
    grep -i 'amr' /tmp/configure.log; \
    make dep >/dev/null 2>&1 && make -j"$(nproc)" >/tmp/make.log 2>&1 || (tail -40 /tmp/make.log; exit 1)

FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get -y install --no-install-recommends iputils-ping dnsutils tcpdump curl \
        iproute2 nftables python3 \
        libopencore-amrnb0 libopencore-amrwb0 libvo-amrwbenc0 && \
    rm -rf /var/lib/apt/lists/*
COPY --from=build /tmp/pjproject/pjsip-apps/bin/pjsua-* /usr/local/bin/pjsua
COPY ims-ipsec.sh /usr/local/bin/ims-ipsec.sh
RUN chmod +x /usr/local/bin/ims-ipsec.sh
CMD ["bash"]
