ARG VERSION

FROM ghcr.io/jqlang/jq:1.8.0 AS jq

FROM consensys/teku:${VERSION}

# jq is used by run.sh to render Teku's proposer config from the charon-generated one.
COPY --from=jq /jq /usr/local/bin/jq
