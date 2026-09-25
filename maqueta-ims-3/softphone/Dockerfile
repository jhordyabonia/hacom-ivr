FROM ubuntu:22.04 AS build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get -y install --no-install-recommends build-essential autoconf && \
    rm -rf /var/lib/apt/lists/*
COPY pjproject-2.14.tar.gz /tmp/pj.tar.gz
RUN tar -xzf /tmp/pj.tar.gz -C /tmp && mv /tmp/pjproject-2.14 /tmp/pjproject
RUN cd /tmp/pjproject && \
    ./configure --disable-video --disable-sound --disable-libwebrtc >/dev/null && \
    make dep >/dev/null 2>&1 && make -j >/dev/null 2>&1

FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get -y install iputils-ping dnsutils tcpdump curl && \
    rm -rf /var/lib/apt/lists/*
COPY --from=build /tmp/pjproject/pjsip-apps/bin/pjsua-* /usr/local/bin/pjsua
CMD ["bash"]