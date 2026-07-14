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
CapC = calibrate_cap(ps0, Ptarget, o.MatchTol, o.MatchIters);

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
% Runs the PV-trip models at the knife-edge dP. Requires the study-local models
% (built via Simulink MCP -- see models/SPEC.md) to exist first.
mdir = fullfile(sc,'models');
figdir = fullfile(sc,'phase2_pvtrip'); if ~isfolder(figdir), mkdir(figdir); end
cmldPath = fullfile(mdir,'pv_cmld.slx');
statPath = fullfile(mdir,'pv_static.slx');
assert(isfile(cmldPath) && isfile(statPath), ...
    'Phase 2 needs pv_cmld.slx + pv_static.slx in %s (build them via the Simulink MCP first)', mdir);
error('pv_trip:phase2:pending','Phase 2 runner is filled in once the PV-trip models are built.');
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

function C = calibrate_cap(pbase, Ptarget, tol, maxit)
% Static shunt cap CapC so its (constant-Z) settled P_load == P_W (secant; P
% rises monotonically with CapC via Vterm). Seeds sized for the 220 kV bus.
C1 = 2e-5; [P1,V1] = probe_PV(pbase, struct('CapC',C1));
C2 = 1e-4; [P2,V2] = probe_PV(pbase, struct('CapC',C2));
fprintf('  [calCap C=%.5f] P=%.1f MW V=%.4f\n  [calCap C=%.5f] P=%.1f MW V=%.4f\n', ...
        C1,P1/1e6,V1, C2,P2/1e6,V2);
C = C2;
for it = 1:maxit
    if abs((P2-Ptarget)/Ptarget) < tol, C = C2; return; end
    slope = (P2-P1)/(C2-C1); if slope==0, break; end
    C = max(C2 + (Ptarget-P2)/slope, 0);
    [P,V] = probe_PV(pbase, struct('CapC',C));
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
