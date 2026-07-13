function build_stage1()
%BUILD_STAGE1  Scaffold the generated full-CMLD model from the working T2 model.
%
% Stage 1 (scaffold, topology-preserving except the Fb feeder-shunt split):
%   * clone models/T2_fullcmld.slx -> studies/validating_cmld/T2_fullcmld_generated.slx
%   * replace the init_testbench_params('T2') PreLoadFcn with SELF-CONTAINED
%     defaults for every MotorX_* var (incl. Stator/Lm) + load/CapC defaults,
%     so the model opens & compiles with NO H: bridge dependency.
%   * fix the static-load nominal [500e3 60] -> [11e3 50] (W4).
%   * wire both shunt caps to the CapC workspace var (W1: capMult now effective).
%   * split the single feeder shunt into head (Fb) + end (1-Fb) caps (F4).
%
% Marked _generated per the authoring-override directive. Idempotent: regenerates
% the file from the canonical model each run. Prints STAGE1_OK / STAGE1_FAIL.

repo = 'C:\Users\mnea0003\dev\sb_grid_lab'; cd(repo); startup_sbgrid;
src  = fullfile(repo,'models','T2_fullcmld.slx');
gen  = fullfile(repo,'studies','validating_cmld','T2_fullcmld_generated.slx');
genmdl = 'T2_fullcmld_generated';

% --- fresh clone (close/discard any prior loads) -----------------------------
for m = {'T2_fullcmld', genmdl}
    if bdIsLoaded(m{1}), close_system(m{1},0); end
end
if isfile(gen), delete(gen); end
load_system(src);                        % opens as 'T2_fullcmld'
save_system('T2_fullcmld', gen);         % clone + rename in memory to genmdl
fprintf('cloned -> %s\n', gen);

sub = [genmdl '/CMLD'];

% --- self-contained defaults (kills the init_testbench_params bridge) ---------
set_param(genmdl, 'PreLoadFcn', preload_str());
fprintf('PreLoadFcn: self-contained defaults installed\n');
% run them now (in BASE) so the current session can compile
evalin('base', preload_str());

% --- W4: fix static-load nominal voltage/frequency ---------------------------
sload = [sub '/' sprintf('Three-Phase\nDynamic Load')];   % name has a newline
assert(getSimulinkBlockHandle(sload) > 0, 'static load block not found: %s', sload);
set_param(sload, 'NominalVoltage', '[11e3 50]');
fprintf('static load NominalVoltage -> [11e3 50]\n');

% --- W1: wire both shunt caps to CapC (topology-preserving) -------------------
% (Fb head/end split is a later, separately-verified step -- keep full CapC now.)
ssh = [sub '/Substation shunt'];
fsh = [sub '/Feeder shunt'];
set_param(ssh, 'Capacitance', 'CapC');
set_param(fsh, 'Capacitance', 'CapC');
fprintf('shunt caps wired to CapC (W1)\n');

% --- save + compile ----------------------------------------------------------
save_system(genmdl, gen);
fprintf('saved %s\n', gen);

p = sb_grid_sim.default_params('full_cmld');
sb_grid_sim.apply_params(p);            % engine vars (motors via PreLoadFcn defaults)
try
    sb_grid_sim.enforce_config(genmdl, p);
    set_param(genmdl,'SimulationCommand','update');
    fprintf('COMPILE_OK\nSTAGE1_OK\n');
catch ME
    fprintf('COMPILE_FAIL: %s\n', ME.message);
    for i=1:numel(ME.stack), fprintf('   at %s:%d\n', ME.stack(i).name, ME.stack(i).line); end
    fprintf('STAGE1_FAIL\n');
end
end

% =============================================================================
function s = preload_str()
% Self-contained base-workspace defaults so the generated model opens/compiles
% with NO external bridge. Values are computed from the AUTHORITATIVE recipe
% cmld_params_for (vendored beside this script) at the bus-313 baseline
% (P=2405 MW, Q=240 MVAr, 220 kV) and BAKED IN AS LITERALS, so the .slx carries
% no dependency on any .m at runtime. apply_params/model_vars still override at
% sim time (testbench-compatible). Also sets CapC (now wired) + Fb_head.
C = sb_grid_sim.cmld_params_for(2405e6, 240e6, 220);   % authoritative baseline recipe (packaged)
L = {'% --- generated CMLD self-contained defaults (cmld_params_for recipe, P=2405 MW baseline) ---'};
for X = 'ABC'
    m = C.(X);
    L{end+1} = sprintf(['Motor%s_Nom=%s; Motor%s_Stator=%s; Motor%s_Rotor=%s; ' ...
        'Motor%s_Lm=%s; Motor%s_Mech=%s; Motor%s_Pmec=%s; Motor%s_Tm=%s; Motor%s_IC=%s;'], ...
        X,mat2str(m.Nom), X,mat2str(m.Stator), X,mat2str(m.Rotor), X,num2str(m.Lm,'%.10g'), ...
        X,mat2str(m.Mech), X,num2str(m.Pmec,'%.10g'), X,num2str(m.Tm,'%.10g'), X,mat2str(m.IC)); %#ok<AGROW>
end
L{end+1} = sprintf('CMLD_ElecP=%s; P0=%s; Q0=%s; Pfrq=1.0;', ...
    num2str(C.ElecP,'%.10g'), num2str(C.StaticP,'%.10g'), num2str(C.StaticQ,'%.10g'));
L{end+1} = sprintf('CapC=%s; Fb_head=0.5;', num2str(C.CapC,'%.10g'));
s = strjoin(L, newline);
end
