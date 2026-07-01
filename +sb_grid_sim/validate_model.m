function rep = validate_model(load_type, varargin)
%SB_GRID_SIM.VALIDATE_MODEL  Check a model against the engine<->model contract.
%
%   rep = sb_grid_sim.validate_model('static')
%   rep = sb_grid_sim.validate_model('static', 'ModelPath', fullpath)
%
% Loads the model (resolved from load_type via sb_grid_sim.load_types, or a
% 'ModelPath' override), applies default params, enforces the solver/state
% config, compiles it (SimulationCommand 'update'), and verifies the contract:
%   - required logged signals exist:  freq_hz, P_load, vrms_pu
%       (interface().signals)
%   - required Goto routing tags exist: P_g1, omega_g1
%       (interface().tags)
%   - the model compiles with the base vars set by apply_params.
%
% The .slx is NEVER saved. Returns rep struct:
%   .ok                logical (all checks passed)
%   .missing_signals   cellstr of contract signals not found
%   .missing_tags      cellstr of contract Goto tags not found
%   .errors            cellstr of error messages (compile/load failures)
% and prints a clear report.

ip = inputParser; ip.KeepUnmatched = true;
ip.addParameter('ModelPath','');
ip.parse(varargin{:});
modelPath = ip.Results.ModelPath;

I = sb_grid_sim.interface();
reqSignals = {I.signals.name};                 % freq_hz, P_load, vrms_pu
reqTags    = {I.tags.name};                    % P_g1, omega_g1

rep = struct('ok',false,'missing_signals',{{}},'missing_tags',{{}},'errors',{{}});

% --- resolve + load ----------------------------------------------------------
if ~isempty(modelPath)
    [~, model] = fileparts(modelPath);
    loadTarget = modelPath;
else
    model      = sb_grid_sim.load_types(load_type);
    loadTarget = model;
end

wasLoaded = bdIsLoaded(model);
if ~wasLoaded
    try
        load_system(loadTarget);
    catch ME
        rep.errors{end+1} = sprintf('load_system failed: %s', ME.message);
        printReport(model, rep); return;
    end
    cleanupModel = onCleanup(@() close_system(model,0)); %#ok<NASGU>
end

% --- params + config ---------------------------------------------------------
params = sb_grid_sim.default_params(load_type);
try
    sb_grid_sim.apply_params(params);
    sb_grid_sim.enforce_config(model, params);
catch ME
    rep.errors{end+1} = sprintf('apply_params/enforce_config failed: %s', ME.message);
end

% --- structural checks (find_system) -----------------------------------------
% Logged signals: a model may mark them via signal logging or name them through
% an outport-bound Goto. Accept either a named line/signal or a To Workspace /
% Goto carrying the name.
foundSignals = signalNames(model);
rep.missing_signals = setdiff(reqSignals, foundSignals);

gotoTags = find_system(model,'FindAll','on','LookUnderMasks','all', ...
    'FollowLinks','on','Type','block','BlockType','Goto');
tagNames = get_param(gotoTags,'GotoTag');
if ischar(tagNames), tagNames = {tagNames}; end
rep.missing_tags = setdiff(reqTags, tagNames);

% --- compile (update diagram) ------------------------------------------------
try
    set_param(model,'SimulationCommand','update');
catch ME
    rep.errors{end+1} = sprintf('compile (update) failed: %s', ME.message);
end

rep.ok = isempty(rep.missing_signals) && isempty(rep.missing_tags) && isempty(rep.errors);
printReport(model, rep);
end

% =============================================================================
function names = signalNames(model)
%SIGNALNAMES  Collect candidate logged-signal names in a model.
% Looks at named signal lines, To Workspace variable names, and Goto tags --
% any of which a hand-authored model may use to expose freq_hz/P_load/vrms_pu.
names = {};
% named signal lines
lines = find_system(model,'FindAll','on','LookUnderMasks','all', ...
    'FollowLinks','on','Type','line');
for i = 1:numel(lines)
    nm = get_param(lines(i),'Name');
    if ~isempty(nm), names{end+1} = nm; end %#ok<AGROW>
end
% To Workspace variable names
tw = find_system(model,'FindAll','on','LookUnderMasks','all', ...
    'FollowLinks','on','Type','block','BlockType','ToWorkspace');
for i = 1:numel(tw)
    nm = get_param(tw(i),'VariableName');
    if ~isempty(nm), names{end+1} = nm; end %#ok<AGROW>
end
% Goto tags (a logged signal is often routed by a same-named Goto)
gt = find_system(model,'FindAll','on','LookUnderMasks','all', ...
    'FollowLinks','on','Type','block','BlockType','Goto');
for i = 1:numel(gt)
    nm = get_param(gt(i),'GotoTag');
    if ~isempty(nm), names{end+1} = nm; end %#ok<AGROW>
end
names = unique(names);
end

% =============================================================================
function printReport(model, rep)
fprintf('\n=== validate_model: %s ===\n', model);
if rep.ok
    fprintf('  OK: all required signals + tags present, model compiles.\n');
else
    if ~isempty(rep.missing_signals)
        fprintf('  MISSING signals: %s\n', strjoin(rep.missing_signals,', '));
    end
    if ~isempty(rep.missing_tags)
        fprintf('  MISSING Goto tags: %s\n', strjoin(rep.missing_tags,', '));
    end
    for i = 1:numel(rep.errors)
        fprintf('  ERROR: %s\n', rep.errors{i});
    end
end
fprintf('=== end (%s) ===\n\n', mat2str(rep.ok));
end
