function fix_bridge()
%FIX_BRIDGE  Remove the H: init_testbench_params dependency from the production
% T1/T2 models by editing VARS/CALLBACKS only (no structural change), repointing
% them at the vendored sb_grid_sim.init_load_internals and wiring CapC.
%
% Edits (set_param only; no blocks/lines added or removed):
%   T2_fullcmld : PreLoadFcn -> sb_grid_sim.init_load_internals('T2')
%                 Substation shunt / Feeder shunt Capacitance -> CapC   (W1)
%   T1_static   : PreLoadFcn -> sb_grid_sim.init_load_internals('T1')
%                 static-load ActivePower load(16,2)*1e6 -> P_W          (drop AU14 dep)
%                 static-load InductivePower load(16,3)*1e6 -> Q_var
%
% Behaviour is preserved at baseline (CapC defaults to 0.037092; P_W/Q_var default
% to 2405 MW/240 MVAr = the AU14 bus-313 values). Validates each model loads +
% compiles + smoke-runs with NO bridge on the path.

repo = 'C:\Users\mnea0003\dev\sb_grid_lab'; cd(repo); startup_sbgrid;
assert(isempty(which('init_testbench_params')), ...
    'H: bridge is on the path -- run this with the bridge OFF to prove independence.');

% ---------- T2_fullcmld ------------------------------------------------------
edit_model('T2_fullcmld', @(mdl) deal_T2(mdl));
% ---------- T1_static --------------------------------------------------------
edit_model('T1_static', @(mdl) deal_T1(mdl));

fprintf('FIX_BRIDGE_OK\n');
end

% =============================================================================
function edit_model(mdl, editfun)
src = which([mdl '.slx']);
assert(~isempty(src), 'model %s not found on path', mdl);
if bdIsLoaded(mdl), close_system(mdl,0); end
load_system(src);
editfun(mdl);
save_system(mdl);
fprintf('  edited + saved %s\n', src);
% validate: compile + smoke through the engine (bridge-free)
lt = struct('T2_fullcmld','full_cmld','T1_static','static');
p = sb_grid_sim.default_params(lt.(mdl));
p.solver.SettleTime = 8; p.solver.StopTime = 6;
close_system(mdl,0);                                  % discard in-memory; reload clean
r = sb_grid_sim.simulate(p, 'ModelPath', src);
fprintf('  SMOKE %s: baseHz=%.4f RoCoF=%.4f dip=%.4f Vterm=%.4f\n', ...
    mdl, r.meta.baseline_Hz, r.metrics.RoCoF, r.metrics.dip, r.metrics.Vbase);
end

% =============================================================================
function deal_T2(mdl)
set_param(mdl, 'PreLoadFcn', 'sb_grid_sim.init_load_internals(''T2'');');
sub = [mdl '/CMLD'];
set_param([sub '/Substation shunt'], 'Capacitance', 'CapC');
set_param([sub '/Feeder shunt'],     'Capacitance', 'CapC');
% ensure the vars exist for THIS session's compile (PreLoadFcn already ran at load,
% but re-assert in case the bridge-era PreLoadFcn errored silently)
sb_grid_sim.init_load_internals('T2');
end

% =============================================================================
function deal_T1(mdl)
set_param(mdl, 'PreLoadFcn', 'sb_grid_sim.init_load_internals(''T1'');');
% repoint the static load block (named 'Load' at root) off the AU14 `load` matrix
% and onto the engine-provided P_W/Q_var. (SourceType is NOT a runtime get_param
% field on these masked SPS blocks, so address the block by name.)
sload = [mdl '/Load'];
assert(getSimulinkBlockHandle(sload) > 0, 'T1 static load block not found: %s', sload);
set_param(sload, 'ActivePower', 'P_W', 'InductivePower', 'Q_var');
sb_grid_sim.init_load_internals('T1');
end
