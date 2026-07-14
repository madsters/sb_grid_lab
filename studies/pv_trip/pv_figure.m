function pv_figure(stat, cmld, f_trip, figdir)
%PV_FIGURE  The headline: same load step, opposite protection outcome, driven
% purely by load-model choice. Overlays the frequency response of a constant-Z
% static load vs a full CMLD at the knife-edge disturbance, draws the 49.5 Hz DER
% trip line (and the 49 Hz UFLS reference), and marks each nadir -- static dips
% below 49.5 (rooftop PV would trip) while the CMLD rides through.
%
%   pv_figure(stat, cmld, f_trip, figdir)
%
% stat/cmld are sb_grid_sim.simulate result structs (.t .f .metrics .meta .params)
% at the SAME dP. Styled after reducing_cmld/motivating/motivating_figure.m.
if nargin < 3 || isempty(f_trip), f_trip = 49.5; end
if nargin < 4, figdir = fileparts(mfilename('fullpath')); end

td  = cmld.meta.dist_time_abs; t0 = td-1;
dp  = cmld.params.disturbance.dist_dP_frac;
Mg  = cmld.params.grid.M; SCRg = cmld.params.grid.SCR;
ms  = stat.metrics; mc = cmld.metrics;
f_ufls = 49.0;

cS = [.85 .33 .10];   % static (orange)
cC = [0 .45 .74];     % CMLD (blue)

fig = figure('Visible','off','Position',[100 100 1000 620],'Color','w');
try, theme(fig,'light'); catch, end     % R2025b defaults to dark under -batch; force light
ax = axes(fig); hold(ax,'on'); grid(ax,'on');
set(ax,'Color','w','GridColor',[.15 .15 .15],'GridAlpha',0.15);

plot(ax, stat.t, stat.f, 'Color',cS, 'LineWidth',1.8, 'DisplayName','static load');
plot(ax, cmld.t, cmld.f, 'Color',cC, 'LineWidth',1.8, 'DisplayName','full CMLD');
yline(ax, f_trip, '--', sprintf('%.1f Hz DER trip',f_trip), ...
    'Color',[.15 .15 .15], 'LineWidth',1.3, 'LabelHorizontalAlignment','left', ...
    'LabelVerticalAlignment','bottom', 'HandleVisibility','off');
yline(ax, f_ufls, ':', sprintf('%.1f Hz UFLS (ref)',f_ufls), ...
    'Color',[.45 .45 .45], 'LineWidth',1.0, 'LabelHorizontalAlignment','left', ...
    'LabelVerticalAlignment','bottom', 'HandleVisibility','off');
xline(ax, td, ':', 'HandleVisibility','off');

% nadir markers
plot(ax, stat.t(argmin(stat,td)), ms.nadir, 'v', 'MarkerFaceColor',cS, ...
    'MarkerEdgeColor',cS, 'MarkerSize',8, 'HandleVisibility','off');
plot(ax, cmld.t(argmin(cmld,td)), mc.nadir, 'v', 'MarkerFaceColor',cC, ...
    'MarkerEdgeColor',cC, 'MarkerSize',8, 'HandleVisibility','off');
text(ax, stat.t(argmin(stat,td)), ms.nadir-0.01, sprintf(' %.3f',ms.nadir), ...
    'Color',cS, 'VerticalAlignment','top', 'FontWeight','bold');
text(ax, cmld.t(argmin(cmld,td)), mc.nadir+0.008, sprintf(' %.3f',mc.nadir), ...
    'Color',cC, 'VerticalAlignment','bottom', 'FontWeight','bold');

% the outcome annotation
outcome = sprintf(['static \\Rightarrow nadir %.3f < %.1f \\Rightarrow PV TRIPS\n' ...
                   'CMLD \\Rightarrow nadir %.3f > %.1f \\Rightarrow rides through'], ...
                   ms.nadir, f_trip, mc.nadir, f_trip);
xr = td+6;
text(ax, xr, f_trip+0.02, outcome, 'FontSize',10, 'Color',[.1 .1 .1], ...
     'BackgroundColor',[1 1 .85], 'EdgeColor',[.6 .6 .6], 'VerticalAlignment','bottom');

xlim(ax,[t0 td+10]);
ylo = min([ms.nadir mc.nadir f_ufls]) - 0.06;
ylim(ax,[ylo max([stat.f(:);cmld.f(:)])+0.02]);
xlabel(ax,'time (s)'); ylabel(ax,'grid frequency (Hz)');
legend(ax,'Location','southeast');
title(ax, sprintf(['Same +%.2f pu load step, opposite DER-protection outcome (M = %g s, SCR = %g, H = 2.5)\n' ...
    'load-model fidelity alone decides whether rooftop PV trips'], dp, Mg, SCRg));

out = fullfile(figdir, sprintf('pv_trip_threshold_dp%.2f.png', dp));
exportgraphics(fig, out, 'Resolution',150); close(fig);
fprintf('  figure -> %s\n', out);
end

function i = argmin(r, td)
post = find(r.t >= td); [~,k] = min(r.f(post)); i = post(k);
end
