function T = study_cmld(round, varargin)
% CMLD motor-parameter sensitivity vs static -- round-based runner.
%
%   T = study_cmld('r1')   4 corners x 3-level {H,Rr,phi}   112 sims  (~30-45 min)
%   T = study_cmld('r2')   4 corners x 5-level {H,Rr,phi}   504 sims  (<3 h)
%   T = study_cmld('r3')   9 corners x 5-level {H,Rr,phi}  1134 sims  (<12 h)
%
% Factors (Lr DROPPED -- screened inert ~1% SS, see cmld_inertia_sensitivity.md):
%   H   motor inertia constant   (s)
%   Rr  rotor-resistance scale   (x nominal)
%   phi motor penetration        (motor share of load)
% Corners (fixed conditions):  M (grid inertia) x SCR (grid strength).
% Nested levels so each round dedups into the next (SQLite: sim_version,param_hash).
%
% Operating-point filter: ALL points are computed + stored; the ANOVA and
% best-config ranking use only rows with Vterm (vbase) in [0.95,1.05]. The
% excluded (collapse/overvoltage) count + region is reported.
%
% Options:  'Pool',<n> workers (default 7)   'Vlo'/'Vhi' filter band.
% The .slx models are loaded READ-ONLY; motor params are supplied as model-owned
% base-workspace vars via params.model_vars (never editing the model).

ip = inputParser;
ip.addParameter('Pool',7); ip.addParameter('Vlo',0.95); ip.addParameter('Vhi',1.05);
ip.addParameter('Corners',[]);    % subset of corner indices to run this launch (default all)
ip.addParameter('Analyze',true);  % run the Vterm-filter + ANOVA/plots pass at the end
ip.addParameter('CapMult',1);     % shunt-cap scale (1=baseline). Scalar = fixed for all
                                  % corners; 'auto' = calibrate per-corner to Vterm~=1
                                  % (cached to study_cmld_<round>_capmult.mat, resumable).
ip.addParameter('CalibrateOnly',false); % just fill the per-corner capMult file, then stop
ip.addParameter('BatchSize',35);  % grid points per sweep() call -- each sweep STORES on
                                  % completion, so a wall-cap kill loses <= one batch.
ip.parse(varargin{:}); o = ip.Results;

sc     = fileparts(mfilename('fullpath'));
repo   = fileparts(sc);
db     = fullfile(sc,'study_cmld.db');  raw = fullfile(sc,'study_cmld_raw');
figdir = fullfile(repo,'results','fig'); if ~isfolder(figdir), mkdir(figdir); end
ST=15; RT=10;                                   % settle / disturbance-run stop (s)

% same PreLoadFcn bridge as study4 (models' init_testbench_params dependency)
if isempty(which('init_testbench_params'))
    tb = 'H:\My Drive\Education\Zettelkasten\05 - Projects\IEEE 14 Generator Model\testbench';
    assert(isfolder(tb),'study_cmld:missingDep','testbench bridge dir not found: %s',tb);
    addpath(tb);
end

% ----- round design ----------------------------------------------------------
switch lower(round)
  case 'r1'
    Hs=[0.1 1 4]; Rrs=[0.5 1 2]; phis=[0.2 0.5 0.8];
    Ms=[3 5.5]; SCRs=[5 8];
  case 'r2'
    Hs=[0.1 0.5 1 2 4]; Rrs=[0.5 0.75 1 1.5 2]; phis=[0.2 0.35 0.5 0.65 0.8];
    Ms=[3 5.5]; SCRs=[5 8];
  case 'r3'
    Hs=[0.1 0.5 1 2 4]; Rrs=[0.5 0.75 1 1.5 2]; phis=[0.2 0.35 0.5 0.65 0.8];
    Ms=[3 4.25 5.5]; SCRs=[5 6.5 8];
  otherwise, error('study_cmld:round','unknown round "%s"',round);
end
[HH,RR,PP]=ndgrid(Hs,Rrs,phis); Gc=[HH(:) RR(:) PP(:)]; ncell=size(Gc,1);
[MM,SS]=ndgrid(Ms,SCRs); corners=[MM(:) SS(:)]; ncorner=size(corners,1);
fprintf('study_cmld %s: %d corners x %d CMLD pts (+1 static each) = %d sims, pool=%d\n',...
    round, ncorner, ncell, ncorner*(ncell+1), o.Pool);

% Shared PERSISTENT Simulink cache (client + workers) so parallel/repeated compiles
% don't contend on a repo-root .slxc and don't recompile every launch.
cdir = fullfile(tempdir,'sbgrid_slcache');
setcache = @() Simulink.fileGenControl('set','CacheFolder',cdir,'CreateDir',true);
try, setcache(); catch ME, warning('study_cmld:cache','client cache skipped: %s',ME.message); end

csel = o.Corners; if isempty(csel), csel = 1:ncorner; end

% ----- per-corner capMult: fixed scalar, or 'auto' = calibrate to Vterm~1 ------
if (ischar(o.CapMult)||isstring(o.CapMult)) && strcmpi(o.CapMult,'auto')
    capfile = fullfile(sc, sprintf('study_cmld_%s_capmult.mat', lower(round)));
    capByCorner = resolve_capmult(capfile, corners, csel, ST, RT);   % serial probes, cached
else
    capByCorner = repmat(double(o.CapMult), ncorner, 1);
end
fprintf('capMult by corner = %s\n', mat2str(capByCorner(:)',4));
if o.CalibrateOnly
    fprintf('CALIBRATE ONLY.\nSTUDY_CMLD_%s_CAL_OK\n', upper(round)); return;
end

% pool for the sweeps (calibration above ran serially on the client)
if isempty(gcp('nocreate')), parpool('local',o.Pool); end
try, parfevalOnAll(gcp,setcache,0); catch ME, warning('study_cmld:cache','worker cache skipped: %s',ME.message); end

% ----- run every corner; grid swept in cap-sized BATCHES (each sweep stores) ---
rows = {};
for c = csel
    M = corners(c,1); SCR = corners(c,2); cm = capByCorner(c);
    baseS = setcorner(sb_grid_sim.default_params('static'),   M,SCR,ST,RT);
    baseC = setcorner(sb_grid_sim.default_params('full_cmld'),M,SCR,ST,RT);
    rs = sb_grid_testbench.run_point(baseS,'DBFile',db,'RawDir',raw);
    fprintf('[corner %d/%d] M=%g SCR=%g capMult=%.3f  static RoCoF=%.4f dip=%.4f Vterm=%.3f\n',...
        c,ncorner,M,SCR,cm,rs.rocof,rs.dip,rs.vbase);
    builder = @(p,idx) compose(p, Gc(idx,1), Gc(idx,2), Gc(idx,3), cm);
    for b0 = 1:o.BatchSize:ncell
        bidx = b0:min(b0+o.BatchSize-1, ncell);
        Tc = sb_grid_testbench.sweep(baseC, builder, bidx, 'DBFile',db,'RawDir',raw,'Parallel',true);
        adv  = 100*(abs(rs.rocof)-abs(Tc.rocof))./abs(rs.rocof);
        advN = 100*(rs.dip - Tc.dip)./rs.dip;
        for j=1:numel(bidx)
            i=bidx(j);
            rows(end+1,:) = {M,SCR,Gc(i,1),Gc(i,2),Gc(i,3), ...
                Tc.rocof(j),Tc.nadir(j),Tc.dip(j),Tc.vbase(j),adv(j),advN(j), rs.rocof,rs.dip}; %#ok<AGROW>
        end
        fprintf('  corner %d pts %d-%d stored (%d)\n', c, bidx(1), bidx(end), numel(bidx));
    end
end
T = cell2table(rows,'VariableNames',{'M','SCR','H','Rr','phi', ...
    'rocof','nadir','dip','vbase','adv','advN','rocof_stat','dip_stat'});
save(fullfile(sc,['study_cmld_' round '.mat']),'T');
if ~o.Analyze
    fprintf('ran corners %s (Analyze=false); %d rows.\nSTUDY_CMLD_%s_CHUNK_OK\n', mat2str(csel), height(T), upper(round));
    return;
end

% ----- operating-point filter ------------------------------------------------
ok = T.vbase>=o.Vlo & T.vbase<=o.Vhi;
fprintf('\nVterm filter [%.2f,%.2f]: %d/%d points kept, %d excluded (Vterm %.3f..%.3f)\n',...
    o.Vlo,o.Vhi,nnz(ok),height(T),nnz(~ok),min(T.vbase),max(T.vbase));

% ----- per-corner ANOVA + heatmaps + best config -----------------------------
Hss = nan(ncorner,2);   % [RoCoF-adv, nadir-adv] SS% of H, per corner
for c=1:ncorner
    M=corners(c,1); SCR=corners(c,2);
    sel = ok & T.M==M & T.SCR==SCR;
    tag = sprintf('M%g_SCR%g',M,SCR);
    nsel = nnz(sel); ntot = nnz(T.M==M & T.SCR==SCR);
    fprintf('\n[%s] %d/%d points pass the Vterm filter\n', tag, nsel, ntot);
    if nsel < 1, continue; end
    % heatmaps + best-config are robust to few points
    try
        save_heat(T(sel,:),'H','phi','adv', sprintf('RoCoF adv%% H x phi @ %s',tag), ['heat_' tag '_Hphi.png'], figdir);
        save_heat(T(sel,:),'H','Rr', 'adv', sprintf('RoCoF adv%% H x Rr @ %s', tag), ['heat_' tag '_HRr.png'],  figdir);
    catch ME, warning('study_cmld:heat','heatmap %s skipped: %s',tag,ME.message); end
    best = sortrows(T(sel,:),'adv','descend');
    fprintf('  best @ %s: H=%g Rr=%g phi=%g -> RoCoF adv %.1f%% nadir adv %.1f%% (Vterm %.3f)\n',...
        tag,best.H(1),best.Rr(1),best.phi(1),best.adv(1),best.advN(1),best.vbase(1));
    % ANOVA needs enough DOF for the 3-factor interaction model (~19 params)
    if nsel >= 22
        try
            Hss(c,1)=anova_ss(T.adv(sel),  T(sel,:), sprintf('RoCoF adv @ %s',tag));
            Hss(c,2)=anova_ss(T.advN(sel), T(sel,:), sprintf('nadir adv @ %s',tag));
        catch ME, warning('study_cmld:anova','ANOVA %s skipped: %s',tag,ME.message); end
    else
        fprintf('  (ANOVA skipped: %d<22 filtered pts -- insufficient DOF for interaction model)\n',nsel);
    end
end

% ----- cross-corner robustness figure ----------------------------------------
f=figure('Visible','off','Color','w','Position',[100 100 700 400]);
bar(categorical(compose_labels(corners)), Hss); ylabel('H variance share (SS %)');
legend({'RoCoF adv','nadir adv'},'Location','best'); grid on;
title(sprintf('study\\_cmld %s: motor-inertia dominance across corners',round));
exportgraphics(f,fullfile(figdir,['xcorner_Hdominance_' round '.png']),'Resolution',150); close(f);
fprintf('\nfigures -> %s\nSTUDY_CMLD_%s_OK\n', figdir, upper(round));
end

% =============================== helpers ====================================
function p = setcorner(p, M, SCR, ST, RT)
% model resolves by p.load_type -> load_types -> models/<name>.slx (read-only)
p.grid.M=M; p.grid.SCR=SCR; p.solver.SettleTime=ST; p.solver.StopTime=RT;
end

function capByCorner = resolve_capmult(capfile, corners, csel, ST, RT)
% Per-corner capMult that centres Vterm ~1.0, cached to capfile and computed
% INCREMENTALLY (saved after each corner) so a wall-cap kill is resumable.
ncorner=size(corners,1);
if isfile(capfile), S=load(capfile); capByCorner=S.capByCorner; done=S.done;
else, capByCorner=nan(ncorner,1); done=false(ncorner,1); end
for c = csel(:)'
    if done(c), continue; end
    M=corners(c,1); SCR=corners(c,2);
    fprintf('  [cal] corner %d (M=%g SCR=%g):\n', c, M, SCR);
    capByCorner(c)=calibrate_corner(M,SCR,ST,RT); done(c)=true;
    save(capfile,'capByCorner','done');
    fprintf('  [cal] -> capMult=%.3f (saved)\n', capByCorner(c));
end
end

function cm = calibrate_corner(M,SCR,ST,RT)
% Find capMult giving Vterm~1.0 at the mid grid point (H=1,Rr=1,phi=0.5).
% Vterm increases with capMult; 1-3 serial probes + secant, clamped.
p0=setcorner(sb_grid_sim.default_params('full_cmld'),M,SCR,ST,RT);
v1=probeV(p0,1.0); fprintf('     capMult=1.00 -> Vterm=%.4f\n',v1);
if abs(v1-1.0)<=0.03, cm=1.0; return; end
cm2=0.7; v2=probeV(p0,cm2); fprintf('     capMult=%.2f -> Vterm=%.4f\n',cm2,v2);
if abs(v2-v1)<1e-6, cm=1.0; else, cm=1.0+(1.0-v1)*(cm2-1.0)/(v2-v1); end
cm=min(max(cm,0.2),1.2);
v3=probeV(p0,cm); fprintf('     capMult=%.3f -> Vterm=%.4f (refine)\n',cm,v3);
if abs(v3-1.0)>0.04 && abs(v3-v2)>1e-6
    cm=cm+(1.0-v3)*(cm-cm2)/(v3-v2); cm=min(max(cm,0.2),1.2);
end
end

function v = probeV(p0,cm)
r=sb_grid_sim.simulate(compose(p0,1,1,0.5,cm)); v=r.metrics.Vbase;
end

function prm = compose(prm, H, Rrs, phi, capMult)
% {H,Rr,phi} composition with Lr fixed at 1 (dropped factor). Supplies the
% MODEL-OWNED motor/composition vars via prm.model_vars (see apply_params).
if nargin<5 || isempty(capMult), capMult=1; end
fA=0.152;fB=0.166;fC=0.129; fmot=fA+fB+fC; LF=0.75;
felec=0.337; fstat=0.216; e=felec/(felec+fstat); st=1-e;
Pw=prm.scale.P_W; rw=struct('A',fA/fmot,'B',fB/fmot,'C',fC/fmot);
EC.A=[0.05955 0.04937]; EC.B=[0.02810 0.07959]; EC.C=[0.02810 0.07959];
mv=struct();
for X=['A' 'B' 'C']
    Rr=EC.(X)(1)*Rrs; Lr=EC.(X)(2)*1; s=deal_slip(Rr,LF);   % Lr scale = 1 (dropped)
    Pmec=phi*rw.(X)*Pw; Pn=Pmec/LF;
    mv.(['Motor' X '_Nom'])   = [Pn 11000 50];
    mv.(['Motor' X '_Rotor']) = [Rr Lr];
    mv.(['Motor' X '_Mech'])  = [H 0 2];
    mv.(['Motor' X '_Pmec'])  = Pmec;
    mv.(['Motor' X '_Tm'])    = LF/(1-s);
    mv.(['Motor' X '_IC'])    = [s 0 0 0 0 0 -120 120];
end
mv.CMLD_ElecP=e*(1-phi)*Pw; mv.P0=st*(1-phi)*Pw; mv.Q0=0.20*mv.P0;
mv.CapC = 0.037092*(Pw/2405e6)*capMult;   % shunt cap (model baseline * capMult)
prm.model_vars=mv;
end

function s = deal_slip(Rr, LF)
s=LF*Rr; for it=1:8, s=(LF/(1-s))*Rr; end
end

function ssH = anova_ss(y, R, label)
% 3-factor ANOVA (main + 2-way); prints SS% table; returns H main-effect SS%.
[~,tbl] = anovan(y, {R.H,R.Rr,R.phi}, 'model','interaction', ...
    'varnames',{'H','Rr','phi'}, 'display','off');
rowsSS = cell2mat(tbl(2:end-2,2)); tot=sum(rowsSS); ssH=NaN;
fprintf('\nANOVA (%s), SS-fraction:\n', label);
for k=2:size(tbl,1)-2
    ss=100*tbl{k,2}/tot;
    fprintf('  %-10s p=%.3g  SS%%=%.1f\n', tbl{k,1}, tbl{k,7}, ss);
    if strcmp(tbl{k,1},'H'), ssH=ss; end
end
end

function save_heat(R, fa, fb, val, ttl, fname, figdir)
ua=unique(R.(fa)); ub=unique(R.(fb)); Z=nan(numel(ub),numel(ua));
for i=1:numel(ua), for j=1:numel(ub)
    Z(j,i)=mean(R.(val)(R.(fa)==ua(i) & R.(fb)==ub(j)));
end, end
f=figure('Visible','off','Color','w'); imagesc(ua,ub,Z); axis xy; colorbar;
xlabel(fa); ylabel(fb); title(ttl);
exportgraphics(f,fullfile(figdir,fname),'Resolution',150); close(f);
end

function L = compose_labels(corners)
L = arrayfun(@(i) sprintf('M%g/SCR%g',corners(i,1),corners(i,2)), ...
    1:size(corners,1),'uni',0);
end
