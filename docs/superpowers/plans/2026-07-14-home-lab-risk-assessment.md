# Home-lab Security Risk Assessment Report — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author the two-scenario home-lab security risk assessment report at `docs/security/2026-07-14-home-lab-risk-assessment.md`, per the approved design.

**Architecture:** This is a **documentation deliverable**, not code. Each task writes one section of the report, then "tests" it with a verification checklist (every claim tagged `[verified]`/`[assumption]`, every finding rated, facts match the spec baseline), then commits. The executive summary is written last because it distills the findings. All facts come from the already-completed reconnaissance frozen in the spec's *Verified environment baseline* — **no new reconnaissance is performed**; if a fact is not in the spec, it is written as `[assumption]`.

**Tech Stack:** Markdown. Slovak prose (technical terms in English). Git.

## Global Constraints

- **Deliverable file:** `docs/security/2026-07-14-home-lab-risk-assessment.md` (new `docs/security/` directory).
- **Source of truth:** `docs/superpowers/specs/2026-07-14-home-lab-security-assessment-design.md` — the *Verified environment baseline* and *Current operational state* sections. Do not invent facts beyond it.
- **Language:** Slovak prose; technical identifiers (hostnames, ports, `sslmode=disable`, product names) stay verbatim.
- **Evidence tags:** every material claim ends with `[overené]` (verified this engagement) or `[predpoklad]` (assumption; state what would confirm it). (Spec uses English `[verified]`/`[assumption]`; the Slovak report uses `[overené]`/`[predpoklad]` — keep this mapping consistent.)
- **Risk scale:** `Kritická` / `Vysoká` / `Stredná` / `Nízka` (= Critical/High/Medium/Low). Each finding shows: popis → útočná cesta → dopad → **závažnosť** → odporúčanie.
- **Finding IDs (stable, used for cross-references — do not rename):**
  - Scenario 1 findings: `S1-01`..`S1-07`
  - Scenario 2 findings: `S2-01`..`S2-10`
  - Cross-cutting: `C-01`..`C-09`
  - Remediations: `P1`/`P2`/`P3` buckets
- **Frozen date:** all "current state" claims are as of **2026-07-14**.
- **No secrets in the report:** never paste passwords/keys. Reference credentials by role only (e.g., "Postgres superuser").
- **Commit style:** `docs(security): <what>` with the Co-Authored-By trailer used elsewhere in this repo.

---

## File Structure

- Create: `docs/security/2026-07-14-home-lab-risk-assessment.md` — the entire report (single file; the sections are tightly cross-referenced and belong together).

Single-file deliverable. Tasks build it section by section in authoring order (summary last).

---

### Task 1: Scaffold the report (skeleton + conventions)

**Files:**
- Create: `docs/security/2026-07-14-home-lab-risk-assessment.md`

**Interfaces:**
- Produces: the section skeleton and the two shared conventions every later task depends on — the **risk scale** (`Kritická/Vysoká/Stredná/Nízka`) and the **evidence tags** (`[overené]`/`[predpoklad]`). Later tasks fill sections in place.

- [ ] **Step 1: Create the directory and file with the skeleton**

Write this exact content:

```markdown
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

## 3. Scenár 1 — bez WireGuardu (z internetu)

## 4. Scenár 2 — autorizovaný WireGuard klient (+ kompromitovaný klient)

## 5. Prierezové zistenia

## 6. Prioritizované odporúčania

## Príloha A — Autentifikačná matica vystavených služieb

## Príloha B — Hardening checklist (CIS-style)
```

- [ ] **Step 2: Verify the skeleton**

Run: `ls docs/security/ && grep -c '^## ' docs/security/2026-07-14-home-lab-risk-assessment.md`
Expected: file listed; heading count ≥ 8.

- [ ] **Step 3: Commit**

```bash
git add docs/security/2026-07-14-home-lab-risk-assessment.md
git commit -m "docs(security): scaffold home-lab risk assessment report"
```

---

### Task 2: Section 2 — Verified baseline

**Files:**
- Modify: `docs/security/2026-07-14-home-lab-risk-assessment.md` (fill `## 2.`)

**Interfaces:**
- Consumes: spec *Verified environment baseline* + *Current operational state*.
- Produces: the fact base that Sections 3–6 cite. Keep hostnames/ports verbatim so later sections can reference them.

- [ ] **Step 1: Write the baseline content**

Condense the spec baseline into these labelled sub-parts (all `[overené]` unless noted). Include:
- **Aktuálny prevádzkový stav:** live = `cwwk` (`172.16.1.11`), MAAS/Omada box (`172.16.1.2`), Omada switche; vypnuté = OpenStack/Ceph/Juju (9 serverov: 6× HP ProLiant DL3xx + 3 neznačkové, 10G + 40G switch, 40G mimo Omady); VLAN 10/20 bez živých hostov.
- **Perimeter (ER605 `172.16.1.1`, fw 2.3.3):** WAN1 DHCP, IPv6 na WAN vypnuté; port-forward = **len TCP 80 → `172.16.1.11:80` a TCP 443 → `172.16.1.11:443`**; žiadny DMZ/one-to-one NAT.
- **WireGuard (Site-to-Site „RACK" na ER605):** UDP **51820** na WAN (bez port-forwardu), tunel `10.172.16.0/24` (router `.1`), 3 peery /32 (MacBook `.2`, Motorola `.3`, MacBookProM5 `.4`), roaming, osobné zariadenia; `serverClientWireguard=false` (road-warrior realizovaný cez site-to-site).
- **VLAN/segmentácia:** VLAN 1 `172.16.1.0/24`, VLAN 10 `172.16.2.0/24` (OpenStack), VLAN 20 `172.16.3.0/24` (Ceph); **všetky `isolation=false`, gateway ACL vypnuté, 0 pravidiel** → plochá routovaná sieť. Router DHCP vypnutý (DHCP/DNS rieši MAAS).
- **Reach WireGuard klienta:** per-peer /32 „Allowed Address" len pripína zdrojovú IP; **neobmedzuje ciele** → klient dosiahne všetky subnety na všetkých portoch (reálny limit je len client-side `AllowedIPs`, ktorý router nevynucuje).
- **Node `cwwk` (`172.16.1.11`):** Ubuntu 24.04, MAAS/cloud-init, k8s-snap + Cilium (eBPF) + MetalLB; **host firewall žiadny** (`ufw inactive`, iptables `INPUT ACCEPT`); DNS `172.16.1.2` + `8.8.8.8`, domény `klucovsky.com`, `fatto.online`.
- **Otvorené z LAN/VPN na node (overené TCP connectom):** `22` SSH, `6443` k8s API, `10250` kubelet, `2379/2380` etcd, `9100` node_exporter, `4244` Hubble, `2049` NFS, `111` rpcbind; NodePorty `30432` **PostgreSQL plaintext (`sslmode=disable`)**, `30910/30911` RustFS, `30417/30418` Tempo.
- **NFS:** `/data` exportované na `10.172.16.0/24` (VPN) **a** `172.16.1.0/24` (LAN); `no_root_squash`? = `[predpoklad]`, overí `exportfs -v` na node.
- **`172.16.1.2` (kombinovaný box):** MAAS (DNS `53`, API `5240`, HTTPS `5443`, proxy `3128`) + Omada controller (`8043`) + SSH `22`.
- **Switche:** SX3016F `172.16.1.24`, TL-SG2428P `172.16.1.23`, SG3210X-M2 `172.16.1.25`.
- **Vystavené aplikácie (cez in-cluster Cilium Gateway, TLS terminovaný v clustri, wildcard `*.klucovsky.com` LE prod):** argocd, db (pgadmin), nexus, alertmanager, grafana, prometheus, registry (zot), auth (keycloak, `start-dev`), mail (mailpit), s3 (rustfs), fatto-aac (302 redirect). Autentifikácia: SSO cez Keycloak len RustFS; standalone auth ArgoCD/Grafana/pgAdmin/Nexus/Zot; **bez autentifikácie Mailpit/Prometheus/Alertmanager** (auth správanie appiek = `[predpoklad]` z repo config, potvrdiť pri high-impact).

- [ ] **Step 2: Verify the baseline section**

Checklist (fix inline if any fail):
- Every bullet has an evidence tag or is under an `[overené]`-labelled block.
- Ports/hostnames match the spec exactly (no typos: `30432`, `51820`, `10.172.16.0/24`).
- The current-vs-off state is stated.

Run: `grep -E 'overené|predpoklad' docs/security/2026-07-14-home-lab-risk-assessment.md | wc -l`
Expected: ≥ 8 tagged claims in this section.

- [ ] **Step 3: Commit**

```bash
git add docs/security/2026-07-14-home-lab-risk-assessment.md
git commit -m "docs(security): add verified baseline section"
```

---

### Task 3: Section 3 — Scenario 1 (no WireGuard, internet)

**Files:**
- Modify: `docs/security/2026-07-14-home-lab-risk-assessment.md` (fill `## 3.`)

**Interfaces:**
- Consumes: Section 2 facts.
- Produces: findings `S1-01`..`S1-07` (referenced by Sections 1 and 6).

- [ ] **Step 1: Write the attack-surface intro**

State: from the internet only **TCP 80/443 → in-cluster Cilium/Envoy gateway** (all `*.klucovsky.com` apps; TLS terminated in-cluster) and **UDP 51820 WireGuard** on the router are reachable `[overené]`. No DB/SSH/NodePort/etcd is internet-exposed (only 80/443 are forwarded) `[overené]`.

- [ ] **Step 2: Write findings S1-01..S1-07**

Write each as popis → útočná cesta → dopad → závažnosť → odporúčanie:

- **S1-01 — Vysoká — Neautentifikované vystavené UI (Prometheus, Alertmanager, Mailpit).** Cesta: útočník pozná hostname → otvorí `prometheus/alertmanager/mail.klucovsky.com` bez prihlásenia. Dopad: Prometheus/Alertmanager odhalia internú topológiu, targets, metriky (a potenciálne citlivé labely); Mailpit vystaví zachytené e-maily vrátane reset-tokenov a interných správ; Alertmanager sa dá zneužiť (silences). Odporúčanie: dať za forward-auth (napr. oauth2-proxy/Keycloak) alebo len-VPN; odstrániť z internetu.
- **S1-02 — Vysoká (pgAdmin, ArgoCD) / Stredná (ostatné) — Standalone login-y vystavené brute-force/cred-stuffing.** Cesta: priame prihlasovacie stránky ArgoCD, Grafana, pgAdmin, Nexus, Zot na internete bez WAF/MFA/rate-limit pred nimi. Dopad: pgAdmin = správa DB, ArgoCD = deploy do clustra → pri prelomení hesla vysoký dopad. Odporúčanie: forward-auth/SSO alebo len-VPN pre admin nástroje; MFA; silné heslá.
- **S1-03 — Vysoká — Keycloak beží v `start-dev` a je na internete.** Cesta: `auth.klucovsky.com` v dev režime. Dopad: dev režim vypína produkčné hardening (povolené HTTP, voľnejší hostname/cache), nevhodné pre exposed IdP, ktorý chráni RustFS. Odporúčanie: prejsť na produkčný režim (`build`+`start`, `KC_HOSTNAME` strict, HTTPS-only), skryť admin konzolu.
- **S1-04 — Stredná — CVE povrch vystavených verzií (vrátane beta).** Cesta: verejne dostupné verzie (napr. RustFS `1.0.0-beta.8`, Keycloak `26.6.4`, Nexus, Zot, Grafana). Dopad: beta/nepatchnutý softvér na internete = riziko známych zraniteľností. Odporúčanie: patch cadence, sledovať CVE, beta služby nevystavovať verejne. (Konkrétne CVE = `[predpoklad]`, doplniť pri revízii verzií.)
- **S1-05 — Nízka — TCP 80 otvorené (redirect na 443) + HSTS chýba.** Dopad: minimálny; priestor pre SSL-strip pri prvom kontakte. Odporúčanie: HSTS + preload, prípadne len 443.
- **S1-06 — Nízka/Info — UDP 51820 WireGuard na WAN.** Toto je *správna* kontrola: WG je pre neautentifikované sondy tichý, silná kryptografia. Odporúčanie: držať firmware ER605 patchnutý; zvážiť zmenu portu (security-by-obscurity, low value).
- **S1-07 — Stredná — Vystavený OIDC/SSO povrch (`auth`, `fatto-aac` redirect).** Cesta: OIDC flow RustFS a redirect endpoint verejne. Dopad: štandardné, ale rozširuje povrch Keycloaku (viď S1-03). Odporúčanie: obmedziť redirect URIs, monitorovať.

- [ ] **Step 3: Verify the section**

Checklist: 7 findings present with IDs `S1-01`..`S1-07`; each has a `Závažnosť:` line using the scale; each ends with an `Odporúčanie:`; version-CVE claim tagged `[predpoklad]`.

Run: `grep -E 'S1-0[1-7]' docs/security/2026-07-14-home-lab-risk-assessment.md | wc -l`
Expected: ≥ 7.

- [ ] **Step 4: Commit**

```bash
git add docs/security/2026-07-14-home-lab-risk-assessment.md
git commit -m "docs(security): add scenario 1 (no-VPN) analysis"
```

---

### Task 4: Section 4 — Scenario 2 (WireGuard client + compromised client)

**Files:**
- Modify: `docs/security/2026-07-14-home-lab-risk-assessment.md` (fill `## 4.`)

**Interfaces:**
- Consumes: Section 2 facts.
- Produces: findings `S2-01`..`S2-10` (referenced by Sections 1 and 6).

- [ ] **Step 1: Write the "what the tunnel grants" intro + current-vs-latent framing**

State: an authorized peer gets **full L3 to `172.16.1.0/24` + (routable but empty) `172.16.2.0/24`, `172.16.3.0/24`, on all ports**, plus NFS `/data` `[overené]`. **Súčasný blast radius** = `cwwk` + MAAS/Omada box + switche; **latentný blast radius** = celý cloud po zapnutí. **Kompromitovaný klient** (ukradnutý notebook/telefón alebo unesený peer kľúč) = rovnaký dosah s nepriateľským zámerom; peery sú osobné roaming zariadenia → reálny vektor.

- [ ] **Step 2: Write findings S2-01..S2-10**

- **S2-01 — Kritická — Žiadna segmentácia medzi VPN klientom a infraštruktúrou.** Cesta: plochá sieť, ACL vypnuté → peer dosiahne všetko. Dopad: jeden kompromitovaný osobný device = plný L3 na celý lab. Odporúčanie: gateway ACL „VPN → len potrebné služby/porty", default-deny; inter-VLAN isolation.
- **S2-02 — Kritická — Vystavený k8s control-plane vrátane etcd.** Cesta: `6443` API, `10250` kubelet, **`2379` etcd** dosiahnuteľné z VPN `[overené]`. Dopad: etcd drží všetky secrets clustra; kubelet API umožňuje exec do podov; pri slabom/žiadnom cert-enforcemente = úplné prevzatie clustra. Odporúčanie: host firewall — etcd/kubelet viazať len na loopback/interné rozhranie; k8s API obmedziť na potrebné zdroje; overiť client-cert auth na etcd/kubelet `[predpoklad]`.
- **S2-03 — Kritická — MAAS + Omada box (`172.16.1.2`) dosiahnuteľný z VPN.** Cesta: MAAS `5240/5443` + provisioning/BMC, Omada `8043`, DNS `53`, proxy `3128`. Dopad: MAAS ovláda PXE/re-image/BMC power → prevzatie fyzických serverov; Omada = kontrola siete (firewall/VLAN/port-forward); DNS/DHCP poisoning. Kompromitácia jedného boxu = kontrola provisioning aj siete. Odporúčanie: obmedziť admin prístup (mgmt-only zdroje), oddeliť MAAS a Omada, silné creds + MFA, patch; ACL blokujúca VPN→mgmt okrem výslovných adminov.
- **S2-04 — Vysoká — PostgreSQL v plaintexte na NodePort `30432` (`sslmode=disable`).** Cesta: priamy TCP z VPN. Dopad: odpočúvanie creds na trase + priamy útok na DB; drží Terraform state (superuser creds) a tenant dáta. Odporúčanie: zapnúť TLS; NodePort neexponovať do VPN (firewall/bind); rotovať superuser heslo.
- **S2-05 — Vysoká — NFS `/data` exportované na VPN subnet.** Cesta: `mount -t nfs 172.16.1.11:/data` z ktoréhokoľvek peera. Dopad: čítanie (možno zápis) dát; pri `no_root_squash` eskalácia. Odporúčanie: zúžiť export (odstrániť `10.172.16.0/24` alebo len konkrétne hosty), `root_squash`, `ro` kde stačí; overiť `exportfs -v` `[predpoklad]`.
- **S2-06 — Stredná — Ďalšie NodePorty: RustFS `30910/30911`, Tempo `30417/30418`.** Dopad: prístup k object-store admin/API a tracing dátam z VPN. Odporúčanie: firewall/obmedziť zdroje; auth na RustFS admin.
- **S2-07 — Stredná/Nízka — Info-disclosure služby: node_exporter `9100`, Hubble `4244`, rpcbind `111`.** Dopad: interné metriky/topológia/flow, enumerácia RPC. Odporúčanie: viazať na interné rozhranie / firewall.
- **S2-08 — Vysoká — Management roviny switchov + Omada z VPN.** Cesta: `172.16.1.23/24/25` + controller `8043`. Dopad: prekonfigurácia siete, VLAN, port mirroring → prevzatie siete. Odporúčanie: mgmt VLAN oddelená od VPN; ACL default-deny na mgmt.
- **S2-09 — Stredná teraz / Kritická latentne — Blast radius po zapnutí cloudu.** Cesta: po zapnutí 9 serverov budú OpenStack API, Ceph (mon/OSD/dashboard), Juju controller a **BMC/IPMI** dosiahnuteľné z VPN (plochá sieť). Dopad: masívny latentný blast radius. Odporúčanie: pred zapnutím zaviesť segmentáciu + ACL; BMC na dedikovanú OOB VLAN. (BMC sieť = `[predpoklad]`, dedikovanú OOB VLAN som nevidel.)
- **S2-10 — Stredná — Chýba least-privilege na VPN.** Cesta: server-side /32 pripína len zdroj; nič neobmedzuje ciele; žiadne MFA (len kľúč), bez zdokumentovanej rotácie. Dopad: kompromitovaný kľúč = trvalý plný prístup. Odporúčanie: gateway ACL na tunel (viď S2-01), least-privilege client-side `AllowedIPs`, politika rotácie kľúčov, per-device oddelenie.

- [ ] **Step 3: Verify the section**

Checklist: 10 findings `S2-01`..`S2-10`; each has severity + recommendation; current-vs-latent stated; compromised-client sub-case covered; `[predpoklad]` on etcd cert-auth, NFS squash, BMC network.

Run: `grep -E 'S2-(0[1-9]|10)' docs/security/2026-07-14-home-lab-risk-assessment.md | wc -l`
Expected: ≥ 10.

- [ ] **Step 4: Commit**

```bash
git add docs/security/2026-07-14-home-lab-risk-assessment.md
git commit -m "docs(security): add scenario 2 (WireGuard) analysis"
```

---

### Task 5: Section 5 — Cross-cutting findings

**Files:**
- Modify: `docs/security/2026-07-14-home-lab-risk-assessment.md` (fill `## 5.`)

**Interfaces:**
- Produces: `C-01`..`C-09` (referenced by Section 6).

- [ ] **Step 1: Write cross-cutting findings**

Short paragraphs, each with ID + one-line impact (these are structural, cited by remediations):
- **C-01 — Plochá sieť napriek 3 VLAN** (`isolation=false`, ACL vypnuté) — najväčší štrukturálny problém; umocňuje S2-01/08/09.
- **C-02 — Jeden box koncentruje MAAS + Omada + DNS/DHCP** — SPOF a najvyššia hodnota cieľa (S2-03).
- **C-03 — Žiadny host firewall na node** — príčina širokej expozície v S2-02/04/06/07.
- **C-04 — PostgreSQL v plaintexte** (S2-04) — creds + TF state.
- **C-05 — Monitoring bez autentifikácie** (S1-01) — Prometheus/Alertmanager/Mailpit.
- **C-06 — Keycloak v dev režime** (S1-03).
- **C-07 — Secrets vo vystavenom etcd + TF state v dosiahnuteľnom Postgrese** (S2-02/04).
- **C-08 — VPN = osobné roaming zariadenia, bez per-device segmentácie, bez MFA, bez rotácie kľúčov** (S2-10).
- **C-09 — NFS export na VPN** (S2-05).

- [ ] **Step 2: Verify**

Run: `grep -E 'C-0[1-9]' docs/security/2026-07-14-home-lab-risk-assessment.md | wc -l`
Expected: ≥ 9.

- [ ] **Step 3: Commit**

```bash
git add docs/security/2026-07-14-home-lab-risk-assessment.md
git commit -m "docs(security): add cross-cutting findings"
```

---

### Task 6: Section 6 — Prioritized remediations (P1/P2/P3)

**Files:**
- Modify: `docs/security/2026-07-14-home-lab-risk-assessment.md` (fill `## 6.`)

**Interfaces:**
- Consumes: finding IDs from Sections 3–5 (cite them per remediation).

- [ ] **Step 1: Write the P1/P2/P3 buckets**

Each remediation: action + which findings it closes.

**P1 (hneď):**
- Gateway ACL: tunel `10.172.16.0/24` → infra default-deny, povoliť len nevyhnutné (napr. 443 k vybraným službám); zapnúť inter-VLAN isolation. → S2-01, S2-08, S2-10, C-01.
- Zapnúť host firewall na `cwwk` (ufw/nft): etcd/kubelet len loopback/interné; k8s API a NodePorty obmedziť na potrebné zdroje; blokovať `2379/10250/2049/9100` z VPN/LAN. → S2-02, S2-04, S2-06, S2-07, C-03.
- Neautentifikované UI (Prometheus/Alertmanager/Mailpit) za forward-auth alebo len-VPN; stiahnuť z internetu. → S1-01, C-05.
- Zúžiť NFS export (odstrániť VPN subnet alebo len konkrétne hosty), `root_squash`. → S2-05, C-09.

**P2 (krátkodobo):**
- Admin appky (ArgoCD, pgAdmin, Nexus, Grafana) za SSO forward-auth alebo len-VPN; MFA. → S1-02.
- Keycloak do produkčného režimu (HTTPS-only, strict hostname, skrytá admin konzola). → S1-03, C-06.
- TLS na PostgreSQL; NodePort `30432` neexponovať do VPN; rotovať superuser heslo. → S2-04, C-04, C-07.
- Hardening MAAS/Omada boxu: oddeliť roly, obmedziť mgmt prístup, silné creds + MFA, patch. → S2-03, C-02.

**P3 (strednodobo):**
- Segmentovať VPN klientov (samostatná politika/VLAN), least-privilege client-side `AllowedIPs`, politika rotácie WG kľúčov. → S2-10, C-08.
- BMC/IPMI na dedikovanú OOB VLAN pred zapnutím cloudu; pripraviť ACL pre OpenStack/Ceph. → S2-09.
- Patch cadence + CVE monitoring pre vystavené beta služby (RustFS); HSTS/security headers na gateway. → S1-04, S1-05.

- [ ] **Step 2: Verify**

Checklist: every P-item cites ≥1 finding ID; every Critical/High finding from Sections 3–4 appears in at least one remediation.

Run: `grep -E 'S[12]-|C-0' docs/security/2026-07-14-home-lab-risk-assessment.md | grep -c '→'` (rough cross-reference count) — expect several.

- [ ] **Step 3: Commit**

```bash
git add docs/security/2026-07-14-home-lab-risk-assessment.md
git commit -m "docs(security): add prioritized remediations"
```

---

### Task 7: Appendix A — Authentication matrix

**Files:**
- Modify: `docs/security/2026-07-14-home-lab-risk-assessment.md` (fill `## Príloha A`)

- [ ] **Step 1: Write the table**

Columns: `Hostname | Backend (ns:port) | Autentifikácia | Na internete? | Poznámka`. Rows (from Section 2 / spec): argocd (argocd-server), db→pgAdmin (cnpg-system), nexus, alertmanager, grafana, prometheus, registry→zot, auth→keycloak, mail→mailpit, s3→rustfs, fatto-aac (redirect). Mark auth = `Keycloak SSO` (rustfs) / `standalone` (argocd, grafana, pgadmin, nexus, zot) / `žiadna` (mailpit, prometheus, alertmanager). Mark all "Na internete? = áno (443)". Add note that auth type is `[predpoklad]` from repo config for the standalone ones.

- [ ] **Step 2: Verify**

Run: `grep -c '|' docs/security/2026-07-14-home-lab-risk-assessment.md`
Expected: table present (many `|`); ≥ 11 service rows.

- [ ] **Step 3: Commit**

```bash
git add docs/security/2026-07-14-home-lab-risk-assessment.md
git commit -m "docs(security): add authentication matrix appendix"
```

---

### Task 8: Appendix B — CIS-style hardening checklist

**Files:**
- Modify: `docs/security/2026-07-14-home-lab-risk-assessment.md` (fill `## Príloha B`)

- [ ] **Step 1: Write the checklist**

Table `Kontrola | Kategória | Stav (Pass/Fail/NA) | Zistenie`. One row per control, status derived from findings:
- Sieťová segmentácia (inter-VLAN isolation) — **Fail** (C-01).
- Gateway ACL / VPN least-privilege — **Fail** (S2-01/10).
- Host firewall na node — **Fail** (C-03).
- k8s control-plane nevystavený (etcd/kubelet/API) — **Fail** (S2-02).
- NodePorty obmedzené — **Fail** (S2-04/06).
- Šifrovanie DB (Postgres TLS) — **Fail** (S2-04).
- Autentifikácia vystavených UI — **Fail** (S1-01), čiastočne (standalone) (S1-02).
- Keycloak produkčný režim — **Fail** (S1-03).
- MAAS/BMC hardening + OOB sieť — **Fail/čiastočne** (S2-03/09).
- NFS export least-privilege — **Fail** (S2-05).
- Správa secrets (etcd/TF state) — **Fail** (C-07).
- Monitoring/alerting na bezpečnostné udalosti — **NA/čiastočne** (`[predpoklad]`).
- WG kľúče: rotácia + MFA — **Fail** (C-08).

- [ ] **Step 2: Verify**

Run: `grep -Ei 'Pass|Fail|NA' docs/security/2026-07-14-home-lab-risk-assessment.md | wc -l`
Expected: ≥ 12 control rows.

- [ ] **Step 3: Commit**

```bash
git add docs/security/2026-07-14-home-lab-risk-assessment.md
git commit -m "docs(security): add CIS-style hardening checklist"
```

---

### Task 9: Section 1 — Executive summary (written last)

**Files:**
- Modify: `docs/security/2026-07-14-home-lab-risk-assessment.md` (fill `## 1.`)

**Interfaces:**
- Consumes: all findings + remediations. Must not introduce new facts.

- [ ] **Step 1: Write the summary**

~1 page: the headline contrast (**bez VPN = 2 TCP porty na 1 host; s VPN = plný L3 na celý lab, žiadne ACL**); the top risks per scenario (S1-01/02/03 for scenario 1; S2-01/02/03 Critical for scenario 2); the current-vs-latent framing (dnes len `cwwk`+MAAS/Omada; celý cloud latentne); and the P1 actions. Reference finding IDs.

- [ ] **Step 2: Verify consistency with body**

Checklist: every finding ID cited in the summary exists in the body; the headline numbers (80/443, 51820, 3 subnets) match Section 2; no new claims.

- [ ] **Step 3: Commit**

```bash
git add docs/security/2026-07-14-home-lab-risk-assessment.md
git commit -m "docs(security): add executive summary"
```

---

### Task 10: Final consistency pass

**Files:**
- Modify: `docs/security/2026-07-14-home-lab-risk-assessment.md`

- [ ] **Step 1: Cross-check the whole report**

Checklist (fix inline):
- Every finding ID (`S1-*`, `S2-*`, `C-*`) referenced in Sections 1 and 6 is defined exactly once.
- Every claim has `[overené]` or `[predpoklad]`; no untagged factual assertions.
- Ports/subnets consistent throughout (`30432`, `51820`, `10.172.16.0/24`, `172.16.1/2/3.0/24`).
- No secrets present. Run: `grep -iE 'password|privatekey|BEGIN|Bobino' docs/security/2026-07-14-home-lab-risk-assessment.md` → expect **no matches** (fix if any).
- Slovak prose reads cleanly; technical terms intact.

- [ ] **Step 2: Final commit**

```bash
git add docs/security/2026-07-14-home-lab-risk-assessment.md
git commit -m "docs(security): final consistency pass on risk assessment"
```

---

## Self-Review (plan vs spec)

- **Spec coverage:** exec summary (Task 9), verified baseline (Task 2), scenario 1 (Task 3), scenario 2 incl. compromised-client + current-vs-latent (Task 4), cross-cutting (Task 5), remediations P1/P2/P3 (Task 6), appendix A auth matrix (Task 7), appendix B CIS checklist (Task 8) — all 8 spec sections mapped. ✓
- **Evidence tagging** (spec requirement) enforced in every section's verify step + Task 10. ✓
- **Current-vs-latent** (spec revision) covered in Tasks 2, 4, 6, 9. ✓
- **Placeholder scan:** findings, severities, and remediations are written out inline (not "add findings here"); remaining `[predpoklad]` items (CVE list, etcd cert-auth, NFS squash, BMC network) are genuine open items the spec already flags, not plan placeholders. ✓
- **ID consistency:** `S1-01..07`, `S2-01..10`, `C-01..09`, `P1/P2/P3` defined in Global Constraints and used identically across tasks. ✓
