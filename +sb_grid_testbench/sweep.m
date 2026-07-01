function T = sweep(base_params, axis_name, values, varargin)
%SB_GRID_TESTBENCH.SWEEP  Run a 1-D parameter sweep and collect the rows.
%
%   T = sb_grid_testbench.sweep(base_params, axis_name, values)
%   T = sb_grid_testbench.sweep(base_params, axis_name, values, 'Name',Value, ...)
%
% Expands `base_params` into one params struct per element of `values`, each
% with the DOTTED field `axis_name` overridden (e.g. 'grid.M', 'grid.SCR',
% 'disturbance.dist_dP_frac'), runs every point, and returns the combined table
% of DB rows.
%
% Name-Value options (forwarded to run_point where relevant):
%   'SimFcn'   function handle  sim engine (default @sb_grid_sim.simulate).
%   'DBFile'   char             results DB path (default results/results.db).
%   'RawDir'   char             trace dir (default <DBFile dir>/raw).
%   'Parallel' logical          true -> simulate points on parfor workers, but
%                               the ORCHESTRATOR (this process) is the SOLE DB
%                               writer. Default false.
%
% --- SINGLE-WRITER SEAM --------------------------------------------------
% SQLite tolerates only one writer at a time. The contract is: workers may
% SIMULATE and write their own trace .mat, but they NEVER touch the DB. The
% dedup-check + INSERT happen here, in the main loop, on the one connection this
% function owns. In serial mode that is trivially true. In Parallel mode we:
%   (1) split each point into a pure compute step `simulate_point` (hash, run,
%       save trace) that returns a row struct WITHOUT touching the DB, run those
%       on parfor;  (2) back in the main process, do the dedup-check + store for
%       each returned row sequentially on the single owned connection.
% If Parallel Computing Toolbox / a pool is unavailable, parfor degrades to a
% serial loop, which still honours the single-writer seam.

opt = parse_opts(varargin{:});

n = numel(values);
params_list = cell(1, n);
for i = 1:n
    params_list{i} = set_dotted(base_params, axis_name, value_at(values, i));
end

% one owned connection -- the SOLE DB writer for this sweep
conn = sb_grid_testbench.db.open_db(opt.DBFile);
cleanupConn = onCleanup(@() close(conn));                       %#ok<NASGU>

dbfile = resolve_dbfile(opt.DBFile);
if isempty(opt.RawDir)
    rawdir = fullfile(fileparts(dbfile), 'raw');
else
    rawdir = opt.RawDir;
end

sv = sb_grid_sim.version();
rows = cell(1, n);

if opt.Parallel
    % ---- compute on workers (NO DB access), then store in the main loop ----
    simfcn = opt.SimFcn;
    computed = cell(1, n);
    needs = false(1, n);

    % pre-check the cache HERE (main process) so workers only run new points
    cached_rows = cell(1, n);
    for i = 1:n
        h = sb_grid_testbench.param_hash(params_list{i});
        c = sb_grid_testbench.db.query_results(conn, ...
                struct('sim_version', sv, 'param_hash', h));
        if ~isempty(c) && height(c) >= 1
            cached_rows{i} = table2struct(c(1,:));
        else
            needs(i) = true;
        end
    end

    idx = find(needs);
    pl  = params_list(idx);
    tmp = cell(1, numel(idx));
    parfor j = 1:numel(idx)
        tmp{j} = simulate_point(pl{j}, simfcn, rawdir, sv);   %#ok<PFBNS>
    end
    for j = 1:numel(idx)
        computed{idx(j)} = tmp{j};
    end

    % single-writer store + assemble
    for i = 1:n
        if needs(i)
            sb_grid_testbench.db.store_result(conn, computed{i});   % only writer
            rows{i} = computed{i};
        else
            rows{i} = cached_rows{i};
        end
    end
else
    % ---- serial: run_point on the shared owned connection (single writer) --
    for i = 1:n
        rows{i} = sb_grid_testbench.run_point(params_list{i}, ...
            'SimFcn', opt.SimFcn, 'Conn', conn, 'RawDir', rawdir);
    end
end

T = rows_to_table(rows);
end

% =========================================================================
function row = simulate_point(params, simfcn, rawdir, sv)
%SIMULATE_POINT  Pure compute step for a worker: hash, simulate, save trace,
% build the row. Touches NO database. Mirrors run_point's row construction.
h = sb_grid_testbench.param_hash(params);

if ~isfolder(rawdir)
    try mkdir(rawdir); catch, end   % race-safe: workers may create concurrently
end
trace_path = fullfile(rawdir, [h '.mat']);

r = simfcn(params);
results = r;                                   %#ok<NASGU>
save(trace_path, 'results', '-v7.3');

m = r.metrics;
dist_dP = params.disturbance.dist_dP_frac * params.scale.P_W;
row = struct();
row.sim_version = sv;
row.param_hash  = h;
row.load_type   = char(params.load_type);
row.scr         = params.grid.SCR;
row.m           = params.grid.M;
row.dist_dp     = dist_dP;
row.dp_mw       = dist_dP / 1e6;
row.dist_time   = params.disturbance.dist_time;
row.stop_time   = params.solver.StopTime;
row.settle_time = params.solver.SettleTime;
row.p_w         = params.scale.P_W;
row.pfrq        = field_or(params, {'load','Pfrq'}, NaN);
row.rocof   = field_or(m, {'RoCoF'},   NaN);
row.nadir   = field_or(m, {'nadir'},   NaN);
row.dip     = field_or(m, {'dip'},     NaN);
row.settle  = field_or(m, {'settle'},  NaN);
row.f0      = field_or(m, {'f0'},      NaN);
row.vbase   = field_or(m, {'Vbase'},   NaN);
row.t_nadir = field_or(m, {'t_nadir'}, NaN);
row.trace_path = trace_path;
row.created_at = char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss'));
end

% -------------------------------------------------------------------------
function p = set_dotted(p, dotted, val)
%SET_DOTTED  Set a dotted field path (e.g. 'grid.M') in struct p.
parts = strsplit(dotted, '.');
p = setfield(p, parts{:}, val);   %#ok<SFLD>  -- variable-depth path
end

function v = value_at(values, i)
if iscell(values), v = values{i}; else, v = values(i); end
end

function v = field_or(s, path, dflt)
v = s;
for i = 1:numel(path)
    if isstruct(v) && isfield(v, path{i}), v = v.(path{i}); else, v = dflt; return; end
end
if isempty(v), v = dflt; end
end

function dbfile = resolve_dbfile(dbfile)
if isempty(dbfile)
    here = fileparts(fileparts(mfilename('fullpath')));   % .../sb_grid_lab
    dbfile = fullfile(here, 'results', 'results.db');
end
end

function T = rows_to_table(rows)
%ROWS_TO_TABLE  Combine row structs that may have DIFFERENT field sets.
% A cached row (from a dedup hit via the DB) carries the `id` column; a freshly
% built row does not. Align all rows onto the UNION of field names (missing ->
% [] / NaN) before assembling, preserving a stable column order.
rows = rows(~cellfun(@isempty, rows));
if isempty(rows)
    T = table();
    return
end

% preferred column order; any extras (e.g. 'id') appended in first-seen order
order = {'id','sim_version','param_hash','load_type','scr','m','dist_dp','dp_mw', ...
         'dist_time','stop_time','settle_time','p_w','pfrq','rocof','nadir','dip', ...
         'settle','f0','vbase','t_nadir','trace_path','created_at'};

allf = {};
for i = 1:numel(rows), allf = union(allf, fieldnames(rows{i}), 'stable'); end
cols = [intersect(order, allf, 'stable'), setdiff(allf, order, 'stable')];

n = numel(rows);
S(n) = struct();                                   %#ok<*AGROW>
for i = 1:n
    for k = 1:numel(cols)
        c = cols{k};
        if isfield(rows{i}, c)
            S(i).(c) = rows{i}.(c);
        else
            S(i).(c) = NaN;     % numeric-missing default; text cols always present
        end
    end
end
T = struct2table(S, 'AsArray', true);
end

% -------------------------------------------------------------------------
function opt = parse_opts(varargin)
opt = struct('SimFcn', @sb_grid_sim.simulate, 'DBFile', '', 'RawDir', '', 'Parallel', false);
if mod(numel(varargin), 2) ~= 0
    error('sb_grid_testbench:sweep:badArgs', 'Name-Value args must come in pairs.');
end
for i = 1:2:numel(varargin)
    name = validatestring(varargin{i}, {'SimFcn','DBFile','RawDir','Parallel'});
    opt.(name) = varargin{i+1};
end
end
