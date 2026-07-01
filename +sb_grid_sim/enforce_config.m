function enforce_config(model, params)
%SB_GRID_SIM.ENFORCE_CONFIG  Set the model's solver/state config in memory.
%
%   sb_grid_sim.enforce_config(model, params)
%
% Applies the solver and final-state configuration that the engine REQUIRES
% (see sb_grid_sim.interface().solver) to an already-loaded model, IN MEMORY
% (set_param only; the .slx is NEVER saved). The powergui block's Continuous
% simulation mode is authored in the model itself -- this function only sets the
% Simulink model solver options:
%
%   - variable-step ode23tb (the stiff motors diverge under fixed-step explicit)
%   - MaxStep = params.solver.MaxStep
%   - SaveCompleteFinalSimState / FinalStateName='xFinal' for the settle ->
%     disturbance handoff (init_operating_point captures it; simulate loads it).
%
% StopTime / LoadInitialState / InitialState are NOT set here -- they are run-
% phase knobs driven by init_operating_point (settle) and simulate (disturbance).

if nargin < 2 || isempty(params)
    params = sb_grid_sim.default_params();
end
maxstep = params.solver.MaxStep;

set_param(model, ...
    'SolverType',                'Variable-step', ...
    'Solver',                    'ode23tb', ...
    'MaxStep',                   num2str(maxstep), ...
    'SaveCompleteFinalSimState', 'on', ...
    'FinalStateName',            'xFinal');
end
