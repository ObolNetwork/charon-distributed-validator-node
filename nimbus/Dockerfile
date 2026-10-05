ARG VERSION

FROM statusim/nimbus-eth2:${VERSION} AS nimbusbn

FROM statusim/nimbus-validator-client:${VERSION}

COPY --from=nimbusbn /home/user/nimbus_beacon_node /home/user/nimbus_beacon_node

# jq is used by run.sh to render per-validator proposer config files.
USER root
RUN apt-get update && apt-get install -y --no-install-recommends jq && rm -rf /var/lib/apt/lists/*
USER user

ENTRYPOINT ["/home/user/data/run.sh"]
