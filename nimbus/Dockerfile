ARG VERSION

FROM statusim/nimbus-eth2:${VERSION} AS nimbusbn

FROM statusim/nimbus-validator-client:${VERSION}

COPY --from=nimbusbn /home/user/nimbus_beacon_node /home/user/nimbus_beacon_node

ENTRYPOINT ["/home/user/data/run.sh"]
