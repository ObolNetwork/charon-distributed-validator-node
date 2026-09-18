ARG VERSION

FROM ghcr.io/jqlang/jq:1.8.0 AS jq

FROM offchainlabs/prysm-validator:${VERSION}

# jq is used by run.sh to render Prysm's proposer settings from the charon-generated config.
COPY --from=jq /jq /usr/local/bin/jq
