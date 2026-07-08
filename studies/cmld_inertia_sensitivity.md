# CMLD vs Static — Motor-Parameter Sensitivity Study

**Question:** which CMLD motor parameters most improve frequency response (RoCoF, nadir) relative to a
static (constant-PQ) load, under NEM-realistic grid conditions — and can the CMLD be *significantly*
better?

**Framework:** `sb_grid_lab` (`+sb_grid_sim` engine, `+sb_grid_testbench` orchestration, SQLite deduped
results, versioned). Driver: `studies/study4.m` (currently in scratchpad; to be formalised here).

---

## 1. Method

- **Models:** legacy `T2_fullcmld.slx` as the CMLD testbed (motor params reachable as base-workspace
  vars via `params.overrides`), `T1_static.slx` as the static reference. *(Interim — to be replaced by
  the hand-authored models; the interface is identical.)*
- **Disturbance:** fixed **+601 MW** step (= 0.25 × nominal 2405 MW), *matched absolute MW* across all
  cases so the CMLD-vs-static comparison isn't confounded by step size.
- **Metrics:** `RoCoF advantage = (|RoCoF_static| − |RoCoF_cmld|) / |RoCoF_static|` (%); `nadir-dip
  advantage` likewise. `Vterm` (pre-disturbance terminal voltage) tracked as a covariate.
- **Composition knob (φ):** motor share of load scaled via `MotorX_Nom/_Pmec` (ratings), with the
  non-motor remainder rebalanced across electronic/static; per-motor equivalent-circuit ratios preserved;
  operating slip / `Tm` recomputed via `deal_slip` when `Rr` changes. Baseline empirically rebalanced
  (`P_ref_g1` ← settled `P_load`) so pre-disturbance frequency sits at 50 Hz regardless of composition.
- **Analysis:** full-factorial **ANOVA** (main effects + all 2-way interactions); SS-fraction = importance.
  This recovers *which* factors interact (the pairwise structure), which plain Sobol Sᵢ/S_Tᵢ cannot.

---

## 2. Sense-check result (midrange corner M=5, SCR=6, 3⁴=81 points)

Factors screened: **H** (motor inertia), **Rr** (rotor-R scale), **Lr** (rotor-leakage scale),
**φ** (motor penetration). Static reference at this corner: RoCoF = −0.3365 Hz/s, dip = 0.347 Hz.

### ANOVA — variance explained (SS-fraction, %)

| factor | RoCoF adv | nadir adv | note |
|---|--:|--:|---|
| **H** | **50.7** | **54.9** | dominant, p≈1e-24 |
| H×φ | 8.8 | **27.2** | inertia's nadir benefit is strongly penetration-dependent |
| φ | 12.5 | 3.7 | |
| H×Rr | 12.0 | 4.8 | |
| Rr | 10.9 | 3.5 | |
| Rr×φ | 2.9 | 4.7 | |
| **Lr** | **1.0** | **0.6** | inert |
| H×Lr, Rr×Lr, Lr×φ | ≤0.6 | ≤0.3 | inert |

### Findings
1. **Motor inertia H dominates** both metrics (~half the variance). The inertia lever is real and
   unambiguous — the core hypothesis holds.
2. **Key interactions (named):** `H×Rr` for RoCoF (12%) and `H×φ` for the nadir (27%). How much inertia
   helps depends on rotor damping and on motor penetration. `Rr` and `φ` are the secondary main effects.
3. **Lr is inert** (~1%, no interactions) over the 0.5–2× range — a **null result** against the
   electrical-time-constant hypothesis (τ_rotor doesn't shift the RoCoF↔nadir split at this scale).
4. **Significant CMLD advantage is achievable at the extreme:** best config **H=4, Rr=0.5, φ=0.8 →
   +14.1% RoCoF, +8.8% nadir** (Vterm 1.019, physical). It needs **high inertia + high penetration +
   low rotor resistance**. At realistic H (0.1–2) / moderate φ the advantage is ~2–7%.

### Operating-point caveats
- **~3 degenerate points**: `H=0.1, φ=0.8, Rr=0.5` collapsed to **Vterm 0.71–0.77** (drew ~556 MW) and
  gave *negative* advantage — low-inertia + high-penetration motors fall into a voltage-collapse basin
  during settle. Vterm spanned **0.712–1.123** across the grid.
- **Mild overvoltage 1.01–1.12** on the healthy grid from the CMLD shunt cap at SCR=6 (cap is not a
  base-var on the fixture, so not rescalable here). Worse at weaker SCR — hence the SCR=5 floor.

### Decisions taken
- **Drop Lr** as a factor (inert; the 0.5–2× range can't move τ enough to test its hypothesis; revisit
  only with a much wider range if ever).
- **Add an operating-point filter:** keep only `Vterm ∈ [0.95, 1.05]`; exclude collapse/overvoltage
  points from the ANOVA (won't change H-dominance, but cleans the degenerate tail).
- **Keep H, Rr, φ** (the movers). Cap/voltage handling deferred to the authored models (expose `CapC`).

---

## 3. Longer run plan (overnight)

**Design:** k=3 full-factorial `{H, Rr, φ}` inside each of the 4 fixed-condition corners; per-corner
ANOVA + advantage surfaces; cross-corner robustness check.

- **Factors / levels (5 each):**
  - `H` ∈ {0.1, 0.5, 1, 2, 4} s
  - `Rr_scale` ∈ {0.5, 0.75, 1, 1.5, 2}
  - `φ_motor` ∈ {0.2, 0.35, 0.5, 0.65, 0.8}
- **Corners (fixed conditions, 2×2):** `M ∈ {3, 5.5}` × `SCR ∈ {5, 8}`.
- **Runs:** 5³ = **125 CMLD/corner** × 4 + 4 static = **504 runs**.
- **Filter:** compute all, then analyse only `Vterm ∈ [0.95, 1.05]`; report the excluded count/region.
- **Metrics:** RoCoF advantage (primary), nadir advantage, Vterm covariate; derive H_eff.
- **Analysis per corner:** ANOVA SS-fractions (main + 2-way) for RoCoF and nadir; heatmaps `H×φ` and
  `H×Rr`. **Cross-corner:** does H-dominance and the H×φ / H×Rr interaction structure hold as inertia
  (M) and grid strength (SCR) vary? That's the robustness claim.
- **Deliverables:** this doc updated with the 4-corner ANOVA tables, advantage surfaces, a best-config
  table per corner, and the physical-vs-degenerate point census.

**Compute:** after the Google-Drive → local-disk move (kills the model-load I/O stall, frees RAM), ~7
workers at ~60–76 s/sim → **~1.5 h** for 504 runs. Comfortable overnight; could densify to 7 levels
(343/corner → 1,372 runs, ~4 h) for smoother surfaces if desired. Results are deduped in SQLite, so the
run is resumable and re-runs are free.

**Prereqs before launch:**
1. Move `sb_grid_lab` (+ fixtures) off Google Drive to local disk.
2. Formalise `study4.m` into `studies/`: drop Lr, add the Vterm filter, parametrise the corner list for
   the 4-corner sweep, cap the pool at the memory-safe worker count.

**Open question for the model authors:** expose the shunt cap (`CapC`) and ideally a transformer tap as
base variables in the hand-authored CMLD models, so weaker-SCR corners can be voltage-balanced and the
SCR=3 (regulatory-floor) condition becomes reachable without the 1.1+ pu overvoltage.
