# biomni-arm MCP pod image (linux/arm64).
# Build via: bash platform/docker/build.sh
# Expects build context prepared by build.sh (env tarball + app tree).
FROM nvidia/cuda:12.6.0-base-ubuntu22.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        tini \
    && rm -rf /var/lib/apt/lists/*

# Conda env packed from host biomni_e1 (cu130 torch + deps).
COPY biomni_e1.tar.gz /tmp/biomni_e1.tar.gz
RUN mkdir -p /opt/conda/envs/biomni_e1 \
    && tar -xzf /tmp/biomni_e1.tar.gz -C /opt/conda/envs/biomni_e1 \
    && rm -f /tmp/biomni_e1.tar.gz \
    && /opt/conda/envs/biomni_e1/bin/python /opt/conda/envs/biomni_e1/bin/conda-unpack \
    && ln -sf /opt/conda/envs/biomni_e1/bin/python /usr/local/bin/python \
    && ln -sf /opt/conda/envs/biomni_e1/bin/python3 /usr/local/bin/python3

# biomni-arm source + platform tools (CLI binaries under platform/biomni_tools).
COPY app /app

ENV CONDA_PREFIX=/opt/conda/envs/biomni_e1 \
    PATH=/opt/conda/envs/biomni_e1/bin:/app/platform/biomni_tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
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
    && mkdir -p /app/tmp

WORKDIR /app
EXPOSE 8000
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
