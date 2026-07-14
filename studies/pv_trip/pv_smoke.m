function pv_smoke(model)
%PV_SMOKE  De-risk the PV-trip model surgery before replicating/running Phase 2.
% Checks, for the given study-local model (default pv_cmld):
%   1. validate_model compiles it (signals + tags present).
%   2. P_pv=0 reproduces the Phase-1 (no-PV) nadir at the knife-edge dP=0.30
%      (proves the load-bus net rewire didn't perturb the physics).
%   3. baseline settles at ~50 Hz WITH PV generating (net P_ref balancing works).
%   4. a large disturbance with PV on FIRES the trip -> net P_load steps up by
%      ~P_pv and the nadir deepens (proves the latch/gate mechanism).
% Reuses the saved Phase-1 CMLD model_vars (compose_full at LFm=0.7033).
if nargin < 1, model = 'pv_cmld'; end
sc   = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(sc));
if isempty(which('sb_grid_sim.default_params')), run(fullfile(repo,'startup_sbgrid.m')); end
mdir = fullfile(sc,'models'); mpath = fullfile(mdir,[model '.slx']);
Pw   = sb_grid_sim.default_params('full_cmld').scale.P_W;

% Phase-1 CMLD model_vars (compose_full 0.8/2.5/0.5, LFm pinned gross->P_W)
S = load(fullfile(sc,'phase1_threshold','pv_phase1.mat'));
mv = S.traces(1).cmld.params.model_vars;

% --- 1. validate ------------------------------------------------------------
rep = sb_grid_sim.validate_model('full_cmld','ModelPath',mpath);
fprintf('[smoke] validate ok = %d\n', rep.ok);

base = @() setfield(setfield(setfield(sb_grid_sim.default_params('full_cmld'), ...
    'grid', struct('SCR',5,'M',3,'k_droop_f_g1',1/0.07,'kt_hp',0.3,'kt_lp',0.7,'t_rh',8,'theta_g0',0,'snub_Q',0,'f1',50)), ...
    'solver', struct('Ts',50e-6,'StopTime',12,'SettleTime',15,'MaxStep',5e-4)), ...
    'model_path', mpath);

run_case = @(dp,ppv) runone(base(), mv, dp, ppv, Pw);

% --- 2 & 3. P_pv=0 at dP=0.30 must reproduce Phase-1 CMLD (nadir 49.521) -----
r0 = run_case(0.30, 0);
fprintf('[smoke] P_pv=0   dP=0.30: baseline=%.4f nadir=%.4f (Phase-1 CMLD was 49.521)\n', r0.metrics.f0, r0.metrics.nadir);

% --- 3b. PV on, rides through (dP=0.30): baseline 50, no deepening -----------
r1 = run_case(0.30, 0.25*Pw);
fprintf('[smoke] P_pv=.25 dP=0.30: baseline=%.4f nadir=%.4f  Pstep=%+.1f MW\n', ...
        r1.metrics.f0, r1.metrics.nadir, pstep(r1)/1e6);

% --- 4. forced trip: big disturbance, PV on -> trip fires, net steps up ------
r2 = run_case(0.60, 0.25*Pw);
fprintf('[smoke] P_pv=.25 dP=0.60: baseline=%.4f nadir=%.4f  Pstep=%+.1f MW (expect ~+%.0f at trip)\n', ...
        r2.metrics.f0, r2.metrics.nadir, pstep(r2)/1e6, 0.25*Pw/1e6);
fprintf('PV_SMOKE_DONE\n');
end

function r = runone(p, mv, dp, ppv, Pw)
p.disturbance.dist_dP_frac = dp;
p.model_vars = mv;
p.model_vars.P_pv = ppv; p.model_vars.f_trip = 49.5; p.model_vars.t_trip_delay = 0.1;
r = sb_grid_sim.simulate(p);
end

function ds = pstep(r)
% net P_load: pre-disturbance mean vs post-nadir tail (a PV trip shows as an
% upward step in net load after the crossing).
td = r.meta.dist_time_abs;
pre  = mean(r.P(r.t<td & r.t>td-1));
post = mean(r.P(r.t>r.t(end)-1));
ds = post - pre;
end
