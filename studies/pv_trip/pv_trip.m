function T = pv_trip(phase, varargin)
%PV_TRIP  Load-model fidelity flips a discrete protection outcome (49.5 Hz DER trip).
%
%   T = pv_trip('P1')                 % Phase 1: threshold-crossing sweep (no new model)
%   T = pv_trip('P1','DP',[.25 .3])   % custom dP set
%   T = pv_trip('P2')                 % Phase 2: PV-trip models at the knife-edge (see below)
%
% RESEARCH QUESTION (plan.md §1): is there a realistic disturbance at which the
% load-model choice alone flips a binary protection outcome -- a *static* load
% predicts frequency dipping below the 49.5 Hz DER trip line (rooftop PV trips ->
% cascade) while the *CMLD's* frequency support keeps it above (PV rides through)?
%
% PHASE 1 (this file, first deliverable, NO model surgery): sweep the load-step
% dP at the stress corner (M=3, SCR=5), motor H=2.5, Rr=0.5, phi=0.8, running the
% EXISTING reducing_cmld models cmld_3m (full CMLD) and true_static (constant-Z),
% BOTH pinned to the P_W (1 pu) operating point exactly as reduce_cmld does
% (CMLD via the motor load factor LFm; static via its shunt cap CapC). For each
% dP it records the nadir of both; the knife-edge is the dP where
%   nadir_static < 49.5 < nadir_cmld.
% Traces + a summary table land in studies/pv_trip/phase1_threshold/; pv_figure
% draws the freq overlay with the 49.5 Hz line.
%
% Uses sb_grid_sim.simulate (PURE -- no DB) + sb_grid_sim.metrics, per memory.md.
% The composition/calibration helpers below are the pinning subset of
% reduce_cmld.m, specialised to cmld_3m + true_static at the stress corner.

ip = inputParser;
ip.addParameter('DP',[0.25 0.28 0.30 0.32 0.35]);  % load-rise fractions to sweep
ip.addParameter('H',2.5);        % motivating-illustration inertia (biggest nadir gap; plan §2)
ip.addParameter('Rr',0.5);       % rotor-R scale
ip.addParameter('phi',0.8);      % motor penetration
ip.addParameter('M',3);          % stress corner swing inertia
ip.addParameter('SCR',5);        % stress corner short-circuit ratio
ip.addParameter('f_trip',49.5);  % DER under-frequency trip line (Hz)
ip.addParameter('ST',15);        % settle time (s)
ip.addParameter('RT',12);        % disturbance-run stop time (s)
ip.addParameter('MatchTol',0.004);
ip.addParameter('MatchIters',6);
ip.addParameter('DPstar',[]);    % Phase 2: knife-edge dP (default: pick from a P1 run)
ip.addParameter('P_pv',[]);      % Phase 2: PV penetration (W); default 0.25*P_W
ip.addParameter('t_trip_delay',0.1);  % Phase 2: DER trip delay (s)
ip.addParameter('DP2',[0.28 0.30 0.32]); % Phase 2: focused knife-edge sweep
ip.parse(varargin{:}); o = ip.Results;

sc   = fileparts(mfilename('fullpath'));           % studies/pv_trip
repo = fileparts(fileparts(sc));                   % sb_grid_lab
if isempty(which('sb_grid_sim.default_params'))
    run(fullfile(repo,'startup_sbgrid.m'));
end

switch upper(char(phase))
    case 'P1', T = phase1(o, sc, repo);
    case 'P2', T = phase2(o, sc, repo);
    otherwise, error('pv_trip:phase','unknown phase "%s" (P1|P2)', phase);
end
end

% ============================ PHASE 1 =====================================
function T = phase1(o, sc, repo)
mdir   = fullfile(repo,'studies','reducing_cmld','models');   % reuse existing models READ-ONLY
figdir = fullfile(sc,'phase1_threshold'); if ~isfolder(figdir), mkdir(figdir); end
Ptarget = sb_grid_sim.default_params('static').scale.P_W;     % 1 pu = P_W

cmldPath = fullfile(mdir,'cmld_3m.slx');
statPath = fullfile(mdir,'true_static.slx');
assert(isfile(cmldPath) && isfile(statPath), 'need cmld_3m.slx + true_static.slx in %s', mdir);

fprintf('\n==== pv_trip PHASE 1: threshold crossing (stress M=%g SCR=%g, H=%.1f Rr=%.1f phi=%.1f) ====\n', ...
        o.M, o.SCR, o.H, o.Rr, o.phi);
fprintf('  49.5 Hz DER trip line; both loads pinned to P_W = %.0f MW (1 pu)\n', Ptarget/1e6);

% ----- pin both models to the 1-pu operating point (dP-independent) ----------
pf0 = mkparams('full_cmld', cmldPath, o, 0.25);
fprintf('[pin CMLD] calibrating motor load factor LFm -> P_W ...\n');
LFm = calibrate_lf(pf0, @(x) compose_full(o.phi,o.H,o.Rr,[],x), Ptarget, o.MatchTol, o.MatchIters);

ps0 = mkparams('static', statPath, o, 0.25);
fprintf('[pin static] calibrating shunt cap CapC -> P_W ...\n');
CapC = calibrate_cap(ps0, @(C) struct('CapC',C), Ptarget, o.MatchTol, o.MatchIters);

% ----- sweep dP, both models, via the PURE engine ---------------------------
DP = o.DP(:)'; n = numel(DP);
rows = cell(n,6); traces = struct('dp',{},'cmld',{},'stat',{});
mv_cmld = compose_full(o.phi,o.H,o.Rr,[],LFm);
mv_stat = struct('CapC',CapC);
for i = 1:n
    dp = DP(i);
    pc = mkparams('full_cmld', cmldPath, o, dp); pc.model_vars = mv_cmld;
    rc = sb_grid_sim.simulate(pc);
    ps = mkparams('static', statPath, o, dp); ps.model_vars = mv_stat;
    rs = sb_grid_sim.simulate(ps);

    nc = rc.metrics.nadir; ns = rs.metrics.nadir;
    verdict = classify(ns, nc, o.f_trip);
    fprintf('  dP=%+.2f pu | static nadir %.3f  CMLD nadir %.3f Hz  -> %s\n', dp, ns, nc, verdict);
    rows(i,:) = {dp, ns, nc, rs.metrics.dip, rc.metrics.dip, verdict};
    traces(i) = struct('dp',dp,'cmld',rc,'stat',rs); %#ok<AGROW>
end

T = cell2table(rows, 'VariableNames', ...
    {'dp','nadir_static','nadir_cmld','dip_static','dip_cmld','verdict'});

% ----- knife-edge: static below 49.5, CMLD above ----------------------------
split = strcmp(T.verdict,'SPLIT');
if any(split)
    idx = find(split); [~,k] = min(abs(T.nadir_cmld(idx)-o.f_trip)+abs(T.nadir_static(idx)-o.f_trip));
    dpstar = T.dp(idx(k));
    fprintf('\n  KNIFE-EDGE dP* = %+.2f pu: static %.3f < %.1f < %.3f CMLD (static trips, CMLD rides through)\n', ...
            dpstar, T.nadir_static(idx(k)), o.f_trip, T.nadir_cmld(idx(k)));
else
    % no exact split in the grid -> interpolate each model's 49.5 crossing for the report
    dpstar = interp_cross(T.dp, T.nadir_static, o.f_trip);
    dpc    = interp_cross(T.dp, T.nadir_cmld,   o.f_trip);
    fprintf(['\n  No sweep point split cleanly. Interpolated 49.5 Hz crossings: ' ...
             'static at dP=%.3f, CMLD at dP=%.3f. Refine DP between them.\n'], dpstar, dpc);
end

save(fullfile(figdir,'pv_phase1.mat'), 'T','traces','LFm','CapC','dpstar','o');
fprintf('\n===== PHASE 1 summary =====\n'); disp(T);

% ----- figure at the knife-edge (or nearest swept dP) -----------------------
[~,ki] = min(abs([traces.dp]-dpstar));
pv_figure(traces(ki).stat, traces(ki).cmld, o.f_trip, figdir);
fprintf('phase1 -> %s\nPV_TRIP_P1_OK\n', figdir);
end

% ============================ PHASE 2 =====================================
function T = phase2(o, sc, repo)
% The dramatic version: identical frequency-tripped PV (behind-the-meter, at the
% load bus) in BOTH pv_cmld and pv_static, so the ONLY difference is the load
% model. At the knife-edge dP the static's nadir crosses 49.5 -> PV trips ->
% secondary cascade; the CMLD stays above -> PV rides through. Net (load - PV) is
% pinned to P_W (1 pu) pre-disturbance (user requirement) via LFm/CapC, so the
% pre-trip trajectory reproduces the Phase-1 net operating point.
mdir = fullfile(sc,'models');
figdir = fullfile(sc,'phase2_pvtrip'); if ~isfolder(figdir), mkdir(figdir); end
cmldPath = fullfile(mdir,'pv_cmld.slx');
statPath = fullfile(mdir,'pv_static.slx');
assert(isfile(cmldPath) && isfile(statPath), ...
    'Phase 2 needs pv_cmld.slx + pv_static.slx in %s (build them via the Simulink MCP first)', mdir);
Ptarget = sb_grid_sim.default_params('full_cmld').scale.P_W;
P_pv = o.P_pv; if isempty(P_pv), P_pv = 0.25*Ptarget; end
ft = o.f_trip; tdel = o.t_trip_delay;
addpv = @(mv) addpvfields(mv, P_pv, ft, tdel);

% OPERATING POINT (see memory.md): pinning NET (load-PV) to 1 pu is INFEASIBLE
% with the simple power-term PV -- it forces the load to *electrically* draw
% gross = P_W + P_pv (1.25 pu), which stalls the CMLD motors (voltage collapse)
% and needs unrealistic overvoltage for the static, because the power-term PV
% does not inject current to relieve the feeder (that is the DER_A refinement).
% So we pin the ELECTRICAL draw (gross) to 1 pu -- the validated Phase-1
% operating point -- via net_target = P_W - P_pv. The PV then nets off to a
% pre-disturbance net = 1 - P_pv pu. This reproduces the Phase-1 pre-trip nadirs
% (same electrical load, M, dP) and keeps SCR/Vterm at the validated corner.
net_target = Ptarget - P_pv;

fprintf('\n==== pv_trip PHASE 2: PV-trip feedback (stress M=%g SCR=%g, H=%.1f Rr=%.1f phi=%.1f) ====\n', ...
        o.M, o.SCR, o.H, o.Rr, o.phi);
fprintf(['  gross (electrical) pinned to P_W=%.0f MW (1 pu, feasible); P_pv=%.0f MW (%.2f pu)\n' ...
         '  -> pre-disturbance NET = %.0f MW (%.2f pu); f_trip=%.1f Hz; t_delay=%.2f s\n' ...
         '  [net=1pu is infeasible with simple PV -> needs DER_A current injection; see memory.md]\n'], ...
        Ptarget/1e6, P_pv/1e6, P_pv/Ptarget, net_target/1e6, net_target/Ptarget, ft, tdel);

% ----- calibrate NET -> (P_W - P_pv), i.e. gross(electrical) -> P_W ----------
pf0 = mkparams('full_cmld', cmldPath, o, 0.25);
fprintf('[pin pv_cmld] LFm so gross(electrical) -> P_W (net -> P_W-P_pv) ...\n');
LFm = calibrate_lf(pf0, @(x) addpv(compose_full(o.phi,o.H,o.Rr,[],x)), net_target, o.MatchTol, o.MatchIters);
ps0 = mkparams('static', statPath, o, 0.25);
fprintf('[pin pv_static] CapC so gross(electrical) -> P_W (net -> P_W-P_pv) ...\n');
CapC = calibrate_cap(ps0, @(C) addpv(struct('CapC',C)), net_target, o.MatchTol, o.MatchIters);
mv_cmld = addpv(compose_full(o.phi,o.H,o.Rr,[],LFm));
mv_stat = addpv(struct('CapC',CapC));

% ----- knife-edge verification sweep (PV feedback live) ---------------------
DP = o.DP2(:)'; n = numel(DP);
rows = cell(n,7); traces = struct('dp',{},'cmld',{},'stat',{});
for i = 1:n
    dp = DP(i);
    rc = runfull(mkparams('full_cmld', cmldPath, o, dp), mv_cmld);
    rs = runfull(mkparams('static',    statPath, o, dp), mv_stat);
    v  = split_verdict(rs.tripped, rc.tripped);
    fprintf('  dP=%+.2f | static nadir %.3f trip=%d | CMLD nadir %.3f trip=%d -> %s\n', ...
            dp, rs.metrics.nadir, rs.tripped, rc.metrics.nadir, rc.tripped, v);
    rows(i,:) = {dp, rs.metrics.nadir, rc.metrics.nadir, rs.tripped, rc.tripped, rs.t_trip-rs.td, v};
    traces(i) = struct('dp',dp,'cmld',rc,'stat',rs); %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', ...
    {'dp','nadir_static','nadir_cmld','trip_static','trip_cmld','static_trip_dt','verdict'});

% knife-edge = the SPLIT nearest 0.30 (Phase-1 crossing), else fall back
split = strcmp(T.verdict,'SPLIT');
if any(split)
    idx = find(split); [~,k] = min(abs(T.dp(idx)-0.30)); dpstar = T.dp(idx(k));
    fprintf('\n  PHASE-2 KNIFE-EDGE dP* = %+.2f pu: static PV trips & cascades, CMLD PV rides through\n', dpstar);
else
    [~,k] = min(abs(T.dp-0.30)); dpstar = T.dp(k);
    warning('pv_trip:phase2:nosplit','no clean SPLIT in DP2 sweep; using dP=%.2f for the figure', dpstar);
end
save(fullfile(figdir,'pv_phase2.mat'), 'T','traces','LFm','CapC','dpstar','P_pv','o');
fprintf('\n===== PHASE 2 summary =====\n'); disp(T);

% ----- assertions (SPEC verification) --------------------------------------
[~,ki] = min(abs([traces.dp]-dpstar)); tr = traces(ki);
assert(tr.stat.tripped,  'Phase2: pv_static did NOT trip at dP*=%.2f', dpstar);
assert(~tr.cmld.tripped,  'Phase2: pv_cmld TRIPPED at dP*=%.2f (should ride through)', dpstar);
assert(tr.stat.metrics.nadir < ft, 'Phase2: static nadir %.3f not below f_trip', tr.stat.metrics.nadir);
assert(tr.cmld.metrics.nadir > ft, 'Phase2: cmld nadir %.3f not above f_trip', tr.cmld.metrics.nadir);
fprintf('  ASSERT ok: static trips (nadir %.3f < %.1f), CMLD rides through (nadir %.3f > %.1f)\n', ...
        tr.stat.metrics.nadir, ft, tr.cmld.metrics.nadir, ft);

% ----- headline figure ------------------------------------------------------
pv_figure2(tr.stat, tr.cmld, ft, figdir);
fprintf('phase2 -> %s\nPV_TRIP_P2_OK\n', figdir);
end

% ---- full run that also captures the PV signals (simulate doesn't expose them) --
function r = runfull(p, mv)
p.model_vars = mv;
modelPath = p.model_path; [~,model] = fileparts(modelPath);
wasLoaded = bdIsLoaded(model);
if ~wasLoaded, load_system(modelPath); cu = onCleanup(@() close_system(model,0)); end %#ok<NASGU>
sb_grid_sim.apply_params(p); sb_grid_sim.enforce_config(model, p);
op = sb_grid_sim.init_operating_point(model, p);
t0 = 0; try, t0 = op.xFinal.snapshotTime; catch, end
td = t0 + p.disturbance.dist_time;
assignin('base','dist_time', td);
assignin('base','dist_dP',   p.disturbance.dist_dP_frac * p.scale.P_W);
set_param(model, 'StopTime',num2str(t0+p.solver.StopTime), 'LoadInitialState','on', ...
    'InitialState','xFinal', 'SaveFinalState','off', 'SaveCompleteFinalSimState','off');
lis = onCleanup(@() reset_lis(model)); %#ok<NASGU>
so = sim(model);
f = so.get('freq_hz'); P = so.get('P_load');
t = f.Time; fd = f.Data;
Pd = interp1(P.Time, P.Data, t, 'linear','extrap');
Vd = getsig(so,'vrms_pu', t, nan(size(t)));
pad = getsig(so,'pv_active', t, nan(size(t)));
ptd = getsig(so,'pv_tripped', t, zeros(size(t)));
m = sb_grid_sim.metrics(t, fd, Pd, Vd, td);
tripped = any(ptd>0.5); t_trip = NaN;
if tripped, k = find(ptd>0.5,1); t_trip = t(k); end
r = struct('t',t,'f',fd,'P',Pd,'V',Vd,'pv_active',pad,'pv_tripped',ptd, ...
           'metrics',m,'td',td,'tripped',tripped,'t_trip',t_trip,'params',p);
end

function d = getsig(so, name, t, dflt)
try, s = so.get(name); d = interp1(s.Time, s.Data, t, 'linear','extrap'); catch, d = dflt; end
end
function reset_lis(model), if bdIsLoaded(model), set_param(model,'LoadInitialState','off'); end, end
function mv = addpvfields(mv, P_pv, ft, tdel), mv.P_pv=P_pv; mv.f_trip=ft; mv.t_trip_delay=tdel; end
function v = split_verdict(s, c)
if s && ~c, v='SPLIT'; elseif s && c, v='both_trip'; elseif ~s && ~c, v='both_ride'; else, v='inverted'; end
end

% ============================ helpers =====================================
function v = classify(ns, nc, ft)
if ns < ft && nc >= ft, v = 'SPLIT';        % the money case: static trips, CMLD rides through
elseif ns < ft && nc < ft, v = 'both_trip';
elseif ns >= ft && nc >= ft, v = 'both_ride';
else, v = 'inverted'; end                    % CMLD below, static above (not expected)
end

function dpx = interp_cross(dp, nadir, ft)
% linear-interpolate the dP at which nadir crosses ft (49.5). nadir decreases
% with dP, so find the bracketing pair.
dp = dp(:); nadir = nadir(:);
below = nadir < ft;
if all(below) || ~any(below), dpx = NaN; return; end
k = find(below,1,'first');          % first point below ft
if k==1, dpx = dp(1); return; end
% between dp(k-1) (above) and dp(k) (below)
dpx = interp1([nadir(k-1) nadir(k)], [dp(k-1) dp(k)], ft);
end

% ------- params (mirrors reduce_cmld.mkparams, stress corner) ----------------
function p = mkparams(load_type, model_path, o, dp)
p = sb_grid_sim.default_params(load_type);
p.grid.M = o.M; p.grid.SCR = o.SCR;
p.disturbance.dist_dP_frac = dp;
p.solver.SettleTime = o.ST; p.solver.StopTime = o.RT;
p.model_path = model_path;
end

% ------- power/voltage probe + calibration (from reduce_cmld) ----------------
function [P, V] = probe_PV(p, mv)
p.model_vars = mv;
p.solver.StopTime = p.disturbance.dist_time + 3;   % short: settled values only
r = sb_grid_sim.simulate(p);
td = r.meta.dist_time_abs;
m  = r.t < td & r.t > td-1;
P  = mean(r.P(m));  V = mean(r.V(m));
end
function P = probe_P(p, mv), [P,~] = probe_PV(p, mv); end

function LFm = calibrate_lf(pbase, compose_lf, Ptarget, tol, maxit)
% Motor load factor so the CMLD's settled P_load == P_W (secant; P monotone in LFm).
LFm = 0.75; LFh = []; Ph = [];
for it = 1:maxit
    P = probe_P(pbase, compose_lf(LFm)); err = (P-Ptarget)/Ptarget;
    fprintf('  [cal LFm=%.4f] P=%.1f MW err=%+.2f%%\n', LFm, P/1e6, 100*err);
    LFh(end+1)=LFm; Ph(end+1)=P; %#ok<AGROW>
    if abs(err) < tol, break; end
    if numel(LFh)>=2 && Ph(end)~=Ph(end-1)
        slope = (Ph(end)-Ph(end-1))/(LFh(end)-LFh(end-1));
        LFm = LFh(end) + (Ptarget-Ph(end))/slope;
    else
        LFm = LFm*(Ptarget/P);
    end
    LFm = min(max(LFm,0.30),2.0);
end
if abs((P-Ptarget)/Ptarget) >= tol
    warning('pv_trip:matchP','LFm P-match not reached (%.2f%% after %d its)', 100*(P-Ptarget)/Ptarget, it);
end
end

function C = calibrate_cap(pbase, mvfun, Ptarget, tol, maxit)
% Static shunt cap CapC so its (constant-Z) settled P_load == P_W (secant; P
% rises monotonically with CapC via Vterm). Seeds sized for the 220 kV bus.
% mvfun(C) builds the model_vars for cap value C (Phase 2 folds in the PV vars).
C1 = 2e-5; [P1,V1] = probe_PV(pbase, mvfun(C1));
C2 = 1e-4; [P2,V2] = probe_PV(pbase, mvfun(C2));
fprintf('  [calCap C=%.5f] P=%.1f MW V=%.4f\n  [calCap C=%.5f] P=%.1f MW V=%.4f\n', ...
        C1,P1/1e6,V1, C2,P2/1e6,V2);
C = C2;
for it = 1:maxit
    if abs((P2-Ptarget)/Ptarget) < tol, C = C2; return; end
    slope = (P2-P1)/(C2-C1); if slope==0, break; end
    C = max(C2 + (Ptarget-P2)/slope, 0);
    [P,V] = probe_PV(pbase, mvfun(C));
    fprintf('  [calCap C=%.5f] P=%.1f MW V=%.4f err=%+.2f%%\n', C,P/1e6,V,100*(P-Ptarget)/Ptarget);
    C1=C2; P1=P2; C2=C; P2=P;
end
if abs((P2-Ptarget)/Ptarget) >= tol
    warning('pv_trip:calCap','static P-match not reached (%.2f%% after %d its)', 100*(P2-Ptarget)/Ptarget, it);
end
end

% ================= composition (from reduce_cmld, cmld_3m only) ==============
function b = motor_baseline()
b.frac  = [0.152 0.166 0.129];
b.Stator = {[0.02 0.072], [0.03 0.114], [0.03 0.114]};
b.Rotor  = {[0.05955 0.04937], [0.02810 0.07959], [0.02810 0.07959]};
b.Lm     = [1.728 1.686 1.686];
b.etrq   = [0 2 2];
b.LF     = 0.75;
b.felec  = 0.337; b.fstat = 0.216;
end

function mv = compose_full(phi, H, Rrscale, Pw, LFm)
% Full 3-motor CMLD at the design point; LFm = common motor load factor (the
% power-match knob). Pn (rating/inertia) stays fixed on the nominal LF.
if nargin < 4 || isempty(Pw), Pw = 2405e6; end
b = motor_baseline(); fm = sum(b.frac); L = 'ABC'; mv = struct();
if nargin < 5 || isempty(LFm), LFm = b.LF; end
for i = 1:3
    X = L(i);
    Pmec = phi*(b.frac(i)/fm)*Pw;  Pn = Pmec/b.LF;
    Rr = b.Rotor{i}(1)*Rrscale;  Llr = b.Rotor{i}(2);
    s  = deal_slip(Rr, LFm);
    mv.(['Motor' X '_Nom'])    = [Pn 11000 50];
    mv.(['Motor' X '_Stator']) = b.Stator{i};
    mv.(['Motor' X '_Rotor'])  = [Rr Llr];
    mv.(['Motor' X '_Lm'])     = b.Lm(i);
    mv.(['Motor' X '_Mech'])   = [H 0 2];
    mv.(['Motor' X '_Pmec'])   = LFm*Pn;
    mv.(['Motor' X '_Tm'])     = LFm/(1-s);
    mv.(['Motor' X '_TrqExp']) = b.etrq(i);
    mv.(['Motor' X '_IC'])     = [s 0 0 0 0 0 -120 120];
end
mv = add_passive(mv, b, phi, Pw, 'split');
mv.CapC = 0.037092*(Pw/2405e6);
end

function mv = add_passive(mv, b, phi, Pw, mode)
Pnm = (1-phi)*Pw;
switch mode
    case 'split'
        e = b.felec/(b.felec+b.fstat);
        mv.CMLD_ElecP = e*Pnm;  mv.P0 = (1-e)*Pnm;  mv.Q0 = 0.20*mv.P0;
end
end

function s = deal_slip(Rr, LF)
s = LF*Rr; for it = 1:8, s = (LF/(1-s))*Rr; end
end
