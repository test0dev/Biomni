# Biomni MCP runtime image: FROM base (conda/E1 already installed), overlay app + entrypoint.
# Build via: bash platform/docker/build.sh
ARG BASE_IMAGE=biomni-base:latest
FROM ${BASE_IMAGE}

# Full application tree (base already has biomni_env/platform/biomni; this refreshes code).
COPY app /app

ENV CONDA_PREFIX=/opt/conda/envs/biomni_e1 \
    PATH=/opt/conda/envs/biomni_e1/bin:/app/platform/biomni_tools/bin:/opt/conda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PYTHONPATH=/app/platform:/app \
    PYTHONUNBUFFERED=1 \
    BIOMNI_DATA_LAKE_PATH=/data \
    BIOMNI_MCP_DATA_PATH=/app/tmp/mcp_runtime \
    MCP_TRANSPORT=http \
    MCP_HOST=0.0.0.0 \
    MCP_PORT=8000 \
    HOME=/app/tmp/home \
    TMPDIR=/app/tmp/tmp \
    XDG_CACHE_HOME=/app/tmp/cache

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && mkdir -p /app/tmp \
    && ln -sfn /opt/conda/envs/biomni_e1/bin/python /usr/local/bin/python \
    && ln -sfn /opt/conda/envs/biomni_e1/bin/python3 /usr/local/bin/python3

WORKDIR /app
EXPOSE 8000
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
