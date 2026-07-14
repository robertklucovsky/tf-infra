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

Útočník na internete, ktorý nepozná WireGuard kľúče a nemá prístup do tunela, dosiahne z celého laboratória iba to, čo router explicitne forwarduje: **TCP 80/443 do in-cluster Cilium/Envoy gateway** (a teda všetky aplikácie na `*.klucovsky.com`, s TLS terminovaným v clustri) a **UDP 51820** WireGuard listener priamo na routri `[overené]`. Žiadna databáza, SSH, NodePort ani etcd nie je z internetu dosiahnuteľný — port-forwarding obsahuje výhradne pravidlá pre 80 a 443 `[overené]`. Nasledujúce zistenia sa týkajú toho, čo je dosiahnuteľné práve cez tento zúžený povrch.

**S1-01 — Vysoká — Neautentifikované vystavené UI (Prometheus, Alertmanager, Mailpit).** Popis: Prometheus, Alertmanager a Mailpit sú vystavené na internete bez akejkoľvek autentifikácie. Útočná cesta: útočník, ktorý pozná hostname, jednoducho otvorí `prometheus/alertmanager/mail.klucovsky.com` a získa prístup bez prihlásenia. Dopad: Prometheus a Alertmanager odhaľujú internú topológiu, monitorovacie targets a metriky (potenciálne aj citlivé labely); Mailpit vystavuje zachytené e-maily vrátane reset-tokenov a interných správ; Alertmanager sa navyše dá zneužiť na potlačenie upozornení (silences), čím útočník môže maskovať vlastnú aktivitu. Závažnosť: **Vysoká**. Odporúčanie: dať tieto UI za forward-auth (napr. oauth2-proxy/Keycloak) alebo ich vystaviť len cez VPN; ideálne ich z internetu úplne odstrániť.

**S1-02 — Vysoká (pgAdmin, ArgoCD) / Stredná (ostatné) — Standalone login-y vystavené brute-force/cred-stuffing.** Popis: ArgoCD, Grafana, pgAdmin, Nexus a Zot majú vlastné (standalone) prihlasovacie stránky priamo na internete, bez WAF, MFA či rate-limitu pred nimi. Útočná cesta: priamy útok na prihlasovaciu stránku hocijakej z týchto aplikácií. Dopad: pgAdmin poskytuje správu databázy a ArgoCD umožňuje deploy do klastra — pri prelomení hesla je teda dopad pre tieto dve aplikácie vysoký; pri ostatných (Grafana, Nexus, Zot) je dopad stredný. Závažnosť: **Vysoká** (pgAdmin, ArgoCD) / **Stredná** (ostatné). Odporúčanie: nasadiť forward-auth/SSO alebo obmedziť administrátorské nástroje len na VPN; vynútiť MFA a silné heslá.

**S1-03 — Vysoká — Keycloak beží v `start-dev` a je vystavený na internete.** Popis: `auth.klucovsky.com` beží v dev móde. Útočná cesta: priamy prístup na verejne dostupný IdP bežiaci v neprodukčnej konfigurácii. Dopad: dev mód vypína produkčné hardeningové mechanizmy (povolené HTTP, voľnejšie nastavenia hostname/cache), čo je nevhodné pre exponovaný identity provider, ktorý chráni prístup k RustFS. Závažnosť: **Vysoká**. Odporúčanie: prejsť na produkčný mód (`build`+`start`, `KC_HOSTNAME` v strict móde, len HTTPS) a skryť administrátorskú konzolu.

**S1-04 — Stredná — CVE povrch vystavených verzií (vrátane beta).** Popis: verejne dostupné sú aj verzie softvéru, ktoré nemusia byť produkčne vyzreté, napríklad RustFS `1.0.0-beta.8`, Keycloak `26.6.4`, Nexus, Zot a Grafana. Útočná cesta: exploatácia známej alebo neznámej zraniteľnosti vo vystavenej verzii. Dopad: beta alebo nepatchnutý softvér vystavený na internete predstavuje riziko zneužitia známych zraniteľností. Závažnosť: **Stredná**. Odporúčanie: zaviesť pravidelný patch cadence, sledovať CVE pre používané verzie a nevystavovať beta služby verejne. Konkrétne CVE identifikátory nie sú súčasťou tohto hodnotenia — `[predpoklad]`, doplniť pri revízii jednotlivých verzií.

**S1-05 — Nízka — TCP 80 otvorené (redirect na 443) + chýbajúce HSTS.** Popis: port 80 je otvorený a presmerováva na 443, no chýba HSTS hlavička. Dopad: minimálny, ale vytvára priestor pre SSL-strip útok pri prvom kontakte klienta. Závažnosť: **Nízka**. Odporúčanie: nasadiť HSTS s preload, prípadne vystaviť len port 443.

**S1-06 — Nízka/Info — UDP 51820 WireGuard na WAN.** Popis: WireGuard listener je počúvajúci priamo na WAN rozhraní routra. Toto je *správna* kontrola — WireGuard je voči neautentifikovaným sondám tichý (nereaguje) a používa silnú kryptografiu. Závažnosť: **Nízka/Info**. Odporúčanie: udržiavať firmware ER605 patchnutý; prípadne zvážiť zmenu portu ako security-by-obscurity opatrenie s nízkou hodnotou.

**S1-07 — Stredná — Vystavený OIDC/SSO povrch (`auth`, `fatto-aac` redirect).** Popis: OIDC flow pre RustFS a redirect endpoint `fatto-aac` sú verejne dostupné. Útočná cesta: interakcia s OIDC/SSO tokom cez tieto verejné endpointy. Dopad: ide o štandardný a očakávaný povrch OIDC flow, ale rozširuje celkovú expozíciu Keycloaku (viď S1-03). Závažnosť: **Stredná**. Odporúčanie: obmedziť redirect URI na nevyhnutné hodnoty a monitorovať tento tok.

## 4. Scenár 2 — autorizovaný WireGuard klient (+ kompromitovaný klient)

## 5. Prierezové zistenia

## 6. Prioritizované odporúčania

## Príloha A — Autentifikačná matica vystavených služieb

## Príloha B — Hardening checklist (CIS-style)
