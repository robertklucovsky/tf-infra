---
scope: project
applies_in_modes: all
updated: 2026-07-17 05:44 CEST
---

# Decisions with Why — infra rozhodnutia + dôvody

> Vivid anchor: prečo platforma vyzerá tak ako vyzerá. Tu žije "prečo", nie "ako".

## Rozhodnutia (init seed)

- **`pg` backend na zdieľanom CNPG (default):** state použiteľný z hociktorého stroja
  s network prístupom, natívny state locking. Connection string out-of-band (`PG_CONN_STR`).
- **Dočasný `local` backend pri teardowne:** aby `terraform destroy` nezávisel od Postgresu,
  ktorý sám ničí (inak by si pílil konár pod sebou). Obnoviť pg backend pri re-apply.
- **Project-agnostic platforma pre OIDC:** platforma beží MinIO + Keycloak a publikuje
  `minio-admin` Secret; tenant si vlastní celé wiring → onboard tenanta needituje platform repo.
- **Role-based MinIO OIDC per tenant:** MinIO dovoľuje len 1 claim-based provider → každý
  tenant je role-based (jeden `role_policy` pre celý realm). Vedomý trade-off za multi-tenant.
- **Platforma NEnastavuje `MINIO_IDENTITY_OPENID_*` env:** env-set kľúče locknú API override;
  provider registrácia musí ísť cez runtime admin API (`minio_iam_idp_openid`).
- **Nexus provider `timeout=60`:** tolerancia pomalých plan-time refresh GET-ov na LAN/API
  (inak "context deadline exceeded" zhodí celý plan).
- **SonarQube default OFF** (`sonarqube_enabled=false`): voliteľná, ťažká služba.

## Rozhodnutia (2026-07-16 — security remediation + DGX)

- **Split-gateway namiesto source-IP filtra:** terminujúca gateway kvôli TLS-passthrough nevidí
  zdrojovú IP → per-route IP ACL nefunguje. Preto **nová verejná gateway na `.12`** (len 3 hosty) +
  router repoint; interné appky ostanú len na `.11`. Robustné, nezávislé od NAT.
- **Postgres hostssl vynútené (nie len sslmode=require):** operátor chcel server-side enforcement,
  nie len šifrovanie klienta. Cena: všetci konzumenti + tenanti musia na TLS naraz.
- **Host firewall na node zámerne VYNECHANÝ:** raw nft/ufw na Cilium node = konflikt s iptables +
  riziko lockout. Cieľ (VPN→node containment) pokrytý sieťovým Omada ACL namiesto toho.
- **Žiadna rotácia secrets / prepis histórie:** overené že `terraform.tfvars` v gite obsahoval len
  placeholdery (nie reálne secrets — tie sú v gitignored `secrets.auto.tfvars`). Rotácia by pridala
  riziko bez benefitu.
- **`dev/` → `tf/`:** názov `dev` navádzal na dev prostredie, pričom je to prod platforma.
- **DGX segregácia: MAAS DHCP-relay (nie ER605 DHCP):** MAAS ostáva jediný IPAM/DNS zdroj pravdy;
  izolácia zachovaná (relay je gateway-sourced, nie DGX→MAAS priamo). DGX = verejné DNS, registrované
  v MAAS ako devices. Blanket network-isolation odmietnutá (rozbila by OpenStack↔Ceph po zapnutí) —
  namiesto toho ACL deny VPN/DGX→cloud.

## Loci

_(Seed z init — ADR-style loci s plným kontextom sa pridajú podľa potreby.)_

Source pointery: `tf/main.tf`, `tf/nexus.tf`, `tf/minio.tf`, `tf/sonarqube.tf`, `README.md`, git log.
