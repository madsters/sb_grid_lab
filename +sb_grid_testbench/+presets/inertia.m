function S = inertia(varargin)
%SB_GRID_TESTBENCH.PRESETS.INERTIA  Sweep grid inertia constant M, per load type.
%
%   S = sb_grid_testbench.presets.inertia
%   S = sb_grid_testbench.presets.inertia('Tests',{'static','full_cmld'})
%   S = sb_grid_testbench.presets.inertia('values',[2 4 6 8 12 16])
%
% Sweeps the grid swing-inertia constant grid.M at a fixed disturbance and
% tabulates RoCoF / nadir dip / settle for each load model (expected RoCoF, dip
% ~ 1/M; settle ~ M-independent). For each requested load type it builds a base
% params via sb_grid_sim.default_params and calls sb_grid_testbench.sweep over
% 'grid.M', then vertically concatenates the per-type result tables and reports.
%
% Name/Value:
%   'Tests'  cellstr   load types to compare (default {'static','full_cmld'})
%   'values' vector    M values (default [2 4 6 8 12 16])
%   'Report' logical   print table + deltas + save figure (default true)
%   ...any other Name/Value is forwarded to sb_grid_testbench.sweep.
%
% Returns the combined results table S.

ip = inputParser; ip.KeepUnmatched = true;
ip.addParameter('Tests',  {'static','full_cmld'});
ip.addParameter('values', [2 4 6 8 12 16]);
ip.addParameter('Report', true);
ip.parse(varargin{:});
tests = cellstr(ip.Results.Tests);
vals  = ip.Results.values(:)';
fwd   = nv(ip.Unmatched);

paramPath = 'grid.M';
fprintf('=== presets.inertia ===  tests={%s}  %s=[%s]\n', ...
    strjoin(tests,','), paramPath, num2str(vals));

parts = cell(1, numel(tests));
for i = 1:numel(tests)
    base = sb_grid_sim.default_params(tests{i});
    parts{i} = sb_grid_testbench.sweep(base, paramPath, vals, fwd{:});
end
S = vertcat(parts{:});

if ip.Results.Report
    sb_grid_testbench.report(S, 'm', 'grid inertia constant  M', ...
        'Inertia sensitivity');
end
end

% ---------------------------------------------------------------------------
function c = nv(s)
c = reshape([fieldnames(s)'; struct2cell(s)'], 1, []);
end
