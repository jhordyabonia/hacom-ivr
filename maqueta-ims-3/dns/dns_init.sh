#!/bin/bash

# BSD 2-Clause License

# Copyright (c) 2020-2025, Supreeth Herle
# All rights reserved.

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:

# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.

# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

cp /mnt/dns/ims_zone /etc/bind
cp /mnt/dns/e164.arpa /etc/bind
cp /mnt/dns/named.conf /etc/bind

[ ${#MNC} == 3 ] && IMS_DOMAIN="ims.mnc${MNC}.mcc${MCC}.3gppnetwork.org" || IMS_DOMAIN="ims.mnc0${MNC}.mcc${MCC}.3gppnetwork.org"

sed -i 's|IMS_DOMAIN|'$IMS_DOMAIN'|g' /etc/bind/ims_zone
sed -i 's|DNS_IP|'$DNS_IP'|g' /etc/bind/ims_zone
sed -i 's|PCSCF_IP|'$PCSCF_IP'|g' /etc/bind/ims_zone
sed -i 's|ICSCF_IP|'$ICSCF_IP'|g' /etc/bind/ims_zone
sed -i 's|SCSCF_IP|'$SCSCF_IP'|g' /etc/bind/ims_zone
sed -i 's|PYHSS_IP|'$PYHSS_DIAMETER_IP'|g' /etc/bind/ims_zone
sed -i 's|ASTERISK_IP|'$ASFRONT_IP'|g' /etc/bind/ims_zone
sed -i 's|ASFRONT_IP|'$ASFRONT_IP'|g' /etc/bind/ims_zone
sed -i 's|FREESWITCH_IP|'$FREESWITCH_IP'|g' /etc/bind/ims_zone
sed -i 's|SMSC_IP|'$SMSC_IP'|g' /etc/bind/ims_zone
sed -i 's|IBCF_IP|'$IBCF_IP'|g' /etc/bind/ims_zone

sed -i 's|IMS_DOMAIN|'$IMS_DOMAIN'|g' /etc/bind/e164.arpa
sed -i 's|DNS_IP|'$DNS_IP'|g' /etc/bind/e164.arpa

sed -i 's|IMS_DOMAIN|'$IMS_DOMAIN'|g' /etc/bind/named.conf

exec /usr/sbin/named -c /etc/bind/named.conf -g -u bind $@

# Sync docker time
#ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
