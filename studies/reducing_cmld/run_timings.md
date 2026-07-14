# Reducing-CMLD — run timings

Wall-clock durations for `reduce_cmld` invocations, to build up estimates for planning
test rounds. Times measured from the background-task output file (created → last modified).

**Machine:** this box, MATLAB R2025b, Pool=4 (RAM-bound). All runs below **cache-cold**
(DB + `reducing_cmld_raw` cleared first) — a cache-warm re-run of the same params is
near-instant (dedup hit). So these are the *sim-bound* figures relevant for estimating.

## Anatomy of a run
1. **PHASE 0/0b — calibration (serial):** secant probes to pin each model to P_W.
   Each probe is a full settle sim (`ST`=15 s). ~1 `[op]` settle per probe.
2. **PHASE 1 — sweep (parallel, Pool):** N sim points = (corners × signed-DPs × models),
   each a settle + disturbance run (`ST`+`RT`).
3. **Analysis + figures (serial, client):** equiv_report + PNGs — small.

## Log

| # | date | config | models/pt | phase1 pts | cal probes | wall | notes |
|---|---|---|---|---|---|---|---|
| 1 | 2026-07-14 | L1 stress, DP=±0.25, H=2.5, Static, Pool=4 | full+ct+vt+static | 8 | 20 op / 9 LF / 3 cap | **4m17s** | cold; incl. motivating_figure. Handoff's "~15 min" est was ~3.5× high. |
| 2 | 2026-07-14 | L1 stress, DP=±0.25, H=2.5, Static, Pool=4 (static P-match fix) | full+ct+vt+static | 8 | 20 op / 9 LF / 4 cap | **4m22s** | cold; same config as #1 after CapC→P_W retarget. Static P-match converged in 2 secant steps (2389→2404 MW). |
| 3 | 2026-07-14 | L1 stress, DP=±0.25, H=2.5, **Rr=1.0** (baseline), Static, Pool=4 | full+ct+vt+static | 8 | ~20 op / 9 LF / 4 cap | **4m16s** | cold; baseline rotor-R run. CMLD RoCoF adv 14.9% (vs 20.9% at Rr=0.5), dip 10.7%. ct load-drop FAILs at baseline R; vt still PASS. |
| 4 | 2026-07-14 | L1 stress, DP=±0.25, H=2.5, Rr=0.5, Static, Pool=4 (3-panel regen) | full+ct+vt+static | 8 | ~20 op / 9 LF / 4 cap | **4m14s** | cold; regen for demand/supply figure. |
| 5 | 2026-07-14 | L1 stress, **DP=±0.40**, H=2.5, Rr=0.5, Static, Pool=4 | full+ct+vt+static | 8 | ~20 op / 9 LF / 4 cap | **4m10s** | cold; larger disturbance. CMLD adv 21.0%/10.1% (≈ same as 0.25). vt PASS both signs, ct AMBER → verdict robust to disturbance size. |
| — | 2026-07-14 | **plot-only** (`motivating_figure`, no sim, warm MATLAB) | — | 0 | 0 | **~10s** | corrects earlier "startup dominates / minutes" guess: a warm plot-only rerun is ~10s. |

## Emerging rule-of-thumb
- ~**4–4.5 min** for 8 phase-1 points + ~30 calibration settle probes, cold, Pool=4.
- Calibration is **serial** and non-trivial (~30 settle probes here) — caching the
  per-corner LFm/CapC (backlog item) would cut repeat runs materially.
- Scale estimate for bigger rounds (rough, until more data): phase-1 points scale
  linearly but parallelise over Pool; calibration probes scale with corners×models.
