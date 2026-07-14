function I = interface()
%SB_GRID_SIM.INTERFACE  The contract every hand-authored model (.slx) must satisfy.
%
% This is the SINGLE SOURCE OF TRUTH for the engine<->model boundary. Both
% sb_grid_sim.apply_params (which writes the base-workspace variables) and
% docs/model-interface.md (the human authoring guide) derive from it, and
% sb_grid_sim.validate_model checks a model against it.
%
% Returns struct I with:
%   I.vars          - struct array of REQUIRED base-workspace variables the model's
%                     block masks must resolve {name, units, group, source, meaning}
%   I.optional_vars - variables the engine sets only if the model uses them
%   I.signals       - REQUIRED logged signals the engine reads back {name, units, meaning}
%   I.tags          - REQUIRED Goto/From routing tags {name, kind, meaning}
%   I.solver        - solver/powergui/state config the engine ENFORCES at run (in memory)
%   I.version       - interface revision (bump if the contract SHAPE changes)
%
% OWNERSHIP: the engine owns the grid-equivalent + disturbance + solver. The
% LOAD INTERNALS (motors, composition, fractions) belong to the user's model and
% are NOT in this contract.

I.version = '1.0';

% --- required base-workspace variables ---------------------------------------
% {name, units, group, source (params path / 'derived' / 'engine-managed'), meaning}
rows = {
 'f1'           'Hz'    'grid'   'grid.f1'               'nominal grid frequency (50)'
 'w_g1'         'rad/s' 'grid'   'derived'               '2*pi*f1'
 'Un1'          'V'     'grid'   'derived'               'line-line RMS base voltage = BusKV*1e3'
 'Sn1'          'VA'    'grid'   'derived'               'base power = P_W'
 'SCR1'         '-'     'grid'   'grid.SCR'              'short-circuit ratio (grid strength)'
 'Scc1'         'VA'    'grid'   'derived'               'short-circuit power = SCR1*Sn1'
 'Xcc1'         'ohm'   'grid'   'derived'               'Thevenin reactance = Un1^2/Scc1'
 'Lg_n1'        'H'     'grid'   'derived'               'Thevenin inductance = Xcc1/w_g1'
 'Rg_n1'        'ohm'   'grid'   'derived'               'Thevenin resistance = Xcc1/10 (X/R=10)'
 'Vpeak_g1'     'V'     'grid'   'derived'               'EMF peak = Un1/sqrt(3)*sqrt(2)'
 'theta_g0'     'rad'   'grid'   'grid.theta_g0'         'EMF angle (0)'
 'M_g1'         's'     'grid'   'grid.M'                'swing inertia constant'
 'k_droop_f_g1' '-'     'grid'   'grid.k_droop_f_g1'     'governor droop gain = 1/droop'
 'kt_hp'        '-'     'grid'   'grid.kt_hp'            'reheat turbine HP fraction'
 'kt_lp'        '-'     'grid'   'grid.kt_lp'            'reheat turbine LP fraction'
 't_rh'         's'     'grid'   'grid.t_rh'             'reheat time constant'
 'P_ref_g1'     'W'     'grid'   'engine-managed'        'mech-power ref (init=P_W; rebalanced by init_operating_point)'
 'snub_P'       'W'     'grid'   'derived'               'resistive snubber ~0.5% of P_W'
 'snub_Q'       'VAr'   'grid'   'grid.snub_Q'           'snubber reactive (0; a cap resonates with the grid L)'
 'P_W'          'W'     'scale'  'scale.P_W'             'nominal active load (SCR base power + disturbance base)'
 'Q_var'        'VAr'   'scale'  'scale.Q_var'           'nominal reactive load'
 'dist_time'    's'     'dist'   'disturbance.dist_time' 'disturbance step time'
 'dist_dP'      'W'     'dist'   'derived'               'step magnitude = dist_dP_frac * P_W'
 'T_solver'     's'     'solver' 'solver.Ts'             'discrete solver step (if the model uses a discrete block)'
 'Tsim'         's'     'solver' 'solver.StopTime'       'simulation stop time'
};
I.vars = struct('name',rows(:,1),'units',rows(:,2),'group',rows(:,3), ...
                'source',rows(:,4),'meaning',rows(:,5));

% --- optional variables (set only if the model uses them) --------------------
I.optional_vars = struct('name',{'Pfrq'},'units',{'-'},'group',{'load'}, ...
   'source',{'load.Pfrq'}, ...
   'meaning',{'static-load frequency sensitivity (only if the model has a freq-dependent static load)'});

% --- required logged signals (read back by simulate) -------------------------
I.signals = struct('name',{'freq_hz','P_load','vrms_pu'}, 'units',{'Hz','W','pu'}, ...
   'meaning',{'grid frequency','load active power','terminal voltage RMS'});

% --- optional logged signals (read back into r.extra if the model logs them) --
% Any additional logged variable beyond the required three is aligned onto the
% freq time base and returned in r.extra.<name> (empty struct if none). Studies
% may wire extra observables into their own model without changing this contract;
% e.g. effective_inertia logs per-motor rotor speed for its KE-from-slip estimator.
I.optional_signals = struct('name',{'speed_A','speed_B','speed_C'}, 'units',{'pu','pu','pu'}, ...
   'meaning',{'Motor A rotor speed (slip = 1 - speed)', ...
              'Motor B rotor speed (slip = 1 - speed)', ...
              'Motor C rotor speed (slip = 1 - speed)'});

% --- required routing tags ---------------------------------------------------
I.tags = struct('name',{'P_g1','omega_g1'}, 'kind',{'Goto','Goto/From'}, ...
   'meaning',{'Pe = P_load + disturbance Step, fed into the swing equation', ...
              'grid speed; load consumes it as omega(pu) = wg/w_g1'});

% --- solver / state config the engine enforces at run (set_param, in memory) -
I.solver = struct('SimulationMode','Continuous', 'Solver','ode23tb', ...
   'MaxStep','params.solver.MaxStep (default 5e-4)', ...
   'SaveCompleteFinalSimState','on  (used for the settle -> disturbance handoff)', ...
   'note','powergui must be Continuous; the engine never SAVES these back to the .slx');
end
