function S = sweep_points()
%SWEEP_POINTS  The heterogeneous (H,F_m) grid + corners + disturbances (docs/sweep.md).
%
%   S = sweep_points()
%
% Single source of truth for the study's design grid, shared by t1_open_loop (T1)
% and t2_driver (T2) so both walk the identical points. Pure data -- no compute.
%
% Returns S with:
%   .mix       struct array of mixes {id, H=[H_A H_B H_C], F=[F_mA F_mB F_mC]}
%   .corners   struct: .stress=[M SCR]=[3 5], .nominal=[5.5 8]
%   .dp_primary  +0.10 (headline near-linear step)
%   .dp_robust   [0.25 -0.10] (stress-corner robustness spurs)
%   .robust_ids  mixes that also get the robustness spurs
%   .windows   RoCoF/regression windows (s) for the H_eff(T) curve; headline 0.50
%   .Pw .LF .Rrscale   composer defaults (P_total, loading factor, rotor-R scale)

% ---- mix ladder (docs/sweep.md §2): H_load spans 0.148 -> 1.19 s ------------
m = @(id,H,F) struct('id',id, 'H',H, 'F',F);
S.mix = [ ...
  m('A0',   [0.1 0.5 0.1], [0.152 0.166 0.129]);   % NEM anchor            H_load 0.148
  m('HB08', [0.1 0.8 0.1], [0.152 0.166 0.129]);   % H_B -> AEMO ceiling   0.215
  m('HB15', [0.1 1.5 0.1], [0.152 0.166 0.129]);   % H_B past recommended  0.369
  m('HB25', [0.1 2.5 0.1], [0.152 0.166 0.129]);   % H_B at motor ceiling  0.591
  m('HA15', [1.5 0.5 0.1], [0.152 0.166 0.129]);   % raise const-torque A  0.432
  m('HC15', [0.1 0.5 1.5], [0.152 0.166 0.129]);   % raise motor C         0.389
  m('HU15', [1.5 1.5 1.5], [0.152 0.166 0.129]);   % uniform high H bridge 0.894
  m('FB30', [0.1 0.5 0.1], [0.152 0.300 0.129]);   % high F_mB share       0.237
  m('JMAX', [0.1 2.5 0.1], [0.100 0.350 0.100]);   % joint -> measured band 1.193
];

% ---- operating corners (reducing_cmld §4):  [M_g1  SCR] -----------------------
S.corners = struct('stress',[3 5], 'nominal',[5.5 8]);

% ---- disturbances (docs/sweep.md §3) ----------------------------------------
S.dp_primary = 0.10;             % headline load rise (near-linear regime)
S.dp_robust  = [0.25 -0.10];     % robustness spurs at the stress corner only
S.robust_ids = {'A0','HB25','JMAX'};

% ---- H_eff(T) curve windows (s); headline 500 ms (AEMO) ---------------------
S.windows = [0.02 0.05 0.10 0.20 0.50];

% ---- composer defaults ------------------------------------------------------
S.Pw = 2405e6;  S.LF = 0.75;  S.Rrscale = 0.5;
end
