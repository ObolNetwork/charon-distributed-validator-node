FROM gcr.io/prysmaticlabs/prysm/validator:HEAD-55a29a as prysm-validator

FROM debian:buster-slim
COPY --from=prysm-validator /app/cmd/validator/validator validator

ENTRYPOINT [ "/home/prysm/run.sh" ]