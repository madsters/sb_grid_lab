function conn = open_db(dbfile)
%SB_GRID_TESTBENCH.DB.OPEN_DB  Open (creating if needed) the results SQLite DB.
%
%   conn = sb_grid_testbench.db.open_db()         % default results/results.db
%   conn = sb_grid_testbench.db.open_db(dbfile)   % explicit path (e.g. a temp DB)
%
% Uses the built-in `sqlite` interface (MATLAB R2025b -- no Database Toolbox).
% Creates the file and its folder if missing, ensures the schema, and sets
% PRAGMAs for resilience under concurrent access:
%   journal_mode = WAL   (readers don't block the single writer)
%   busy_timeout = 5000  (ms; wait out a transient lock rather than erroring)
%
% Returns the open connection. Caller closes it with close(conn).
%
% Note on the single-writer rule (contract 3): WAL + busy_timeout make the DB
% resilient, but the orchestrator is still the SOLE writer in a parallel sweep.

if nargin < 1 || isempty(dbfile)
    here   = fileparts(fileparts(fileparts(mfilename('fullpath'))));  % .../sb_grid_lab
    dbfile = fullfile(here, 'results', 'results.db');
end

folder = fileparts(dbfile);
if ~isempty(folder) && ~isfolder(folder)
    mkdir(folder);
end

% built-in sqlite: opens existing or creates a new file when 'create' is set.
if isfile(dbfile)
    conn = sqlite(dbfile, 'connect');
else
    conn = sqlite(dbfile, 'create');
end

% Resilience PRAGMAs.
%   busy_timeout: per-connection, makes a writer wait out a transient lock
%                 rather than erroring immediately. Safe to set anytime.
%   journal_mode=WAL: would let readers not block the writer, BUT MATLAB's
%                 built-in `sqlite` object holds an implicit transaction for the
%                 connection's lifetime (it COMMITs on close), and SQLite forbids
%                 changing journal_mode inside a transaction. So WAL is NOT
%                 settable through this object; we rely instead on busy_timeout +
%                 the single-writer sweep design (the orchestrator is the only
%                 process that writes -- see sb_grid_testbench.sweep) for
%                 concurrency safety. Setting WAL once out-of-band (sqlite3 CLI)
%                 would persist in the header, but is not required here.
execute(conn, 'PRAGMA busy_timeout=5000');

% ensure the table exists
sb_grid_testbench.db.schema(conn);
end
