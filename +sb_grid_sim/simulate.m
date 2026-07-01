function r = simulate(params, varargin)
%SB_GRID_SIM.SIMULATE  Run one frequency-dynamics scenario end to end.
%
%   r = sb_grid_sim.simulate(params)
%   r = sb_grid_sim.simulate(params, 'ModelPath', fullpath)
%
% The integrator. Resolves the model from params.load_type via
% sb_grid_sim.load_types (-> models/<name>.slx on the path), loads it READ-ONLY,
% applies the params, enforces the solver/state config, settles to a flat
% operating point, then runs the disturbance from that captured state and
% extracts metrics. The .slx is NEVER saved.
%
% Options:
%   'ModelPath'  full path to an .slx to load instead of resolving by load_type
%                (also honoured as params.model_path). Lets a fixture be injected
%                for testing/validation.
%
% Returns the contract-2 results struct:
%   .params .sim_version .t .f .P .V .metrics .meta
% PURE: performs no DB/file/figure I/O and never saves the model.

% --- options -----------------------------------------------------------------
ip = inputParser; ip.KeepUnmatched = true;
ip.addParameter('ModelPath','');
ip.parse(varargin{:});
modelPath = ip.Results.ModelPath;
if isempty(modelPath) && isfield(params,'model_path') && ~isempty(params.model_path)
    modelPath = params.model_path;
end

% --- resolve + load the model READ-ONLY --------------------------------------
if ~isempty(modelPath)
    [~, model] = fileparts(modelPath);
    loadTarget = modelPath;
else
    model      = sb_grid_sim.load_types(params.load_type);   % base name
    loadTarget = model;                                       % resolved on the path
end

wasLoaded = bdIsLoaded(model);
if ~wasLoaded
    load_system(loadTarget);
    % NEVER save: discard the in-memory mutations on exit.
    cleanupModel = onCleanup(@() close_system(model,0));
end

% --- params + solver/state config (in memory) --------------------------------
sb_grid_sim.apply_params(params);
sb_grid_sim.enforce_config(model, params);

% --- settle to a flat operating point (captures base 'xFinal') ---------------
op = sb_grid_sim.init_operating_point(model, params);

% --- disturbance run from the captured state ---------------------------------
% The operating point's snapshotTime is 0 where the release allowed the rebase,
% else the settle StopTime; offset the disturbance + stop time by it so the run
% is valid and the clock is consistent. The disturbance is referenced to the
% NOMINAL load P_W (absolute MW), so every load type gets the same step.
t0 = 0;
try, t0 = op.xFinal.snapshotTime; catch, end

P_W = params.scale.P_W;
td  = t0 + params.disturbance.dist_time;                 % absolute disturbance time
assignin('base','dist_time', td);
assignin('base','dist_dP',   params.disturbance.dist_dP_frac * P_W);

set_param(model, ...
    'StopTime',                 num2str(t0 + params.solver.StopTime), ...
    'LoadInitialState',         'on', ...
    'InitialState',             'xFinal', ...
    'SaveFinalState',           'off', ...
    'SaveCompleteFinalSimState','off');
% don't leak LoadInitialState into a subsequent run on the same loaded model
% (guard on bdIsLoaded: if the model was loaded by us it may already be closed
% by the close_system cleanup, in which case there is nothing to reset)
cleanupLIS = onCleanup(@() reset_lis(model));

so = sim(model);

% --- read back the contract signals ------------------------------------------
fsig = so.get('freq_hz');  Psig = so.get('P_load');
t = fsig.Time;  f = fsig.Data;  P = Psig.Data;
% terminal voltage (pu): align onto the freq time base
try
    Vsig = so.get('vrms_pu');
    V = interp1(Vsig.Time, Vsig.Data, t, 'linear', 'extrap');
catch
    V = nan(size(t));
end

% --- metrics around the absolute disturbance time ----------------------------
m = sb_grid_sim.metrics(t, f, P, V, td);

meta = struct( ...
    'model',          model, ...
    'model_path',     modelPath, ...
    'baseline_Hz',    op.baseline_Hz, ...
    'baseline_drift_Hzps', op.baseline_drift_Hzps, ...
    'Vterm_pu',       op.Vterm_pu, ...
    'P_ref_g1',       op.P_ref_g1, ...
    't0',             t0, ...
    'dist_time_abs',  td, ...
    'run_timestamp',  datestr(now)); %#ok<TNOW1,DATST>

r = struct( ...
    'params',      params, ...
    'sim_version', sb_grid_sim.version(), ...
    't', t, 'f', f, 'P', P, 'V', V, ...
    'metrics',     m, ...
    'meta',        meta);
end

% -------------------------------------------------------------------------
function reset_lis(model)
%RESET_LIS  Clear LoadInitialState only if the model is still loaded.
if bdIsLoaded(model)
    set_param(model, 'LoadInitialState', 'off');
end
end
