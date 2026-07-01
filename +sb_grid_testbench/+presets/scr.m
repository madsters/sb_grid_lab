function S = scr(varargin)
%SB_GRID_TESTBENCH.PRESETS.SCR  Sweep grid strength (SCR), per load type.
%
%   S = sb_grid_testbench.presets.scr
%   S = sb_grid_testbench.presets.scr('Tests',{'static','full_cmld'})
%   S = sb_grid_testbench.presets.scr('values',[2 3 5 8 10])
%
% Sweeps the grid short-circuit ratio grid.SCR at a fixed disturbance and
% tabulates baseline Vterm / RoCoF / nadir dip / settle for each load model.
% Unlike the disturbance and inertia sweeps the operating point DEPENDS on SCR
% (grid strength sets terminal voltage -> load draw -> motor operating point);
% at very weak SCR a CMLD point may fail to settle. For each requested load type
% it builds a base params via sb_grid_sim.default_params and calls
% sb_grid_testbench.sweep over 'grid.SCR', then concatenates and reports
% (the report shows the vbase column when present).
%
% Name/Value:
%   'Tests'  cellstr   load types to compare (default {'static','full_cmld'})
%   'values' vector    SCR values (default [2 3 5 8 10])
%   'Report' logical   print table + deltas + save figure (default true)
%   ...any other Name/Value is forwarded to sb_grid_testbench.sweep.
%
% Returns the combined results table S.

ip = inputParser; ip.KeepUnmatched = true;
ip.addParameter('Tests',  {'static','full_cmld'});
ip.addParameter('values', [2 3 5 8 10]);
ip.addParameter('Report', true);
ip.parse(varargin{:});
tests = cellstr(ip.Results.Tests);
vals  = ip.Results.values(:)';
fwd   = nv(ip.Unmatched);

paramPath = 'grid.SCR';
fprintf('=== presets.scr ===  tests={%s}  %s=[%s]\n', ...
    strjoin(tests,','), paramPath, num2str(vals));

parts = cell(1, numel(tests));
for i = 1:numel(tests)
    base = sb_grid_sim.default_params(tests{i});
    parts{i} = sb_grid_testbench.sweep(base, paramPath, vals, fwd{:});
end
S = vertcat(parts{:});

if ip.Results.Report
    sb_grid_testbench.report(S, 'scr', 'grid short-circuit ratio  SCR', ...
        'Grid-strength sensitivity');
end
end

% ---------------------------------------------------------------------------
function c = nv(s)
c = reshape([fieldnames(s)'; struct2cell(s)'], 1, []);
end
