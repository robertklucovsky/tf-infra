# -----------------------------------------------------------------------------
# DNS RECORDS (DigitalOcean, klucovsky.com zone)
#
# Most host records in the zone were created manually in the DO panel and are
# NOT managed here (yet). New records go here so they live as code.
# -----------------------------------------------------------------------------

# SSO shortcut for the FATTO-AAC storage console: browsers hitting this name
# are 302-redirected straight into the RustFS OIDC authorize flow (see
# routes-platform.tf), skipping the console login page's SSO button.
resource "digitalocean_record" "fatto_aac_sso" {
  domain = "klucovsky.com"
  type   = "CNAME"
  name   = "fatto-aac"
  value  = "cwwk.klucovsky.com."
  ttl    = 300
}
