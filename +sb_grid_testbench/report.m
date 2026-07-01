function report(S, xcol, xlab, ttl)
%SB_GRID_TESTBENCH.REPORT  Console table + deltas + metrics-vs-x figure for a sweep.
%
%   sb_grid_testbench.report(S, xcol, xlab, ttl)
%     S    : results table with contract-3 columns — load_type, the swept column
%            <xcol>, rocof, dip, settle (and optionally vbase). Lowercase contract
%            names are preferred; legacy capitalised names (RoCoF/dip/settle/Vbase,
%            grouping column 'test') are also accepted.
%     xcol : name of the swept-variable column ('dist_dp','dp_mw','m','scr',...)
%     xlab : x-axis label for the figure
%     ttl  : figure super-title
%
% Generic over the swept axis so the disturbance / inertia / SCR presets share it.
% Prints a per-row table, then first-vs-rest deltas at each x (the first load type
% in the table is the reference — e.g. 'static' vs the rest), and saves a
% metrics-vs-x figure (|RoCoF|, nadir dip, settle vs <xcol>, one line per
% load_type) to results/fig/fig_sweep_<xcol>.png via sb_grid_testbench.figures.

if nargin < 1 || isempty(S),  error('sb_grid_testbench:report:noTable','S (results table) is required'); end
if nargin < 2 || isempty(xcol), xcol = 'dp_mw'; end
if nargin < 3 || isempty(xlab), xlab = xcol;    end
if nargin < 4, ttl = ''; end
xcol = char(xcol);

vn = S.Properties.VariableNames;
grpCol = pick(vn, {'load_type','test'});                 % grouping column
rcCol  = pick(vn, {'rocof','RoCoF'});
dipCol = pick(vn, {'dip'});
setCol = pick(vn, {'settle','f_settle'});
vbCol  = pick(vn, {'vbase','Vbase'});                     % optional
assert(~isempty(grpCol), 'sb_grid_testbench:report:noGroup', ...
    'table needs a load_type (or test) column');
assert(ismember(xcol, vn), 'sb_grid_testbench:report:noXcol', ...
    'swept column "%s" not found in table', xcol);

grp = grpval(S.(grpCol));                                 % cellstr of group labels
types = unique(grp, 'stable');
hasV  = ~isempty(vbCol);

% ----- per-row table ----------------------------------------------------------
if hasV
    fprintf('\n%-14s %12s %8s %10s %9s %10s\n', ...
        char(grpCol), xcol, 'Vbase', 'RoCoF/s', 'dip(Hz)', 'settle(Hz)');
else
    fprintf('\n%-14s %12s %10s %9s %10s\n', ...
        char(grpCol), xcol, 'RoCoF/s', 'dip(Hz)', 'settle(Hz)');
end
for i = 1:height(S)
    if hasV
        fprintf('%-14s %12.4g %8.3f %10.4f %9.4f %10.4f\n', grp{i}, ...
            S.(xcol)(i), S.(vbCol)(i), S.(rcCol)(i), S.(dipCol)(i), S.(setCol)(i));
    else
        fprintf('%-14s %12.4g %10.4f %9.4f %10.4f\n', grp{i}, ...
            S.(xcol)(i), S.(rcCol)(i), S.(dipCol)(i), S.(setCol)(i));
    end
end

% ----- first-vs-rest deltas at each x value -----------------------------------
if numel(types) >= 2
    ref = types{1};
    xs  = unique(S.(xcol), 'stable');
    for j = 2:numel(types)
        cmp = types{j};
        fprintf('\n%s vs %s\n', cmp, ref);
        fprintf('%12s %16s %14s\n', xcol, sprintf('dRoCoF(%s-%s)',cmp,ref), 'ddip');
        for k = 1:numel(xs)
            a = S(strcmp(grp, ref) & S.(xcol) == xs(k), :);
            b = S(strcmp(grp, cmp) & S.(xcol) == xs(k), :);
            if height(a) && height(b)
                ra = a.(rcCol)(1); rb = b.(rcCol)(1);
                da = a.(dipCol)(1); db = b.(dipCol)(1);
                fprintf('%12.4g %+15.1f%% %+13.1f%%\n', xs(k), ...
                    100*(rb/ra - 1), 100*(db/da - 1));
            end
        end
    end
end

% ----- metrics-vs-x figure (saved, off-screen) --------------------------------
try
    fig = sb_grid_testbench.figures('newfig', 'sweep', [100 100 1000 360]);
    mets  = {rcCol, dipCol, setCol};
    ylabs = {'RoCoF (Hz/s)', 'nadir dip (Hz)', 'settle (Hz)'};
    for m = 1:3
        ax = subplot(1,3,m); hold(ax,'on'); grid(ax,'on');
        for ti = 1:numel(types)
            tid = types{ti};
            r = S(strcmp(grp, tid), :);
            r = sortrows(r, xcol);
            c = sb_grid_testbench.figures('color', tid);
            plot(ax, r.(xcol), r.(mets{m}), '-o', 'Color',c, ...
                'MarkerFaceColor',c, 'DisplayName', sb_grid_testbench.figures('label', tid));
        end
        xlabel(ax, xlab); ylabel(ax, ylabs{m});
        if m == 1, legend(ax, 'Location','best'); legend(ax, 'boxoff'); end
    end
    if ~isempty(ttl), sgtitle(ttl); end
    sb_grid_testbench.figures('save', fig, sprintf('fig_sweep_%s', xcol));
catch ME
    fprintf('(figure skipped: %s)\n', ME.message);
end
end

% ---------------------------------------------------------------------------
function name = pick(vn, candidates)
% First candidate present in the variable-name list (empty if none).
name = '';
for i = 1:numel(candidates)
    if ismember(candidates{i}, vn), name = candidates{i}; return; end
end
end

% ---------------------------------------------------------------------------
function g = grpval(col)
% Coerce a grouping column (cellstr/string/categorical/char) to cellstr.
if iscell(col)
    g = cellfun(@char, col, 'UniformOutput', false);
elseif isstring(col) || iscategorical(col)
    g = cellstr(col);
elseif ischar(col)
    g = cellstr(col);
else
    g = cellstr(string(col));
end
g = g(:);
end
