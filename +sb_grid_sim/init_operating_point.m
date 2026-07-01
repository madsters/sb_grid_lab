function info = init_operating_point(model, params)
%SB_GRID_SIM.INIT_OPERATING_POINT  Steady-state init by settling (no load flow).
%
%   info = sb_grid_sim.init_operating_point(model, params)
%
% Two-pass settle that balances the swing mechanical-power reference so the
% pre-disturbance frequency sits at ~50 Hz, then captures the COMPLETE final
% state so the disturbance run starts from a flat baseline. Ported from
% testbench/init_operating_point.m but driven by the sb_grid_sim params struct
% via apply_params (NOT the legacy init_testbench_params).
%
% WHY NOT powergui LOAD FLOW: scripted power_loadflow does not converge on these
% models (the CMLD dynamic load runs under external P/Q control and the async
% machine IC vectors are neither returned nor written). So we settle, then set
% P_ref_g1 to the measured load power -> swing balances -> omega -> 1 pu.
%
%   PASS 1: apply_params with the disturbance disabled (huge dist_time); short
%           settle (~10 s) -> measure the P_load tail -> set P_ref_g1 in base.
%   PASS 2: long settle (params.solver.SettleTime) with complete-final-state
%           capture -> xFinal (snapshotTime reset to 0 where the release allows).
%
% Returns info: P_ref_g1, Vterm_pu, baseline_Hz, baseline_drift_Hzps, xFinal.
% Caller (simulate) has already load_system'd and enforce_config'd the model.

% --- physical params with the disturbance OFF (huge dist_time) ---------------
p = params;
p.disturbance.dist_time = 1e9;          % effectively disables the step during settle
sb_grid_sim.apply_params(p);

% --- PASS 1: quick settle to estimate the balanced mechanical-power reference.
% Load power (motors + voltage) settles within a few seconds, so a short run
% gives a good P_ref even though the slow swing/turbine has not settled yet.
set_param(model,'StopTime','10','LoadInitialState','off', ...
          'SaveFinalState','off','SaveCompleteFinalSimState','off');
so   = sim(model);
Vt   = tailmean(so.get('vrms_pu'));
Pset = tailmean(so.get('P_load'));
assignin('base','P_ref_g1', Pset);          % swing balances -> omega -> 1 pu @ 50 Hz

% --- PASS 2: long settle with the balanced P_ref to a flat steady state, and
% capture the COMPLETE final state for the disturbance-run handoff. Do NOT auto-
% drive the EMF up at very weak SCR (the CMLD shunt caps + motors can self-excite
% into overvoltage); lower SCR deliberately and check the reported Vterm instead.
set_param(model,'StopTime',num2str(params.solver.SettleTime), ...
          'LoadInitialState','off', ...
          'SaveFinalState','on','SaveCompleteFinalSimState','on','FinalStateName','xFinal');
so2    = sim(model);
xFinal = so2.get('xFinal');
% Rebase the operating point to t=0 so the disturbance run's clock starts at 0
% (a ModelOperatingPoint stores the settle StopTime as snapshotTime; the next sim
% otherwise CONTINUES from there). If snapshotTime is read-only on this release
% (e.g. R2025b), the catch leaves it and simulate offsets its clock by it.
try, xFinal.snapshotTime = 0; catch, end
assignin('base','xFinal', xFinal);          % simulate starts the run from here

fsig = so2.get('freq_hz');
f2   = fsig.Data;  fb = mean(f2(max(1,end-100):end));
% drift over the last 2 s of the settle -- a flat baseline needs this ~0
fts  = fsig.Time;  tail2 = fts >= fts(end)-2;
drift = (f2(find(tail2,1,'last')) - f2(find(tail2,1,'first'))) / 2;   % Hz/s

info = struct('P_ref_g1',Pset,'Vterm_pu',Vt, ...
              'baseline_Hz',fb,'baseline_drift_Hzps',drift,'xFinal',xFinal);
fprintf(['[op] Vterm=%.3f pu, balanced P_ref=%.1f MW -> baseline %.4f Hz ' ...
         '(drift %+0.2e Hz/s over last 2 s of %gs settle)\n'], ...
        Vt, Pset/1e6, fb, drift, params.solver.SettleTime);
end

function m = tailmean(ts)
%TAILMEAN  Mean of the last <=101 samples of a logged signal.
d = ts.Data;
m = mean(d(max(1,end-100):end));
end
