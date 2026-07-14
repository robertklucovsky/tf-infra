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
