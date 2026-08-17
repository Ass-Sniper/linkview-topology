FROM alpine:latest

ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY

RUN sed -i 's/https/http/g' /etc/apk/repositories && \
    apk add --no-cache net-snmp python3

CMD ["snmpd", "-f", "-Le", "-C", "-I", "-dot1dTpFdbTable", "-c", "/etc/snmp/snmpd.conf"]
