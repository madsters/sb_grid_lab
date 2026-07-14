function motivating_figure(H)
%MOTIVATING_FIGURE  The premise of the reduction study: a (full) CMLD produces a
% materially different frequency response than a true (constant-Z, freq-
% independent) static load under realistic stress conditions -- BOTH pinned to
% 1 pu. Overlays full CMLD (cmld_3m at motor inertia H) vs true_static from the
% cached stress-corner traces and reports the RoCoF / nadir-dip advantage.
%   motivating_figure(2.5)   % use the H=2.5 CMLD trace (default)
if nargin < 1, H = 2.5; end
% this file lives in studies/reducing_cmld/motivating/, so repo is 4 levels up
repo = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
run(fullfile(repo,'startup_sbgrid.m'));
raw    = fullfile(repo,'studies','reducing_cmld','reducing_cmld_raw');
figdir = fileparts(mfilename('fullpath'));   % write alongside this script (the motivating folder)

% +0.25 (load-rise) traces: full CMLD (cmld_3m at motor inertia H) vs the true
% static (true_static). Both are calibrated to 1 pu (CMLD via LFm, static via its
% CapC), so pick each by model, at the requested H, nearest 1 pu.
Pw = sb_grid_sim.default_params('static').scale.P_W;
[cmld, stat] = deal([]); cbest = inf; sbest = inf;
f = dir(fullfile(raw,'*.mat'));
for i = 1:numel(f)
    S = load(fullfile(raw,f(i).name)); r = S.results;
    if r.params.disturbance.dist_dP_frac <= 0, continue; end        % load rise only
    td = r.meta.dist_time_abs; Ppre = mean(r.P(r.t<td & r.t>td-1));
    [~,mb] = fileparts(r.params.model_path);
    if strcmp(mb,'cmld_3m')
        mvH = r.params.model_vars.MotorA_Mech(1);                   % motor inertia of this trace
        if abs(mvH-H) < 0.05 && abs(Ppre-Pw) < cbest, cmld = r; cbest = abs(Ppre-Pw); end
    elseif strcmp(mb,'true_static') && abs(Ppre-Pw) < sbest
        stat = r; sbest = abs(Ppre-Pw);
    end
end
assert(~isempty(cmld) && ~isempty(stat), ...
    'need cmld_3m (H=%.1f) + true_static +0.25 traces (run reduce_cmld L1 H=%.1f Static=true first)', H, H);

mc = cmld.metrics; ms = stat.metrics;
dpfrac = cmld.params.disturbance.dist_dP_frac;      % actual load-step size (pu)
Mg = cmld.params.grid.M; SCRg = cmld.params.grid.SCR;
rocof_adv = (abs(ms.RoCoF)-abs(mc.RoCoF))/abs(ms.RoCoF)*100;
dip_adv   = (ms.dip - mc.dip)/ms.dip*100;
Pc = mean(cmld.P(cmld.t<cmld.meta.dist_time_abs & cmld.t>cmld.meta.dist_time_abs-1));
Ps = mean(stat.P(stat.t<stat.meta.dist_time_abs & stat.t>stat.meta.dist_time_abs-1));
fprintf('\n== full CMLD (H=%.1f) vs true static (const-Z), stress M=%g SCR=%g, +%.2f pu ==\n', H, Mg, SCRg, dpfrac);
fprintf('  pre-dist draw: cmld %.0f MW   static %.0f MW  (both ~1 pu)\n', Pc/1e6, Ps/1e6);
fprintf('  RoCoF:  static %.3f  cmld %.3f Hz/s   -> CMLD better by %.1f%%\n', ms.RoCoF, mc.RoCoF, rocof_adv);
fprintf('  dip  :  static %.3f  cmld %.3f Hz     -> CMLD better by %.1f%%\n', ms.dip, mc.dip, dip_adv);

fig = figure('Visible','off','Position',[100 100 1000 1040]);
td = cmld.meta.dist_time_abs; t0 = td-1;

% -- Panel 1: frequency overlay --
ax1 = subplot(3,1,1); hold(ax1,'on'); grid(ax1,'on');
plot(ax1, stat.t, stat.f, 'Color',[.85 .33 .10], 'LineWidth',1.6, 'DisplayName','static load');
plot(ax1, cmld.t, cmld.f, 'Color',[0 .45 .74], 'LineWidth',1.6, 'DisplayName','full CMLD');
xline(ax1, td, ':', 'HandleVisibility','off');
plot(ax1, stat.t(argmin(stat,td)), ms.nadir, 'v', 'Color',[.85 .33 .10], 'HandleVisibility','off');
plot(ax1, cmld.t(argmin(cmld,td)), mc.nadir, 'v', 'Color',[0 .45 .74], 'HandleVisibility','off');
xlim(ax1,[t0 td+10]); ylabel(ax1,'frequency (Hz)'); legend(ax1,'Location','southeast');
title(ax1, sprintf(['Full CMLD vs. constant-Z static load: response to a +%.2f pu load step (M = %g s, SCR = %g)\n' ...
    'CMLD reduces RoCoF by %.1f%% and nadir dip by %.1f%%'], dpfrac, Mg, SCRg, rocof_adv, dip_adv));

% ---- power decomposition: LOAD (demand) vs GENERATION (supply) ----------------
% The constant-PQ static load's P measurement carries sub-cycle ripple + a few
% control-loop spikes; median+mean filter for a legible slide (frequency above is
% raw). f0 = nominal frequency; both power panels share one y-scale (below).
sm = @(x) movmean(movmedian(x(:),151),151);
f0 = 50;
dPs = stat.params.disturbance.dist_dP_frac*Pw;      % signed step, W (+0.25 here)
dPc = cmld.params.disturbance.dist_dP_frac*Pw;

% LOAD (demand) = each model's own draw + the disturbance step it was hit with
Pload_s = sm(stat.P) + dPs*(stat.t(:)>=td);
Pload_c = sm(cmld.P) + dPc*(cmld.t(:)>=td);

% GENERATION (supply) reconstructed from the swing equation the engine solves:
%   M dw/dt = Pm - Pe   ->   Pm = Pe + K*(df/dt)/f0,   Pe = total load draw.
% Pm is NOT logged (only P_load/f/V are), so recover it from f. K = M_g1*P_sb,
% the swing constant, is calibrated on the STATIC case at the step instant, where
% generation hasn't moved (Pm=P_ref) and the imbalance is exactly dP -- the motors
% give no instantaneous inertia, so this instant RoCoF is grid-only (plan 5.6).
wi = stat.t>=td & stat.t<=td+0.1; ci = polyfit(stat.t(wi), stat.f(wi), 1);
K  = abs(dPs)*f0/abs(ci(1));                          % W per (Hz/s)
% raw derivative keeps the slope-kink sharp so the step in Pe cancels cleanly;
% smooth the reconstructed Pm afterwards to remove differentiation noise.
Pmech_s = movmean((stat.P(:)+dPs*(stat.t(:)>=td)) + K*gradient(stat.f(:),stat.t(:))/f0, 201);
Pmech_c = movmean((cmld.P(:)+dPc*(cmld.t(:)>=td)) + K*gradient(cmld.f(:),cmld.t(:))/f0, 201);

% -- Panel 2: LOAD active power (demand) = own draw + disturbance step --
ax2 = subplot(3,1,2); hold(ax2,'on'); grid(ax2,'on');
plot(ax2, stat.t, Pload_s/1e6, 'Color',[.85 .33 .10], 'LineWidth',1.4, 'DisplayName','static load');
plot(ax2, cmld.t, Pload_c/1e6, 'Color',[0 .45 .74], 'LineWidth',1.4, 'DisplayName','full CMLD');
xline(ax2, td, ':', 'HandleVisibility','off');
xlim(ax2,[t0 td+10]); ylabel(ax2,'load active power (MW)');
title(ax2, 'Load active power (demand)');
legend(ax2,'Location','southeast');

% -- Panel 3: GENERATION active power (supply) = swing/governor response --
ax3 = subplot(3,1,3); hold(ax3,'on'); grid(ax3,'on');
plot(ax3, stat.t, Pmech_s/1e6, 'Color',[.85 .33 .10], 'LineWidth',1.4, 'DisplayName','static load');
plot(ax3, cmld.t, Pmech_c/1e6, 'Color',[0 .45 .74], 'LineWidth',1.4, 'DisplayName','full CMLD');
xline(ax3, td, ':', 'HandleVisibility','off');
xlim(ax3,[t0 td+10]); xlabel(ax3,'time (s)'); ylabel(ax3,'generation active power (MW)');
title(ax3,'Generation active power (supply)');
legend(ax3,'Location','southeast');

% both active-power panels share one y-scale (the demand/supply gap drives freq)
yl = [min([Pload_s;Pload_c;Pmech_s;Pmech_c]) max([Pload_s;Pload_c;Pmech_s;Pmech_c])]/1e6;
yl = yl + [-1 1]*0.04*max(diff(yl),eps); ylim(ax2,yl); ylim(ax3,yl);

% self-label the file with the rotor-R scale so re-runs at different R don't clobber
rrscale = cmld.params.model_vars.MotorA_Rotor(1) / 0.05955;
out = fullfile(figdir, sprintf('motivating_cmld_vs_static_Rr%.1f_dp%.2f.png', rrscale, dpfrac));
exportgraphics(fig, out, 'Resolution',150); close(fig);
fprintf('  figure -> %s\nMOTIVATING_FIGURE_DONE\n', out);
end

function i = argmin(r, td)
post = find(r.t >= td); [~,k] = min(r.f(post)); i = post(k);
end
