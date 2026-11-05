# Exercise Planner — Equity × Tax Integration Design

**Date:** 2026-07-06 · **Status:** Built — see `Api::V1::Equity::ExercisePlansController` and the equity pages
**Scope decision:** one state of residence throughout — California gets full
bracket tables; other states ship as a flat-rate fallback in the parameter schema.

Goal: given the household's grants (already modeled) and a small tax profile, answer the
questions that actually drive exercise decisions:

1. **"How many ISOs can I exercise this year with $0 AMT?"** (the hero number)
2. **"If I exercise N shares, what do I owe — federal AMT + CA AMT — and what total cash
   do I need?"**
3. **"When is it due?"** (safe-harbor analysis: usually April, not quarterly — see below)
4. **"What's my downside if the price falls after Dec 31?"** (the dot-com failure mode)

All outputs are labeled scenarios/estimates — the tool computes numbers under stated
assumptions; it never recommends. (Industry line: computing from inputs = estimate;
"exercise this many" = CPA territory.)

---

## 1. Verified parameters (the engine's constants)

**Federal TY2026 (post-OBBBA, all source-verified):**
- AMT exemption $90,100 S / $140,200 MFJ; phaseout starts at flat **$500k / $1M** AMTI at a
  **50% rate** (doubled by OBBBA) — exemption gone at $680,200 / $1,280,400. Effective
  marginal AMT rate inside the band: **39% / 42%** (26/28% × 1.5). Pre-2026 calculators
  showing 32.5%/35% are obsolete.
- 26% on taxable excess up to $244,500, 28% above. ISO spread is the Form 6251 **line 2i**
  adjustment; SALT (or the standard deduction) is added back at line 2a. LTCG/qualified
  dividends keep 0/15/20% inside TMT (Part III) but count fully in AMTI for exemption
  erosion (marginal LTCG in the band ≈ 34%).
- SALT cap **$40,400**, phasing down 30% of MAGI over $505k to a $10k floor.
- Same-year sale of ISO shares erases the AMT adjustment entirely (the Dec 31 escape hatch).
- No withholding of any kind on ISO exercises (verified to statute) — the planner, not
  payroll, owns this liability.

**California (2025 final figures; 2026 unpublished → carry a `projected` flag and refresh
in the fall):**
- **CA AMT is real for ISOs**: 7.0% rate; exemption $92,749 S / $123,667 MFJ phasing out at
  25¢/$ from AMTI $347,808 / $463,745. FTB Pub 1004 (verbatim): ISO spread is treated as
  NSO income for CA AMT. Credit via FTB 3510 (CA's Form 8801 analog).
- Ordinary brackets 1%–12.3% (9.3% from ~$73k single), **+1% Behavioral Health Services Tax
  over $1M taxable income** (not doubled for MFJ). **No LTCG preference — a qualifying
  disposition is fully ordinary income to CA.**
- CA does **not** conform to QSBS §1202 — the `qsbs_candidate` flag on companies is
  federal-only relief.
- Estimated tax: installments weighted **30/40/0/30**; 110%-of-prior-year safe harbor, but
  **unavailable when current-year CA AGI ≥ $1M**. Critical planner insight: a pure
  exercise-and-hold adds to **AMTI but not AGI**, so it does not trip the $1M rule and the
  prior-year safe harbor still defers the whole AMT bill to April.
- CA supplemental withholding on stock comp is 10.23% (below the 13.3% top liability rate —
  model liability and withholding separately). SDI 1.3% (2026) on wage-type equity income.

**Worked example the engine must reproduce** (single, CA, $400k wages, 20k ISOs @ $2
strike, $17 FMV = $300k spread, held): federal AMT ≈ **$96.5k** (OBBBA adds ~$20k vs 2025
parameters), CA AMT ≈ **$15.3k**, total exercise-year cash = $40k strike + **~$111.8k tax
(~37% of a paper gain)**. Sale at $37 two years later: federal LTCG ~23.8% minus Form 8801
recovery; CA taxes the full $700k gain as ordinary (~$83k incl. BHST) minus FTB 3510
recovery.

---

## 2. Architecture

### Data
- **`tax_profiles`** (household, tax_year): filing_status, state, projected_wages,
  other_ordinary_income, ltcg_qd_income, itemizing flag + salt_paid, prior_year_total_tax,
  prior_year_agi, ytd_withholding_{federal,state}, amt_credit_carryforward_{federal,ca}.
  One editable profile per year; everything prefillable from Fin data later (wages from
  income_like, withholding from paystub imports) but v1 is user-entered.
- **Parameter store**: per (jurisdiction, tax_year) constants as code/YAML per the
  researched schema (brackets, LTCG breakpoints, AMT exemption/phaseout/rate, SALT cap
  rules, surtaxes, estimated-tax weights, `figures_status: final|projected`). Federal 2026
  + CA 2025/2026-projected in v1; other states as `flat_rate` + `ltcg_treatment` fallback.

### Engines (pure services, exhaustively spec'd against the worked examples)
- **`Tax::Federal`** — regular tax (brackets + LTCG stacking), Form 6251 TMT
  (2a addback, 2i spread, exemption with 50% phaseout, Part III), AMT = max(0, TMT − reg).
- **`Tax::California`** — CA regular (brackets + BHST), CA AMT (7%, 25¢ phaseout,
  standard-deduction addback, Pub 1004 ISO treatment).
- **`Equity::ExercisePlanner`** — the integration layer:
  - `crossover(grant, profile)` → max spread & shares with $0 incremental AMT (federal and
    CA computed separately; the binding constraint is whichever hits first). **Bisection
    over the forward engines** (robust to the phaseout kinks and LTCG stacking — the
    industry-standard approach; the closed-form segment walk is a fast path when no LTCG).
  - `simulate(grant, quantity, profile)` → incremental federal AMT, CA AMT, effective
    marginal rate on the next share (26/28/39/42% + CA), total cash needed
    (strike + fed + CA), post-exercise AMTI/AGI split.
  - `safe_harbor(profile)` → federal (110%/100% prior-year vs withholding; deemed-even
    withholding rule) and CA (30/40/0/30, $1M AGI check) → "due April 15" vs "estimated
    payments needed," with the set-aside amount.
  - `nso_gap(grant, quantity, profile)` → spread × (marginal − 22% federal) + CA
    (marginal − 10.23%) under-withholding estimate.
  - `scenarios(grant, quantity)` → exercise-and-hold vs same-year sale (disqualifying:
    ordinary income capped at actual gain, no AMT) vs qualifying sale (LTCG federal,
    ordinary CA) — side-by-side totals.
  - `stress(grant, quantity, drop_pct)` → "if the price falls X% after Dec 31, you still
    owe $Y on vanished paper gains" (the Chou/dot-com panel).

### UI (on the Equity page — a "Plan exercise" action per option grant)
- **Planner drawer/dialog**: tax-profile summary strip (editable inline; stored per year);
  hero number — *"You can exercise **N shares** ($X spread) this year with $0 AMT"*;
  a shares slider with the tax-owed curve (crossover marked, slope-regime shading);
  cash-needed stacked bar (strike / federal AMT / CA AMT); scenario columns; timing note
  (Dec-vs-Jan tradeoff, the Dec 31 same-year-sale escape hatch with countdown when shares
  were exercised this year); safe-harbor line ("covered by the 110% safe harbor — due
  April 15, set aside $Z"); downside stress panel.
- **Assumptions footer** (Equity Simplified pattern): tax-year dropdown showing which
  tables are loaded (+ `projected` badge for CA 2026), enumerated exclusions (NIIT on
  exercise scenarios, 0.9% Additional Medicare, multi-state, AMT FTC), and the standard
  "estimates, not tax advice — confirm with a professional before acting" line.
- **Workflow events**: `equity.exercise_window_closing` (Dec 31 countdown when the escape
  hatch matters), `tax.safe_harbor_behind` (from the safe-harbor module).

### v2 (explicitly deferred)
- Form 8801 / FTB 3510 **credit recovery curves** (dual-basis tracking on sale, negative
  2k adjustment) — the data model already captures FMV-at-exercise per event.
- **Multi-year ladder chart** (shares/year under flat vs rising 409A), Holistiplan-style
  "max ISO income before prior credit stalls" second solve.
- Tax-center page proper (YTD facts: realized gains, dividends, contribution bars,
  estimated-payment ledger) — the §4 design in feature-explorations.md; the exercise
  planner's tax_profiles and engines are shared foundations for it.
- NIIT/Additional-Medicare in scenarios; December/January split optimizer.

---

## 3. Why this is credible (and where the line is)

- Every constant above is primary-source verified (Rev. Proc. 2025-32, IRS i6251, FTB
  Schedule P/Pub 1004/540-ES); the engine is testable against the worked examples to the
  dollar, and cross-checkable against OpenTaxSolver/tenforty.
- The bisection solver reproduces what Secfi ("tax-free ISOs: 5,453") and Holistiplan
  ("Solve for Max") sell; no open-source tool assembles the post-OBBBA piecewise math with
  a state AMT — this would genuinely be the best self-hosted implementation of it.
- The line we don't cross: outputs are scenario numbers under stated assumptions with an
  enumerated exclusion list; no "you should exercise" language; CA 2026 figures flagged
  projected until FTB publishes.

## 4. Build plan

1. Parameter store + `Tax::Federal` + `Tax::California` engines with worked-example specs
   (the bulk of the correctness risk, all backend).
2. `tax_profiles` + API (`GET/PUT /tax_profile?year=`, `POST /equity/grants/:id/exercise_plan`
   returning crossover/simulate/scenarios/safe-harbor for a quantity).
3. Planner UI on the Equity page + assumptions footer.
4. Workflow events + Dec 31 countdown.

Estimated effort: ~1.5–2 weeks. The engines are pure functions with excellent test targets;
the UI reuses the equity page's dialog/slider patterns.
