FROM ghcr.io/herlesupreeth/docker_kamailio:master

# Kamailio 6.2.x con módulos IMS (OpenIMSCore line) y las rutas SQL que esperan
# los init scripts del monorepo docker_open5gs:
#   /usr/local/src/kamailio/misc/examples/ims/icscf/icscf.sql
#   /usr/local/src/kamailio/utils/kamctl/mysql/*.sql
# Incluye cliente mysql y bash.
# ims_isc: el destino "unregistered" (perfil obtenido con SAR UNREGISTERED_USER)
# debe evaluar las iFC con SessionCase 2 = TERMINATING_UNREGISTERED (TS 29.228
# Anexo B). La rama terminating comparaba el retorno de cscf_get_terminating_user
# (k) con IMPU_REGISTERED en lugar del estado de registro (regstate), así que
# nunca se disparaba una iFC terminating-unregistered (corregido en upstream).
RUN cd /usr/local/src/kamailio && \
    sed -i 's/if(k == IMPU_REGISTERED) {/if(regstate == IMPU_REGISTERED) {/' src/modules/ims_isc/ims_isc_mod.c && \
    grep -q 'if(regstate == IMPU_REGISTERED) {' src/modules/ims_isc/ims_isc_mod.c && \
    make -C src/modules/ims_isc >/tmp/ims_isc_build.log 2>&1 && \
    cp src/modules/ims_isc/ims_isc.so /usr/local/lib64/kamailio/modules/ims_isc.so
