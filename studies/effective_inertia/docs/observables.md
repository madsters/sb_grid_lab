# Phase 0 — observable inventory + engine API (gates E2/E3 feasibility)

**Purpose.** Before designing estimators, pin down *exactly which signals the rig logs* and *which
engine calls are available*, so the three effective-inertia estimators (E1/E2/E3 in `plan.md`
"T2 methodology") are built only against signals that actually exist. This document is the gate:
it decides which estimators are feasible with the model **as-authored** and flags the one that is not.

Everything below is from read-only inspection of the `+sb_grid_sim` engine, the
`+sb_grid_testbench` harness, `docs/model-interface.md`, and `studies/reducing_cmld/`. **No MATLAB
was run.** No `.slx` was opened.

---

## 1. Logged signals — the hard constraint

The engine↔model wire contract is `+sb_grid_sim/interface.m` (`I.signals`), mirrored in
`docs/model-interface.md §2`. A model logs **exactly three** signals, and `sb_grid_sim.simulate`
reads back **exactly** these:

| Signal | Units | Meaning | Read back as | Source |
|---|---|---|---|---|
| `freq_hz` | Hz  | grid frequency (`f1·wg/w_g1` from the swing block) | `r.f` | `simulate.m:81` |
| `P_load`  | W   | load active power drawn by the load subsystem (`Vabc·Iabc`, **before** the disturbance step) | `r.P` | `simulate.m:81` |
| `vrms_pu` | pu  | terminal voltage RMS at the load bus | `r.V` (interp onto `r.f` time base) | `simulate.m:84-89` |

`simulate` returns the contract-2 struct `r = {params, sim_version, t, f, P, V, metrics, meta}`
(`simulate.m:105-110`). The trace `.mat` saved by `run_point`/`sweep` (`results` under a
`<param_hash>.mat`) contains this same struct — so **any post-processing estimator has access to
`t`, `f`, `P`, `V` and nothing else per-signal.**

### What is NOT logged
- **Per-motor rotor speed / slip `s_i(t)`** — the SPS asynchronous-machine `m` measurement bus
  (which carries `wr`, slip, torque) is **not** wired to any `freq_hz`/`P_load`/`vrms_pu` logging
  path. The interface deliberately excludes load internals (`interface.m:18-21`,
  `apply_params.m:44-48`): motors/composition are model-owned and invisible to the engine.
- **Per-motor active power `P_i(t)`** — only the *aggregate* bus draw `P_load` is logged.
- **Reactive power `Q(t)`** — not in the contract (only `vrms_pu` proxies the reactive state).

This is the single most consequential Phase-0 finding: **it is what makes E3 infeasible as-authored
(see §3).**

---

## 2. Engine / harness API the study will call (all read-only reuse)

| Call | Role | Notes for this study |
|---|---|---|
| `sb_grid_sim.default_params(load_type)` | canonical params struct | `'full_cmld'` → `P_W=2405 MW`, `Q_var=240 MVAr`, `BusKV=220`; `'static'` for the E1 baseline |
| `sb_grid_sim.apply_params(p)` | writes base-workspace vars; **passes `p.model_vars` straight through** (`apply_params.m:51-56`) | our per-motor `MotorA/B/C_*` reach the model here — no `.slx` touch |
| `sb_grid_sim.simulate(p)` | one settle→disturbance run; returns `{t,f,P,V,metrics,meta}` | pure; loads `.slx` read-only, never saves (`simulate.m:9-11,44-45`) |
| `sb_grid_sim.metrics(t,f,P,V,td)` | RoCoF/nadir/dip/settle/f0 around the step | **RoCoF = 500 ms least-squares slope** (`metrics.m:38-42`) = AEMO window |
| `sb_grid_testbench.run_point(p,...)` | dedup (`sim_version,param_hash`) + SQLite + trace `.mat` | cache hit → no re-sim; returns the DB row incl. `trace_path` |
| `sb_grid_testbench.sweep(base, builder, values, 'Parallel',true,...)` | parallel pre-pass, single-writer DB | builder form `@(base,spec)->params` lets us vary `model_vars` per point (`sweep.m:37-45`) |
| `params.model_path` | study-local hand-authored `.slx` | `simulate` resolves it directly (`simulate.m:27-38`) — no `load_types.m` edit needed |

**Disturbance / operating-point conventions (inherited, do not re-derive):**
- Matched-MW step: `dist_dP = dist_dP_frac · P_W` in **absolute W** (`apply_params.m:28`), same for
  every load type — so full and static get the **identical** ΔP (E1's premise).
- `init_operating_point` settles, rebalances `P_ref_g1` so `f0 ≈ 50 Hz`, captures `xFinal` for a
  flat baseline (`init_operating_point.m`). `meta.dist_time_abs` is the absolute step time `td`.
- Pre-step baseline windows are `[td−0.5, td]` throughout (`metrics.m:29`, `equiv_report.m:106`).

---

## 3. Estimator feasibility verdict

Mapping the three `plan.md` estimators onto the logged signals (`t,f,P,V` only):

### E1 — Differential RoCoF  → **FEASIBLE** (headline metric)
Needs: bus `f(t)` for RoCoF, plus a **static baseline run** at the same corner/ΔP. Both available.
- `E = f0·ΔP/(2·RoCoF)` — the swing-equation KE relation. Confirmed identical to Reactive
  Technologies' measured-inertia eq. (9), `H_sys = ΔP·f0/(2·df/dt)`
  (`source_docs/parsed/ReactiveTech_...txt`, p30) — the operator-standard estimator.
- `E_grid = f0·ΔP/(2·RoCoF_static)`, `E_full = f0·ΔP/(2·RoCoF_full)`,
  `E_load = E_full − E_grid`, `H_eff(T) = E_load / P_total`.
- **Base subtlety (difficulty 3).** `E` from *measured* Hz/W/(Hz·s⁻¹) is a genuine physical energy
  regardless of the model's internal pu swing base — so the differential `E_load` is a true W·s.
  (The `reducing_cmld` note that `f0·ΔP_pu/RoCoF0 ≈ 5·M_g1` is exactly why we must **not** read
  `M_g1` as physical inertia; the static run is the zero-load-inertia reference instead —
  `equiv_report.m:73-85`, memory [[effective-inertia-from-rocof]].) `H_eff` lands on the `P_total`
  base by construction, directly comparable to the paper's `H_load`.
- Windowing: sweep the RoCoF fit window `T` to get the `H_eff(T)` curve; headline `T = 500 ms`.
- **Reuses** `equiv_report.m`'s `M_eff = M_g1·|RoCoF_static|/|RoCoF_case|` machinery (same physics,
  re-expressed on the `P_total` base).

### E2 — Load-bus P–ω regression  → **FEASIBLE** (isolates inertia from damping)
Needs: bus `P(t)` and bus `f(t)` → `ω = f/f0`, `dω/dt`. **Both logged.** No per-motor signal needed.
- Regress `ΔP_load(t) = a·(dω/dt) + b·Δω + c` over the early window; `|a| = 2·H_eff·P_total`
  (inertia), `b` = damping/load-relief. This is the estimator that *separates* `dω/dt` (inertia)
  from `Δω` (damping) — difficulty 2 in `plan.md`.
- Requires a **fixed, stated derivative filter** for `dω/dt` (see Phase 3). Feasible entirely from
  the aggregate trace.

### E3 — KE-from-slip anchor  → **BLOCKED as-authored** (needs a logging signal that does not exist)
Needs: **per-motor slip `s_i(t)`** to evaluate `E_released(t) = Σ_i H_i S_Bi[(1−s_{0,i})² −
(1−s_i(t))²]`. Per §1 the model logs no per-motor slip/speed. Therefore E3 **cannot run against the
model as-authored.**

- **Nature of the change (per `plan.md` Phase-0 instruction): a logging-signal question, i.e.
  parameter/output wiring — NOT a structural change and NOT a `.slx` edit by this agent.** To make
  E3 feasible, `cmld_3m.slx` would need three extra logged signals `slip_A/B/C` (or `wr_A/B/C`),
  taken from each SPS asynchronous machine's `m` measurement output via a Bus Selector → a named,
  log-enabled signal line (or `To Workspace`). This is exactly the pattern the three existing
  signals already use (`model-interface.md §6.4-6.6`).
- **This is flagged for Maddy, not actioned** (guardrail: "if per-motor slip is not logged, note the
  change needed and flag it — do not edit the `.slx`"; models are hand-authored,
  [[models-hand-authored-rule]]). See §4.
- E3 is still **implemented as a pure function with its own synthetic unit test in Phase 3**, so it
  is ready to run the moment the three slip signals are wired — but it is **excluded from the T2
  run set** until then, and the study's reported `r`-decomposition proceeds on E1 (headline) + E2
  (damping arbiter). The `plan.md` decomposition line "E3 is the anchor" is therefore **contingent**;
  without E3 we report the E1/E2 pair and label the stored-vs-released split as pending E3.

**Net:** T2 runs on **E1 + E2**. E3 is authored-but-parked behind a one-line model-wiring request.

---

## 4. ⚑ Flag for Maddy — decision needed before the T2 run (not before authoring)

> **E3 (KE-from-slip anchor) needs per-motor slip logged, which `cmld_3m.slx` does not currently
> expose.** The estimator and its unit test are written and green-able without the model, but E3
> cannot be evaluated against a real run until `cmld_3m.slx` logs `slip_A/B/C` (or rotor speed
> `wr_A/B/C`) from each async-machine `m` output. This is a *signal-wiring* addition (three logged
> lines), not a structure change — but per the hand-authored-model rule it must be done by you, not
> the agent.
>
> **Options:**
> 1. **Run T2 now on E1 + E2 only** (headline `H_eff` + damping-isolated `H_eff`); treat the
>    stored-vs-released `(1−s)²` decomposition as future work. *(Study is complete and publishable on
>    this basis — the `r = H_eff/H_load` calibration, the paper's stated future work, is delivered.)*
> 2. **Wire `slip_A/B/C` into `cmld_3m.slx` first**, then run all three estimators and get the full
>    `r`-decomposition (stored-vs-synchronous × fraction-released × coupling/damping).
>
> The rest of the study (Phases 1–6) is built to run either way — E3 is isolated behind a feature
> flag so enabling it later is a config change, not a rebuild.

---

## 5. Consequences for later phases
- **Phase 1 (sweep):** every T2 point is paired with a **static** run at the same corner + ΔP (E1
  needs `RoCoF_static`). The static model is `true_static` (constant-Z, freq-independent), reused
  from `reducing_cmld` and P-matched to `P_W`.
- **Phase 3 (estimators):** implement E1, E2 as the live pair; implement E3 as a pure function +
  synthetic unit test but gate it behind `opts.use_e3` (default false) with a clear "needs slip
  logging" error if invoked on a real trace without the signals.
- **Phase 5 (T2 driver):** analysis reads only `t,f,P,V` from each trace `.mat`; `H_eff(T)` curve +
  the `(corner,ΔP,mix)×{H_load,H_eff^{E1},H_eff^{E2},r}` table. E3 columns present-but-NaN until §4
  is resolved.
