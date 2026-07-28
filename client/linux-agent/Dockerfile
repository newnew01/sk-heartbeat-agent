FROM alpine:3.20

RUN apk add --no-cache bash curl jq

COPY branch-heartbeat-agent.sh /usr/local/bin/branch-heartbeat-agent.sh
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/branch-heartbeat-agent.sh /usr/local/bin/docker-entrypoint.sh

VOLUME ["/var/lib/branch-heartbeat-agent"]

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
