function T = reduce_cmld(level, varargin)
%REDUCE_CMLD  Regression-tested CMLD model-reduction driver.
%
%   T = reduce_cmld('L0')                 % replication: 2x(1/2) CMLD vs 1 CMLD
%   T = reduce_cmld('L1','Corner','stress')
%   T = reduce_cmld('L1','Corner','both','Pool',4)
%
% Runs the FULL model and each REDUCED candidate under identical conditions,
% through sb_grid_testbench.run_point (dedup + SQLite + trace .mat), then calls
% equiv_report for the gate + two-part error metric + H_eff + verdict + the
% paired frequency/active-power figure. See studies/reducing_cmld/plan.md.
%
% Reduction levels (plan §3):
%   L0  full=cmld_3m_2x (2 identical CMLD, 1/2 power each)  reduced=cmld_3m       [exact]
%   L1  full=cmld_3m (motors A+B+C)     reduced=cmld_1m_ct, cmld_1m_vt           [lossy]
%   L2  full=cmld_3m (elec+static)      reduced=cmld_3m_elec (foil: cmld_3m_stat) [lossy]
%
% Design point (plan §4.1, from the sensitivity study, realistic ceiling):
%   H = 1.5 s,  Rr-scale = 0.5,  phi = 0.8.  Common H across A/B/C -> H_eq = 1.5.
%
% Options:  'Corner' 'stress'|'nominal'|'both'   'Pool' n   'Static' true
%           'DP' signed step fractions (default [.1 .25 .4] both signs)
%
% MODELS ARE HAND-AUTHORED and loaded READ-ONLY; all params (incl. the equivalent
% motor / aggregated load) are supplied as model-owned base-workspace vars via
% params.model_vars. Author the .slx listed in plan §7 into models/ (below) so
% each reads the model_vars this driver composes.

ip = inputParser;
ip.addParameter('Corner','stress');
ip.addParameter('Pool',4);                 % RAM-bound: keep <=4 on this box
ip.addParameter('Static',true);            % run a static ref for absolute H_eff
ip.addParameter('DP',[0.10 0.25 0.40]);    % magnitudes; both signs are added
ip.addParameter('ST',15);                  % settle time (s)
ip.addParameter('RT',12);                  % disturbance-run stop (s; >= TraceWin+buffer)
ip.addParameter('TraceWin',10);
ip.addParameter('MatchP',true);            % calibrate reduced load factor to match full P (gate)
ip.addParameter('MatchTol',0.004);         % pre-disturbance P match tolerance (< gate 0.5%)
ip.addParameter('MatchIters',6);           % max secant iterations per candidate/corner
ip.addParameter('H',1.5);                  % motor inertia design point (plan §4.1; realistic cap 2.5)
ip.addParameter('Rr',0.5);                 % rotor-R scale design point
ip.addParameter('phi',0.8);                % motor penetration design point
ip.addParameter('StaticModel','true_static'); % baseline static: constant-Z, freq-independent (14-gen)
ip.addParameter('VTol',0.004);             % static Vterm-match tolerance (pu) for the CapC calibration
ip.parse(varargin{:}); o = ip.Results;
assert(o.H <= 2.5, 'motor H capped at 2.5 (realistic ceiling); got %g', o.H);

sc     = fileparts(mfilename('fullpath'));      % studies/reducing_cmld
repo   = fileparts(fileparts(sc));              % sb_grid_lab
if isempty(which('sb_grid_sim.default_params'))  % self-sufficient under -batch
    run(fullfile(repo,'startup_sbgrid.m'));
end
mdir   = fullfile(sc,'models');
db     = fullfile(sc,'reducing_cmld.db');
raw    = fullfile(sc,'reducing_cmld_raw');
figdir = fullfile(repo,'results','fig'); if ~isfolder(figdir), mkdir(figdir); end

DP  = o.DP(:)'; dpset = [DP, -DP];              % both signs
Hd = o.H; Rrd = o.Rr; phid = o.phi;             % design point (plan §4.1; H<=2.5)

% corners (plan §4):  [M  SCR]
corners = struct('stress',[3 5], 'nominal',[5.5 8]);
switch lower(o.Corner)
    case 'both', cnames = {'stress','nominal'};
    otherwise,   cnames = {lower(o.Corner)};
end

% ----- level -> (full model, reduced candidates, composers, class) ----------
[fullmodel, reds, class] = level_spec(level);

% ----- shared persistent Simulink cache (parallel-safe, cross-launch) -------
cdir = fullfile(tempdir,'sbgrid_slcache');
try
    Simulink.fileGenControl('set','CacheFolder',cdir,'CreateDir',true);
catch
end

% ----- guard: the hand-authored models must exist --------------------------
need = [{fullmodel}, cellfun(@(r) r.model, reds, 'uni',0)];
if o.Static, need = [need, {o.StaticModel}]; end
assert_models_present(need, mdir);

% Pool>1 first so serial runs (Pool=1) never touch gcp/parpool -- the Parallel
% Computing Toolbox may be absent, and gcp errors rather than returning empty.
useParallel = o.Pool>1 && license('test','Distrib_Computing_Toolbox');
if useParallel && isempty(gcp('nocreate')), parpool('local',o.Pool); end

% ----- PHASE 0: pin every model to the P_W (1 pu) power target --------------
% The equivalence comparison is only valid if full & reduced START from the same
% operating point (plan §5.2). Rather than match reduced -> the full's incidental
% draw, we pin EVERY model (full included) to draw the nominal P_W = 1 pu at the
% bus: the principled operating point (also the SCR + disturbance base, and what
% a correct static draws). Calibrate each model's motor LOAD FACTOR (LFm) by
% secant so its settled P_load == P_W -- tuning slip/Tm only, Pn (inertia) fixed.
% Serial (each secant step needs the last). Keys: "corner|__full__" and
% "corner|<candidate>".
Ptarget = sb_grid_sim.default_params('full_cmld').scale.P_W;   % 1 pu = P_W
lf = containers.Map();
for ci = 1:numel(cnames)
    lf([cnames{ci} '|__full__']) = 0.75;
    for k = 1:numel(reds), lf([cnames{ci} '|' reds{k}.name]) = 0.75; end
end
if o.MatchP
    for ci = 1:numel(cnames)
        cn = cnames{ci}; M = corners.(cn)(1); SCR = corners.(cn)(2);
        fprintf('[matchP %s] target = P_W = %.1f MW (1 pu)\n', cn, Ptarget/1e6);
        % FULL model
        pf0 = mkparams('full_cmld', fullfile(mdir,[fullmodel '.slx']), M,SCR,0.25,o);
        lf([cn '|__full__']) = calibrate_lf(pf0, ...
            @(x) compose_full_or_2x(fullmodel,phid,Hd,Rrd,x), Ptarget, 'full', o.MatchTol, o.MatchIters);
        % each REDUCED candidate
        for k = 1:numel(reds)
            if ~reds{k}.match, continue; end
            pr0 = mkparams('full_cmld', fullfile(mdir,[reds{k}.model '.slx']), M,SCR,0.25,o);
            lf([cn '|' reds{k}.name]) = calibrate_lf(pr0, ...
                @(x) reds{k}.compose(phid,Hd,Rrd,x), Ptarget, reds{k}.name, o.MatchTol, o.MatchIters);
        end
    end
end

% ----- PHASE 0b: pin the (constant-Z) static to 1 pu via its shunt cap -------
% true_static is constant-Z (draws P ~ V^2), so it draws 1 pu only at V ~ 1 pu.
% At weak corners it sags, so we tune its shunt cap CapC (secant) to hold
% Vterm = 1.0 -- then the constant-Z load draws its 1 pu setpoint. Same reactive-
% support mechanism the CMLD has (its CapC); mirrors the sensitivity study's
% capMult centering. scap: "corner" -> calibrated CapC.
scap = containers.Map();
if o.Static
    for ci = 1:numel(cnames)
        cn = cnames{ci}; M = corners.(cn)(1); SCR = corners.(cn)(2);
        ps0 = mkparams('static', fullfile(mdir,[o.StaticModel '.slx']), M,SCR,0.25,o);
        scap(cn) = calibrate_cap(ps0, 1.0, o.VTol, o.MatchIters);
    end
end

% ----- PHASE 1: run every sim ONCE, in parallel, via sweep ------------------
% The analysis loop below is inherently serial (equiv_report + figures run on
% the client). To use the pool we first WARM the dedup cache: build one point
% per (corner x disturbance x {full, static, reduced}) and run them through
% sb_grid_testbench.sweep, which simulates NEW points on parfor workers while
% the orchestrator stays the SOLE DB writer (single-writer seam). The analysis
% loop then hits the cache (run_point returns stored rows, no re-sim). Params
% are built by the SAME path (mkparams + compose) so the hashes match exactly.
% Guarded: if sweep fails, the analysis loop still simulates the points itself.
specs = {};
for ci = 1:numel(cnames)
    cn = cnames{ci}; M = corners.(cn)(1); SCR = corners.(cn)(2);
    for dp = dpset
        specs{end+1} = pt('full_cmld', fullmodel, M,SCR,dp, ...
                          compose_full_or_2x(fullmodel,phid,Hd,Rrd, lf([cn '|__full__']))); %#ok<AGROW>
        if o.Static
            specs{end+1} = pt('static', o.StaticModel, M,SCR,dp, ...
                              struct('CapC', scap(cn))); %#ok<AGROW>
        end
        for k = 1:numel(reds)
            specs{end+1} = pt('full_cmld', reds{k}.model, M,SCR,dp, ...
                              reds{k}.compose(phid,Hd,Rrd, lf([cn '|' reds{k}.name]))); %#ok<AGROW>
        end
    end
end
fprintf('[phase1] %d points; Parallel=%d Pool=%d\n', numel(specs), useParallel, o.Pool);
try
    sb_grid_testbench.sweep(sb_grid_sim.default_params('full_cmld'), ...
        @(~,sp) build_point(sp, mdir, o), specs, ...
        'Parallel', useParallel, 'DBFile', db, 'RawDir', raw);
catch ME
    warning('reduce_cmld:prepass', ...
        'parallel pre-pass failed (%s); analysis loop will simulate serially', ME.message);
end

% ----- PHASE 2: analysis (serial, client-side) ------------------------------
% run every corner x disturbance x candidate
rows = {};
for ci = 1:numel(cnames)
    cn = cnames{ci}; M = corners.(cn)(1); SCR = corners.(cn)(2);
    fprintf('\n==== %s corner %s: M=%g SCR=%g  (H=%.2f Rr=%.2f phi=%.2f) ====\n', ...
            upper(level), cn, M, SCR, Hd, Rrd, phid);

    for dp = dpset
        tag = sprintf('%s_%s_dp%+.2f', level, cn, dp);

        % FULL reference (also pinned to P_W)
        pf = mkparams('full_cmld', fullfile(mdir,[fullmodel '.slx']), M,SCR,dp,o);
        pf.model_vars = compose_full_or_2x(fullmodel, phid, Hd, Rrd, lf([cn '|__full__']));
        rf = sb_grid_testbench.run_point(pf,'DBFile',db,'RawDir',raw);
        full = load_trace(rf.trace_path, dp*pf.scale.P_W);
        full.label = 'full';

        % STATIC reference (constant-Z, cap-centered to 1 pu), optional/guarded
        stat = [];
        if o.Static
            ps = mkparams('static', fullfile(mdir,[o.StaticModel '.slx']), M,SCR,dp,o);
            ps.model_vars = struct('CapC', scap(cn));   % shunt cap tuned to hold Vterm=1.0
            try
                rs = sb_grid_testbench.run_point(ps,'DBFile',db,'RawDir',raw);
                stat = load_trace(rs.trace_path, dp*ps.scale.P_W);
            catch ME
                warning('reduce_cmld:static','static ref skipped (%s)',ME.message);
            end
        end

        % each REDUCED candidate
        for k = 1:numel(reds)
            pr = mkparams('full_cmld', fullfile(mdir,[reds{k}.model '.slx']), M,SCR,dp,o);
            pr.model_vars = reds{k}.compose(phid, Hd, Rrd, lf([cn '|' reds{k}.name]));
            rr = sb_grid_testbench.run_point(pr,'DBFile',db,'RawDir',raw);
            red = load_trace(rr.trace_path, dp*pr.scale.P_W);
            red.label = reds{k}.name;

            fig = fullfile(figdir, sprintf('reduce_%s_%s.png', tag, reds{k}.name));
            R = equiv_report(full, red, 'Static',stat, 'M_g1',M, ...
                    'Class',class, 'TraceWin',o.TraceWin, 'FigFile',fig, ...
                    'Title',sprintf('%s  %s  dP=%+.2f pu  %s vs full', upper(level),cn,dp,reds{k}.name));

            rows(end+1,:) = {level, cn, M, SCR, dp, reds{k}.name, ...
                100*R.rocof_oper_err, 100*R.dip_err, R.f_maxe, R.P_maxe, ...
                R.gate.pass, R.verdict}; %#ok<AGROW>
        end
    end
end

T = cell2table(rows, 'VariableNames', ...
    {'level','corner','M','SCR','dp','candidate', ...
     'rocof500_err_pct','dip_err_pct','f_maxe_pct','P_maxe_pct','gate_pass','verdict'});
save(fullfile(sc, sprintf('reduce_%s.mat',level)), 'T');
fprintf('\n===== %s summary =====\n', upper(level)); disp(T);
fprintf('figures -> %s\nREDUCE_%s_OK\n', figdir, upper(level));
end

% =========================== level specification ============================
function [fullmodel, reds, class] = level_spec(level)
% Each candidate's compose takes (phi,H,Rr,LFm), the motor load factor tuned to
% pin the model to the P_W (1 pu) power target. 'match' = calibrate LFm for this
% candidate (all have a motor lever, so all true).
switch upper(level)
    case 'L0'
        fullmodel = 'cmld_3m_2x'; class = 'exact';
        reds = {struct('name','1cmld','model','cmld_3m','match',true, ...
                       'compose',@(phi,H,Rr,LFm) compose_full(phi,H,Rr,[],LFm))};
    case 'L1'
        fullmodel = 'cmld_3m'; class = 'lossy';
        reds = {struct('name','ct','model','cmld_1m_ct','match',true, ...
                       'compose',@(phi,H,Rr,LFm) compose_1mot(phi,H,Rr,0,[],LFm)), ...  % const torque
                struct('name','vt','model','cmld_1m_vt','match',true, ...
                       'compose',@(phi,H,Rr,LFm) compose_1mot(phi,H,Rr,2,[],LFm))};     % var torque
    case 'L2'
        fullmodel = 'cmld_3m'; class = 'lossy';
        reds = {struct('name','elec','model','cmld_3m_elec','match',true, ...
                       'compose',@(phi,H,Rr,LFm) compose_passive(phi,H,Rr,'elec',[],LFm)), ...  % chosen
                struct('name','stat','model','cmld_3m_stat','match',true, ...
                       'compose',@(phi,H,Rr,LFm) compose_passive(phi,H,Rr,'stat',[],LFm))};     % foil
    otherwise
        error('reduce_cmld:level','unknown level "%s" (L0..L2)', level);
end
end

% =========================== param assembly ================================
function p = mkparams(load_type, model_path, M, SCR, dp, o)
p = sb_grid_sim.default_params(load_type);
p.grid.M = M; p.grid.SCR = SCR;
p.disturbance.dist_dP_frac = dp;              % signed: + load rise, - load drop
p.solver.SettleTime = o.ST; p.solver.StopTime = o.RT;
p.model_path = model_path;                    % study-local hand-authored .slx
end

function sp = pt(lt, model, M, SCR, dp, mv)
% One Phase-1 point spec (a struct, so it survives the sweep builder closure).
sp = struct('lt',lt, 'model',model, 'M',M, 'SCR',SCR, 'dp',dp, 'mv',mv);
end

% =========================== power/voltage calibration ======================
function [P, V] = probe_PV(p, mv)
% Settle the model and return the pre-disturbance active power (W) and terminal
% voltage (pu). SHORT post-disturbance window (settled values are all we need);
% simulate directly (pure, no DB) so calibration probes stay off the results DB.
p.model_vars = mv;
p.solver.StopTime = p.disturbance.dist_time + 3;
r = sb_grid_sim.simulate(p);
td = r.meta.dist_time_abs;
m  = r.t < td & r.t > td-1;                 % last 1 s before the step
P  = mean(r.P(m));  V = mean(r.V(m));
end

function P = probe_P(p, mv)
[P, ~] = probe_PV(p, mv);
end

function C = calibrate_cap(pbase, Vtarget, tol, maxit)
% Tune the (constant-Z) static's shunt cap CapC so its settled Vterm == Vtarget
% (=1.0 pu) -> the constant-Z load then draws its 1 pu setpoint. Vterm rises
% monotonically with CapC (more shunt reactive) below resonance, so secant
% converges fast. Seeds are sized for the 220 kV bus (~1e-4 F range) -- NB the
% CMLD's CapC=0.037 is for its internal 11 kV bus; that value is ~400x too large
% here and shorts the 220 kV node, so do NOT seed from it (verified 2026-07-13).
C1 = 2e-5;  [~,V1] = probe_PV(pbase, struct('CapC',C1));
C2 = 1e-4;  [~,V2] = probe_PV(pbase, struct('CapC',C2));
fprintf('  [calCap C=%.5f] Vterm=%.4f\n  [calCap C=%.5f] Vterm=%.4f\n', C1,V1,C2,V2);
C = C2;
for it = 1:maxit
    if abs(V2 - Vtarget) < tol, C = C2; return; end
    slope = (V2-V1)/(C2-C1);                       % dV/dCapC (>0)
    if slope == 0, break; end
    C = max(C2 + (Vtarget-V2)/slope, 0);           % secant step, cap >= 0
    [~,V] = probe_PV(pbase, struct('CapC',C));
    fprintf('  [calCap C=%.5f] Vterm=%.4f  err=%+.4f\n', C, V, V-Vtarget);
    C1=C2; V1=V2; C2=C; V2=V;                       % advance the secant window
end
if abs(V2-Vtarget) >= tol
    warning('reduce_cmld:calCap','static V-match not reached (%.4f pu after %d its)', V2, it);
end
end

function LFm = calibrate_lf(pbase, compose_lf, Ptarget, name, tol, maxit)
% Find the equivalent-motor load factor LFm so the reduced model's settled
% P_load == Ptarget (the full model's), by secant iteration. P_load is monotone
% increasing in LFm, so this converges quickly (usually 2-3 EMT probes).
LFm = 0.75; LFh = []; Ph = [];
for it = 1:maxit
    P = probe_P(pbase, compose_lf(LFm));
    err = (P - Ptarget)/Ptarget;
    fprintf('  [cal %-3s LFm=%.4f] P=%.1f MW  err=%+.2f%%\n', name, LFm, P/1e6, 100*err);
    LFh(end+1)=LFm; Ph(end+1)=P; %#ok<AGROW>
    if abs(err) < tol, break; end
    if numel(LFh) >= 2 && Ph(end) ~= Ph(end-1)
        slope = (Ph(end)-Ph(end-1))/(LFh(end)-LFh(end-1));   % dP/dLFm
        LFm = LFh(end) + (Ptarget - Ph(end))/slope;          % secant step
    else
        LFm = LFm * (Ptarget/P);                              % first step: proportional
    end
    LFm = min(max(LFm, 0.30), 2.0);                           % sane bounds
end
if abs((P-Ptarget)/Ptarget) >= tol
    warning('reduce_cmld:matchP','%s did not reach P-match tol (%.2f%% after %d its)', ...
            name, 100*(P-Ptarget)/Ptarget, it);
end
end

function p = build_point(sp, mdir, o)
% sweep builder: spec -> full params, via the SAME path as the analysis loop
% (mkparams + model_vars) so param_hash matches and Phase 2 hits the cache.
p = mkparams(sp.lt, fullfile(mdir,[sp.model '.slx']), sp.M, sp.SCR, sp.dp, o);
if ~isempty(fieldnames(sp.mv)), p.model_vars = sp.mv; end
end

function tr = load_trace(trace_path, Pdist_W)
% Build the trace struct equiv_report wants from a run_point trace .mat.
S = load(trace_path); r = S.results;
tr = struct('t',r.t(:), 'f',r.f(:), 'P',r.P(:), 'V',r.V(:), ...
            'td', r.meta.dist_time_abs, 'Pref', r.meta.P_ref_g1, 'Pdist', Pdist_W);
end

% ===================== composition / equivalencing math =====================
% CONTRACT: these produce the model_vars each hand-authored .slx must read
% (plan §7). Motor baselines are the AEMO PSS/E CMLD defaults (per-unit, on each
% motor's own MVA base); A = constant-torque, B/C = variable-torque.

function b = motor_baseline()
% [Rs Lls], [Rr Llr], Lm, load fraction, torque exponent (0=const, 2=~w^2)
b.frac  = [0.152 0.166 0.129];               % A B C  (NSW annual avg)
b.Stator = {[0.02 0.072], [0.03 0.114], [0.03 0.114]};
b.Rotor  = {[0.05955 0.04937], [0.02810 0.07959], [0.02810 0.07959]};
b.Lm     = [1.728 1.686 1.686];
b.etrq   = [0 2 2];
b.LF     = 0.75;                             % loading factor
b.felec  = 0.337; b.fstat = 0.216;           % non-motor split
end

function mv = compose_full(phi, H, Rrscale, Pw, LFm)
% Full 3-motor CMLD at the design point.  mv holds MotorA/B/C_* + passive + CapC.
% LFm (optional) = common motor load factor -- the power-match knob (like
% compose_1mot). Applied uniformly to A/B/C's slip/Tm/IC/Pmec; each motor's Pn
% (rating/inertia) stays fixed on the nominal b.LF, so LFm moves only the
% steady-state draw. Used to pin the full model to the P_W (1 pu) target.
if nargin < 4 || isempty(Pw), Pw = 2405e6; end
b = motor_baseline(); fm = sum(b.frac); L = 'ABC'; mv = struct();
if nargin < 5 || isempty(LFm), LFm = b.LF; end
for i = 1:3
    X = L(i);
    Pmec = phi*(b.frac(i)/fm)*Pw;  Pn = Pmec/b.LF;      % Pn fixed on nominal LF
    Rr = b.Rotor{i}(1)*Rrscale;  Llr = b.Rotor{i}(2);
    s  = deal_slip(Rr, LFm);                            % slip at the tuned load factor
    mv.(['Motor' X '_Nom'])    = [Pn 11000 50];
    mv.(['Motor' X '_Stator']) = b.Stator{i};
    mv.(['Motor' X '_Rotor'])  = [Rr Llr];
    mv.(['Motor' X '_Lm'])     = b.Lm(i);
    mv.(['Motor' X '_Mech'])   = [H 0 2];
    mv.(['Motor' X '_Pmec'])   = LFm*Pn;                % actual mech load, scales w/ LFm
    mv.(['Motor' X '_Tm'])     = LFm/(1-s);
    mv.(['Motor' X '_TrqExp']) = b.etrq(i);
    mv.(['Motor' X '_IC'])     = [s 0 0 0 0 0 -120 120];
end
mv = add_passive(mv, b, phi, Pw, 'split');   % elec + static as in the fixture
mv.CapC = 0.037092*(Pw/2405e6);
end

function mv = compose_1mot(phi, H, Rrscale, trqexp, Pw, LFm)
% L1: aggregate motors A+B+C -> ONE equivalent motor. MVA-weighted average of
% per-unit params (exact for identical motors; validated by L0). H_eq is the
% MVA-weighted H (= H here, since H is common -> so L1 tests torque/electrical
% abstraction, not inertia; plan §4.1). trqexp selects the torque law.
%
% LFm (optional) = equivalent-motor LOAD FACTOR, the power-match knob (plan
% §5.2). The MVA-weighted per-unit aggregation is approximate, so the single
% equivalent draws slightly different P than the 3 real motors; LFm re-tunes the
% mechanical load (slip + Tm) so the reduced model's pre-disturbance P_load
% matches the full model's -- the gate precondition. Crucially the RATING Pn_eq
% (hence the motor's absolute inertia H_eq*Pn_eq) is held FIXED on the nominal
% b.LF, so LFm moves ONLY the steady-state draw, never the inertial response.
if nargin < 5 || isempty(Pw), Pw = 2405e6; end
b = motor_baseline(); fm = sum(b.frac);
if nargin < 6 || isempty(LFm), LFm = b.LF; end
Pmec = phi*(b.frac/fm)*Pw;  S = Pmec/b.LF;  w = S/sum(S);   % MVA weights
Rs_eq  = w*cellfun(@(z)z(1), b.Stator)';   Lls_eq = w*cellfun(@(z)z(2), b.Stator)';
Rr_eq  = (w*cellfun(@(z)z(1), b.Rotor)')*Rrscale;
Llr_eq = w*cellfun(@(z)z(2), b.Rotor)';
Lm_eq  = w*b.Lm';   H_eq = H;                                % w*[H H H]' = H
Pn_eq  = sum(Pmec)/b.LF;                     % RATING fixed on nominal LF -> inertia fixed
s = deal_slip(Rr_eq, LFm);                   % operating slip at the (tuned) load factor
mv = struct();
mv.Motor_Nom    = [Pn_eq 11000 50];
mv.Motor_Stator = [Rs_eq Lls_eq];
mv.Motor_Rotor  = [Rr_eq Llr_eq];
mv.Motor_Lm     = Lm_eq;
mv.Motor_Mech   = [H_eq 0 2];
mv.Motor_Pmec   = LFm*Pn_eq;                 % actual mech load (= Tm*(1-s)*Pn), scales w/ LFm
mv.Motor_Tm     = LFm/(1-s);                 % load torque -- the power-match lever
mv.Motor_TrqExp = trqexp;                                    % 0=const, 2=variable
mv.Motor_IC     = [s 0 0 0 0 0 -120 120];
mv = add_passive(mv, b, phi, Pw, 'split');
mv.CapC = 0.037092*(Pw/2405e6);
end

function mv = compose_passive(phi, H, Rrscale, mode, Pw, LFm)
% L2: motors A+B+C unchanged (full); collapse elec+static into ONE block.
% mode 'elec' (chosen) = single electronic; 'stat' (foil) = single static ZIP.
if nargin < 5 || isempty(Pw), Pw = 2405e6; end
if nargin < 6, LFm = []; end
mv = compose_full(phi, H, Rrscale, Pw, LFm);
b = motor_baseline();
% strip the split passive vars, replace with a single aggregated block
for f = {'CMLD_ElecP','P0','Q0'}, if isfield(mv,f{1}), mv = rmfield(mv,f{1}); end, end
mv = add_passive(mv, b, phi, Pw, mode);
end

function mv = add_passive(mv, b, phi, Pw, mode)
Pnm = (1-phi)*Pw;                            % total non-motor power
switch mode
    case 'split'                             % fixture: elec + static, ratio e:st
        e = b.felec/(b.felec+b.fstat);
        mv.CMLD_ElecP = e*Pnm;  mv.P0 = (1-e)*Pnm;  mv.Q0 = 0.20*mv.P0;
    case 'elec'                              % all non-motor -> one electronic
        mv.CMLD_ElecP = Pnm;    mv.P0 = 0;   mv.Q0 = 0;
    case 'stat'                              % all non-motor -> one static ZIP
        mv.CMLD_ElecP = 0;      mv.P0 = Pnm; mv.Q0 = 0.20*Pnm;
end
end

function mv = compose_full_or_2x(model, phi, H, Rr, LFm)
% cmld_3m -> one CMLD at full power. cmld_3m_2x -> TWO IDENTICAL copies of the
% same CMLD subsystem, both reading the SAME var names; we supply HALF-power
% values so each instance draws 1/2 and the pair totals full (L0 control). No
% per-instance prefixing needed -- the two copies share one model_vars set.
% LFm (optional) = motor load factor for the P_W power-match (pins the full).
if nargin < 5, LFm = []; end
Pw = 2405e6;
if strcmp(model,'cmld_3m_2x')
    mv = compose_full(phi, H, Rr, 0.5*Pw, LFm);   % each of the 2 identical instances draws half
else
    mv = compose_full(phi, H, Rr, Pw, LFm);
end
end

% =============================== small utils ================================
function s = deal_slip(Rr, LF)
s = LF*Rr; for it = 1:8, s = (LF/(1-s))*Rr; end
end

function assert_models_present(names, mdir)
names = unique(names, 'stable'); missing = {};
for i = 1:numel(names)
    if ~isfile(fullfile(mdir, [names{i} '.slx'])), missing{end+1} = names{i}; end %#ok<AGROW>
end
if ~isempty(missing)
    error('reduce_cmld:missingModels', ...
        ['Author these hand-authored models into %s first (plan §7):\n  %s\n' ...
         'Each must honour docs/model-interface.md and read the model_vars this ' ...
         'driver composes.'], mdir, strjoin(strcat(missing,'.slx'), ', '));
end
end
