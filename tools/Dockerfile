FROM alpine:3.19

RUN apk add --no-cache \
        bash \
        coreutils \
        procps \
        util-linux \
        stress-ng \
        fio \
        iperf3 \
        iproute2 \
        sysstat \
        curl

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["sleep infinity"]
