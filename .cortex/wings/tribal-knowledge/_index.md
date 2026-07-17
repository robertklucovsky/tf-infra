---
scope: project
applies_in_modes: all
updated: 2026-07-17 05:44 CEST
---

# Tribal Knowledge — operačné know-how

> Vivid anchor: "ako to reálne spustiť" — príkazy a triky, čo nie sú v kóde.

## Know-how

- **Apply (z `tf/`, od 2026-07-16 sslmode=require):**
  ```bash
  cd tf
  export PG_CONN_STR="postgres://postgres:<password>@172.16.1.11:30432/postgres?sslmode=require"
  terraform init && terraform apply
  ```
  Postgres teraz vynucuje TLS (hostssl) — `sslmode=disable` je odmietnutý.
- **Z iného stroja:** clone, dodaj `terraform.tfvars` + `secrets.auto.tfvars` (gitignored), kubeconfig
  context `k8s`, network na `172.16.1.11:30432` + `*.klucovsky.com`. Reálne secrets sú v `secrets.auto.tfvars`.
- **Omada API (read + write, na LAN):** base `https://172.16.1.2:8043/{omadacId}/api/v2`,
  `omadacId=911e6d163a1e7e9e20ae3728e4ae7cc3`, site `67fe23d9da5d1c5ac5a98a71`. Login `POST /api/v2/login`
  `{username,password}` → token; ďalej header `Csrf-Token: <token>` + session cookie. Self-signed cert (`-k`).
  Užitočné endpointy: `setting/transmission/portForwardings` (NAT), `setting/firewall/acls?type=0` (gateway ACL,
  policy 0=Deny/1=Permit, sourceType/destType 0=NETWORK/1=IP_GROUP/2=IP_PORT_GROUP, protocols [256]=All),
  `setting/profiles/groups` (IP a IP-Port groups). Schémy sa dajú vytiahnuť z frontend JS chunkov (`js_su_configJson`).
- **Ingress architektúra (od 2026-07-16):** verejná gateway `172.16.1.12` (`tf/gateway-public.tf`) terminuje TLS
  priamo na svojej MetalLB IP (netreba passthrough+relay). Interná cesta `.11`→relay→`.13` (všetky hosty).
  Router forwarduje 80/443 na `.12`; interní klienti idú cez MAAS DNS na `.11`.
- **rawfile CSI (RustFS/PVC disk.img):** host path `/var/snap/k8s/common/rawfile-storage/pvc-*/disk.img`
  (v CSI kontajneri = `/data`). `losetup -a` na hoste ukáže loop→disk.img (path je z pohľadu CSI kontajnera).
- **Kubeconfig:** context `k8s`. **macOS nemá `timeout`** — pre TCP testy použi `nc -z -G <sec>`.

## Loci

_(Konsolidované z WM 2026-07-16.)_

Source pointery: `README.md`, `tf/main.tf`, `tf/gateway-public.tf`, `working-memory/robert-klucovsky/2026-07-16.md`.
