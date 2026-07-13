# CMLD vs Static — Motor-Parameter Sensitivity Study

**Question:** which CMLD motor parameters most improve frequency response (RoCoF, nadir) relative to a
static (constant-PQ) load, under NEM-realistic grid conditions — and can the CMLD be *significantly*
better?

**Framework:** `sb_grid_lab` (`+sb_grid_sim` engine, `+sb_grid_testbench` orchestration, SQLite deduped
results, versioned). Driver: `studies/study4.m` (currently in scratchpad; to be formalised here).

---

## 1. Method

- **Models:** `T2_fullcmld.slx` as the CMLD testbed (motor params supplied as model-owned base-workspace
  vars via `params.model_vars`), `T1_static.slx` as the static reference. *(These are the hand-authored
  models in `models/`, registered in `load_types.m` as `full_cmld` / `static`; the engine loads them
  read-only and resolves them by `load_type`.)*
- **Disturbance:** fixed **+601 MW** step (= 0.25 × nominal 2405 MW), *matched absolute MW* across all
  cases so the CMLD-vs-static comparison isn't confounded by step size.
- **Metrics:** `RoCoF advantage = (|RoCoF_static| − |RoCoF_cmld|) / |RoCoF_static|` (%); `nadir-dip
  advantage` likewise. `Vterm` (pre-disturbance terminal voltage) tracked as a covariate.
  - **RoCoF window = 500 ms** (least-squares slope over `[t_d, t_d+0.5 s]`, per `metrics.m`), matching
    the **AEMO standard** measurement window. NB this is the *operational* RoCoF — over 500 ms it
    captures the motors' fast frequency support (slip response, ~0.1–0.5 s) as well as inertia, so the
    "RoCoF advantage" here is **not pure synchronous inertia**: on a short inertial window (~50 ms) the
    CMLD adds ≈0 (motors draw unchanged power at `t=0⁺`). Pure inertia is isolated separately via the
    RoCoF-derived `H_eff` (see `reducing_cmld/plan.md` §5.6). The nadir advantage is window-independent.
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

## 3. Round 1 results — 4-corner 3-level slice (2026-07-08)

Run with the `sb_grid_lab` framework (`studies/study_cmld.m`; factors {H, Rr, φ}, Lr dropped;
models resolved by `load_type`, loaded read-only). Design: 4 corners `M∈{3,5.5} × SCR∈{5,8}`,
3³=27-point {H,Rr,φ} grid + 1 static each = **112 sims**, `capMult=1` (baseline cap).

### 3a. CapC exposed (model parameterisation)
The fixture's shunt cap was hardcoded, so `capMult` was a dead knob. Both `T2_fullcmld/CMLD`
shunt blocks (`Feeder shunt`, `Substation shunt`) changed from `Capacitance = 0.037092` to the
workspace var **`CapC`** (parameter-only edit; SPS blocks in a non-linked subsystem, links intact).
`init_testbench_params` sets a baseline `CapC`; the study overrides it via `model_vars` with
`CapC = 0.037092·(P/2405e6)·capMult`. **Validated:** Vterm tracks CapC monotonically (at one point,
capMult 1→0.5 → Vterm 1.01→0.88). Crucially, **RoCoF/dip are only mildly voltage-sensitive**
(~8% across a Vterm swing 1.01→0.76) → the φ↔voltage confound on the frequency metrics is minor.

### 3b. Findings (Vterm ∈ [0.90, 1.10] filter → 86/108 kept)
SCR=8 corners kept 26/27 (full ANOVA); SCR=5 kept 17/27 (underpowered — overvoltage from the fixed cap).

**ANOVA SS-fraction (SCR=8 corners):**
| factor | RoCoF adv (M3 / M5.5) | nadir adv (M3 / M5.5) |
|---|---|---|
| **H** | **51.8% / 47.8%** | **63.4% / 58.3%** |
| φ | 18.8% / 19.6% | 19.6% / 25.4% |
| Rr | 10.0% / 13.1% | ~0 |
| H×Rr | 9.1% / 9.3% | ~0 |
| H×φ | 6.0% / 5.5% | 16.4% / 15.6% |
| Rr×φ | 4.3% / 4.7% | ~0 |

- **Motor inertia H dominates** (all p ≈ 1e-6…1e-10), stable across M — robustness holds at SCR=8.
- **Nadir** = H + a strong **H×φ (~16%)** + φ; rotor resistance inert for nadir.
- **RoCoF** additionally picks up **Rr and H×Rr (~9–13%)**.
- **Best config H=4, Rr=0.5, φ=0.8 in every corner** → +9.6% (M5.5/SCR8) … +23.9% (M3/SCR5) RoCoF,
  +6–14% nadir. CMLD benefit is **larger at lower system inertia** (M3 > M5.5). Reproduces §2.

### 3c. Decision for Round 2
Use **per-corner `capMult`** (calibrated to centre each corner's Vterm near 1.0) so the SCR=5 corners
become ANOVA-viable and φ is de-confounded. Since the metrics are V-robust, per-corner (not per-point)
balancing suffices.

---

## 4. Longer run plan (overnight)

**Design:** k=3 full-factorial `{H, Rr, φ}` inside each of the 4 fixed-condition corners; per-corner
ANOVA + advantage surfaces; cross-corner robustness check. **Per-corner `capMult`** (calibrated) so
every corner sits near Vterm≈1.0. Execution note: background jobs are wall-capped (~10 min), so the
sweep runs in **sub-batches** (each `sweep()` stores on completion) and is **resumable** via the SQLite
dedup on `(sim_version, param_hash)` — re-launching continues where it left off.

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

---

## 5. Round 2 results — 4-corner 5-level (2026-07-09)

Executed via `study_cmld('r2')`: 4 corners `M∈{3,5.5}×SCR∈{5,8}` × 5³=125 {H,Rr,φ} + 4 static =
**504 sims, capMult=1** (original cap value). Filter [0.90,1.10]: **393/500 kept** (SCR=8: 124/125;
SCR=5: 72–73/125) — **all four corners ANOVA-viable at 5-level**, so per-corner `capMult` proved
unnecessary. (Execution note: Pool=6 stalled on RAM oversubscription/swap; **Pool=4** ran the full
grid — use Pool≤4 on this 31.5 GB box. `CapC` is now an exposed model var (§3a) but cap-reduction was
not needed here.)

### ANOVA SS-fraction — RoCoF advantage
| factor | M3/SCR5 | M5.5/SCR5 | M3/SCR8 | M5.5/SCR8 |
|---|--:|--:|--:|--:|
| **H** | **69.6** | **65.6** | **58.4** | **54.6** |
| Rr | 13.5 | 16.7 | 7.7 | 9.9 |
| φ | 2.9 | 2.8 | 17.8 | 18.9 |
| H×Rr | 12.5 | 13.5 | 7.8 | 8.7 |
| H×φ | 0.3 | 0.3 | 5.9 | 5.2 |
| Rr×φ | 1.1 | 1.1 | 2.4 | 2.7 |

### ANOVA SS-fraction — nadir advantage
| factor | M3/SCR5 | M5.5/SCR5 | M3/SCR8 | M5.5/SCR8 |
|---|--:|--:|--:|--:|
| **H** | **90.0** | **88.1** | **66.5** | **59.6** |
| φ | 5.5 | 6.5 | 19.5 | 27.0 |
| H×φ | 3.8 | 4.6 | 13.6 | 12.9 |
| Rr / H×Rr / Rr×φ | ≤0.3 | ≤0.5 | ≤0.2 | ≤0.4 |

(all H effects p ≈ 1e-32 … 1e-83)

### Findings
1. **Motor inertia H dominates every corner** — 55–70% of RoCoF variance, 60–90% of nadir. Unambiguous.
2. **Grid strength (SCR) reshapes the secondary structure — the key cross-corner result:**
   - **Weak grid (SCR=5):** RoCoF's secondary drivers are **Rr (13–17%) + H×Rr (12–14%)**; φ tiny (~3%)
     — rotor damping matters when the grid is weak.
   - **Stronger grid (SCR=8):** **φ (18–19%) + H×φ (5–6%)** take over; Rr shrinks — penetration matters
     when the grid is stronger.
3. **Nadir = H + φ + H×φ** in all corners; **rotor resistance is inert for the nadir** (~0%).
4. **Best config H=4, Rr=0.5, φ=0.8 in all 4 corners:** +9.6% (M5.5/SCR8) … **+23.9%** (M3/SCR5) RoCoF;
   +6.1 … +13.8% nadir. Benefit largest at **low system inertia** (M3 > M5.5).
5. **Robustness:** H-dominance and the interaction structure (H×φ for nadir; H×Rr for RoCoF at weak grid)
   hold across M and SCR. Confirms + sharpens Round 1.

### Caveats / next
- capMult=1 → SCR=5 runs elevated (some Vterm→1.14 excluded); φ's share at SCR=8 carries a mild
  voltage-confound (H robust to it). A per-corner-capMult re-run at Pool≤4 would clean φ if wanted.
- Deliverables: `results/fig/heat_*_{Hphi,HRr}.png` (8), `xcorner_Hdominance_r2.png`;
  data in `study_cmld.db` + `study_cmld_r2.mat`.
- Round 3 (denser / 9-corner) is available (`study_cmld('r3')`) but Round 2 already establishes the
  core claims; densification is optional for smoother surfaces.
