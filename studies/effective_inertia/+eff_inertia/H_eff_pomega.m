function [Heff, aux] = H_eff_pomega(caseRun, Pt, windows, varargin)
%EFF_INERTIA.H_EFF_POMEGA  E2 -- effective inertia by load-bus P-omega regression.
%
%   [Heff, aux] = eff_inertia.H_eff_pomega(caseRun, Pt, windows, 'Name',Value,...)
%
% The estimator that ISOLATES inertia from damping (plan.md "T2 methodology" E2,
% difficulty 2). Regresses the load-bus active-power deviation on BOTH the frequency
% acceleration (inertia) and the frequency deviation (damping / load relief):
%
%       dP_load(t) = a * (domega/dt) + b * domega + c
%
% with omega = f/f0. The inertial power a motor releases while decelerating reduces
% its net electrical draw, dP_load_inertial = 2*H_eff*Pt*(domega/dt), so
%       a = 2 * H_eff * Pt   ->   H_eff = a / (2*Pt)      [s]
%       b = load damping / relief coefficient (W per pu-omega)
% Because the load-bus P is logged BEFORE the disturbance step is summed in
% (model-interface.md §2), dP_load is the load's OWN response -- exactly the signal
% this regression needs. Needs NO static baseline (unlike E1): it reads inertia off
% the load trace directly, and the b term absorbs the damping that contaminates a
% pure-RoCoF reading at longer windows.
%
% INPUTS
%   caseRun  struct with fields .t (s) .f (Hz) .P (W, load active power) .td (abs)
%   Pt       P_total (W)
%   windows  vector of regression windows T (s); a separate fit per window so the
%            result is an H_eff(T) curve comparable to E1. Default [0.05 0.10 0.20 0.50].
% OPTIONS
%   'FiltMs'  derivative smoothing half-window (ms), default 5. domega/dt is a
%             zero-phase moving-average-smoothed central difference (fixed, stated).
%   'MinPts'  minimum samples in a window to attempt the fit, default 8.
%
% OUTPUTS
%   Heff  1xN H_eff(T) (s) = a/(2*Pt) per window
%   aux   .windows .a .b .c .damping(=b) .R2 .f0 .P0 .headline(T=0.5 s)
%
% E2 arbitrates the E1-vs-E3 gap (the residual coupling/damping term of r).

ip = inputParser;
ip.addParameter('FiltMs', 5);
ip.addParameter('MinPts', 8);
ip.parse(varargin{:}); op = ip.Results;

if nargin < 3 || isempty(windows), windows = [0.05 0.10 0.20 0.50]; end
windows = windows(:).';

t = caseRun.t(:);  f = caseRun.f(:);  P = caseRun.P(:);  td = caseRun.td;
f0 = prestep_mean(t, f, td);
P0 = prestep_mean(t, P, td);

omega = f / f0;
dw    = omega - 1;
dP    = P - P0;

% fixed, stated derivative: smooth omega, then central difference
dwdt = smooth_deriv(t, omega, op.FiltMs*1e-3);

N = numel(windows);
Heff = nan(1,N);  a = nan(1,N);  b = nan(1,N);  c = nan(1,N);  R2 = nan(1,N);  kcond = nan(1,N);
for k = 1:N
    T   = windows(k);
    sel = t >= td & t <= td+T;
    if nnz(sel) < op.MinPts, continue; end
    X   = [dwdt(sel), dw(sel), ones(nnz(sel),1)];
    y   = dP(sel);
    % CONDITIONING: the inertia (dw/dt) and damping (dw) regressors go collinear
    % when the window is dominated by a SINGLE exponential mode (then dw/dt is affine
    % in dw), so the a/b split is untrustworthy. Report cond(X) on standardised
    % columns so a caller can flag it; E1 remains the headline for this reason.
    Xn = X ./ vecnorm(X);  kcond(k) = cond(Xn);
    beta = X \ y;
    a(k) = beta(1);  b(k) = beta(2);  c(k) = beta(3);
    Heff(k) = a(k) / (2*Pt);
    resid = y - X*beta;  ss = sum((y-mean(y)).^2);
    if ss > 0, R2(k) = 1 - sum(resid.^2)/ss; else, R2(k) = NaN; end
end

aux = struct('windows',windows, 'a',a, 'b',b, 'c',c, 'damping',b, 'R2',R2, ...
             'cond',kcond, 'f0',f0, 'P0',P0);
ih = find(abs(windows-0.5) < 1e-9, 1);
if isempty(ih), ih = N; end
aux.headline = Heff(ih);
end

% =============================== helpers =====================================
function m = prestep_mean(t, x, td)
sel = t < td & t > td-0.5;
if ~any(sel), sel = t < td; end
m = mean(x(sel));
end

function d = smooth_deriv(t, x, halfwin_s)
%SMOOTH_DERIV  central difference of a moving-average-smoothed signal (zero-phase).
% halfwin_s sets the moving-average half-window; on a ~uniform grid this is a fixed,
% stated low-pass. Falls back to a raw central difference if the grid is too coarse.
t = t(:);  x = x(:);  n = numel(x);
dt = median(diff(t));
w  = max(1, round(halfwin_s / max(dt, eps)));    % half-window in samples
if w >= 1 && n > 2*w+1
    k  = 2*w+1;
    xs = movmean_sym(x, k);
else
    xs = x;
end
d = zeros(n,1);
d(2:n-1) = (xs(3:n) - xs(1:n-2)) ./ (t(3:n) - t(1:n-2));
d(1)   = (xs(2)-xs(1))/(t(2)-t(1));
d(end) = (xs(end)-xs(end-1))/(t(end)-t(end-1));
end

function y = movmean_sym(x, k)
%MOVMEAN_SYM  symmetric moving average, window k (odd), edge-shrinking.
% Local implementation (no Signal Processing / R2016a movmean dependency assumed).
n = numel(x);  h = (k-1)/2;  y = zeros(n,1);
cs = [0; cumsum(x)];
for i = 1:n
    lo = max(1, i-h);  hi = min(n, i+h);
    y(i) = (cs(hi+1) - cs(lo)) / (hi - lo + 1);
end
end
