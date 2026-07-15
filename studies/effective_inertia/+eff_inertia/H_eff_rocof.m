function [Heff, aux] = H_eff_rocof(caseRun, staticRun, dP_W, Pt, windows)
%EFF_INERTIA.H_EFF_ROCOF  E1 -- delivered effective inertia by DIFFERENTIAL RoCoF.
%
%   [Heff, aux] = eff_inertia.H_eff_rocof(caseRun, staticRun, dP_W, Pt, windows)
%
% The paper's headline estimator (plan.md "T2 methodology" E1). Back-computes the
% load's delivered inertial contribution from the measured RoCoF of a matched-DeltaP
% load step, DIFFERENCED against a frequency/voltage-independent static load carrying
% grid inertia only. Pure post-processing of two logged traces -- no model work.
%
% Swing-equation kinetic energy for a step |dP| (Reactive Technologies eq.(9);
% reducing_cmld/plan.md §5.6):
%       E = f0 * |dP| / (2 * |RoCoF|)          [W*s], from MEASURED Hz / W / (Hz/s]
% so the base is physical regardless of the model's internal pu swing base (this is
% why M_g1 must NOT be read as physical inertia -- the static run is the zero-load-
% inertia reference instead). Then, per window T:
%       E_grid(T) = f0*|dP| / (2*|RoCoF_static(T)|)   grid KE (static ref)
%       E_full(T) = f0*|dP| / (2*|RoCoF_full(T)|)      total system KE
%       E_load(T) = E_full - E_grid                    load's inertial contribution
%       Heff(T)   = E_load(T) / Pt                     on the P_total base (== H_load base)
%
% INPUTS
%   caseRun    struct with fields .t (s) .f (Hz) .td (abs disturbance time, s)
%   staticRun  struct with fields .t .f .td   (static baseline at the SAME corner+dP)
%   dP_W       matched disturbance magnitude (W); sign ignored (|dP| used)
%   Pt         P_total (W) -- the base H_eff is reported on
%   windows    vector of RoCoF fit windows T (s), e.g. [0.02 0.05 0.1 0.2 0.5].
%              Default [0.02 0.05 0.10 0.20 0.50]. Headline is 0.50 (AEMO).
%
% OUTPUTS
%   Heff  1xN vector of H_eff(T) (s), one per window (E_load/Pt)
%   aux   struct: .windows .rocof_full .rocof_static .E_grid .E_full .E_load
%                 .Meff_ratio (=|RoCoF_static|/|RoCoF_full|, unit-free, cf equiv_report)
%                 .f0  .headline (H_eff at T=0.5 s if present, else last)
%
% NOTE this is E1 of three cross-validated estimators; E2 (H_eff_pomega) arbitrates
% the inertia-vs-damping confound at longer windows, E3 (H_eff_ke) is the energy
% anchor (parked until per-motor slip is logged -- observables.md §4).

if nargin < 5 || isempty(windows), windows = [0.02 0.05 0.10 0.20 0.50]; end
windows = windows(:).';

f0 = prestep_mean(caseRun.t, caseRun.f, caseRun.td);   % ~50 Hz baseline of the case
adP = abs(dP_W);

N = numel(windows);
rocof_full = nan(1,N);  rocof_static = nan(1,N);
E_grid = nan(1,N);  E_full = nan(1,N);  E_load = nan(1,N);  Heff = nan(1,N);

for k = 1:N
    T = windows(k);
    rf = windowed_rocof(caseRun.t,   caseRun.f,   caseRun.td,   T);
    rs = windowed_rocof(staticRun.t, staticRun.f, staticRun.td, T);
    rocof_full(k) = rf;  rocof_static(k) = rs;
    if isnan(rf) || isnan(rs) || rf == 0 || rs == 0, continue; end
    E_grid(k) = f0 * adP / (2 * abs(rs));
    E_full(k) = f0 * adP / (2 * abs(rf));
    E_load(k) = E_full(k) - E_grid(k);
    Heff(k)   = E_load(k) / Pt;
end

aux = struct('windows',windows, 'rocof_full',rocof_full, 'rocof_static',rocof_static, ...
             'E_grid',E_grid, 'E_full',E_full, 'E_load',E_load, ...
             'Meff_ratio', abs(rocof_static)./abs(rocof_full), 'f0',f0);
ih = find(abs(windows-0.5) < 1e-9, 1);
if isempty(ih), ih = N; end
aux.headline = Heff(ih);
end

% =============================== helpers =====================================
function m = prestep_mean(t, x, td)
%PRESTEP_MEAN  mean of x over [td-0.5, td] (the standard pre-step baseline window).
sel = t < td & t > td-0.5;
if ~any(sel), sel = t < td; end
m = mean(x(sel));
end

function r = windowed_rocof(t, f, td, T)
%WINDOWED_ROCOF  least-squares slope of f over [td, td+T] (Hz/s); NaN if <2 pts.
sel = t >= td & t <= td+T;
if nnz(sel) < 2, r = NaN; return; end
pf = polyfit(t(sel)-td, f(sel), 1);
r  = pf(1);
end
