function pv_figure_sa(runs, T, f_trip, Ptarget, dp, figdir)
%PV_FIGURE_SA  South-Australia-like scenario figures. Produces:
%  (1) the headline freq + load-active-power(demand+PV) panels (via pv_figure2)
%      at the highest DER penetration that still SPLITs (static trips, CMLD
%      rides) -- the most dramatic legible case;
%  (2) a scaling summary: post-disturbance nadir vs PV penetration for the
%      static vs CMLD load model, with the 49.5 Hz DER-trip and 49.0 Hz UFLS
%      lines -- shows the CONSEQUENCE of the load-model error growing with
%      penetration (static plunges past UFLS; CMLD rides through flat).
%
%   pv_figure_sa(runs, T, f_trip, Ptarget, dp, figdir)
f_ufls = 49.0; cS = [.85 .33 .10]; cC = [0 .45 .74];

% ---- headline penetration = highest that SPLITs (static trips, CMLD rides) ----
split = T.trip_static & ~T.trip_cmld;
if any(split), hi = find(split,1,'last'); else, [~,hi] = max(T.pv_frac); end
sr = runs(hi).stat; cr = runs(hi).cmld;
pv_figure2(sr, cr, f_trip, figdir, sprintf('sa_headline_pv%02d_dp%.2f', round(T.pv_frac(hi)*100), dp));

% ---- scaling summary: nadir vs penetration ----
fig = figure('Visible','off','Position',[100 100 900 560],'Color','w');
try, theme(fig,'light'); catch, end
ax = axes(fig); hold(ax,'on'); grid(ax,'on'); set(ax,'Color','w','GridAlpha',0.15);
pf = T.pv_frac*100;
plot(ax, pf, T.nadir_static, '-o', 'Color',cS, 'MarkerFaceColor',cS, 'LineWidth',1.8, 'DisplayName','static load + PV');
plot(ax, pf, T.nadir_cmld,   '-o', 'Color',cC, 'MarkerFaceColor',cC, 'LineWidth',1.8, 'DisplayName','full CMLD + PV');
yline(ax, f_trip, '--', sprintf('%.1f Hz DER trip',f_trip), 'Color',[.15 .15 .15], ...
    'LineWidth',1.3, 'LabelHorizontalAlignment','left','HandleVisibility','off');
yline(ax, f_ufls, ':', sprintf('%.1f Hz UFLS',f_ufls), 'Color',[.45 .45 .45], ...
    'LineWidth',1.1, 'LabelHorizontalAlignment','left','HandleVisibility','off');
% shade the trip-fired region for the static (where it dips below the DER line)
xlabel(ax,'instantaneous DER penetration / trip block (% of P_W)');
ylabel(ax,'post-disturbance frequency nadir (Hz)');
legend(ax,'Location','southwest');
title(ax, sprintf(['South-Australia-like scenario: consequence of the load-model choice scales with DER penetration\n' ...
    '(same +%.2f pu disturbance; stress corner). Static trips \\Rightarrow deep cascade; CMLD rides through.'], dp));
ylim(ax, [min([T.nadir_static; f_ufls])-0.15, 50.0]);

out = fullfile(figdir, sprintf('pv_sa_scaling_dp%.2f.png', dp));
exportgraphics(fig, out, 'Resolution',150); close(fig);
fprintf('  figure -> %s\n', out);
end
