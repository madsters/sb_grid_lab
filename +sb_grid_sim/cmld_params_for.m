function C = cmld_params_for(P, Q, busKV, capMult)
% cmld_params_for  Per-bus CMLD parameters for a composite-load instance that
% replaces a static load of P (W) / Q (VAr) at a bus of base voltage busKV (kV).
%
%   C = cmld_params_for(P, Q, busKV [, capMult])
%
% capMult (default 1) scales the shunt-cap reactive sizing. The default cap is
% CapC prop. P (tuned for the strong bus 313); at electrically weak nodes that
% OVER-injects reactive -> overvoltage -> V^2 passive loads over-draw active power
% -> Fr droop (see buses 212/216). cap_balance.m finds the per-bus capMult that
% restores balance; pass it here (or via apply_cmld's capMap) to build a balanced
% instance. capMult<1 shrinks the cap at weak nodes.
%
% Returns a struct of NUMERIC values (no workspace-variable refs) so each CMLD
% instance can be made self-contained by writing the values straight into its
% block parameters -- this lets many instances coexist without variable-name
% collisions. Mirrors the bus-313 recipe in cmld_parameters.m (AEMO NSW split,
% single-cage SPS asynchronous motors A/B/C), generalised to any P/Q/busKV:
%   * motor per-unit equivalent-circuit params are fixed; ratings scale with P
%   * passive electronic + static(ZIP) loads scale with P (AEMO fractions)
%   * substation transformer primary = busKV, rating ~1.25*P
%   * active-power balance trim scales with P (motor losses + V^2 droop)
%
% Field groups: C.ElecP/StaticP/StaticQ (passive, W/VAr); C.A/.B/.C (per motor:
% Nom,Stator,Rotor,Lm,Mech,IC,Pmec,Tm); C.Xfmr* ; C.CapC ; C.Pbalance ; meta.
%
% VENDORED into +sb_grid_sim from the H: testbench bridge so the models are
% reproducible without the bridge. Called by sb_grid_sim.init_load_internals
% (the models' PreLoadFcn) and by the generated-model build. Called as
% sb_grid_sim.cmld_params_for(...).

if nargin<4 || isempty(capMult), capMult=1; end

% ----- AEMO NSW composition --------------------------------------------------
fA=0.152; fB=0.166; fC=0.129; LF=0.75;
f_mot  = fA+fB+fC;            % 0.447
f_elec = 0.337;
f_stat = 1 - f_mot - f_elec;  % 0.216
stat_QP = 0.20;               % static-load X/R (Q/P), as on bus 313
BAL_FRAC = -110e6/2405e6;     % -0.04574: balance trim as a fraction of P (bus-313 cal)

% ----- per-motor equivalent circuit (pu, single-cage 50 Hz), fixed -----------
EC.A = struct('Stator',[0.02 0.072], 'Rotor',[0.05955 0.04937], 'Lm',1.728, 'H',0.1);
EC.B = struct('Stator',[0.03 0.114], 'Rotor',[0.02810 0.07959], 'Lm',1.686, 'H',0.5);
EC.C = struct('Stator',[0.03 0.114], 'Rotor',[0.02810 0.07959], 'Lm',1.686, 'H',0.1);
fr  = struct('A',fA,'B',fB,'C',fC);
Vn  = 11000;   % motor / LV-bus voltage (transformer steps busKV -> 11 kV)

for X = ['A' 'B' 'C']
    e = EC.(X);
    Pmec = fr.(X) * P;          % mechanical load (W)
    Pn   = Pmec / LF;           % machine MVA base (VA)
    s    = deal_slip(e.Rotor(1), LF);
    m.Nom    = [Pn Vn 50];
    m.Stator = e.Stator;
    m.Rotor  = e.Rotor;
    m.Lm     = e.Lm;
    m.Mech   = [e.H 0 2];                 % [H F polepairs]
    m.IC     = [s 0 0 0 0 0 -120 120];    % first entry = operating slip
    m.Pmec   = Pmec;
    m.Tm     = LF/(1-s);
    m.slip   = s;
    C.(X) = m;
end

% ----- passive loads + balance trim -----------------------------------------
C.Pbalance = BAL_FRAC * P;
C.ElecP    = f_elec * P;
C.StaticP  = f_stat * P + C.Pbalance;
C.StaticQ  = stat_QP * (f_stat * P);

% ----- substation transformer (primary = busKV) + shunt cap -----------------
C.XfmrWinding1 = [busKV*1e3, 0.002, 0.08];
C.XfmrWinding2 = [Vn,        0.002, 0.08];
C.XfmrNomPower = [1.247 * P, 50];          % ~1.25x load, as on bus 313 (3000/2405)
C.CapC         = 0.037092 * (P/2405e6) * capMult;  % shunt cap (313 value), per-bus reactive sizing

% ----- meta ------------------------------------------------------------------
C.P = P; C.Q = Q; C.busKV = busKV;
C.f_mot = f_mot; C.f_elec = f_elec; C.f_stat = f_stat;
end

function s = deal_slip(Rr, LF)
s = LF*Rr;
for it = 1:8
    T = LF/(1-s);
    s = T*Rr;
end
end
