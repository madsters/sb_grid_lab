function [Heff, aux] = H_eff_ke(caseRun, S_B, H, Pt, windows)
%EFF_INERTIA.H_EFF_KE  E3 -- energy actually released, from per-motor slip (ANCHOR).
%
%   [Heff, aux] = eff_inertia.H_eff_ke(caseRun, S_B, H, Pt, windows)
%
% The ground-truth energy anchor (plan.md "T2 methodology" E3). If the model logs
% per-motor slip s_i(t), the kinetic energy each induction motor has PHYSICALLY
% released by time t is exact (no RoCoF / base ambiguity):
%
%   E_released(t) = sum_i H_i * S_Bi * [ (1 - s0_i)^2 - (1 - s_i(t))^2 ]
%
% comparable DIRECTLY to the stored E_load = sum_i H_i*S_Bi. Then per window T:
%   Heff(T)      = E_released(td+T) / Pt            (on the H_load base)
%   frac_rel(T)  = E_released(td+T) / E_load        (= Heff(T)/H_load; fraction released)
% This cleanly decomposes r into the (1-s)^2 stored-vs-synchronous correction and the
% coupling-limited release fraction -- the part E1/E2 cannot separate.
%
% *** BLOCKED as-authored: cmld_3m.slx does NOT log per-motor slip (observables.md
% §1,§3-4). This function is authored + unit-tested against synthetic slip so it is
% ready the moment slip_A/B/C are wired, but the T2 driver does NOT call it until
% then (it errors clearly if invoked without slip). ***
%
% INPUTS
%   caseRun  struct with fields .t (s) .td (abs disturbance time) and EITHER
%              .slip  [Nt x 3] per-motor slip s_A,s_B,s_C(t), OR
%              .speed [Nt x 3] per-motor pu speed (slip = 1 - speed).
%            If neither is present the function ERRORS (points to observables.md §4).
%   S_B      [1x3] per-motor inertia base = rating Pn_i (W) (from compose info.S_B)
%   H        [1x3] per-motor inertia constants (s)          (from compose info.H)
%   Pt       P_total (W)
%   windows  vector of windows T (s). Default [0.02 0.05 0.10 0.20 0.50].
%
% OUTPUTS
%   Heff  1xN H_eff(T) (s) = E_released(td+T)/Pt
%   aux   .windows .E_released .E_load .frac_released .s0 .headline(T=0.5 s)

if nargin < 5 || isempty(windows), windows = [0.02 0.05 0.10 0.20 0.50]; end
windows = windows(:).';
S_B = S_B(:).';  H = H(:).';

slip = local_slip(caseRun);        % [Nt x 3] or ERROR
t = caseRun.t(:);  td = caseRun.td;

% pre-disturbance slip (mean over [td-0.5, td])
pre = t < td & t > td-0.5;  if ~any(pre), pre = t < td; end
s0  = mean(slip(pre,:), 1);

E_load = sum(H .* S_B);            % total stored KE (W*s)  == H_load*Pt

N = numel(windows);
Heff = nan(1,N);  E_rel = nan(1,N);  frac = nan(1,N);
for k = 1:N
    T  = windows(k);
    ix = find(t <= td+T, 1, 'last');
    if isempty(ix), continue; end
    sT = slip(ix,:);
    E_rel(k) = sum( H .* S_B .* ((1-s0).^2 - (1-sT).^2) );
    Heff(k)  = E_rel(k) / Pt;
    frac(k)  = E_rel(k) / E_load;
end

aux = struct('windows',windows, 'E_released',E_rel, 'E_load',E_load, ...
             'frac_released',frac, 's0',s0);
ih = find(abs(windows-0.5) < 1e-9, 1);  if isempty(ih), ih = N; end
aux.headline = Heff(ih);
end

% =============================== helpers =====================================
function slip = local_slip(caseRun)
if isfield(caseRun,'slip') && ~isempty(caseRun.slip)
    slip = caseRun.slip;
elseif isfield(caseRun,'speed') && ~isempty(caseRun.speed)
    slip = 1 - caseRun.speed;
else
    error('eff_inertia:H_eff_ke:noSlip', ...
        ['E3 needs per-motor slip, which cmld_3m.slx does not log. Wire slip_A/B/C ' ...
         '(or wr_A/B/C) from each async-machine m-output first -- see ' ...
         'studies/effective_inertia/docs/observables.md §4. E3 is parked until then.']);
end
if size(slip,2) ~= 3
    error('eff_inertia:H_eff_ke:shape', 'slip/speed must be [Nt x 3] (motors A,B,C)');
end
end
