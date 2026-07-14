function pv_diag(model, dp, ppv_frac)
%PV_DIAG  Inspect the PV-trip internal signals (pv_tripped, pv_active) directly
% from the SimulationOutput -- replicates sb_grid_sim.simulate's settle+disturbance
% flow but returns the extra logged signals so we can see WHETHER/when the trip
% fires. Debug aid for the trip mechanism.
if nargin<1, model='pv_cmld'; end
if nargin<2, dp=0.60; end
if nargin<3, ppv_frac=0.25; end
sc=fileparts(mfilename('fullpath')); repo=fileparts(fileparts(sc));
if isempty(which('sb_grid_sim.default_params')), run(fullfile(repo,'startup_sbgrid.m')); end
mpath=fullfile(sc,'models',[model '.slx']);
Pw=sb_grid_sim.default_params('full_cmld').scale.P_W;
S=load(fullfile(sc,'phase1_threshold','pv_phase1.mat'));
mv=S.traces(1).cmld.params.model_vars;
mv.P_pv=ppv_frac*Pw; mv.f_trip=49.5; mv.t_trip_delay=0.1;

p=sb_grid_sim.default_params('full_cmld');
p.grid.M=3; p.grid.SCR=5; p.disturbance.dist_dP_frac=dp;
p.solver.SettleTime=15; p.solver.StopTime=12; p.model_path=mpath; p.model_vars=mv;

if bdIsLoaded(model), close_system(model,0); end
load_system(mpath); c=onCleanup(@()close_system(model,0));
sb_grid_sim.apply_params(p); sb_grid_sim.enforce_config(model,p);
op=sb_grid_sim.init_operating_point(model,p);
t0=0; try t0=op.xFinal.snapshotTime; catch, end
td=t0+p.disturbance.dist_time;
assignin('base','dist_time',td); assignin('base','dist_dP',dp*Pw);
set_param(model,'StopTime',num2str(t0+p.solver.StopTime),'LoadInitialState','on', ...
    'InitialState','xFinal','SaveFinalState','off','SaveCompleteFinalSimState','off');
so=sim(model);

f=so.get('freq_hz'); trp=so.get('pv_tripped'); act=so.get('pv_active');
fprintf('\n[diag %s dp=%.2f P_pv=%.2fpu] t0=%.3f td=%.3f\n', model, dp, ppv_frac, t0, td);
fprintf('  freq: min=%.4f at t=%.3f\n', min(f.Data), f.Time(find(f.Data==min(f.Data),1)));
fprintf('  pv_tripped: max=%.3f  first>0.5 at t=%s\n', max(trp.Data), tstr(trp,td));
fprintf('  pv_active: pre=%.1f MW  min=%.1f MW  end=%.1f MW\n', ...
    interp1(act.Time,act.Data,td-0.1)/1e6, min(act.Data)/1e6, act.Data(end)/1e6);
% debug internals
try
  da=so.get('dbg_armed'); du=so.get('dbg_under'); dfq=so.get('dbg_freq'); ddt=so.get('dbg_dt');
  fprintf('  dbg_dt (dist_time seen by armed): first=%.3g  last=%.3g\n', ddt.Data(1), ddt.Data(end));
  fprintf('  at t=%.3f (start): freq=%.4f armed=%.0f under=%.0f\n', dfq.Time(1), dfq.Data(1), da.Data(1), du.Data(1));
  fq0=min(dfq.Data(dfq.Time<td)); i0=find(dfq.Data==fq0,1);
  fprintf('  pre-step min freq=%.4f at t=%.3f  armed there=%.0f under there=%.0f\n', fq0, dfq.Time(i0), da.Data(i0), du.Data(i0));
catch e, fprintf('  (dbg signals unavailable: %s)\n', e.message); end
fprintf('PV_DIAG_DONE\n');
end

function s=tstr(ts,td)
i=find(ts.Data>0.5,1);
if isempty(i), s='(never)'; else, s=sprintf('%.3f (%.3f after step)',ts.Time(i),ts.Time(i)-td); end
end
