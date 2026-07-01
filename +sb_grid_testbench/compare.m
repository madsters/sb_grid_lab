function out = compare(varargin)
%SB_GRID_TESTBENCH.COMPARE  Overlay frequency + per-load-type voltage panels.
%
%   out = sb_grid_testbench.compare(r1, r2, ...)
%   out = sb_grid_testbench.compare({r1, r2, ...})
%   out = sb_grid_testbench.compare(S)                 % results table w/ trace_path
%   out = sb_grid_testbench.compare(..., 'Name','my_compare')
%
% Compares two (or more) load types' simulation results. Each input is either a
% contract-2 results struct (with .t/.f/.V traces and .metrics/.params), or rows
% of a results table whose trace_path column points at results/raw/<hash>.mat
% (loaded and reconstituted into results structs).
%
% Plots:
%   panel 1            : grid frequency, all load types overlaid, nadir + the
%                        disturbance instant annotated, with a metrics text box.
%   panels 2..(N+1)    : terminal voltage, ONE panel per load type, each centred
%                        on its own operating level but sharing an IDENTICAL y-span
%                        so transient magnitudes are directly comparable.
%
% Saves results/fig/<Name>.png (default fig_compare_freq) via
% sb_grid_testbench.figures and returns out.results (the structs used) and
% out.path (the figure written).

% ----- parse inputs: split off Name/Value, collect result sources -------------
name = 'fig_compare_freq';
args = varargin;
keep = true(1, numel(args));
i = 1;
while i <= numel(args)
    if (ischar(args{i}) || isstring(args{i})) && strcmpi(args{i}, 'Name') && i < numel(args)
        name = char(args{i+1});
        keep(i) = false; keep(i+1) = false; i = i + 2;
    else
        i = i + 1;
    end
end
args = args(keep);

results = collect_results(args);
assert(numel(results) >= 2, 'sb_grid_testbench:compare:need2', ...
    'compare needs at least two results (got %d)', numel(results));
n = numel(results);

% ----- pull traces / metrics / disturbance time into a uniform form -----------
T = cell(1,n);                 % time, zero-based to each run start
F = cell(1,n); V = cell(1,n);
lt = cell(1,n);                % load type label
nad = nan(1,n); tnad = nan(1,n); rcf = nan(1,n); dip = nan(1,n); f0 = nan(1,n);
tdrel = nan(1,n);
for k = 1:n
    r = results{k};
    t0 = r.t(1);
    T{k} = r.t(:) - t0;        % zero-base (settle handoff makes t(1)>0)
    F{k} = r.f(:);
    V{k} = r.V(:);
    lt{k} = res_loadtype(r);
    m = res_metrics(r);
    nad(k)  = getfieldd(m, {'nadir'},  NaN);
    tnad(k) = getfieldd(m, {'t_nadir','tnadir'}, NaN) - t0;
    rcf(k)  = getfieldd(m, {'RoCoF','rocof'}, NaN);
    dip(k)  = getfieldd(m, {'dip'}, NaN);
    f0(k)   = getfieldd(m, {'f0'},  NaN);
    tdrel(k) = res_disttime(r) - t0;
end
td = median(tdrel(~isnan(tdrel)));  if isempty(td) || isnan(td), td = 0; end

% ----- console comparison -----------------------------------------------------
fprintf('\n%-14s %10s %10s %10s %10s\n','load type','RoCoF','nadir','dip','settle/f0');
for k = 1:n
    fprintf('%-14s %9.3f/s %8.3fHz %8.3fHz %9.3fHz\n', lt{k}, rcf(k), nad(k), dip(k), f0(k));
end
if n >= 2 && rcf(1) ~= 0 && dip(1) ~= 0
    for k = 2:n
        fprintf('  %s vs %s:  RoCoF %+0.1f%%   dip %+0.1f%%\n', lt{k}, lt{1}, ...
            100*(rcf(k)/rcf(1)-1), 100*(dip(k)/dip(1)-1));
    end
end

% ----- figure -----------------------------------------------------------------
fig = sb_grid_testbench.figures('newfig', 'compare', [100 100 920 260+260*n]);
xhi = max(cellfun(@(t) t(end), T));

% (1) frequency overlay
ax1 = subplot(n+1, 1, 1); hold(ax1,'on'); grid(ax1,'on');
for k = 1:n
    c = sb_grid_testbench.figures('color', lt{k});
    plot(ax1, T{k}, F{k}, '-', 'Color',c, 'LineWidth',1.6, ...
        'DisplayName', sb_grid_testbench.figures('label', lt{k}));
end
xline(ax1, td, 'k:', 'disturbance', 'LabelVerticalAlignment','bottom', ...
    'LabelHorizontalAlignment','left', 'HandleVisibility','off');
for k = 1:n
    if ~isnan(tnad(k)) && ~isnan(nad(k))
        c = sb_grid_testbench.figures('color', lt{k});
        plot(ax1, tnad(k), nad(k), 'o', 'Color',c, 'MarkerFaceColor',c, 'HandleVisibility','off');
    end
end
ylabel(ax1, 'grid frequency  (Hz)');
title(ax1, 'frequency response');
legend(ax1, 'Location','best'); legend(ax1, 'boxoff');
% metrics text box
lines = sprintf('%-12s %8s %8s\n', 'load','RoCoF','dip');
for k = 1:n
    lines = [lines, sprintf('%-12s %+7.3f %7.3f\n', lt{k}, rcf(k), dip(k))]; %#ok<AGROW>
end
text(ax1, 0.985, 0.04, lines, 'Units','normalized', 'HorizontalAlignment','right', ...
    'VerticalAlignment','bottom', 'FontName','FixedWidth', 'FontSize',9, ...
    'BackgroundColor',[1 1 1 0.85], 'EdgeColor',[0.7 0.7 0.7]);

% (2..) terminal voltage — one panel per load type, shared y-span
vspan = max([cellfun(@range, V), 0.01]) * 1.3;            % common span, with a floor
axV = gobjects(1,n);
for k = 1:n
    ax = subplot(n+1, 1, k+1); hold(ax,'on'); grid(ax,'on');
    c = sb_grid_testbench.figures('color', lt{k});
    plot(ax, T{k}, V{k}, '-', 'Color',c, 'LineWidth',1.6);
    xline(ax, td, 'k:', 'HandleVisibility','off');
    ctr = (max(V{k}) + min(V{k}))/2;
    ylim(ax, ctr + [-1 1]*vspan/2);
    base = mean(V{k}(T{k} < td));
    ylabel(ax, 'V_{term}  (pu)');
    title(ax, sprintf('%s  —  terminal voltage  (baseline %.3f pu)', ...
        sb_grid_testbench.figures('label', lt{k}), base));
    if k == n, xlabel(ax, 'time  (s)'); end
    axV(k) = ax;
end
linkaxes([ax1, axV], 'x'); xlim(ax1, [max(0, td-1) xhi]);

out.results = results;
out.path = sb_grid_testbench.figures('save', fig, name);
end

% ===========================================================================
function results = collect_results(args)
% Flatten args into a cell array of contract-2 results structs. Args may be
% individual structs, a single cell array of structs, or a results table whose
% trace_path column points at saved trace .mat files.
results = {};
for i = 1:numel(args)
    a = args{i};
    if istable(a)
        for r = 1:height(a)
            results{end+1} = load_trace_row(a(r,:)); %#ok<AGROW>
        end
    elseif iscell(a)
        for j = 1:numel(a)
            results{end+1} = a{j}; %#ok<AGROW>
        end
    elseif isstruct(a) && numel(a) > 1
        for j = 1:numel(a)
            results{end+1} = a(j); %#ok<AGROW>
        end
    else
        results{end+1} = a; %#ok<AGROW>
    end
end
end

% ---------------------------------------------------------------------------
function r = load_trace_row(row)
% Load a results struct from a table row's trace_path. The .mat is expected to
% hold either a 'results' struct (contract 2) or the trace fields directly.
vn = row.Properties.VariableNames;
assert(ismember('trace_path', vn), 'sb_grid_testbench:compare:noTracePath', ...
    'table rows need a trace_path column to load traces');
tp = char(string(row.trace_path));
% resolve relative to results/raw if not absolute and not found as given
if ~isfile(tp)
    pkgdir = fileparts(mfilename('fullpath'));
    root   = fileparts(pkgdir);
    alt    = fullfile(root, 'results', 'raw', tp);
    if isfile(alt), tp = alt; end
    [~,b,e] = fileparts(tp);
    alt2   = fullfile(root, 'results', 'raw', [b e]);
    if ~isfile(tp) && isfile(alt2), tp = alt2; end
end
assert(isfile(tp), 'sb_grid_testbench:compare:traceMissing', ...
    'trace file not found: %s', tp);
S = load(tp);
if isfield(S, 'results'),    r = S.results;
elseif isfield(S, 'r'),      r = S.r;
else,                        r = S;          % fields saved at top level
end
% carry the load_type from the table row if the struct lacks it
if (~isfield(r, 'params') || ~isfield(r.params, 'load_type')) && ismember('load_type', vn)
    r.params.load_type = char(string(row.load_type));
end
end

% ---------------------------------------------------------------------------
function lt = res_loadtype(r)
if isfield(r, 'params') && isfield(r.params, 'load_type')
    lt = char(r.params.load_type);
elseif isfield(r, 'load_type')
    lt = char(r.load_type);
else
    lt = 'load';
end
end

% ---------------------------------------------------------------------------
function m = res_metrics(r)
if isfield(r, 'metrics'), m = r.metrics; else, m = r; end
end

% ---------------------------------------------------------------------------
function td = res_disttime(r)
td = NaN;
if isfield(r, 'params') && isfield(r.params, 'disturbance') ...
        && isfield(r.params.disturbance, 'dist_time')
    td = r.params.disturbance.dist_time;
elseif isfield(r, 'meta') && isfield(r.meta, 'dist_time')
    td = r.meta.dist_time;
elseif isfield(r, 'dist_time')
    td = r.dist_time;
end
end

% ---------------------------------------------------------------------------
function v = getfieldd(s, names, default)
v = default;
if ~isstruct(s), return; end
for i = 1:numel(names)
    if isfield(s, names{i}), v = s.(names{i}); return; end
end
end
