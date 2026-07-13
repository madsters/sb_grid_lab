# Auto-mode work log — CMLD sensitivity study

Running log while the user is away (~1 h from **2026-07-08**). Newest entry at the
bottom. When the user asks for "an update", summarise everything below the last
checkpoint they saw.

---

## CHECKPOINT 0 — where things stood when auto-mode began (2026-07-08)

**Goal for this session:** fix the run blocker, then deliver Round 1 results + plots
for the CMLD motor-parameter sensitivity study (`studies/cmld_inertia_sensitivity.md`).

**Done just before auto-mode:**
- `sb_grid_lab` relocated off Google Drive to `C:\Users\mnea0003\dev\sb_grid_lab`
  (git repo, pushed to origin/main earlier).
- Hand-authored models moved into `models/` (`T1_static.slx`=static,
  `T2_fullcmld.slx`=full_cmld), registered in `load_types.m`, resolved by `load_type`.
- `study4.m` preserved from scratchpad into `studies/`, paths made repo-relative.
- `p.overrides` → **`p.model_vars`** rename across engine + study + docs.

**Round plan agreed with user (time-boxed):**
- Round 1: 30–45 min → results + plots → user go-ahead.
- Round 2: < 3 h.
- Round 3: < 12 h.
- Design: factors {H, Rr, φ} (Lr DROPPED — inert), corners M∈{3,5.5}×SCR∈{5,8},
  Vterm∈[0.95,1.05] operating-point filter. Nested level sets so each round dedups
  into the next (SQLite dedup on (sim_version, param_hash)).

**BLOCKER found by the smoke test (this is the "issue" to fix):**
- Smoke `study4('smoke')` FAILED. Models' `PreLoadFcn = init_testbench_params('T1'/'T2')`
  is undefined → `Load` block params never set → `init_operating_point` errors.
- Root cause: the models depend on `init_testbench_params.m` + its tree
  (`cmld_params_for.m`, `dataaustralian14gen.m`, the AU14 `load` matrix, motor
  equivalent-circuit baselines `MotorX_Stator/Lm`). All still on Google Drive at
  `H:\...\IEEE 14 Generator Model\testbench` + `Australian14gen`; none moved with the .slx.
- So the models are NOT self-contained. `compose4` only overrides Nom/Rotor/Mech/
  Pmec/Tm/IC — Stator/Lm and the static-load baseline come from `init_testbench_params`.

**Plan for this session (in progress):**
1. Bridge the dependency (put `init_testbench_params` + AU14 tree on the path) so the
   PreLoadFcn resolves — WITHOUT editing the .slx. [in progress]
2. Re-run smoke → confirm end-to-end (load → model_vars → settle → disturbance →
   metrics → SQLite).
3. Refactor `study4.m` to the round design (drop Lr, add Vterm filter, parametrise
   the 4 corners, nested 3/5-level grids).
4. Run Round 1 (4 corners × 3-level = ~112 sims) → ANOVA + heatmaps + cross-corner.
5. Update this log with results.

**Known tech-debt to flag to user:** models depend on the old testbench/AU14 infra via
their PreLoadFcn → the run currently reads small .m deps off Google Drive. Follow-up:
vendor those into `sb_grid_lab`, or refactor the models to drop the PreLoadFcn.

---

## CHECKPOINT 1 — blocker fixed, pipeline validated (2026-07-08)

1. **Bridge fix works.** Added a guarded `addpath(testbench)` in `study4.m` /
   `study_cmld.m` so the models' `PreLoadFcn` resolves `init_testbench_params`.
   Re-ran smoke → the model loads and the **static run reproduces the §2 reference
   EXACTLY: RoCoF=-0.3365, dip=0.3471** (doc: -0.3365 / 0.347). Also confirmed the
   layering: PreLoadFcn sets baselines (its defaults SCR=10/M=8), then `apply_params`
   overrides with the study's M=5/SCR=6 — the matching result proves the override wins.
2. **CMLD sims run** (T2 settling, `Vterm=1.089` = expected shunt-cap overvoltage at
   low SCR; the Vterm filter excludes such points in analysis).
3. **New issue found + fixed:** Simulink writes the model cache (`*.slxc`) to the repo
   root; parallel workers contend on one file (write-permission warning — benign at
   2 workers, risky at 7). Fix: `study_cmld.m` now gives the client + each worker its
   OWN cache dir via `Simulink.fileGenControl('CacheFolder',tempname)`. Stray root
   `.slxc` to be deleted before Round 1 (they're git-ignored anyway).
4. **Built `studies/study_cmld.m`** — the round runner: factors {H,Rr,φ} (Lr dropped),
   corners M×SCR, Vterm∈[0.95,1.05] filter, per-corner ANOVA + heatmaps, cross-corner
   H-dominance figure. Rounds: r1=4 corners×3-level (112 sims), r2=4×5-level (504),
   r3=9×5-level (1134). Nested levels → dedup carries r1⊂r2.

**Next:** confirm smoke completes clean → delete stray .slxc → launch **Round 1**
(`study_cmld('r1')`, pool≈7 on this 16-core box) → collect ANOVA + plots.

---

## CHECKPOINT 2 — Round 1 launched (2026-07-08)

- Smoke fully passed (exit 0, 360 s incl. overhead). 4 CMLD points gave sensible
  advantage (H=2/φ=0.6 → +6.5% RoCoF, +6.0% nadir; rises with H and φ).
- Machine: 31.5 GB RAM (17.8 free), 16 cores. Chose **pool=6** (~16 GB, safe;
  7 would edge past free RAM). Stray root .slxc deleted; cache now per-worker.
- **Round 1 launched:** `study_cmld('r1','Pool',6)` → 4 corners (M∈{3,5.5}×SCR∈{5,8})
  × 27 CMLD + 4 static = 112 sims. Est ~28–32 min. Log: jobs tmp `r1.log`,
  DB `studies/study_cmld.db`, figs `results/fig/`.
- study_cmld.m is NEW code (first run) — watching early output for bugs.

---

## CHECKPOINT 3 — Round 1 hit a wall-cap; resuming (2026-07-08)

- Round 1 run 1 was **killed at ~10 min** (background commands have a ~10-min wall
  cap; the 6-min smoke finished, this didn't). No detached MATLAB left (clean).
  Got through corners 1–2 (M=3/SCR=5, M=5.5/SCR=5) → **29 results in the DB**.
- Confirmed `run_point` returns CACHED rows without re-simulating (dedup), so the run
  is resumable: re-launching skips done points and continues. The final all-cached
  launch will complete the analysis + plots fast (under the cap).
- **Data confirms the predicted issue:** SCR=5 corners overvoltage (CMLD points
  Vterm≈1.14) → they'll be filtered out. Static refs: M=3/SCR=5 RoCoF=-0.582,
  M=5.5/SCR=5 RoCoF=-0.373 (lower M ⇒ steeper RoCoF, as expected).
- **Hardened analysis:** heatmaps + best-config now run on any non-empty corner;
  ANOVA only when ≥22 filtered pts (interaction model needs ~19 DOF), wrapped in
  try/catch so one bad corner can't kill the run.
- Resume launched (`study_cmld('r1','Pool',6)`); iterating on completion until OK.

**FOR NEXT SESSION / bigger rounds:** the 10-min background cap means r2 (504 sims,
~1.5 h) and r3 (12 h) CANNOT run as one background job. Options: (a) run MATLAB
detached via Start-Process and poll, or (b) chunk by corner. Resumability via the DB
makes both safe. Decide before launching r2.

---

## CHECKPOINT 4 — switched to DETACHED run (2026-07-08)

- Confirmed via `sweep.m`: it runs the whole `parfor` THEN stores in one batch, so a
  mid-sweep kill loses all 27 points (that's why corner 3 had a static but 0 CMLD).
  Storage granularity = per corner/sweep. Also: sweep pre-checks cache on the client,
  so cached corners are cheap to re-confirm.
- DB now has corners 1 & 2 complete (SCR=5, both will mostly filter out on Vterm),
  + corner 3 static. Remaining: corner 3 & 4 CMLD (54 sims) + corner 4 static.
- **Launched Round 1 remainder DETACHED** (`Start-Process`, PID in r1b.pid, log r1b.log)
  so it isn't subject to the 10-min cap. It cache-hits corners 1–2, runs 3–4 (workers
  compile once, reuse within the session), stores each corner as its sweep finishes,
  then runs the hardened analysis + writes plots to results/fig/. Est ~15 min.
- A background "waiter" (Wait-Process, 9-min timeout) will notify me when MATLAB exits
  (or to re-check). Runaway risk low (smoke validated the sim); will Stop-Process if stuck.

---

## CHECKPOINT 5 — the cap hits detached too; new chunked plan (2026-07-08)

- The detached run ALSO made no progress (DB still 57, corner 3 sweep unfinished) —
  so the ~10-min reap applies to detached processes too. Root cause of stall: a fresh
  MATLAB spends ~2.5 min on parpool + per-worker RECOMPILE before a 27-pt sweep, which
  then can't finish in the remaining budget; sweep stores only at the end → 0 saved.
- **Fixes applied to study_cmld.m:**
  - Shared PERSISTENT Simulink cache (`tempdir/sbgrid_slcache`) so launches reuse the
    compiled model instead of recompiling every time.
  - `'Corners',idx` + `'Analyze',false` options → run ONE corner per launch (fits the
    cap), analyse separately at the end.
- **Plan:** corner 3 (running now, warms cache) → corner 4 → final analysis launch
  (`study_cmld('r1')`, all cached → Vterm filter + ANOVA + plots). Corners 1&2 (SCR=5)
  already stored but expected to filter out on overvoltage.
- Round-1 deliverable will centre on the SCR=8 corners (3,4). If a first corner launch
  is still reaped, its compile has warmed the shared cache → the retry completes fast.

---

## CHECKPOINT 6 — chunking works; corner 3 done, corner 4 finishing (2026-07-08)

- **Corner 3 (M=3,SCR=8) COMPLETE** (27 CMLD stored, DB=84). Its static Vterm=0.969
  (healthy). Chunked one-corner launch with `Analyze=false` fits the cap.
- Corner 4 first attempt was reaped because its static wasn't pre-cached (spent ~90 s
  on it before the sweep). Static now stored (DB=85); re-launched corner 4 — with static
  cached + shared model cache warm it's a pure 27-pt sweep → should complete.
- **Watch item (real finding):** even SCR=8 CMLD points overvoltage — corner 4 CMLD
  settling at Vterm≈1.09 (>1.05 filter). The fixture's shunt cap (not rescalable here)
  over-injects reactive as penetration rises, so the Vterm∈[0.95,1.05] filter may cut
  many points even at SCR=8. This is exactly the doc's §3 open question (expose CapC).
  Round-1 analysis will report kept-vs-excluded counts and I'll also show UNFILTERED
  trends so there's signal regardless.
- After corner 4: final `study_cmld('r1')` (all cached → filter + ANOVA + plots).

---

## CHECKPOINT 7 — ROUND 1 COMPLETE (2026-07-08)

All 112 sims stored; analysis + 9 plots in `results/fig/`. `study_cmld_r1.mat` saved.

**Best CMLD config is consistent across all 4 corners: H=4, Rr=0.5, φ=0.8** (matches
the doc's §2 finding). RoCoF / nadir advantage (filtered, physical points):
| corner (M/SCR) | RoCoF adv | nadir adv | Vterm |
|---|---|---|---|
| M3 / SCR5  | +23.9% | +13.8% | 1.010 |
| M3 / SCR8  | +17.2% |  +9.6% | 1.012 |
| M5.5 / SCR5| +13.2% |  +9.4% | 1.010 |
| M5.5 / SCR8|  +9.6% |  +6.1% | 1.012 |
→ CMLD benefit is LARGER at lower system inertia (M=3 > M=5.5) — physically sensible.

**PROBLEM (needs a decision before Round 2):** the Vterm∈[0.95,1.05] filter kept only
**32/108 points (exactly 8/27 per corner)**; Vterm spanned 0.695–1.146. So ~70% of the
grid is non-physical (shunt-cap OVERvoltage at high φ, voltage COLLAPSE at low-H/high-φ).
8 pts/corner is far below the ~22 needed for the 3-factor interaction ANOVA → **ANOVA
skipped in every corner** (so the xcorner H-dominance figure is empty this round).
Root cause = the fixture's shunt cap is fixed (not a base var here). Round 2 at 5³=125/
corner would still yield ~30% and still no clean ANOVA — wasteful until this is fixed.

**Recommendation:** resolve the operating-point issue before Round 2 (expose/rescale
CapC in the model, or rethink the filter). Awaiting user direction.

---

## CHECKPOINT 8 — Round 1 ANOVA at relaxed band [0.90,1.10] (2026-07-08)

Re-ran analysis at Vterm∈[0.90,1.10] (no new sims): 86/108 kept. SCR=8 corners hit
26/27 → full 3-factor interaction ANOVA ran; SCR=5 corners 17/27 → still skipped.

**H DOMINATES, reproducing §2:**
- RoCoF adv: H 48–52%, φ 19–20%, Rr 10–13%, H×Rr ~9%, H×φ ~6%, Rr×φ ~4%.
- Nadir adv: H 58–63%, φ 20–25%, H×φ 16%, Rr/H×Rr/Rr×φ all ~0. (all H p≈1e-6..1e-10)
- Stable across M3 vs M5.5 (robustness holds at SCR=8). Best config H=4/Rr=0.5/φ=0.8
  everywhere (+17%/+10% at SCR=8; +24%/+14% at weak M3/SCR5).
Caveat: relaxed band includes Vterm up to 1.10, static ref ~0.97 → φ attribution has a
mild V-confound (H robust to it). SCR=5 corners underpowered.

**Round 1 = DONE and reported to user.** Open decision before Round 2: expose CapC (clean
φ) vs proceed. Also note the 10-min background cap → r2/r3 must be chunked per corner.

---

## CHECKPOINT 9 — CapC exposed (2026-07-08)

User clarified the model rule: PARAMETER edits are OK, only STRUCTURE is banned; and
always ask permission before accessing the model. Got permission to expose CapC.
- `cmld_params_for` has a `capMult` knob but it was DEAD: T2's shunt caps were hardcoded
  `0.037092`, never reading `C.CapC`. Two blocks: `CMLD/Feeder shunt` + `CMLD/Substation
  shunt` (plain SPS Three-Phase Parallel RLC Branch; the CMLD subsystem itself is
  LinkStatus=none, so editing their params is local to T2, no structure change).
- **Model edit (done, saved):** both shunts `Capacitance: 0.037092 -> CapC`. Model
  compiles OK with CapC defined. One shared CapC (user choice).
- **Plumbing:** `init_testbench_params` now sets baseline `CapC=C.CapC`; `study_cmld` has
  a `CapMult` option (default 1) and `compose` sets `model_vars.CapC=0.037092*(P/2405e6)*capMult`.
- NOTE: adding CapC to model_vars changes param_hash → Round-1 CMLD points won't dedup
  against CapC-aware runs (expected; we're changing the cap anyway). Statics unaffected.
- Validating now: capMult sweep {1,0.5,0.25,0} at a worst-overvoltage point to confirm
  CapC drives Vterm and find the balancing value for Round 2.

---

## CHECKPOINT 10 — Round 2 launched, autonomous overnight (2026-07-08)

CapC validated: Vterm tracks capMult monotonically (1.00->1.012, 0.50->0.884, ...);
RoCoF/dip only ~8% sensitive across a huge V swing → voltage confound is minor.
User approved: per-corner capMult for R2, doc updated, run R2 to completion autonomously.

**Round 2 = 4 corners (M{3,5.5}xSCR{5,8}) x 5^3 {H,Rr,phi} = 500 CMLD + 4 static.**
`study_cmld.m` reworked for this:
- `CapMult='auto'` → per-corner capMult calibrated to Vterm~1.0 (mid grid point, 1-3 serial
  probes + secant), cached to `study_cmld_r2_capmult.mat`, INCREMENTAL (resumable).
- Grid swept in `BatchSize=35` batches; each `sweep()` STORES on completion, so the ~10-min
  wall-cap loses <= 1 batch. Fully resumable via SQLite dedup (CapC is in the param_hash).
- `CalibrateOnly` mode fills the capMult file first (no pool).

**Execution loop (autonomous):** (1) calibrate all corners [running: b4jbe34qf]; (2) repeatedly
launch `study_cmld('r2','CapMult','auto')` — each does 1-2 batches (~35-70 pts) then is reaped;
re-launch continues; ~13-18 launches for 500 pts; (3) final all-cached launch runs the Vterm
filter + per-corner ANOVA + heatmaps + cross-corner figure and prints STUDY_CMLD_R2_OK.
Then Round 2 results get written into cmld_inertia_sensitivity.md.
NOTE: doc §3/§4 already updated with Round 1 results + CapC.

---

## CHECKPOINT 11 — per-corner capMult GRINDS; pivoted to capMult=1 (2026-07-08)

**IMPORTANT FINDING for the user:** running the grid at the calibrated per-corner
`capMult` (~0.74–0.77) makes the sims **GRIND** — 6 workers each printed `[init T2]`
then never completed a single sim in the whole ~10-min window (0 stored, twice).
Reducing the shunt cap removes voltage support and tips points into the non-converging
regime (the known CMLD init-grind). The calibration probes completed only because they
sit at φ=0.5; the grid's points (esp. low-H / low-φ) grind at reduced cap.
→ **Per-corner capMult<1 is NOT viable for the sweep.** capMult=1 (= the original
hardcoded cap value 0.037092) is proven to complete every sim (Round 1 ran all 108).

**PIVOT (autonomous decision to deliver results):** run Round 2 at **capMult=1** + the
**[0.90,1.10] Vterm filter** (same reliable recipe as Round 1, now 5-level). SCR=8 gets a
full 125-pt ANOVA; SCR=5 stays partial (overvoltage) — same limitation as R1, but the
finding above shows cap-shrinking can't fix it (it grinds). The clean fix for SCR5 /
φ-deconfound needs a DIFFERENT lever (e.g. a transformer-tap var, or a solver-timeout
guard so grinders abort to NaN instead of hanging) — for the user to decide when awake.
NOTE: capMult=1 points now carry a CapC field in model_vars, so they DON'T dedup against
Round 1's points (which predate the CapC field) → 500 fresh sims; statics reuse (4).

---

## CHECKPOINT 12 — CORRECTION: the grind was RAM (Pool=6), not the cap (2026-07-09)

**My CHECKPOINT-11 diagnosis was WRONG.** The grinds were **RAM oversubscription at
Pool=6** (6 workers × ~2.7 GB ≈ 16.2 GB vs 16.7 GB free → swap → stall → 0 progress).
NOT cap-reduction physics, NOT the model edit. Evidence: dropping to **Pool=4** (comfy
headroom) at capMult=1 ran the **entire 500-point grid to completion** (500 `[op]` settles)
and even started the analysis before being stopped. So:
- **Round 2 grid COMPLETE: 500/500 CMLD points stored** (152 full_cmld per corner = 27 R1
  + 125 R2). `study_cmld_r2.mat` saved.
- The Pool=4 launch was NOT wall-capped at 10 min — it ran the full ~2.4 h sweep. (The
  earlier Pool=6 "kills" were the stalled/swapping jobs being reaped, which I misread as a
  10-min cap.) So the whole "10-min cap → chunk everything" scaffolding was chasing a RAM
  problem. Lesson: **use Pool<=4 on this 31.5 GB box.**
- Round 2 filter [0.90,1.10]: 393/500 kept; even SCR=5 keeps 73/125 → ANOVA viable in ALL
  four corners at 5-level (per-corner capMult NOT needed — capMult=1 suffices).
- The per-corner capMult calibration/plumbing still exists and is validated; it's just
  unnecessary for R2 given 5-level yield. (And it likely runs fine at Pool<=4 if ever wanted.)

Running the analysis pass now (all cached) → ANOVA + plots + STUDY_CMLD_R2_OK, then write
Round 2 into the doc.

---

## CHECKPOINT 13 — ROUND 2 COMPLETE (2026-07-09)

Analysis done (STUDY_CMLD_R2_OK). **Full 3-factor interaction ANOVA in all 4 corners.**
Filter [0.90,1.10]: 393/500 kept (SCR8 124/125, SCR5 72–73/125). Written into
`cmld_inertia_sensitivity.md` §5. 8 heatmaps + `xcorner_Hdominance_r2.png` in results/fig.

**Headline results:**
- **H dominates every corner**: RoCoF 55–70% SS, nadir 60–90% (p to 1e-83).
- **SCR reshapes the secondary structure (new cross-corner finding):** weak grid (SCR5) →
  Rr + H×Rr matter for RoCoF (φ tiny); stronger grid (SCR8) → φ + H×φ matter (Rr shrinks).
- **Nadir = H + φ + H×φ**; Rr inert for nadir everywhere.
- **Best config H=4/Rr=0.5/φ=0.8** all corners: +9.6…+23.9% RoCoF, +6.1…+13.8% nadir; bigger
  benefit at low system inertia (M3>M5.5). Confirms + sharpens Round 1.

**Status: Round 1 + Round 2 DONE.** Deliverables: doc §3+§5, DB `study_cmld.db` (612 rows),
figures, `study_cmld_r*.mat`. Uncommitted to git (never committed the new study_cmld.m, models,
DB, doc updates — awaiting user OK to commit/push). Round 3 available but optional.

**Open items for the user:**
1. Commit/push? (study_cmld.m, models/, doc, AUTOMODE_LOG — the .slx edit + all the code).
2. Per-corner-capMult re-run at Pool≤4 to de-confound φ (optional; effect is minor).
3. Round 3 (9-corner / 7-level) for smoother surfaces (optional).
4. Note the model edit: T2_fullcmld shunt caps now read `CapC` (pristine original still at
   H:\...\testbench\T2_fullcmld.slx if you want to compare/revert).
