function applied = apply_params(p)
%SB_GRID_SIM.APPLY_PARAMS  Write the base-workspace variables a model resolves.
%
%   applied = sb_grid_sim.apply_params(p)
%
% Takes a params struct (see sb_grid_sim.default_params), computes the derived
% grid-equivalent / disturbance quantities, and ASSIGNS every base-workspace
% variable named in sb_grid_sim.interface into the base workspace, so the loaded
% model's block masks resolve them at compile.
%
% Returns `applied`: a flat struct of every name->value written (for logging /
% validation). This is the ONE function that touches the base workspace for
% physical params; the variable names here MUST match interface().vars exactly.
%
% P_ref_g1 is initialised to P_W here; init_operating_point rebalances it after
% the settle. Solver/state config is handled separately by enforce_config.

g = p.grid;  s = p.scale;  d = p.disturbance;  sv = p.solver;

f1   = g.f1;            w_g1 = 2*pi*f1;
Un1  = s.BusKV*1e3;     Sn1  = s.P_W;
SCR1 = g.SCR;           Scc1 = SCR1*Sn1;
Xcc1 = Un1^2/Scc1;      Lg_n1 = Xcc1/w_g1;     Rg_n1 = Xcc1/10;
Vpeak_g1 = Un1/sqrt(3)*sqrt(2);
P_W  = s.P_W;           Q_var = s.Q_var;
P_ref_g1 = P_W;                                   % init; rebalanced by init_operating_point
snub_P = 0.005*P_W;
dist_time = d.dist_time;   dist_dP = d.dist_dP_frac * P_W;
T_solver = sv.Ts;          Tsim = sv.StopTime;

applied = struct( ...
    'f1',f1, 'w_g1',w_g1, 'Un1',Un1, 'Sn1',Sn1, 'SCR1',SCR1, 'Scc1',Scc1, ...
    'Xcc1',Xcc1, 'Lg_n1',Lg_n1, 'Rg_n1',Rg_n1, 'Vpeak_g1',Vpeak_g1, ...
    'theta_g0',g.theta_g0, 'M_g1',g.M, 'k_droop_f_g1',g.k_droop_f_g1, ...
    'kt_hp',g.kt_hp, 'kt_lp',g.kt_lp, 't_rh',g.t_rh, 'P_ref_g1',P_ref_g1, ...
    'snub_P',snub_P, 'snub_Q',g.snub_Q, 'P_W',P_W, 'Q_var',Q_var, ...
    'dist_time',dist_time, 'dist_dP',dist_dP, 'T_solver',T_solver, 'Tsim',Tsim);

% optional: only set Pfrq if the params carry it (model may or may not use it)
if isfield(p,'load') && isfield(p.load,'Pfrq') && ~isempty(p.load.Pfrq)
    applied.Pfrq = p.load.Pfrq;
end

% ESCAPE HATCH: model-specific overrides. A study can push arbitrary base-
% workspace variables (e.g. a particular model's motor inertia MotorA_Mech) via
% p.overrides = struct(name -> value). Written verbatim AFTER the engine vars,
% so they take precedence. The engine does not "own" these; they are part of the
% param identity (param_hash covers them), so results stay reproducible/deduped.
if isfield(p,'overrides') && isstruct(p.overrides) && ~isempty(fieldnames(p.overrides))
    ofn = fieldnames(p.overrides);
    for i = 1:numel(ofn)
        applied.(ofn{i}) = p.overrides.(ofn{i});
    end
end

fn = fieldnames(applied);
for i = 1:numel(fn)
    assignin('base', fn{i}, applied.(fn{i}));
end
end
