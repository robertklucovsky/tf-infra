# -----------------------------------------------------------------------------
# NEXUS NPM REPOSITORIES
#
# Self-hosted npm registry for the FATTO monorepo packages (@fatto-erp/*).
#   - npm-proxy  : caches public packages from registry.npmjs.org
#   - npm-hosted : holds the org's own @fatto-erp/* packages
#   - npm-group  : single endpoint combining hosted + proxy
#
# Publishers publish to npm-hosted; consumers install from npm-group.
# -----------------------------------------------------------------------------

resource "nexus_repository_npm_proxy" "npmjs" {
  name   = "npm-proxy"
  online = true

  storage {
    blob_store_name                = "default"
    strict_content_type_validation = true
  }

  proxy {
    remote_url = "https://registry.npmjs.org/"
  }

  negative_cache {
    enabled = true
    ttl     = 1440
  }

  http_client {
    blocked    = false
    auto_block = true
  }
}

resource "nexus_repository_npm_hosted" "internal" {
  name   = "npm-hosted"
  online = true

  storage {
    blob_store_name                = "default"
    strict_content_type_validation = true
    # ALLOW (not ALLOW_ONCE) so CI can republish the same version in dev.
    write_policy = "ALLOW"
  }
}

resource "nexus_repository_npm_group" "group" {
  name   = "npm-group"
  online = true

  storage {
    blob_store_name = "default"
  }

  group {
    member_names = [
      nexus_repository_npm_hosted.internal.name,
      nexus_repository_npm_proxy.npmjs.name,
    ]
  }
}
