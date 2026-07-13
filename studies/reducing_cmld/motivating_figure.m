function motivating_figure(H)
%MOTIVATING_FIGURE  The premise of the reduction study: a (full) CMLD produces a
% materially different frequency response than a true (constant-Z, freq-
% independent) static load under realistic stress conditions -- BOTH pinned to
% 1 pu. Overlays full CMLD (cmld_3m at motor inertia H) vs true_static from the
% cached stress-corner traces and reports the RoCoF / nadir-dip advantage.
%   motivating_figure(2.5)   % use the H=2.5 CMLD trace (default)
if nargin < 1, H = 2.5; end
repo = fileparts(fileparts(fileparts(mfilename('fullpath'))));
run(fullfile(repo,'startup_sbgrid.m'));
raw    = fullfile(repo,'studies','reducing_cmld','reducing_cmld_raw');
figdir = fullfile(repo,'results','fig'); if ~isfolder(figdir), mkdir(figdir); end

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
rocof_adv = (abs(ms.RoCoF)-abs(mc.RoCoF))/abs(ms.RoCoF)*100;
dip_adv   = (ms.dip - mc.dip)/ms.dip*100;
Pc = mean(cmld.P(cmld.t<cmld.meta.dist_time_abs & cmld.t>cmld.meta.dist_time_abs-1));
Ps = mean(stat.P(stat.t<stat.meta.dist_time_abs & stat.t>stat.meta.dist_time_abs-1));
fprintf('\n== full CMLD (H=%.1f) vs true static (const-Z), stress M=3 SCR=5, +0.25 pu ==\n', H);
fprintf('  pre-dist draw: cmld %.0f MW   static %.0f MW  (both ~1 pu)\n', Pc/1e6, Ps/1e6);
fprintf('  RoCoF:  static %.3f  cmld %.3f Hz/s   -> CMLD better by %.1f%%\n', ms.RoCoF, mc.RoCoF, rocof_adv);
fprintf('  dip  :  static %.3f  cmld %.3f Hz     -> CMLD better by %.1f%%\n', ms.dip, mc.dip, dip_adv);

fig = figure('Visible','off','Position',[100 100 1000 760]);
td = cmld.meta.dist_time_abs; t0 = td-1;

% -- Panel 1: frequency overlay --
ax1 = subplot(2,1,1); hold(ax1,'on'); grid(ax1,'on');
plot(ax1, stat.t, stat.f, 'Color',[.85 .33 .10], 'LineWidth',1.6, 'DisplayName','static load');
plot(ax1, cmld.t, cmld.f, 'Color',[0 .45 .74], 'LineWidth',1.6, 'DisplayName','full CMLD');
xline(ax1, td, ':', 'disturbance', 'HandleVisibility','off');
plot(ax1, stat.t(argmin(stat,td)), ms.nadir, 'v', 'Color',[.85 .33 .10], 'HandleVisibility','off');
plot(ax1, cmld.t(argmin(cmld,td)), mc.nadir, 'v', 'Color',[0 .45 .74], 'HandleVisibility','off');
xlim(ax1,[t0 td+10]); ylabel(ax1,'frequency (Hz)'); legend(ax1,'Location','southeast');
title(ax1, sprintf(['Why the CMLD matters: full CMLD vs static  (stress M=3, SCR=5, +0.25 pu)\n' ...
    'RoCoF %.1f%% shallower,  nadir dip %.1f%% smaller with the CMLD'], rocof_adv, dip_adv));

% -- Panel 2: active power overlay (plotting standard; display-smoothed) --
% The constant-PQ static load's P measurement carries sub-cycle ripple + a few
% control-loop spikes; median+mean filter for a legible slide (frequency above
% is raw). Physics unchanged -- the trend (static ~flat, CMLD motor recovery).
ax2 = subplot(2,1,2); hold(ax2,'on'); grid(ax2,'on');
sm = @(x) movmean(movmedian(x(:),151),151);
plot(ax2, stat.t, sm(stat.P)/1e6, 'Color',[.85 .33 .10], 'LineWidth',1.4, 'DisplayName','static load');
plot(ax2, cmld.t, sm(cmld.P)/1e6, 'Color',[0 .45 .74], 'LineWidth',1.4, 'DisplayName','full CMLD');
xline(ax2, td, ':', 'HandleVisibility','off');
xlim(ax2,[t0 td+10]); xlabel(ax2,'time (s)'); ylabel(ax2,'load active power P_{load} (MW, smoothed)');
legend(ax2,'Location','southeast');

out = fullfile(figdir,'motivating_cmld_vs_static.png');
exportgraphics(fig, out, 'Resolution',150); close(fig);
fprintf('  figure -> %s\nMOTIVATING_FIGURE_DONE\n', out);
end

function i = argmin(r, td)
post = find(r.t >= td); [~,k] = min(r.f(post)); i = post(k);
end
