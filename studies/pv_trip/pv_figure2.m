function pv_figure2(stat, cmld, f_trip, figdir)
%PV_FIGURE2  Phase-2 headline: identical frequency-tripped rooftop PV in both a
% static and a full-CMLD load model. At the same load step the static's nadir
% crosses the 49.5 Hz DER line -> PV trips -> secondary cascade toward the 49 Hz
% UFLS line; the CMLD stays above 49.5 -> PV rides through. Two panels:
%   (1) grid frequency, with the 49.5 (DER trip) + 49.0 (UFLS ref) lines, nadirs,
%       and the PV-trip instant marked.
%   (2) PV generation: the static case collapses to 0 at the trip; the CMLD holds.
%
%   pv_figure2(stat, cmld, f_trip, figdir)  % stat/cmld are runfull() structs
if nargin < 3 || isempty(f_trip), f_trip = 49.5; end
if nargin < 4, figdir = fileparts(mfilename('fullpath')); end
f_ufls = 49.0;
td = cmld.td; t0 = td-1;
dp = cmld.params.disturbance.dist_dP_frac;
Mg = cmld.params.grid.M; SCRg = cmld.params.grid.SCR;
P_pv = cmld.params.model_vars.P_pv;
ms = stat.metrics; mc = cmld.metrics;
cS = [.85 .33 .10]; cC = [0 .45 .74];

fig = figure('Visible','off','Position',[100 100 1000 780],'Color','w');
try, theme(fig,'light'); catch, end
tl = tiledlayout(fig,2,1,'TileSpacing','compact','Padding','compact');

% ---- Panel 1: frequency ----
ax1 = nexttile(tl); hold(ax1,'on'); grid(ax1,'on'); set(ax1,'Color','w','GridAlpha',0.15);
plot(ax1, stat.t, stat.f, 'Color',cS, 'LineWidth',1.8, 'DisplayName','static load + PV');
plot(ax1, cmld.t, cmld.f, 'Color',cC, 'LineWidth',1.8, 'DisplayName','full CMLD + PV');
yline(ax1, f_trip, '--', sprintf('%.1f Hz DER trip',f_trip), 'Color',[.15 .15 .15], ...
    'LineWidth',1.3, 'LabelHorizontalAlignment','left','LabelVerticalAlignment','bottom','HandleVisibility','off');
yline(ax1, f_ufls, ':', sprintf('%.1f Hz UFLS (ref)',f_ufls), 'Color',[.45 .45 .45], ...
    'LineWidth',1.0, 'LabelHorizontalAlignment','left','LabelVerticalAlignment','bottom','HandleVisibility','off');
xline(ax1, td, ':', 'HandleVisibility','off');
plot(ax1, stat.t(argmin(stat.f,stat.t,td)), ms.nadir, 'v','MarkerFaceColor',cS,'MarkerEdgeColor',cS,'MarkerSize',8,'HandleVisibility','off');
plot(ax1, cmld.t(argmin(cmld.f,cmld.t,td)), mc.nadir, 'v','MarkerFaceColor',cC,'MarkerEdgeColor',cC,'MarkerSize',8,'HandleVisibility','off');
text(ax1, stat.t(argmin(stat.f,stat.t,td)), ms.nadir-0.02, sprintf(' %.3f',ms.nadir),'Color',cS,'VerticalAlignment','top','FontWeight','bold');
text(ax1, cmld.t(argmin(cmld.f,cmld.t,td)), mc.nadir+0.01, sprintf(' %.3f',mc.nadir),'Color',cC,'VerticalAlignment','bottom','FontWeight','bold');
if stat.tripped
    xline(ax1, stat.t_trip, '-', 'PV trips', 'Color',cS, 'LineWidth',1.0, ...
        'LabelVerticalAlignment','top','LabelHorizontalAlignment','right','HandleVisibility','off');
end
xlim(ax1,[t0 td+10]);
ylo = min([ms.nadir mc.nadir f_ufls])-0.08; ylim(ax1,[ylo max([stat.f(:);cmld.f(:)])+0.03]);
ylabel(ax1,'grid frequency (Hz)'); legend(ax1,'Location','southeast');
title(ax1, sprintf(['Same +%.2f pu load step + identical 49.5 Hz-trip rooftop PV: opposite outcome (M=%g s, SCR=%g, H=2.5)\n' ...
    'static \\Rightarrow nadir %.3f < 49.5 \\Rightarrow PV TRIPS & cascades   |   CMLD \\Rightarrow nadir %.3f > 49.5 \\Rightarrow rides through'], ...
    dp, Mg, SCRg, ms.nadir, mc.nadir));

% ---- Panel 2: PV generation ----
ax2 = nexttile(tl); hold(ax2,'on'); grid(ax2,'on'); set(ax2,'Color','w','GridAlpha',0.15);
plot(ax2, stat.t, stat.pv_active/1e6, 'Color',cS, 'LineWidth',1.8, 'DisplayName','static case');
plot(ax2, cmld.t, cmld.pv_active/1e6, 'Color',cC, 'LineWidth',1.8, 'DisplayName','CMLD case');
xline(ax2, td, ':', 'HandleVisibility','off');
if stat.tripped
    xline(ax2, stat.t_trip, '-', 'Color',cS, 'LineWidth',1.0, 'HandleVisibility','off');
end
xlim(ax2,[t0 td+10]); ylim(ax2,[-0.05*P_pv/1e6 1.15*P_pv/1e6]);
xlabel(ax2,'time (s)'); ylabel(ax2,'PV generation (MW)'); legend(ax2,'Location','east');
title(ax2, sprintf('Behind-the-meter PV generation (%.0f MW ~ %.2f pu): static PV trips to 0, CMLD PV holds', ...
    P_pv/1e6, P_pv/cmld.params.scale.P_W));

out = fullfile(figdir, sprintf('pv_trip_phase2_dp%.2f.png', dp));
exportgraphics(fig, out, 'Resolution',150); close(fig);
fprintf('  figure -> %s\n', out);
end

function i = argmin(f, t, td)
post = find(t >= td); [~,k] = min(f(post)); i = post(k);
end
