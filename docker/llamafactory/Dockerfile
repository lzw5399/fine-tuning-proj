ARG LLAMAFACTORY_BASE_IMAGE=hiyouga/llamafactory@sha256:cde9745570861693a8a0e7da6aa1a1fadde7c728b8ceeb189191ddc3a3a8d3f3
FROM ${LLAMAFACTORY_BASE_IMAGE}

ARG BITSANDBYTES_VERSION=0.49.2
RUN pip install --no-cache-dir "bitsandbytes==${BITSANDBYTES_VERSION}"

WORKDIR /app

CMD ["llamafactory-cli", "webui"]
