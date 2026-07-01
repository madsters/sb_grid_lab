function S = disturbance(varargin)
%SB_GRID_TESTBENCH.PRESETS.DISTURBANCE  Sweep the load-step size, per load type.
%
%   S = sb_grid_testbench.presets.disturbance
%   S = sb_grid_testbench.presets.disturbance('Tests',{'static','full_cmld'})
%   S = sb_grid_testbench.presets.disturbance('values',[0.05 0.1 0.2 0.3 0.4 0.5])
%
% Sweeps the matched-fraction load step disturbance.dist_dP_frac (a fraction of
% the nominal P_W, identical across load types) and tabulates RoCoF / nadir dip /
% settle for each load model. For each requested load type it builds a base
% params via sb_grid_sim.default_params and calls sb_grid_testbench.sweep over
% 'disturbance.dist_dP_frac', then vertically concatenates the per-type result
% tables (contract-3 rows) and reports via sb_grid_testbench.report.
%
% Name/Value:
%   'Tests'  cellstr   load types to compare (default {'static','full_cmld'})
%   'values' vector    dist_dP_frac values (default [0.05 0.1 0.2 0.3 0.4 0.5])
%   'Report' logical   print table + deltas + save figure (default true)
%   ...any other Name/Value is forwarded to sb_grid_testbench.sweep
%       (e.g. 'DBFile','Conn','SimFcn','UseParallel').
%
% Returns the combined results table S.

ip = inputParser; ip.KeepUnmatched = true;
ip.addParameter('Tests',  {'static','full_cmld'});
ip.addParameter('values', [0.05 0.10 0.20 0.30 0.40 0.50]);
ip.addParameter('Report', true);
ip.parse(varargin{:});
tests  = cellstr(ip.Results.Tests);
vals   = ip.Results.values(:)';
fwd    = nv(ip.Unmatched);                          % extra args -> sweep

paramPath = 'disturbance.dist_dP_frac';
fprintf('=== presets.disturbance ===  tests={%s}  %s=[%s]\n', ...
    strjoin(tests,','), paramPath, num2str(vals));

parts = cell(1, numel(tests));
for i = 1:numel(tests)
    base = sb_grid_sim.default_params(tests{i});
    parts{i} = sb_grid_testbench.sweep(base, paramPath, vals, fwd{:});
end
S = vertcat(parts{:});

if ip.Results.Report
    sb_grid_testbench.report(S, 'dp_mw', 'disturbance \DeltaP (MW)', ...
        'Disturbance-size sensitivity');
end
end

% ---------------------------------------------------------------------------
function c = nv(s)
% struct -> flat Name/Value cell array (for forwarding ip.Unmatched).
c = reshape([fieldnames(s)'; struct2cell(s)'], 1, []);
end
