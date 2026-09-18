ARG VERSION

FROM sigp/lighthouse:${VERSION}

# jq is used by run.sh to render the validator definitions from the charon proposer config.
RUN apt-get update && apt-get install -y --no-install-recommends jq && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/opt/lighthouse/run.sh"]
