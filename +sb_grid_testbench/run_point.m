function row = run_point(params, varargin)
%SB_GRID_TESTBENCH.RUN_POINT  Run (or fetch cached) one sim point and store it.
%
%   row = sb_grid_testbench.run_point(params)
%   row = sb_grid_testbench.run_point(params, 'Name',Value, ...)
%
% Computes the canonical param_hash, opens the results DB, and:
%   * if (sim_version, hash) is ALREADY stored -> returns the cached row, runs
%     NO simulation (dedup hit).
%   * otherwise -> runs the sim, saves the full results struct to
%     results/raw/<hash>.mat, builds the DB row, stores it (INSERT OR IGNORE),
%     and returns it.
%
% Name-Value options:
%   'SimFcn'   function handle  sim engine (default @sb_grid_sim.simulate).
%                               Override with a stub for testing.
%   'DBFile'   char             results DB path (default: built-in results/results.db).
%   'RawDir'   char             trace .mat dir   (default: <DBFile dir>/raw).
%   'Conn'     sqlite           reuse an already-open connection (sweep uses this
%                               so the orchestrator is the single DB writer).
%
% Returns the DB row as a scalar struct (the columns of contract 3). dp_mw =
% dist_dp / 1e6.

opt = parse_opts(varargin{:});

h = sb_grid_testbench.param_hash(params);
sv = sb_grid_sim.version();

% -- connection (own one unless the caller passed a shared one) -----------
own_conn = isempty(opt.Conn);
if own_conn
    conn = sb_grid_testbench.db.open_db(opt.DBFile);
    cleanupConn = onCleanup(@() close(conn));
else
    conn = opt.Conn;
end

% resolve where the DB file lives so raw/ sits beside it
if isempty(opt.RawDir)
    dbfile = db_path(opt.DBFile);
    rawdir = fullfile(fileparts(dbfile), 'raw');
else
    rawdir = opt.RawDir;
end

% -- dedup check ----------------------------------------------------------
cached = sb_grid_testbench.db.query_results(conn, ...
            struct('sim_version', sv, 'param_hash', h));
if ~isempty(cached) && height(cached) >= 1
    row = table2struct(cached(1,:));
    return
end

% -- not cached: simulate -------------------------------------------------
r = opt.SimFcn(params);

if ~isfolder(rawdir), mkdir(rawdir); end
trace_path = fullfile(rawdir, [h '.mat']);
results = r;                           %#ok<NASGU>  saved under a stable name
save(trace_path, 'results', '-v7.3');

row = build_row(params, r, h, sv, trace_path);
sb_grid_testbench.db.store_result(conn, row);
end

% =========================================================================
function row = build_row(params, r, h, sv, trace_path)
%BUILD_ROW  Map params + metrics to the contract-3 DB columns.
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
row.pfrq        = getfield_default(params, {'load','Pfrq'}, NaN);

row.rocof   = getfield_default(m, {'RoCoF'},   NaN);
row.nadir   = getfield_default(m, {'nadir'},   NaN);
row.dip     = getfield_default(m, {'dip'},     NaN);
row.settle  = getfield_default(m, {'settle'},  NaN);
row.f0      = getfield_default(m, {'f0'},      NaN);
row.vbase   = getfield_default(m, {'Vbase'},   NaN);
row.t_nadir = getfield_default(m, {'t_nadir'}, NaN);

row.trace_path = trace_path;
row.created_at = char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss'));
end

% -------------------------------------------------------------------------
function v = getfield_default(s, path, dflt)
v = s;
for i = 1:numel(path)
    if isstruct(v) && isfield(v, path{i})
        v = v.(path{i});
    else
        v = dflt; return
    end
end
if isempty(v), v = dflt; end
end

% -------------------------------------------------------------------------
function p = db_path(dbfile)
if ~isempty(dbfile)
    p = dbfile;
else
    % default DB path mirrors open_db's default
    here = fileparts(fileparts(mfilename('fullpath')));   % .../sb_grid_lab
    p = fullfile(here, 'results', 'results.db');
end
end

% -------------------------------------------------------------------------
function opt = parse_opts(varargin)
opt = struct('SimFcn', @sb_grid_sim.simulate, 'DBFile', '', 'RawDir', '', 'Conn', []);
if mod(numel(varargin), 2) ~= 0
    error('sb_grid_testbench:run_point:badArgs', 'Name-Value args must come in pairs.');
end
for i = 1:2:numel(varargin)
    name = validatestring(varargin{i}, {'SimFcn','DBFile','RawDir','Conn'});
    opt.(name) = varargin{i+1};
end
end
