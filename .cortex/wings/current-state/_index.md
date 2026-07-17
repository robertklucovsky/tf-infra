---
scope: project
applies_in_modes: all
updated: 2026-07-17 05:44 CEST
---

# Current State — kde sme teraz

> Vivid anchor: platforma beží na homelab K8s (172.16.1.11). Po veľkej **bezpečnostnej
> remediácii** (2026-07-16, merged do main): internet vidí len s3/auth/fatto-aac cez novú
> verejnú gateway na **172.16.1.12**, zvyšok je intranet-only. Root modul sa presunul
> `dev/` → **`tf/`**.

## Loci

_(Detaily v `working-memory/robert-klucovsky/2026-07-16.md`. Promotnú sa pri ďalšej konsolidácii.)_

## Snapshot (2026-07-17)

- **Fáza:** bezpečnostne zahardenená platforma; segregácia NVIDIA DGX Spark rozpracovaná.
- **Root modul:** `tf/` (bol `dev/`, premenované 2026-07-16 — "prod, nie dev"). Backend stále
  `backend "local"` v `tf/main.tf` (teardown-era; pg backend zakomentovaný).
- **Ingress:** split — verejná gateway `172.16.1.12` (`tf/gateway-public.tf`, len s3/auth/fatto-aac,
  router forward .11→.12); interná cesta `.11`→relay→`.13` (všetky hosty, cez MAAS DNS). Split-horizon DNS.
- **Zahardenené:** Keycloak `start` (prod); Postgres **hostssl** (server odmieta plaintext, konzumenti
  `sslmode=require`); Omada gateway ACL deny VPN→node-mgmt(2379/10250/9100) a VPN→cloud(172.16.2/3.0/24);
  NFS `/data` len peer /32 + `secure`; `terraform.tfvars` odsledovaný z gitu.
- **Storage:** MinIO nahradené **RustFS** (s3.klucovsky.com, single-disk xl-single). Po odstávke krehké
  (viď risks-and-watchouts). Beží.
- **Vypnuté:** OpenStack (VLAN 10) / Ceph (VLAN 20) cloud — 9 serverov mimo prevádzky, VLAN prázdne.
- **Otvorené:** DGX segregácia (VLAN 40, MAAS DHCP-relay — čaká na switch/port DGX); B2 ACL peer-test;
  GitLab tenant (stále neplánovaný ako `.tf`).

Source pointery: `tf/main.tf`, `tf/gateway-public.tf`, `docs/security/2026-07-14-home-lab-risk-assessment.md`, git log @ c53ae6a.
