FROM ubuntu:22.04 AS build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get -y install --no-install-recommends build-essential autoconf python3 \
        libopencore-amrnb-dev libopencore-amrwb-dev libvo-amrwbenc-dev && \
    rm -rf /var/lib/apt/lists/*
COPY pjproject-2.14.tar.gz /tmp/pj.tar.gz
RUN tar -xzf /tmp/pj.tar.gz -C /tmp && mv /tmp/pjproject-2.14 /tmp/pjproject
COPY ims_ext.c /tmp/pjproject/pjsip-apps/src/pjsua/ims_ext.c
COPY patch_ims_aka.py /tmp/patch_ims_aka.py
# IMS-AKA (TS 33.203): AKA nativo de pjsip + Milenage con OPc (la USIM de la
# maqueta se provisiona con OPc en PyHSS); extensión IMS (sec-agree/IPsec, PANI,
# MMTEL) enganchada en pjsua_app.c.
RUN cd /tmp/pjproject && \
    printf '#define PJSIP_HAS_DIGEST_AKA_AUTH 1\n' > pjlib/include/pj/config_site.h && \
    printf '/* MTU 9000 en la red del laboratorio (RFC 3261 §18.1.1) */\n#define PJSIP_UDP_SIZE_THRESHOLD 8000\n' >> pjlib/include/pj/config_site.h && \
    python3 /tmp/patch_ims_aka.py && \
    test -f pjsip/src/pjsip/ims_milenage.c && \
    grep -q 'ims_milenage.o ims_rijndael.o' pjsip/build/Makefile && \
    grep -q 'ims_ext_init(&app_config)' pjsip-apps/src/pjsua/pjsua_app.c
RUN cd /tmp/pjproject && \
    ./configure --disable-video --disable-sound --disable-libwebrtc > /tmp/configure.log && \
    grep -i 'amr' /tmp/configure.log; \
    make dep >/dev/null 2>&1 && \
    make -j"$(nproc)" lib >/tmp/make.log 2>&1 && \
    (ar t pjsip/lib/libpjsip-x86_64-unknown-linux-gnu.a | grep -E 'ims_milenage|ims_rijndael|sip_auth_aka' || true) && \
    (nm -A pjsip/lib/libpjsip-x86_64-unknown-linux-gnu.a | grep -E 'f2345| f1$' || true) && \
    nm -A pjsip/lib/libpjsip-*.a | grep -E ' [Tt] f2345$' && \
    nm -A pjsip/lib/libpjsip-*.a | grep -E ' [Tt] f1$' && \
    make -j"$(nproc)" -C pjsip-apps/build pjsua >>/tmp/make.log 2>&1 || \
    (tail -40 /tmp/make.log; exit 1)

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
