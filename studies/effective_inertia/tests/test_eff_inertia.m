function tests = test_eff_inertia()
%TEST_EFF_INERTIA  Synthetic-signal unit tests for the effective-inertia study.
%
%   % RUN: from studies/effective_inertia (or with it on the path):
%   % RUN:   results = runtests('test_eff_inertia');   assertSuccess(results)
%   % Expected: ALL PASS (7 tests). Establishes estimator + composer correctness
%   % with KNOWN H/D on hand-built swing responses -- no Simulink model needed, so
%   % these run first and fast when MATLAB is available.
%
% Covers:
%   compose_heterogeneous  -- closed-form H_load / S_B / model_vars wiring, frac guard
%   E1 H_eff_rocof         -- recovers E_load/H_eff from differenced linear-ramp RoCoF
%   E2 H_eff_pomega        -- recovers H_eff AND damping from a shaped P-omega signal
%   E3 H_eff_ke            -- recovers released KE exactly from synthetic slip; no-slip guard
tests = functiontests(localfunctions);
end

function setupOnce(tc)
% put the study root (compose_heterogeneous + the +eff_inertia package) on the path
here = fileparts(mfilename('fullpath'));            % studies/effective_inertia/tests
tc.TestData.studyRoot = fileparts(here);
addpath(tc.TestData.studyRoot);
end

% ============================ compose_heterogeneous ==========================
function test_compose_closed_form(tc)
Pw = 2405e6; LF = 0.75;
H  = [0.1 0.5 0.1];  F = [0.152 0.166 0.129];       % AEMO NEM anchor (A0)
[mv, info] = compose_heterogeneous(H, F, 'Pw',Pw, 'LF',LF);

% closed form eq:hload reproduced exactly
verifyEqual(tc, info.H_load, sum((F/LF).*H), 'RelTol',1e-12);
% and lands at the case-study value ~0.148 s
verifyEqual(tc, info.H_load, 0.14813, 'AbsTol',1e-3);
% inertia base S_Bi = F_mi*Pw/LF
verifyEqual(tc, info.S_B, F*Pw/LF, 'RelTol',1e-12);
% E_k,load = sum H_i S_Bi = H_load*Pw
verifyEqual(tc, info.E_k_load, info.H_load*Pw, 'RelTol',1e-12);

% model_vars wiring: rating -> Nom(1), inertia -> Mech(1), torque law A=const B/C=var
verifyEqual(tc, mv.MotorA_Nom(1), info.S_B(1), 'RelTol',1e-12);
verifyEqual(tc, mv.MotorB_Nom(1), info.S_B(2), 'RelTol',1e-12);
verifyEqual(tc, mv.MotorB_Mech,  [0.5 0 2]);
verifyEqual(tc, mv.MotorC_Mech,  [0.1 0 2]);
verifyEqual(tc, [mv.MotorA_TrqExp mv.MotorB_TrqExp mv.MotorC_TrqExp], [0 2 2]);

% passive fills 1 - phi, split in the elec:stat ratio
phi = sum(F);  Pnm = (1-phi)*Pw;  e = 0.337/(0.337+0.216);
verifyEqual(tc, mv.CMLD_ElecP + mv.P0, Pnm, 'RelTol',1e-12);
verifyEqual(tc, mv.CMLD_ElecP, e*Pnm, 'RelTol',1e-12);
end

function test_compose_frac_guard(tc)
% motor fractions must leave room for non-motor load (sum < 1)
verifyError(tc, @() compose_heterogeneous([0.1 0.5 0.1], [0.4 0.4 0.4]), ...
    'compose_heterogeneous:frac');
end

function test_compose_independent_H(tc)
% JMAX corner: independent high H_B + high F_mB -> H_load into the measured band
H = [0.1 2.5 0.1];  F = [0.10 0.35 0.10];
[~, info] = compose_heterogeneous(H, F);
verifyEqual(tc, info.H_load, sum((F/0.75).*H), 'RelTol',1e-12);
verifyEqual(tc, info.H_load, 1.1933, 'AbsTol',1e-3);   % in the ~1.4 s measured regime
end

% ================================ E1 rocof ===================================
function test_e1_recovers_load_inertia(tc)
% Build two linear-ramp frequency traces with KNOWN grid + load kinetic energy,
% differenced RoCoF must recover E_load / H_eff exactly (ramp -> polyfit exact).
Pt = 2405e6;  f0 = 50;  dP = 0.10*Pt;                  % matched load rise
E_grid = 18.3e9;  E_load = 3.0e9;                      % W*s (grid ~ plan value)
rocof_s = -f0*dP/(2*E_grid);                           % static (grid only)
rocof_f = -f0*dP/(2*(E_grid+E_load));                  % full (grid + load)

t = (0:1e-3:5).';  td = 2;
mkf = @(rocof) f0 + rocof*max(t-td,0);                 % flat, then ramp at td
caseRun   = struct('t',t, 'f',mkf(rocof_f), 'td',td);
staticRun = struct('t',t, 'f',mkf(rocof_s), 'td',td);

[Heff, aux] = eff_inertia.H_eff_rocof(caseRun, staticRun, dP, Pt, 0.5);
verifyEqual(tc, Heff, E_load/Pt, 'RelTol',1e-3);
verifyEqual(tc, aux.E_grid, E_grid, 'RelTol',1e-3);
verifyEqual(tc, aux.E_load, E_load, 'RelTol',1e-3);
verifyEqual(tc, aux.headline, E_load/Pt, 'RelTol',1e-3);
end

% ================================ E2 p-omega =================================
function test_e2_recovers_inertia_and_damping(tc)
% Shaped load-bus response dP = a*(dw/dt) + b*dw, a=2*Heff*Pt, recover both.
% omega must be a genuine 2nd-order (oscillatory) swing: a single-exponential dip
% has dw/dt affine in dw (dw/dt = -(1/tau)dw - A/tau), collinearising the inertia
% and damping regressors so the split is non-unique -- a degeneracy of the test
% signal, not the estimator (real swings are underdamped, multi-mode). A damped
% sinusoid puts dw/dt ~90 deg out of phase with dw -> near-orthogonal, cond ~5.
Pt = 2405e6;  f0 = 50;  P0 = Pt;
Heff_true = 0.30;  a_true = 2*Heff_true*Pt;  b_true = 5e8;   % damping (W per pu-omega)

dt = 1e-3;  t = (0:dt:4).';  td = 2;
A = 2e-3;  sig = 1.5;  wd = 2*pi*1.6;                        % underdamped swing dip
x    = max(t-td,0);  on = (t>=td);  env = exp(-sig*x);
w    = 1 - A*(1 - env.*cos(wd*x));                          % omega: damped-oscillatory dip
dwdt = (-A*env.*(sig*cos(wd*x) + wd*sin(wd*x))) .* on;      % analytic derivative
f    = f0*w;
P    = P0 + a_true*dwdt + b_true*(w-1);
caseRun = struct('t',t, 'f',f, 'P',P, 'td',td);

[Heff, aux] = eff_inertia.H_eff_pomega(caseRun, Pt, 0.5);
verifyLessThan(tc, aux.cond, 15);                       % well-conditioned (non-degenerate)
verifyEqual(tc, Heff,      Heff_true, 'RelTol',0.02);   % inertia: <2% (the headline quantity)
verifyEqual(tc, aux.damping, b_true,  'RelTol',0.10);   % damping: looser (secondary; corner bias)
verifyGreaterThan(tc, aux.R2, 0.99);
end

% ================================= E3 ke =====================================
function test_e3_recovers_released_energy(tc)
% Synthetic per-motor slip ramp -> released KE is exact (no derivative/RoCoF).
H   = [0.1 1.0 0.1];  S_B = [2e8 5e8 2e8];  Pt = 2405e6;
s0  = [0.01 0.02 0.01];  ds = [0.005 0.010 0.005];
dt  = 1e-3;  t = (0:dt:4).';  td = 2;  T = 0.5;
frac = min(max((t-td)/T,0),1);                          % 0 before td, 1 by td+T
slip = s0 + frac*ds;                                    % [Nt x 3] linear ramp
caseRun = struct('t',t, 'td',td, 'slip',slip);

[Heff, aux] = eff_inertia.H_eff_ke(caseRun, S_B, H, Pt, T);
sT   = s0 + ds;
Eexp = sum( H .* S_B .* ((1-s0).^2 - (1-sT).^2) );
verifyEqual(tc, aux.E_released, Eexp, 'RelTol',1e-9);
verifyEqual(tc, Heff, Eexp/Pt, 'RelTol',1e-9);
verifyEqual(tc, aux.frac_released, Eexp/sum(H.*S_B), 'RelTol',1e-9);
end

function test_e3_guards_missing_slip(tc)
% Without slip logged the anchor must refuse clearly (points to observables.md §4).
caseRun = struct('t',(0:1e-3:4).', 'td',2);            % no .slip / .speed
verifyError(tc, @() eff_inertia.H_eff_ke(caseRun, [2e8 5e8 2e8], [0.1 1 0.1], 2405e6, 0.5), ...
    'eff_inertia:H_eff_ke:noSlip');
end
