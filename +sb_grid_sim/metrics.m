function m = metrics(t, f, P, V, td)
%SB_GRID_SIM.METRICS  Frequency-response metrics around a load-step disturbance.
%
%   m = sb_grid_sim.metrics(t, f, P, V, td)
%
% Inputs (column vectors on a common time base, plus the disturbance time):
%   t   time (s)
%   f   grid frequency (Hz)
%   P   load active power (W)               -- carried for completeness/parity
%   V   terminal voltage (pu), aligned onto t
%   td  ABSOLUTE disturbance time (s)
%
% Returns struct m (contract-2 metrics):
%   f0       pre-step baseline   = mean(f over [td-0.5, td])
%   nadir    minimum frequency for t >= td
%   t_nadir  time of the nadir
%   RoCoF    rate of change of freq = polyfit slope of f over [td, td+0.5] (Hz/s)
%   settle   post-step steady state = mean(f over the last 0.5 s)
%   Vbase    pre-step terminal voltage = mean(V over [td-0.5, td]) (pu)
%   dip      f0 - nadir (Hz)
%
% Ported from the metric block of testbench/run_testbench.m.

t = t(:); f = f(:);
if nargin < 4 || isempty(V), V = nan(size(t)); end
V = V(:);

% pre-step baseline over the 0.5 s before the step
pre = t < td & t > td-0.5;
f0  = mean(f(pre));

% nadir: minimum frequency after the step
post = t >= td;
tp   = t(post);
[nadir, ni] = min(f(post));
t_nadir = tp(ni);

% RoCoF: linear slope over the 0.5 s following the step
w  = t >= td & t <= td+0.5;
pf = polyfit(t(w)-td, f(w), 1);
RoCoF = pf(1);

% settle: post-step steady state over the last 0.5 s
settle = mean(f(t > t(end)-0.5));

% pre-step terminal voltage
Vbase = mean(V(pre));

dip = f0 - nadir;

m = struct('RoCoF',RoCoF, 'nadir',nadir, 'dip',dip, 'settle',settle, ...
           'f0',f0, 'Vbase',Vbase, 't_nadir',t_nadir);
end
