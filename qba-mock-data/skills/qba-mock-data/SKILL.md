---
name: qba-mock-data
description: Prepare a ready-to-demo QBA environment on staging from a plain description of what a pitch or test needs ("UAE café group, 3 branches, 30 days, high tips"). Creates synthetic demo venues, sets their config flags, generates payment and tip history, fills the dashboards, links a demo manager, and returns how to show it in QBA. Also lists and deletes earlier demo runs. Use when someone asks for demo, pitch, mock or test data, "a restaurant with X to show", or to prepare staging for a QBA demo. Staging (lower envs) only, never production.
---

# QBA mock data: describe it, get a ready env

Talks to the staging-only admin API `admin/mock-data/runs` (admin-backend, VP-3599) through `mockdata.sh` next to this file.
No repo, VPN or cluster access needed: only the person's own **staging admin** login (role QlubAdmin or QlubSuperAdmin).

## Rules

- Staging (or another lower env via `QBA_MOCK_API`) only. The API itself 404s on production.
- Synthetic only: never copy customer or merchant names, emails, phones, menus or payments. Venue names come from the generator
  (`Demo · …`) or from the person's own words (`venueNames`), never a real merchant brand.
- Never ask for, read, print or store a password or token in the chat. The person stores their token with `login` themselves (below).
- Never write the staging OTP code anywhere. Say "ask the QA owner for the staging test code".
- Delete only runs the person asks to delete.

## 1. One-time: log in (the person does it, not you)

Tell the person:

1. Open **admin-panel-staging.qlub.cloud** and log in as usual.
2. Open the browser console (Cmd+Option+J) and run `copy(localStorage.getItem('accessToken'))`. The token is now in the clipboard.
3. In Claude Code, type `! <path-to-this-skill>/mockdata.sh login` and paste the token when asked. It is hidden, and it is saved only on their own machine (`~/.config/qba-mock-data/token`, mode 600).

Do this again when a call says the token expired (HTTP 401). If a call returns 403, their staging account lacks QlubAdmin or QlubSuperAdmin: they ask the Panel squad to grant it on staging.

## 2. Turn the request into a profile

Write a JSON profile to a temp file. Fields (all optional except `country`):

| Field | Meaning | Default |
|---|---|---|
| `name` | Run prefix, `a-z0-9-` | `custom` |
| `country` | `ae` `sa` `qa` `tr` `gb` `us` `sg` `au` `br` `jp` `hk` `in` (currency and timezone follow) | required |
| `venues` / `venueNames` | 1–10 venues / fixed names | 1 |
| `cuisine` | `cafe`, `casual`, `fine` (names and menu) | `casual` |
| `days` | 1–110 days of history up to now | 60 |
| `txPerDay` | `[min, max]` bills per day, weekends busier (max 400) | `[20, 60]` |
| `avgTicket` | Average bill, local currency | 120 |
| `tipShare` / `tipRate` | Share of payments tipped / tip size, 0–1 | 0.4 / 0.1 |
| `splitShare` | Share of bills split into 2–3 payments | 0.15 |
| `peakHours` | Local hours traffic clusters around | `[13, 20]` |
| `cardMix` / `walletShare` | Card brand weights / Apple-Google Pay share | per country |
| `managerEmail` | `@qlub.io` demo manager linked to the venues, created if missing | none |
| `configOverrides` | Restaurant config flags the pitch shows | none |
| `seed` | Same profile + seed = same data | 42 |

- Fill gaps with realistic defaults for that country and segment, and state them in the reply. Ask only when the answer changes the story of the pitch (for example, which country).
- One run is capped at 60,000 bills (`venues × days × txPerDay max`). Split bigger asks into several runs.
- Ready-made examples are in `presets/`.
- **Manager login:** use the demo manager emails listed on the Confluence page "QBA Mock Data: Pitch-Ready Demo Environments On Staging (VP-3599)" (Vendor Panel space). Those accounts log in on staging without an OTP email; any other `@qlub.io` email gets a real OTP by mail.
- **Feature flags:** when the pitch shows a feature, find its restaurant config key and put it in `configOverrides`:
  - QA's Confluence pages "Functional Overview of QBA Configurations" and "… Restaurant Configurations" list the keys;
  - or ask the Panel squad.
- **Not generated yet:** reviews, staff/waiters, floor layout, qlub+ members, loyalty/discount payments. Say so up front if the pitch needs one; don't fake it another way.

## 3. Run and report

```
mockdata.sh generate /tmp/profile.json   # → runId, per venue: id, name, bills, payments, gross, tips, backfillJobId
mockdata.sh list                         # every demo run; backfillState should reach "completed" within a minute or two
mockdata.sh cleanup <runId>              # deletes exactly that run
```

1. Run `generate`. A failed run is removed automatically; fix the profile and run it again.
2. Run `list` until each new venue's `backfillState` is `completed`. The dashboards are ready then.
3. Reply in a few lines:
   - the run id;
   - each venue's name, id, currency, gross, tips and days;
   - flags set and anything not included;
   - **how to show it:** QBA login screen → tap the logo 5 times → Staging → manager email → code from the QA owner;
   - the cleanup command.
