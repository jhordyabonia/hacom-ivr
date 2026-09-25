FROM safarov/freeswitch:latest

COPY conf/sip_profiles/external.xml /usr/share/freeswitch/conf/vanilla/sip_profiles/external.xml
COPY conf/dialplan/public.xml /usr/share/freeswitch/conf/vanilla/dialplan/public.xml
COPY conf/autoload_configs/sofia.conf.xml /usr/share/freeswitch/conf/vanilla/autoload_configs/sofia.conf.xml
COPY conf/autoload_configs/event_socket.conf.xml /usr/share/freeswitch/conf/vanilla/autoload_configs/event_socket.conf.xml
COPY conf/vars.xml /usr/share/freeswitch/conf/vanilla/vars.xml
COPY init.sh /init.sh
RUN chmod +x /init.sh

ENTRYPOINT ["/init.sh"]
