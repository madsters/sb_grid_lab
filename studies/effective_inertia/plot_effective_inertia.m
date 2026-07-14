function plot_effective_inertia(figdir)
%PLOT_EFFECTIVE_INERTIA  Clean publication figures from the T2 results (.mat).
%
%   plot_effective_inertia()            % -> results/fig/eff_inertia_*.png
%   plot_effective_inertia(figdir)
%
% Loads t2_results.mat (T table + curves) and draws three headless figures that
% tell the stored-vs-delivered story:
%   (A) H_eff(T) window curves  -- E1 (RoCoF-apparent) rises from ~0; E3 (delivered
%       inertia) stays ~0 -> motors give NO synchronous inertia; the RoCoF benefit
%       is fast frequency response that builds over the window.
%   (B) stored vs delivered bars -- H_load (stored, eq:hload) vs H_eff^E3 (delivered
%       inertia, 500 ms) vs H_eff^E1 (RoCoF-apparent, 500 ms), per mix. Delivered
%       inertia is ~2 orders of magnitude below stored.
%   (C) response factor r vs H_load -- r_E1 (apparent, >1, drifts) and r_E3 (true
%       delivered fraction, ~0.004, flat) on a log axis; r=1 upper bound marked.
% Pure plotting of stored results -- no simulation.

sc = fileparts(mfilename('fullpath'));
if nargin < 1 || isempty(figdir)
    figdir = fullfile(fileparts(fileparts(sc)),'results','fig');
end
if ~isfolder(figdir), mkdir(figdir); end
D = load(fullfile(sc,'t2_results.mat'));   % T, curves
T = D.T; curves = D.curves;

pal = distinct9();   % 9 visually-distinct colors (lines() only has 7)

% ============================ (A) H_eff(T) curves ==========================
for cn = ["stress","nominal"]
    sel = curves(strcmp({curves.corner},char(cn)) & ([curves.dp]==0.10));
    if isempty(sel), continue; end
    f = figure('Visible','off','Color','w','Position',[100 100 860 580]);
    ax = axes(f); hold(ax,'on'); grid(ax,'on'); set(ax,'XScale','log');
    for i = 1:numel(sel)
        c = sel(i);
        plot(ax, c.windows, c.Heff_E1, '-o', 'Color',pal(i,:), 'LineWidth',1.5, ...
             'MarkerFaceColor',pal(i,:), 'MarkerSize',4, ...
             'DisplayName',sprintf('%s  (H_{load}=%.2f)', c.id, c.H_load));
        plot(ax, c.windows, c.Heff_E3, ':s', 'Color',pal(i,:), 'LineWidth',1.2, ...
             'MarkerSize',3, 'HandleVisibility','off');
    end
    xlabel(ax,'RoCoF measurement window T (s)'); ylabel(ax,'effective inertia H_{eff} (s)');
    title(ax, {sprintf('Delivered effective inertia H_{eff}(T) — %s corner (\\DeltaP=+0.10 pu)', cn), ...
        'solid = E1 RoCoF-apparent (inertia + fast freq response);  dotted = E3 delivered inertia (KE released)'}, ...
        'FontSize',10);
    legend(ax,'Location','northwest','FontSize',8,'NumColumns',2);
    xlim(ax,[0.018 0.6]);
    exportgraphics(f, fullfile(figdir,sprintf('eff_inertia_Heff_curve_%s.png',cn)), 'Resolution',150);
    close(f);
end

% ==================== (B) stored vs delivered bars (stress) ================
m = strcmp(T.corner,'stress') & T.dp==0.10;
ids = T.mix(m); Hl = T.H_load_s(m); H1 = T.Heff_E1_500ms(m); H3 = T.Heff_E3_500ms(m);
[Hl,ord] = sort(Hl); ids = ids(ord); H1 = H1(ord); H3 = H3(ord);
f = figure('Visible','off','Color','w','Position',[100 100 900 560]);
ax = axes(f);
Y = [Hl, H1, max(H3,1e-4)];              % floor E3 for log display
b = bar(ax, Y, 'grouped'); grid(ax,'on'); set(ax,'YScale','log');
b(1).FaceColor=[0.30 0.35 0.55]; b(2).FaceColor=[0.85 0.55 0.20]; b(3).FaceColor=[0.55 0.75 0.45];
set(ax,'XTick',1:numel(ids),'XTickLabel',ids);
ylabel(ax,'inertia (s, log scale)'); ylim(ax,[1e-4 3]);
legend(ax, {'H_{load} stored (eq:hload)', 'H_{eff}^{E1} RoCoF-apparent (500 ms)', ...
            'H_{eff}^{E3} delivered inertia (500 ms)'}, 'Location','northoutside','NumColumns',3,'FontSize',9);
title(ax,'Stored vs delivered inertia per mix — stress corner, \DeltaP=+0.10 pu','FontSize',11);
exportgraphics(f, fullfile(figdir,'eff_inertia_stored_vs_delivered.png'), 'Resolution',150); close(f);

% ============ (C) measured 500ms-RoCoF H_eff vs formula H_load =============
% THE headline comparison: does the stored-energy formula predict the measured
% effective inertia? y=x is the formula's claim (H_eff = H_load); the fit shows
% slope~1 (formula gets the sensitivity) + an offset (fast freq response it misses).
f = figure('Visible','off','Color','w','Position',[100 100 820 620]);
ax = axes(f); hold(ax,'on'); grid(ax,'on'); axis(ax,'equal');
cols = containers.Map({'stress','nominal'},{[0.85 0.33 0.10],[0.00 0.45 0.74]});
mk   = containers.Map({'stress','nominal'},{'o','^'});
xl = [0 1.6];
plot(ax, xl, xl, 'k--', 'LineWidth',1.2, 'DisplayName','formula: H_{eff}=H_{load} (y=x)');
for cn = ["stress","nominal"]
    mm = strcmp(T.corner,char(cn)) & T.dp==0.10;
    hl = T.H_load_s(mm); he = T.Heff_E1_500ms(mm);
    scatter(ax, hl, he, 60, cols(char(cn)), mk(char(cn)), 'filled', ...
        'DisplayName',sprintf('measured (%s)',cn));
    p = polyfit(hl,he,1); xx=linspace(min(hl),max(hl),2);
    plot(ax, xx, polyval(p,xx), '-', 'Color',cols(char(cn)), 'LineWidth',1.6, ...
        'DisplayName',sprintf('fit %s: H_{eff}=%.2f·H_{load}+%.2f', cn, p(1),p(2)));
end
xlabel(ax,'stored-energy H_{load} (s)  [your formula \Sigma(F_{mi}/LF)H_i]');
ylabel(ax,'measured 500 ms-RoCoF effective inertia H_{eff} (s)');
title(ax,{'Measured effective inertia vs the stored-energy formula (\DeltaP=+0.10 pu)', ...
    'slope\approx1 (formula tracks the H/fraction sensitivity); intercept = fast freq response the formula omits'}, ...
    'FontSize',10);
legend(ax,'Location','southeast','FontSize',8); xlim(ax,xl); ylim(ax,[0 1.7]);
exportgraphics(f, fullfile(figdir,'eff_inertia_measured_vs_formula.png'), 'Resolution',150); close(f);

fprintf('PLOTS_OK -> %s\n', figdir);
end

function c = distinct9()
c = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.93 0.69 0.13; 0.49 0.18 0.56; ...
     0.47 0.67 0.19; 0.30 0.75 0.93; 0.64 0.08 0.18; 0.25 0.25 0.25; 0.90 0.40 0.70];
end
