function study4(mode)
% CMLD 4-factor sensitivity (H, Rr, Lr, phi) vs static, at one (M,SCR) corner.
%   study4('smoke')  -> 4 pts, PARALLEL(2), validate plumbing + worker paths
%   study4('sense')  -> 3^4=81 grid at midrange M=5,SCR=6, parallel(6) (~20 min)
%   study4('phase1') -> 4^4=256 grid, parallel(6) (~1 h)  [overnight-scale]
%
% NOTE (2026-07-08): preserved pre-refactor driver. Models resolve by load_type
% via sb_grid_sim.load_types -> models/<name>.slx (startup_sbgrid puts models/ on
% the path); the .slx is loaded read-only, never modified. Per
% studies/cmld_inertia_sensitivity.md the next revision should DROP Lr (inert,
% ~1% SS), ADD the Vterm in [0.95,1.05] operating-point filter, and parametrise
% the corner list for the 4-corner run.
if nargin<1, mode='smoke'; end
sc    = fileparts(mfilename('fullpath'));                 % studies/
repo  = fileparts(sc);                                    % sb_grid_lab/
db    = fullfile(sc,'study4.db');  raw = fullfile(sc,'study4_raw');
figdir= fullfile(repo,'results','fig'); if ~isfolder(figdir), mkdir(figdir); end

% BRIDGE (KNOWN TECH-DEBT, 2026-07-08): the hand-authored models' PreLoadFcn calls
% init_testbench_params(...), which sets the load-internal baselines (MotorX_Stator/Lm,
% static load) and pulls the AU14 data tree. That function did NOT move into sb_grid_lab,
% so put the original testbench dir on the path (it self-bootstraps AU14). Reads a few
% small .m files off Google Drive; models + sims stay local. Follow-up: vendor these in
% or refactor the models to drop the PreLoadFcn dependency.
if isempty(which('init_testbench_params'))
    tb = 'H:\My Drive\Education\Zettelkasten\05 - Projects\IEEE 14 Generator Model\testbench';
    assert(isfolder(tb), 'study4:missingDep', ...
        'init_testbench_params not on path and testbench bridge dir not found: %s', tb);
    addpath(tb);   % before parpool so local workers inherit it (AutoAddClientPath)
end

M = 5; SCR = 6;                                   % MIDRANGE corner
switch mode
  case 'smoke'
    Hs=[1 2]; Rrs=[1]; Lrs=[1]; phis=[0.4 0.6]; ST=12; RT=8;  npool=2;
  case 'sense'
    Hs=[0.1 2 4]; Rrs=[0.5 1 2]; Lrs=[0.5 1 2]; phis=[0.2 0.5 0.8]; ST=15; RT=10; npool=5;
  case 'phase1'
    Hs=[0.1 1 2 4]; Rrs=[0.5 1 1.5 2]; Lrs=[0.5 1 1.5 2]; phis=[0.2 0.4 0.6 0.8]; ST=15; RT=10; npool=6;
end

[HH,RR,LL,PP] = ndgrid(Hs,Rrs,Lrs,phis);
G = [HH(:) RR(:) LL(:) PP(:)];  n = size(G,1);
fprintf('study4 %s: corner M=%g SCR=%g, %d CMLD points, pool=%d\n', mode, M, SCR, n, npool);

if isempty(gcp('nocreate')), parpool('local',npool); end   % local pool inherits client path

baseC   = base(sb_grid_sim.default_params('full_cmld'), M, SCR, ST, RT);
builder = @(p,idx) compose4(p, G(idx,1), G(idx,2), G(idx,3), G(idx,4));

rs = sb_grid_testbench.run_point(base(sb_grid_sim.default_params('static'),M,SCR,ST,RT), ...
        'DBFile',db,'RawDir',raw);
fprintf('static @ corner: RoCoF=%.4f  dip=%.4f\n', rs.rocof, rs.dip);

Tc = sb_grid_testbench.sweep(baseC, builder, 1:n, 'DBFile',db,'RawDir',raw,'Parallel',true);

adv   = 100*(abs(rs.rocof)-abs(Tc.rocof))./abs(rs.rocof);   % RoCoF advantage (%)
advN  = 100*(rs.dip - Tc.dip)./rs.dip;                      % nadir-dip advantage (%)
R = table(G(:,1),G(:,2),G(:,3),G(:,4),Tc.rocof,Tc.nadir,Tc.dip,Tc.vbase,adv,advN, ...
     'VariableNames',{'H','Rr','Lr','phi','rocof','nadir','dip','vbase','adv','advN'});
save(fullfile(sc,['study4_' mode '.mat']),'R','rs');
disp(sortrows(R,'adv','descend'));

if n >= 16
    anova_ss(R.adv,  R, 'RoCoF advantage');
    anova_ss(R.advN, R, 'nadir-dip advantage');
    % interaction heatmaps (mean advantage over the other two factors)
    save_heat(R,'H','phi','adv', 'RoCoF adv %: H x phi', 'study4_heat_Hphi.png', figdir);
    save_heat(R,'H','Lr', 'adv', 'RoCoF adv %: H x Lr',  'study4_heat_HLr.png',  figdir);
    save_heat(R,'H','Lr', 'advN','nadir adv %: H x Lr',  'study4_heat_HLr_nadir.png', figdir);
    fprintf('heatmaps -> %s\n', figdir);
end
fprintf('STUDY4_%s_OK  (Vterm range %.3f..%.3f)\n', upper(mode), min(R.vbase), max(R.vbase));
end

% ---- helpers ----
function p = base(p, M, SCR, ST, RT)
% model resolves by p.load_type (set by default_params) -> load_types -> models/
p.grid.M=M; p.grid.SCR=SCR; p.solver.SettleTime=ST; p.solver.StopTime=RT;
end

function prm = compose4(prm, H, Rrs, Lrs, phi)
fA=0.152;fB=0.166;fC=0.129; fmot=fA+fB+fC; LF=0.75;
felec=0.337; fstat=0.216; e=felec/(felec+fstat); st=1-e;
Pw=prm.scale.P_W; rw=struct('A',fA/fmot,'B',fB/fmot,'C',fC/fmot);
EC.A=[0.05955 0.04937]; EC.B=[0.02810 0.07959]; EC.C=[0.02810 0.07959];
ov=struct();
for X=['A' 'B' 'C']
    Rr=EC.(X)(1)*Rrs; Lr=EC.(X)(2)*Lrs; s=deal_slip(Rr,LF);
    Pmec=phi*rw.(X)*Pw; Pn=Pmec/LF;
    ov.(['Motor' X '_Nom'])   = [Pn 11000 50];
    ov.(['Motor' X '_Rotor']) = [Rr Lr];
    ov.(['Motor' X '_Mech'])  = [H 0 2];
    ov.(['Motor' X '_Pmec'])  = Pmec;
    ov.(['Motor' X '_Tm'])    = LF/(1-s);
    ov.(['Motor' X '_IC'])    = [s 0 0 0 0 0 -120 120];
end
ov.CMLD_ElecP=e*(1-phi)*Pw; ov.P0=st*(1-phi)*Pw; ov.Q0=0.20*ov.P0;
prm.model_vars=ov;
end

function s = deal_slip(Rr, LF)
s=LF*Rr; for it=1:8, s=(LF/(1-s))*Rr; end
end

function anova_ss(y, R, label)
[~,tbl] = anovan(y, {R.H,R.Rr,R.Lr,R.phi}, 'model','interaction', ...
    'varnames',{'H','Rr','Lr','phi'}, 'display','off');
fprintf('\nANOVA (%s), SS-fraction:\n', label);
rowsSS = cell2mat(tbl(2:end-2,2)); tot=sum(rowsSS);
for k=2:size(tbl,1)-2
    fprintf('  %-14s p=%.3g  SS%%=%.1f\n', tbl{k,1}, tbl{k,7}, 100*tbl{k,2}/tot);
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
