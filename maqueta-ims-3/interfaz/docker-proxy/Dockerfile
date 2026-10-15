FROM haproxy:3.0-alpine

USER root
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
RUN haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
CMD ["haproxy", "-db", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]
