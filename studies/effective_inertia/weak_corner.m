function weak_corner(dp, Pool)
%WEAK_CORNER  Weak low-inertia grid (M_g1=1, H~2.6 s, SCR=5) frequency response.
%
%   weak_corner(0.30)        % simulate + plot at dP=+0.30 pu
%   weak_corner(0.30, 2)     % 2-way parallel (default)
%   weak_corner.plot(0.30)   % re-draw from saved traces (no re-sim) -- see below
%
% EXPLORATORY driver (2026-07-15) probing the study's mixes at a GENUINELY weak
% grid, after the M=3/5.5 "stress"/"nominal" corners were found to be HIGH-inertia
% (H=7.6/13.9 s). Weak corner = M_g1=1 (grid H~2.6 s; SCR=5 stays weak on strength).
% See studies/reducing_cmld/memory.md (GRID INERTIA section) for the M_g1->H mapping.
%
% Runs three mixes {A0 NEM anchor, HB25 high-H, JMAX extreme} + the true_static
% baseline, extracts the 500 ms-RoCoF effective inertia (differenced vs static),
% and draws the reducing_cmld 3-panel: frequency (Hz, 49-51) / load active power
% (pu) / accelerating power (pu) -- the two power panels share a y-scale.
% Traces -> weak_raw/weak_dp<..>.mat (regenerable); figure -> results/fig/.
%
% Reuses the SCR=5 LFm calibration (operating point is M-independent).

if nargin<2, Pool=2; end
cd(fileparts(fileparts(fileparts(mfilename('fullpath')))));   % repo root
if isempty(which('sb_grid_sim.default_params')), run('startup_sbgrid.m'); end
repo=pwd; sc='studies/effective_inertia'; addpath(sc); S=sweep_points(); Pw=S.Pw;
mp=fullfile(sc,'models','cmld_3m.slx'); spath=fullfile(repo,'studies','reducing_cmld','models','true_static.slx');
LFm=containers.Map({'0.152_0.166_0.129','0.152_0.3_0.129','0.1_0.35_0.1'},{0.3386,0.5675,0.5271});
key=@(F) sprintf('%g_%g_%g',F(1),F(2),F(3)); mixes={'A0','HB25','JMAX'};

pts={struct('id','static','lt','static','mp',spath,'mv',struct('CapC',5e-5),'H_load',NaN)};
for j=1:numel(mixes)
  mx=S.mix(strcmp({S.mix.id},mixes{j}));
  [~,info]=compose_heterogeneous(mx.H,mx.F,'Pw',Pw,'LF',S.LF,'Rrscale',S.Rrscale,'LFm',LFm(key(mx.F)));
  pts{end+1}=struct('id',mixes{j},'lt','full_cmld','mp',mp, ...
     'mv',compose_heterogeneous(mx.H,mx.F,'Pw',Pw,'LF',S.LF,'Rrscale',S.Rrscale,'LFm',LFm(key(mx.F))), ...
     'H_load',info.H_load); %#ok<AGROW>
end
n=numel(pts);
if Pool>1 && license('test','Distrib_Computing_Toolbox') && isempty(gcp('nocreate')), try, parpool('local',Pool); catch, end, end
tr=cell(1,n);
parfor i=1:n
  p=mkp(pts{i}.lt,pts{i}.mp,dp); p.model_vars=pts{i}.mv;   %#ok<PFBNS>
  r=sb_grid_sim.simulate(p);
  tr{i}=struct('id',pts{i}.id,'t',r.t(:),'f',r.f(:),'P',r.P(:),'td',r.meta.dist_time_abs, ...
               'Pref',r.meta.P_ref_g1,'Pdist',dp*Pw,'H_load',pts{i}.H_load);
end
rawdir=fullfile(sc,'weak_raw'); if ~isfolder(rawdir), mkdir(rawdir); end
save(fullfile(rawdir,sprintf('weak_dp%02.0f.mat',100*abs(dp))),'tr','dp');
weak_corner_plot(dp);
% report the 500 ms-RoCoF effective inertia (load contribution, differenced vs static)
f0=50; is=find(cellfun(@(x)strcmp(x.id,'static'),tr)); Rs=rocof(tr{is}.t,tr{is}.f,tr{is}.td,0.5); Eg=f0*abs(dp)*Pw/(2*abs(Rs));
for i=1:n
  if strcmp(tr{i}.id,'static'), continue; end
  Rf=rocof(tr{i}.t,tr{i}.f,tr{i}.td,0.5); Heff=(f0*abs(dp)*Pw/(2*abs(Rf))-Eg)/Pw; nad=min(tr{i}.f(tr{i}.t>=tr{i}.td));
  fprintf('%-5s H_load=%.2f | RoCoF500=%.3f Hz/s nadir=%.2f Hz | H_eff=%.2f s\n',tr{i}.id,tr{i}.H_load,Rf,nad,Heff);
end
fprintf('WEAK_CORNER_DONE dp=%+.2f\n',dp);
end

function p=mkp(lt,mpath,dp)
p=sb_grid_sim.default_params('full_cmld'); p.load_type=lt; p.grid.M=1; p.grid.SCR=5;
p.disturbance.dist_dP_frac=dp; p.model_path=mpath; p.solver.SettleTime=40; p.solver.StopTime=12;
end
function r=rocof(t,f,td,W), m=t>=td & t<=td+W; pf=polyfit(t(m)-td,f(m),1); r=pf(1); end
