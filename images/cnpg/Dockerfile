# Custom CloudNativePG operand image: stock PG17 + pgvector + Apache AGE.
# Keep the "17" tag prefix when publishing — the CNPG operator parses the
# PG major version from the image tag.
ARG BASE=ghcr.io/cloudnative-pg/postgresql:17-bookworm

# ---- builder: compile Apache AGE from source (no apt package exists) --------
FROM ${BASE} AS builder
USER root
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      build-essential git flex bison postgresql-server-dev-17; \
    rm -rf /var/lib/apt/lists/*
ARG AGE_REF=release/PG17/1.7.0
RUN set -eux; \
    git clone --depth 1 --branch "${AGE_REF}" https://github.com/apache/age.git /tmp/age; \
    cd /tmp/age; \
    make PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config; \
    make PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config install

# ---- final: stock base + pgvector (apt) + AGE artifacts (copied) ------------
FROM ${BASE}
USER root
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends postgresql-17-pgvector; \
    rm -rf /var/lib/apt/lists/*
COPY --from=builder /usr/lib/postgresql/17/lib/age.so \
                    /usr/lib/postgresql/17/lib/age.so
COPY --from=builder /usr/share/postgresql/17/extension/age.control \
                    /usr/share/postgresql/17/extension/age.control
COPY --from=builder /usr/share/postgresql/17/extension/age--*.sql \
                    /usr/share/postgresql/17/extension/
# Restore the non-root operand user used by the base image.
USER 26
