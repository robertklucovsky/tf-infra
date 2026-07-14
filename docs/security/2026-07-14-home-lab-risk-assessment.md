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

Autorizovaný peer po pripojení do tunela získava **plnú L3 konektivitu na `172.16.1.0/24`** a na (routovateľné, ale momentálne prázdne) `172.16.2.0/24` a `172.16.3.0/24`, na všetkých portoch, vrátane NFS `/data` `[overené]`. **Súčasný blast radius** zodpovedá živým komponentom: `cwwk` + kombinovaný MAAS/Omada box + switche. **Latentný blast radius** je celý súkromný cloud, ktorý sa stane dosiahnuteľným po opätovnom zapnutí. Sub-prípad **kompromitovaného klienta** — ukradnutý notebook alebo telefón, prípadne unesený WireGuard peer kľúč — dáva útočníkovi rovnaký dosah ako legitímnemu peerovi, len s nepriateľským zámerom; keďže peery sú osobné roaming zariadenia bez ďalšej segmentácie, ide o reálny a nie hypotetický vektor.

**S2-01 — Kritická — Žiadna segmentácia medzi VPN klientom a infraštruktúrou.** Popis: sieť je plochá a gateway ACL je vypnuté. Útočná cesta: ktorýkoľvek autorizovaný (alebo kompromitovaný) peer dosiahne bez akéhokoľvek ďalšieho filtrovania všetko. Dopad: jediné kompromitované osobné zariadenie znamená plný L3 prístup na celý lab. Závažnosť: **Kritická**. Odporúčanie: gateway ACL „VPN → len potrebné služby/porty" s princípom default-deny; zapnúť inter-VLAN isolation.

**S2-02 — Vysoká — Zbytočne vystavený k8s control-plane (autentifikovaný).** Popis: `6443` (API), `10250` (kubelet) a **`2379` (etcd)** sú dosiahnuteľné z VPN `[overené]`; každý komponent však vynucuje autentifikáciu — API vracia `401`, kubelet `Unauthorized`, etcd vynucuje mTLS `[overené]`. Dopad: nejde o okamžité prevzatie, ale o zbytočne rozšírený útočný povrch — priestor pre CVE v control-plane komponentoch, brute-force/credential útoky, pričom bezpečnosť etcd v konečnom dôsledku stojí na ochrane klientskych certifikátov, čo v rámci tohto engagementu nebolo nezávisle overené (`[predpoklad]`); kompromitácia ktoréhokoľvek z týchto komponentov znamená plné prevzatie klastra. Závažnosť: **Vysoká**. Odporúčanie: nasadiť host firewall — etcd a kubelet viazať len na loopback/interné rozhranie; k8s API obmedziť na potrebné zdrojové adresy.

**S2-03 — Kritická — MAAS + Omada box (`172.16.1.2`) dosiahnuteľný z VPN.** Popis: box koncentruje MAAS (`5240/5443`, provisioning/BMC), Omada (`8043`), DNS (`53`) a proxy (`3128`), všetko dosiahnuteľné z tunela. Útočná cesta: priamy prístup k administrácii provisioningu a siete cez VPN. Dopad: MAAS ovláda PXE/re-image/BMC power, čo umožňuje prevzatie fyzických serverov; Omada je kontrola siete (firewall/VLAN/port-forward pravidlá); ďalej hrozí DNS/DHCP poisoning. Kompromitácia jedného boxu tak znamená kontrolu nad provisioningom aj nad sieťou naraz. Závažnosť: **Kritická**. Odporúčanie: obmedziť administrátorský prístup len na mgmt zdroje, oddeliť role MAAS a Omada, vynútiť silné poverenia a MFA, udržiavať patch cadence; nasadiť ACL blokujúce VPN → mgmt s výnimkou pre explicitne určených administrátorov.

**S2-04 — Vysoká — PostgreSQL v plaintexte na NodePort `30432` (`sslmode=disable`).** Popis: databáza počúva na NodePort `30432` bez TLS. Útočná cesta: priame TCP spojenie z VPN. Dopad: možnosť odpočúvania poverení na trase aj priameho útoku na databázu; databáza uchováva Terraform state (vrátane superuser poverení) a tenantské dáta. Závažnosť: **Vysoká**. Odporúčanie: zapnúť TLS; NodePort `30432` neexponovať do VPN (firewall/bind); rotovať superuser heslo.

**S2-05 — Vysoká — NFS `/data` exportované na čítanie aj zápis na VPN podsieť.** Popis: export `/data` zahŕňa aj tunelovú podsieť. Útočná cesta: `mount -t nfs 172.16.1.11:/data` z ktoréhokoľvek peera `[overené: exportfs -v — rw, insecure na `10.172.16.0/24`]`. Dopad: čítanie **aj zápis** dát pod uid 1000; `root_squash` a `all_squash` bránia priamej ceste k root/priv-esc, avšak účinnosť tejto ochrany proti sofistikovanejším technikám nebola v rámci tohto hodnotenia nezávisle penetračne overená (`[predpoklad]`) — dáta samotné sú v každom prípade plne čitateľné a modifikovateľné (dopad na integritu/dôvernosť). Závažnosť: **Vysoká**. Odporúčanie: zúžiť export (odstrániť `10.172.16.0/24` alebo povoliť len konkrétne hosty), použiť `ro` tam, kde to postačuje, zvážiť `sec=krb5`.

**S2-06 — Stredná — Ďalšie NodePorty: RustFS `30910/30911`, Tempo `30417/30418`.** Popis: tieto NodePorty sú dosiahnuteľné z VPN. Dopad: prístup k object-store admin rozhraniu/API a k tracing dátam. Závažnosť: **Stredná**. Odporúčanie: obmedziť zdrojové adresy firewallom; vynútiť autentifikáciu na RustFS admin rozhraní.

**S2-07 — Stredná/Nízka — Info-disclosure služby: node_exporter `9100`, Hubble `4244`, rpcbind `111`.** Popis: tieto porty vystavujú interné informácie bez ďalšej ochrany. Dopad: únik interných metrík, topológie a network flow dát, možnosť enumerácie cez RPC. Závažnosť: **Stredná/Nízka**. Odporúčanie: viazať tieto služby na interné rozhranie alebo ich obmedziť firewallom.

**S2-08 — Vysoká — Management roviny switchov a Omada dosiahnuteľné z VPN.** Popis: manažment rozhrania switchov (`172.16.1.23/24/25`) aj Omada kontrolér (`8043`) sú dosiahnuteľné z tunela. Dopad: prekonfigurácia siete, VLAN alebo port mirroringu môže viesť k prevzatiu celej siete. Závažnosť: **Vysoká**. Odporúčanie: oddeliť mgmt VLAN od VPN; nasadiť ACL s politikou default-deny na mgmt rozhrania.

**S2-09 — Stredná teraz / Kritická latentne — Blast radius po zapnutí cloudu.** Popis: po opätovnom zapnutí 9 serverov budú z VPN dosiahnuteľné OpenStack API, Ceph (mon/OSD/dashboard), Juju controller a **BMC/IPMI**, keďže sieť je plochá. Dopad: masívny latentný blast radius v porovnaní so súčasným stavom. Závažnosť: **Stredná teraz / Kritická latentne**. Odporúčanie: pred zapnutím cloudu zaviesť segmentáciu a ACL; BMC umiestniť na dedikovanú OOB VLAN. (Sieť, na ktorej sú BMC pripojené, nebola v rámci tohto hodnotenia overená — `[predpoklad]`; dedikovaná OOB VLAN nebola pozorovaná.)

**S2-10 — Stredná — Chýba least-privilege na VPN.** Popis: server-side `/32` pripína len zdrojovú IP klienta, nič neobmedzuje ciele; nie je vynútené MFA (len vlastníctvo kľúča) a rotácia kľúčov nie je zdokumentovaná. Dopad: kompromitovaný kľúč znamená trvalý plný prístup do celej siete. Závažnosť: **Stredná**. Odporúčanie: gateway ACL na tunel (viď S2-01), least-privilege nastavenie client-side `AllowedIPs`, politika pravidelnej rotácie kľúčov, oddelenie prístupov podľa jednotlivých zariadení.

## 5. Prierezové zistenia

Nasledujúce zistenia majú štrukturálny charakter — nevznikajú z jedného konkrétneho portu či služby, ale opakovane umocňujú viacero zistení z kapitol 3 a 4 naprieč oboma scenármi. Slúžia ako podklad pre prioritizované odporúčania v kapitole 6.

**C-01 — Plochá sieť napriek 3 VLAN.** Napriek existencii troch samostatných VLAN (`isolation=false`, ACL vypnuté) je sieť fakticky plochá a voľne routovaná. Toto je najväčší štrukturálny problém celého hodnotenia a priamo umocňuje zistenia S2-01, S2-08 a S2-09.

**C-02 — Jeden box koncentruje MAAS + Omada + DNS/DHCP.** Kombinácia provisioningu, sieťovej kontroly a DNS/DHCP na jedinom hostiteľovi (`172.16.1.2`) predstavuje jednobodovú poruchu (SPOF) a zároveň najhodnotnejší cieľ pre útočníka v labe, ako popisuje zistenie S2-03.

**C-03 — Žiadny host firewall na node.** Absencia host firewallu na `cwwk` je príčinou širokej sieťovej expozície control-plane a doplnkových služieb popísaných v zisteniach S2-02, S2-04, S2-06 a S2-07.

**C-04 — PostgreSQL v plaintexte.** Databáza bežiaca bez TLS (zistenie S2-04) vystavuje poverenia aj Terraform state riziku odpočúvania na trase.

**C-05 — Monitoring bez autentifikácie.** Prometheus, Alertmanager a Mailpit sú vystavené bez akejkoľvek autentifikácie (zistenie S1-01), čo umožňuje únik internej topológie, metrík a e-mailovej komunikácie.

**C-06 — Keycloak v dev režime.** Identity provider chrániaci prístup k RustFS beží v móde `start-dev`, ktorý vypína produkčné hardeningové mechanizmy (zistenie S1-03).

**C-07 — Secrets vo vystavenom etcd + TF state v dosiahnuteľnom Postgrese.** Citlivé dáta — secrets uložené v etcd a Terraform state (vrátane superuser poverení) v Postgrese — sú uložené v komponentoch, ktoré sú sieťovo dosiahnuteľné z VPN (zistenia S2-02 a S2-04), čo zvyšuje hodnotu prípadného kompromisu.

**C-08 — VPN = osobné roaming zariadenia, bez per-device segmentácie, bez MFA, bez rotácie kľúčov.** WireGuard peery sú osobné roamingové zariadenia koncových používateľov bez ďalšej segmentácie prístupu, bez vynúteného MFA a bez zdokumentovanej politiky rotácie kľúčov, ako popisuje zistenie S2-10.

**C-09 — NFS export na VPN.** Export `/data` na tunelovú podsieť `10.172.16.0/24` rozširuje dosah na súborový systém na každého autorizovaného (alebo kompromitovaného) VPN klienta, ako popisuje zistenie S2-05.

## 6. Prioritizované odporúčania

Odporúčania sú rozdelené do troch časových horizontov podľa naliehavosti. Pri každom je uvedené, ktoré zistenia z kapitol 3–5 rieši.

### P1 (hneď)

- **Gateway ACL na tuneli:** nasadiť pravidlo `10.172.16.0/24` → infra s politikou default-deny, povoliť len nevyhnutné (napr. 443 k vybraným službám); zapnúť inter-VLAN isolation. → S2-01, S2-08, S2-10, C-01.
- **Host firewall na `cwwk` (ufw/nft):** etcd a kubelet viazať len na loopback/interné rozhranie; k8s API a NodePorty obmedziť na potrebné zdroje; blokovať `2379/10250/2049/9100` z VPN aj LAN. → S2-02, S2-04, S2-06, S2-07, C-03.
- **Neautentifikované UI (Prometheus/Alertmanager/Mailpit):** dať za forward-auth alebo len na VPN; stiahnuť z internetu. → S1-01, C-05.
- **Zúžiť NFS export:** odstrániť VPN podsieť z exportu alebo povoliť len konkrétne hosty; zachovať `root_squash`. → S2-05, C-09.

### P2 (krátkodobo)

- **Admin aplikácie (ArgoCD, pgAdmin, Nexus, Grafana):** presunúť za SSO forward-auth alebo len na VPN; vynútiť MFA. → S1-02.
- **Keycloak do produkčného režimu:** HTTPS-only, strict hostname, skrytá administrátorská konzola. → S1-03, C-06.
- **TLS na PostgreSQL:** NodePort `30432` neexponovať do VPN; rotovať superuser heslo. → S2-04, C-04, C-07.
- **Hardening MAAS/Omada boxu:** oddeliť role, obmedziť mgmt prístup, vynútiť silné poverenia a MFA, udržiavať patch cadence. → S2-03, C-02.

### P3 (strednodobo)

- **Segmentovať VPN klientov:** samostatná politika/VLAN pre VPN, least-privilege client-side `AllowedIPs`, politika rotácie WireGuard kľúčov. → S2-10, C-08.
- **BMC/IPMI na dedikovanú OOB VLAN** pred zapnutím cloudu; pripraviť ACL pre OpenStack/Ceph. → S2-09.
- **Patch cadence a CVE monitoring** pre vystavené beta služby (RustFS); nasadiť HSTS a bezpečnostné hlavičky na gateway. → S1-04, S1-05.

## Príloha A — Autentifikačná matica vystavených služieb

Tabuľka zhŕňa všetky hostname vystavené cez in-cluster Cilium Gateway (viď kapitola 2) spolu s ich autentifikačnou pozíciou. Všetky sú vystavené na internete cez TCP 443 (TLS terminovaný v clustri, wildcard `*.klucovsky.com`) `[overené]`.

| Hostname | Backend (ns:port) | Autentifikácia | Na internete? | Poznámka |
|---|---|---|---|---|
| `argocd.klucovsky.com` | argocd-server | standalone | áno (443) | vlastný login ArgoCD; viď S1-02 |
| `db.klucovsky.com` | pgAdmin (cnpg-system) | standalone | áno (443) | správa databázy; vysoký dopad pri prelomení, viď S1-02 |
| `nexus.klucovsky.com` | nexus | standalone | áno (443) | vlastný login Nexus, viď S1-02 |
| `alertmanager.klucovsky.com` | alertmanager | žiadna | áno (443) | bez prihlásenia, viď S1-01 |
| `grafana.klucovsky.com` | grafana | standalone | áno (443) | vlastný login Grafana, viď S1-02 |
| `prometheus.klucovsky.com` | prometheus | žiadna | áno (443) | bez prihlásenia, viď S1-01 |
| `registry.klucovsky.com` | zot | standalone | áno (443) | vlastný login Zot, viď S1-02 |
| `auth.klucovsky.com` | keycloak | vlastné prihlasovanie (IdP + admin konzola) `[predpoklad]` | áno (443) | beží v móde `start-dev`, viď S1-03 |
| `mail.klucovsky.com` | mailpit | žiadna | áno (443) | bez prihlásenia, viď S1-01 |
| `s3.klucovsky.com` | rustfs | Keycloak SSO | áno (443) | jediná appka so SSO cez Keycloak |
| `fatto-aac.klucovsky.com` | redirect → RustFS OIDC flow | Keycloak SSO (cez redirect) | áno (443) | 302 redirect, viď S1-07 |

Poznámka: konkrétny typ autentifikácie pri standalone aplikáciách (ArgoCD, Grafana, pgAdmin, Nexus, Zot) aj pri Keycloaku samotnom vychádza z konfigurácie v repozitári a je `[predpoklad]` — malo by sa potvrdiť priamym testom pri jednotlivých aplikáciách s vysokým dopadom.

## Príloha B — Hardening checklist (CIS-style)

Checklist slúži na opakované sledovanie stavu hardeningu v čase. Stav vychádza priamo zo zistení uvedených v predchádzajúcich kapitolách.

| Kontrola | Kategória | Stav (Pass/Fail/NA) | Zistenie |
|---|---|---|---|
| Sieťová segmentácia (inter-VLAN isolation) | Sieť/Segmentácia | **Fail** | C-01 |
| Gateway ACL / VPN least-privilege | VPN | **Fail** | S2-01, S2-10 |
| Host firewall na node | Host | **Fail** | C-03 |
| k8s control-plane nevystavený (etcd/kubelet/API) | Kubernetes | **Fail** | S2-02 |
| NodePorty obmedzené | Sieť/Exposure | **Fail** | S2-04, S2-06 |
| Šifrovanie DB (Postgres TLS) | Dáta/Šifrovanie | **Fail** | S2-04 |
| Autentifikácia vystavených UI | Autentifikácia | **Fail** (S1-01), čiastočne pri standalone appkách | S1-01, S1-02 |
| Keycloak produkčný režim | Identity | **Fail** | S1-03 |
| MAAS/BMC hardening + OOB sieť | Fyzická infra/BMC | **Fail/čiastočne** | S2-03, S2-09 |
| NFS export least-privilege | Storage | **Fail** | S2-05 |
| Správa secrets (etcd/TF state) | Secrets management | **Fail** | C-07 |
| Monitoring/alerting na bezpečnostné udalosti | Monitoring | **NA/čiastočne** `[predpoklad]` | — |
| WG kľúče: rotácia + MFA | VPN/Identity | **Fail** | C-08 |
