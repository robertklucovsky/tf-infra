# Bezpečnostné hodnotenie rizík — domáci lab

**Dátum:** 2026-07-14
**Rozsah:** dva prístupové scenáre cez perimeter ER605 (bez WireGuardu / s WireGuardom)
**Stav prostredia k dátumu:** živý len `cwwk` + MAAS/Omada box (`172.16.1.2`) + switche; OpenStack/Ceph/Juju cluster vypnutý
**Spec:** `docs/superpowers/specs/2026-07-14-home-lab-security-assessment-design.md`

## Konvencie

- **Značky dôkazov:** `[overené]` = potvrdené počas tohto hodnotenia (Omada read-only API, SSH na `cwwk`, TCP connect testy); `[predpoklad]` = nepotvrdené, uvedené s tým, čo by to overilo.
- **Škála závažnosti:** `Kritická` > `Vysoká` > `Stredná` > `Nízka`. Závažnosť = pravdepodobnosť × dopad.
- Každé zistenie má formát: **popis → útočná cesta → dopad → závažnosť → odporúčanie**, a stabilné ID (napr. `S2-02`).

## 1. Zhrnutie pre vedenie (Executive summary)

_(vypĺňa sa naposledy)_

## 2. Overený stav prostredia (baseline)

Táto kapitola zhŕňa overenú fakticitu, z ktorej vychádzajú obidva scenáre (kapitoly 3 a 4). Zdroje: read-only API Omada kontroléra (`172.16.1.2:8043`), read-only SSH na `cwwk` a TCP connect testy z uzla. Pokiaľ nie je uvedené inak, každé tvrdenie je `[overené]`.

### Aktuálny prevádzkový stav

Lab je momentálne zmenšenou verziou väčšieho súkromného cloudu, ktorý je vypnutý. Živé sú len tri komponenty: uzol `cwwk` (`172.16.1.11`), kombinovaný box MAAS/Omada (`172.16.1.2`) a Omadou spravované switche `[overené]`. Vypnutý je OpenStack/Ceph/Juju klaster — 9 serverov (6× HP ProLiant DL3xx a 3 neznačkové kusy), spolu s 10G switchom a 40G switchom, ktorý navyše nie je spravovaný Omada kontrolérom (preto v ňom nefiguruje) `[overené]`. Dôsledkom je, že VLAN 10 (OpenStack) a VLAN 20 (Ceph) momentálne nemajú žiadne živé hosty — sú routované a nefiltrované konfiguráciou, ale aktuálne prázdne `[overené]`. Táto správa preto dôsledne rozlišuje **aktuálny stav** rizika (čo je dnes živé a dosiahnuteľné) od **latentného/navrhnutého stavu** (blast radius, ktorý sa vráti pri opätovnom zapnutí celého cloudu); nálezy o plochej sieti bez ACL platia pre oba stavy, líši sa len počet vystavených hostov.

### Perimeter (ER605 `172.16.1.1`, firmware 2.3.3)

Router beží na firmware 2.3.3, WAN1 má verejnú IPv4 cez DHCP a IPv6 na WAN je vypnuté `[overené]`. Celý inbound povrch z internetu tvorí port-forwarding len dvoch pravidiel: TCP **80** → `172.16.1.11:80` a TCP **443** → `172.16.1.11:443`; žiadne iné pravidlo, žiadny DMZ, žiadny one-to-one NAT `[overené]`.

### WireGuard (Site-to-Site „RACK" na ER605)

Vzdialený prístup zabezpečuje WireGuard bežiaci na ER605 ako Site-to-Site VPN s názvom „RACK", počúvajúci na **UDP 51820** priamo na WAN rozhraní routra (bez potreby port-forwardu, preto sa `51820` v NAT tabuľke nenachádza) `[overené]`. Tunelová podsieť je `10.172.16.0/24` s routrom na `.1`; existujú traja peer-i, každý pripnutý na `/32`: MacBook (`10.172.16.2`), Motorola (`10.172.16.3`) a MacBookProM5 (`10.172.16.4`), s roamingom (bez statického endpointu) — ide o osobné zariadenia koncových používateľov `[overené]`. Zariadenie hlási `serverClientWireguard=false`; road-warrior prístup je teda realizovaný cez site-to-site funkciu s per-klient `/32` peer-mi, nie cez natívny WireGuard server mód `[overené]`.

### VLAN/segmentácia

Sieť je rozdelená na tri VLAN, všetky s `isolation=false`: VLAN 1 „Default" (`172.16.1.0/24`, uzol k8s, MAAS/Omada, switche), VLAN 10 „OpenStack VLAN" (`172.16.2.0/24`) a VLAN 20 „Ceph VLAN" (`172.16.3.0/24`) `[overené]`. Gateway ACL je vypnuté a obsahuje 0 pravidiel — bez akéhokoľvek inter-VLAN filtrovania je sieť plochá a voľne routovaná medzi všetkými tromi podsieťami `[overené]`. DHCP na routri je na všetkých VLAN vypnuté, DHCP aj DNS rieši MAAS `[overené]`.

### Reach WireGuard klienta (východisko pre scenár 2)

Per-peer `/32` „Allowed Address" nastavené na routri obmedzuje len zdrojovú IP daného klienta v tuneli; **nijako neobmedzuje ciele** v LAN. Pri vypnutom ACL a plochej routovanej sieti tak autorizovaný WireGuard klient dosiahne **všetky tri podsiete na všetkých portoch** — celý lab. Jediným obmedzením je vlastný client-side `AllowedIPs` klienta, ktorý router žiadnym spôsobom nevynucuje `[overené]`.

### Node `cwwk` (`172.16.1.11`)

Uzol beží na Ubuntu 24.04 (kernel 6.8), provisioning cez cloud-init/MAAS, s Canonical Kubernetes (`k8s-snap`) využívajúcim Cilium (eBPF, náhrada kube-proxy) a MetalLB `[overené]`. Na uzle nebeží žiadny host firewall — `ufw` je `inactive` a politika reťazca iptables `INPUT` je `ACCEPT` `[overené]`. DNS rozlišuje cez `172.16.1.2` (MAAS) a `8.8.8.8`, s vyhľadávacími doménami `klucovsky.com` a `fatto.online` `[overené]`.

**Otvorené z LAN/VPN na node (overené TCP connectom):** `22` (SSH), `6443` (k8s API), `10250` (kubelet), `2379`/`2380` (etcd), `9100` (node_exporter), `4244` (Hubble), `2049` (NFS) a `111` (rpcbind); ďalej NodePorty `30432` — **PostgreSQL v plaintexte (`sslmode=disable`)**, `30910`/`30911` (RustFS, S3/konzola) a `30417`/`30418` (Tempo OTLP) `[overené]`.

**Autentifikácia control-plane (overené):** hoci sú vyššie uvedené komponenty control-plane sieťovo dosiahnuteľné, každý z nich vynucuje autentifikáciu — anonymný pokus o čítanie secrets na k8s API `6443` vracia `401 Unauthorized`; anonymný prístup na kubelet `10250` vracia `Unauthorized`; etcd na `2379` bez klientskeho certifikátu neodpovedá vôbec (vynucuje mTLS) `[overené]`. Komponenty sú teda sieťovo dosiahnuteľné, ale nie sú okamžite prevziateľné bez ďalšieho kompromisu.

### NFS

Adresár `/data` je exportovaný na obe podsiete `10.172.16.0/24` (WireGuard tunel) aj `172.16.1.0/24` (LAN), s options `rw, sync, no_subtree_check, root_squash, all_squash (anonuid/anongid=1000), sec=sys, insecure` `[overené: exportfs -v]`. Ktokoľvek z LAN alebo VPN teda môže exportovaný zväzok mountnúť a čítať/zapisovať dáta pod uid 1000; `root_squash` a `all_squash` bránia priamej ceste k root/priv-esc, ale nie čítaniu ani zápisu dát.

### `172.16.1.2` (kombinovaný box MAAS + Omada)

Jeden box koncentruje MAAS (DNS `53`, API `5240`, HTTPS `5443`, proxy `3128`) aj Omada kontrolér (`8043`), plus SSH `22` `[overené]`. MAAS ovláda bare-metal provisioning (PXE, re-image, commissioning) a typicky aj napájanie cez BMC/IPMI; Omada je sieťová kontrolná rovina (spravuje ER605 a switche). Táto koncentrácia rolí na jednom hostiteľovi je popísaná ako prierezové zistenie `C-02` v kapitole 5.

### Switche

Manažment rozhrania switchov sú dosiahnuteľné z LAN/VPN: SX3016F (`172.16.1.24`), TL-SG2428P (`172.16.1.23`) a SG3210X-M2 (`172.16.1.25`) `[overené]`.

### Vystavené aplikácie (cez in-cluster Cilium Gateway)

TLS je terminovaný priamo v clustri (wildcard certifikát `*.klucovsky.com`, Let's Encrypt produkčný), router forwarduje na uzol len TCP 80/443 `[overené]`. Vystavené hostname → backend: argocd, db (pgadmin), nexus, alertmanager, grafana, prometheus, registry (zot), auth (keycloak, beží v móde `start-dev`), mail (mailpit), s3 (rustfs) a fatto-aac (302 redirect) `[overené]`. Z hľadiska autentifikácie: SSO cez Keycloak platí len pre RustFS; ArgoCD, Grafana, pgAdmin, Nexus a Zot majú standalone autentifikáciu; Mailpit, Prometheus a Alertmanager **bez akejkoľvek autentifikácie**. Autentifikačné správanie jednotlivých aplikácií vychádza z konfigurácie v repozitári a je `[predpoklad]` — malo by sa potvrdiť priamo pri aplikáciách s vysokým dopadom (viď kapitola 3).

## 3. Scenár 1 — bez WireGuardu (z internetu)

## 4. Scenár 2 — autorizovaný WireGuard klient (+ kompromitovaný klient)

## 5. Prierezové zistenia

## 6. Prioritizované odporúčania

## Príloha A — Autentifikačná matica vystavených služieb

## Príloha B — Hardening checklist (CIS-style)
