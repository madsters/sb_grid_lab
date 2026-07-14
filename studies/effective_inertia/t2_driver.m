function T = t2_driver(varargin)
%T2_DRIVER  T2 -- delivered effective inertia H_eff and the response factor r.
%
%   T = t2_driver('Corner','both','Pool',4)
%
% Wires the heterogeneous (H,F_m) sweep (sweep_points) through the engine and
% extracts, for every (mix, corner, dP), a DELIVERED effective inertia H_eff(T)
% and the response factor r = H_eff/H_load relating it to the paper's stored-energy
% closed form (plan.md T2). Runs the cross-validated estimators E1 (differential
% RoCoF, headline) and E2 (P-omega regression, damping-isolated); E3 (KE-from-slip)
% is present but PARKED (needs slip logging -- observables.md §4) and off by default.
%
% Structure mirrors reduce_cmld (proven): pin every point to P_W (LFm secant),
% pin the static baseline to P_W (CapC secant), warm the dedup cache in parallel,
% then analyse serially on the client. Models loaded READ-ONLY; all params flow in
% as model_vars (compose_heterogeneous) -- no .slx is opened or edited.
%
% Every point that needs MATLAB is marked  % RUN:  with its expected output shape,
% so the eventual run is a check, not a discovery. Succinct outputs only: a compact
% results table (CSV + .mat), H_eff(T) curves, and the r-vs-mix trend; raw traces
% go to the gitignored DB + _raw dir.
%
% OPTIONS
%   'Corner'  'both'|'stress'|'nominal'   corners to run (default 'both')
%   'Pool'    4        parallel workers (RAM-bound; keep <=4)
%   'Robust'  true     also run the stress-corner dP robustness spurs
%   'E3'      false    enable the KE-from-slip anchor (errors unless slip logged)
%   'ST'      40       settle time (s)
%   'RT'      12       disturbance-run stop (s; >= max window + buffer)
%   'MatchTol' 0.004   pre-disturbance P-match tolerance
%   'MatchIters' 6     max secant iterations
%   'StaticPath' ''    true_static.slx (default reducing_cmld/models/true_static.slx)
%
% RETURNS T : table, one row per (corner,mix,dP), with H_load and the E1/E2 H_eff
%   at the headline 500 ms window, r factors, and E2 damping. Full H_eff(T) curves
%   + aux saved to t2_results.mat; T also written to t2_results.csv.

ip = inputParser;
ip.addParameter('Corner','both');
ip.addParameter('Pool',4);
ip.addParameter('Robust',true);
ip.addParameter('E3',false);
ip.addParameter('ST',40);
ip.addParameter('RT',12);
ip.addParameter('MatchTol',0.004);
ip.addParameter('MatchIters',6);
ip.addParameter('StaticPath','');
ip.parse(varargin{:}); o = ip.Results;

% ---- paths / setup ----------------------------------------------------------
sc   = fileparts(mfilename('fullpath'));           % studies/effective_inertia
repo = fileparts(fileparts(sc));
if isempty(which('sb_grid_sim.default_params'))
    run(fullfile(repo,'startup_sbgrid.m'));
end
addpath(sc);                                       % compose_heterogeneous + +eff_inertia
S      = sweep_points();
mdir   = fullfile(sc,'models','cmld_3m.slx');
spath  = o.StaticPath;
if isempty(spath), spath = fullfile(repo,'studies','reducing_cmld','models','true_static.slx'); end
db     = fullfile(sc,'effective_inertia.db');
raw    = fullfile(sc,'effective_inertia_raw');
figdir = fullfile(repo,'results','fig'); if ~isfolder(figdir), mkdir(figdir); end
assert(isfile(mdir),  't2_driver:model',  'missing hand-authored model: %s', mdir);
assert(isfile(spath), 't2_driver:static', 'missing static baseline: %s (reducing_cmld)', spath);

Pw = S.Pw;

switch lower(o.Corner)
    case 'both', cnames = {'stress','nominal'};
    otherwise,   cnames = {lower(o.Corner)};
end

% shared Simulink cache (parallel-safe, cross-launch) -- as reduce_cmld
try, Simulink.fileGenControl('set','CacheFolder',fullfile(tempdir,'sbgrid_slcache'),'CreateDir',true); catch, end
useParallel = o.Pool>1 && license('test','Distrib_Computing_Toolbox');
if useParallel && isempty(gcp('nocreate')), parpool('local',o.Pool); end

% =========================================================================
% PHASE 0: calibrate LFm (per mix,corner) and static CapC (per corner) to P_W.
% Serial secant; each step is one settle. % RUN: expect P_load -> P_W within tol.
% =========================================================================
lf   = containers.Map();   % "corner|mix" -> LFm
scap = containers.Map();   % "corner"     -> CapC
for ci = 1:numel(cnames)
    cn = cnames{ci}; M = S.corners.(cn)(1); SCR = S.corners.(cn)(2);
    fprintf('[matchP %s] target P_W = %.0f MW\n', cn, Pw/1e6);
    for k = 1:numel(S.mix)
        mx = S.mix(k);
        pbase = mkparams(M,SCR,0.10, mdir, o);
        % % RUN: calibrate_lf secant -> LFm; expect 2-4 EMT settles per mix, |err|<MatchTol
        lf([cn '|' mx.id]) = calibrate_lf(pbase, ...
            @(LFm) compose_heterogeneous(mx.H, mx.F, 'Pw',Pw,'LF',S.LF,'Rrscale',S.Rrscale,'LFm',LFm), ...
            Pw, mx.id, o.MatchTol, o.MatchIters);
    end
    % static baseline CapC (constant-Z; P ~ V^2) -- % RUN: secant on CapC -> P_W
    psb = mkparams(M,SCR,0.10, spath, o);
    scap(cn) = calibrate_cap(psb, Pw, o.MatchTol, o.MatchIters);
end

% =========================================================================
% Build the point list: (mix,corner,dP) CMLD + (corner,dP) static.
% =========================================================================
specs = {};
addpt = @(lt,model,M,SCR,dp,mv) struct('lt',lt,'model',model,'M',M,'SCR',SCR,'dp',dp,'mv',mv);
for ci = 1:numel(cnames)
    cn = cnames{ci}; M = S.corners.(cn)(1); SCR = S.corners.(cn)(2);
    dps = S.dp_primary;
    if o.Robust && strcmp(cn,'stress'), dps = [S.dp_primary, S.dp_robust]; end
    for dp = dps
        % static baseline for this (corner,dp)
        specs{end+1} = addpt('static', spath, M,SCR,dp, struct('CapC',scap(cn))); %#ok<AGROW>
        for k = 1:numel(S.mix)
            mx = S.mix(k);
            if ismember(dp, S.dp_robust) && ~ismember(mx.id, S.robust_ids), continue; end
            mv = compose_heterogeneous(mx.H, mx.F, 'Pw',Pw,'LF',S.LF,'Rrscale',S.Rrscale, ...
                                       'LFm',lf([cn '|' mx.id]));
            specs{end+1} = addpt('full_cmld', mdir, M,SCR,dp, mv); %#ok<AGROW>
        end
    end
end
fprintf('[phase1] %d points; Parallel=%d Pool=%d\n', numel(specs), useParallel, o.Pool);

% =========================================================================
% PHASE 1: warm the dedup cache in parallel (single-writer DB), as reduce_cmld.
% % RUN: simulates each NEW point on a worker; expect one trace .mat per point.
% =========================================================================
try
    sb_grid_testbench.sweep(sb_grid_sim.default_params('full_cmld'), ...
        @(~,sp) build_point(sp, o), specs, ...
        'Parallel', useParallel, 'DBFile', db, 'RawDir', raw);
catch ME
    warning('t2_driver:prepass','parallel pre-pass failed (%s); analysis will sim serially', ME.message);
end

% =========================================================================
% PHASE 2: analysis (serial). For each (mix,corner,dP): E1 (vs static) + E2 [+E3].
% =========================================================================
rows = {};  curves = struct('key',{},'corner',{},'id',{},'dp',{},'H_load',{}, ...
                            'windows',{},'Heff_E1',{},'Heff_E2',{});
for ci = 1:numel(cnames)
    cn = cnames{ci}; M = S.corners.(cn)(1); SCR = S.corners.(cn)(2);
    dps = S.dp_primary;
    if o.Robust && strcmp(cn,'stress'), dps = [S.dp_primary, S.dp_robust]; end
    for dp = dps
        % static trace for this (corner,dp)  -- % RUN: cache hit (already simmed)
        ps = mkparams(M,SCR,dp, spath, o); ps.model_vars = struct('CapC',scap(cn));
        rs = sb_grid_testbench.run_point(ps,'DBFile',db,'RawDir',raw);
        stat = load_trace(rs.trace_path);

        for k = 1:numel(S.mix)
            mx = S.mix(k);
            if ismember(dp, S.dp_robust) && ~ismember(mx.id, S.robust_ids), continue; end
            [~, info] = compose_heterogeneous(mx.H, mx.F, 'Pw',Pw,'LF',S.LF, ...
                            'Rrscale',S.Rrscale, 'LFm',lf([cn '|' mx.id]));
            Hload = info.H_load;

            pf = mkparams(M,SCR,dp, mdir, o);
            pf.model_vars = compose_heterogeneous(mx.H, mx.F, 'Pw',Pw,'LF',S.LF, ...
                                'Rrscale',S.Rrscale, 'LFm',lf([cn '|' mx.id]));
            % % RUN: cache hit -> stored trace; NO re-sim
            rf   = sb_grid_testbench.run_point(pf,'DBFile',db,'RawDir',raw);
            cmld = load_trace(rf.trace_path);

            dP_W = dp * Pw;
            % --- E1 differential RoCoF (headline) --------------------------
            [H1, a1] = eff_inertia.H_eff_rocof(cmld, stat, dP_W, Pw, S.windows);
            % --- E2 P-omega regression (damping-isolated) ------------------
            [H2, a2] = eff_inertia.H_eff_pomega(cmld, Pw, S.windows);
            % --- E3 KE-from-slip anchor (parked; only aux.frac_released used) ---
            a3 = struct('frac_released', nan(size(S.windows)));
            if o.E3
                [~, info3] = compose_heterogeneous(mx.H, mx.F, 'Pw',Pw,'LF',S.LF,'Rrscale',S.Rrscale);
                [~, a3] = eff_inertia.H_eff_ke(cmld, info3.S_B, info3.H, Pw, S.windows);  % errors w/o slip
            end

            iH = find(abs(S.windows-0.5)<1e-9,1);         % headline 500 ms index
            r1 = a1.headline / Hload;  r2 = a2.headline / Hload;
            rows(end+1,:) = {cn, mx.id, dp, Hload, a1.headline, a2.headline, ...
                             r1, r2, a2.damping(iH), a1.E_load(iH)/1e9, ...
                             a3.frac_released(iH)}; %#ok<AGROW>

            curves(end+1) = struct('key',sprintf('%s|%s|%+.2f',cn,mx.id,dp), ...
                'corner',cn, 'id',mx.id, 'dp',dp, 'H_load',Hload, ...
                'windows',S.windows, 'Heff_E1',H1, 'Heff_E2',H2); %#ok<AGROW>
        end
    end
end

T = cell2table(rows, 'VariableNames', ...
    {'corner','mix','dp','H_load_s','Heff_E1_500ms','Heff_E2_500ms', ...
     'r_E1','r_E2','damping_W_pu','E_load_GWs','frac_released_E3'});

% =========================================================================
% Outputs (succinct): CSV + .mat + two figures.
% =========================================================================
writetable(T, fullfile(sc,'t2_results.csv'));
save(fullfile(sc,'t2_results.mat'), 'T', 'curves');
fprintf('\n===== T2 summary (headline 500 ms) =====\n'); disp(T);

for ci = 1:numel(cnames)
    fig_heff_curve(curves, cnames{ci}, fullfile(figdir, sprintf('eff_inertia_Heff_curve_%s.png',cnames{ci})));
end
fig_r_trend(T, fullfile(figdir,'eff_inertia_r_vs_mix.png'));
fprintf('figures -> %s\nT2_DRIVER_OK  (table -> t2_results.csv/.mat)\n', figdir);
end

% =========================== param assembly ================================
function p = mkparams(M, SCR, dp, model_path, o)
p = sb_grid_sim.default_params('full_cmld');
if endsWith(lower(model_path),'true_static.slx'), p.load_type = 'static'; end
p.grid.M = M; p.grid.SCR = SCR;
p.disturbance.dist_dP_frac = dp;
p.solver.SettleTime = o.ST; p.solver.StopTime = o.RT;
p.model_path = model_path;
end

function p = build_point(sp, o)
% sweep builder: spec -> full params (SAME path as analysis so param_hash matches)
p = mkparams(sp.M, sp.SCR, sp.dp, sp.model, o);
if strcmp(sp.lt,'static'), p.load_type = 'static'; end
if ~isempty(fieldnames(sp.mv)), p.model_vars = sp.mv; end
end

function tr = load_trace(trace_path)
S = load(trace_path); r = S.results;
tr = struct('t',r.t(:), 'f',r.f(:), 'P',r.P(:), 'V',r.V(:), 'td',r.meta.dist_time_abs);
end

% =========================== P/V calibration ===============================
function [P,V] = probe_PV(p, mv)
% short settle -> pre-disturbance P (W) and Vterm (pu). Pure (no DB).
p.model_vars = mv;
p.solver.StopTime = p.disturbance.dist_time + 3;
r  = sb_grid_sim.simulate(p);                       % % RUN: one settle
td = r.meta.dist_time_abs;
m  = r.t < td & r.t > td-1;
P  = mean(r.P(m));  V = mean(r.V(m));
end
function P = probe_P(p, mv), [P,~] = probe_PV(p, mv); end

function LFm = calibrate_lf(pbase, compose_lf, Pt, name, tol, maxit)
% secant on LFm so settled P_load == Pt (P_load monotone in LFm) -- as reduce_cmld.
LFm = 0.75; LFh = []; Ph = [];
for it = 1:maxit
    P = probe_P(pbase, compose_lf(LFm));
    err = (P - Pt)/Pt;
    fprintf('  [cal %-4s LFm=%.4f] P=%.1f MW err=%+.2f%%\n', name, LFm, P/1e6, 100*err);
    LFh(end+1)=LFm; Ph(end+1)=P; %#ok<AGROW>
    if abs(err) < tol, break; end
    if numel(LFh)>=2 && Ph(end)~=Ph(end-1)
        slope = (Ph(end)-Ph(end-1))/(LFh(end)-LFh(end-1));
        LFm = LFh(end) + (Pt-Ph(end))/slope;
    else
        LFm = LFm*(Pt/P);
    end
    LFm = min(max(LFm,0.30),2.0);
end
if abs((P-Pt)/Pt) >= tol
    warning('t2_driver:matchP','%s P-match not reached (%.2f%% after %d its)', name, 100*(P-Pt)/Pt, it);
end
end

function C = calibrate_cap(pbase, Pt, tol, maxit)
% secant on the static shunt cap CapC so settled P_load == Pt (P ~ V^2 rises with
% CapC) -- as reduce_cmld.calibrate_cap. Seeds sized for the 220 kV bus.
C1 = 2e-5; [P1,~] = probe_PV(pbase, struct('CapC',C1));
C2 = 1e-4; [P2,~] = probe_PV(pbase, struct('CapC',C2));
C = C2;
for it = 1:maxit
    if abs((P2-Pt)/Pt) < tol, C = C2; return; end
    slope = (P2-P1)/(C2-C1); if slope==0, break; end
    C = max(C2 + (Pt-P2)/slope, 0);
    [P,~] = probe_PV(pbase, struct('CapC',C));
    fprintf('  [calCap C=%.5f] P=%.1f MW err=%+.2f%%\n', C, P/1e6, 100*(P-Pt)/Pt);
    C1=C2; P1=P2; C2=C; P2=P;
end
if abs((P2-Pt)/Pt) >= tol
    warning('t2_driver:calCap','static P-match not reached (%.2f%% after %d its)', 100*(P2-Pt)/Pt, it);
end
end

% =============================== figures ===================================
function fig_heff_curve(curves, corner, figfile)
% H_eff(T) vs window T for every mix at this corner (E1 solid, E2 dashed), with the
% mix's stored-energy H_load as a reference marker at the right edge. Headless.
sel = curves(strcmp({curves.corner},corner) & ([curves.dp]==0.10));
if isempty(sel), return; end
f = figure('Visible','off','Color','w','Position',[100 100 820 560]);
ax = axes(f); hold(ax,'on'); grid(ax,'on'); set(ax,'XScale','log');
co = lines(numel(sel));
for i = 1:numel(sel)
    c = sel(i);
    plot(ax, c.windows, c.Heff_E1, '-o', 'Color',co(i,:), 'LineWidth',1.3, ...
         'DisplayName',sprintf('%s (H_{load}=%.2f)', c.id, c.H_load));
    plot(ax, c.windows, c.Heff_E2, '--', 'Color',co(i,:), 'HandleVisibility','off');
end
xlabel(ax,'RoCoF window T (s)'); ylabel(ax,'H_{eff} (s)');
title(ax, sprintf('Delivered effective inertia H_{eff}(T) -- %s corner (dP=+0.10)  [E1 solid, E2 dashed]', corner));
legend(ax,'Location','northwest','FontSize',8);
exportgraphics(f, figfile, 'Resolution',150); close(f);
end

function fig_r_trend(T, figfile)
% The core result: response factor r = H_eff/H_load vs the stored-energy H_load,
% at the headline 500 ms window. Is r stable, or does it drift with the mix?
f = figure('Visible','off','Color','w','Position',[100 100 760 520]);
ax = axes(f); hold(ax,'on'); grid(ax,'on');
prim = T(T.dp==0.10,:);
cc = categorical(prim.corner);
gscatter_local(ax, prim.H_load_s, prim.r_E1, cc);
xlabel(ax,'stored-energy H_{load} (s)'); ylabel(ax,'response factor r = H_{eff}/H_{load}  (E1, 500 ms)');
title(ax,'Response factor vs mix -- is r stable as per-motor H / fractions vary?');
yline(ax,1,':','r = 1 (full release)'); legend(ax,'Location','best');
exportgraphics(f, figfile, 'Resolution',150); close(f);
end

function gscatter_local(ax, x, y, g)
% minimal grouped scatter (avoids Statistics Toolbox gscatter)
cats = categories(g); co = lines(numel(cats));
for i = 1:numel(cats)
    m = g==cats{i};
    scatter(ax, x(m), y(m), 48, co(i,:), 'filled', 'DisplayName',char(cats{i}));
end
end
