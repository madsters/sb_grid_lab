function p = default_params(load_type)
%SB_GRID_SIM.DEFAULT_PARAMS  Canonical default sim-input struct.
%
%   p = sb_grid_sim.default_params()            % defaults, load_type = 'static'
%   p = sb_grid_sim.default_params('full_cmld') % defaults for a given load type
%
% Returns the grouped params struct that every part of the framework codes
% against. Override fields then pass to sb_grid_sim.simulate / sb_grid_testbench.
% This is the ONLY place defaults live. The engine owns grid + disturbance +
% solver; the LOAD INTERNALS live in the user's model, not here.
%
% Groups:
%   .load_type     which model to load (see sb_grid_sim.load_types)
%   .grid          grid-equivalent + swing/governor knobs
%   .scale         nominal load size (SCR base power + disturbance base)
%   .disturbance   the load-step event
%   .solver        solver + run/settle timing
%   .load          optional load-level knob the engine may set (Pfrq)
%
% Derived quantities (Scc1, Xcc1, Lg_n1, Rg_n1, w_g1, Vpeak_g1, dist_dP, snub_P,
% P_ref_g1) are computed in sb_grid_sim.apply_params, NOT stored here.

if nargin < 1 || isempty(load_type), load_type = 'static'; end
p.load_type = char(load_type);

p.grid = struct( ...
    'SCR',          10, ...        % short-circuit ratio (grid strength)
    'M',            8, ...         % swing inertia constant M_g1
    'k_droop_f_g1', 1/0.07, ...    % 7% droop
    'kt_hp',        0.3, ...       % reheat turbine HP fraction
    'kt_lp',        0.7, ...       % reheat turbine LP fraction
    't_rh',         8, ...         % reheat time constant (s)
    'theta_g0',     0, ...         % EMF angle (rad)
    'snub_Q',       0, ...         % snubber reactive (no cap)
    'f1',           50);           % nominal grid frequency (Hz)

p.scale = struct( ...
    'P_W',   2405e6, ...           % nominal active load (W)
    'Q_var', 240e6, ...            % nominal reactive load (VAr)
    'BusKV', 220);                 % transmission base voltage (kV)

p.disturbance = struct( ...
    'dist_time',    2, ...         % step time (s, relative to the run start)
    'dist_dP_frac', 0.25);         % step magnitude as a fraction of P_W (+ = load rise)

p.solver = struct( ...
    'Ts',         50e-6, ...       % discrete step (if used)
    'StopTime',   60, ...          % disturbance-run stop time (s)
    'SettleTime', 40, ...          % pre-disturbance settle (s; >= ~5x t_rh)
    'MaxStep',    5e-4);           % variable-step solver max step

p.load = struct( ...
    'Pfrq', 1.0);                  % optional static-load frequency sensitivity
end
