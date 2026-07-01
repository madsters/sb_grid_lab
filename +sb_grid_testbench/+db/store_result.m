function inserted = store_result(conn, row)
%SB_GRID_TESTBENCH.DB.STORE_RESULT  Dedup INSERT of one results row.
%
%   inserted = sb_grid_testbench.db.store_result(conn, row)
%
% Inserts ONE row into the results table using INSERT OR IGNORE, so a row whose
% (sim_version, param_hash) already exists is silently skipped (the UNIQUE
% constraint dedups). `row` is a scalar struct with the column fields (see
% contract 3 / sb_grid_testbench.run_point):
%
%   sim_version param_hash load_type
%   scr m dist_dp dp_mw dist_time stop_time settle_time p_w pfrq
%   rocof nadir dip settle f0 vbase t_nadir
%   trace_path created_at
%
% Returns true if a new row was inserted, false if it was a dedup hit. `conn` is
% an open built-in sqlite connection. This is the only write path to the table;
% in a parallel sweep ONLY the orchestrator calls it (single-writer rule).
%
% The built-in `sqlite` execute() does not bind `?` placeholders, so values are
% formatted into the SQL with strict per-type literal escaping (sql_literal).

text_cols = {'sim_version','param_hash','load_type','trace_path','created_at'};
num_cols  = {'scr','m','dist_dp','dp_mw','dist_time','stop_time','settle_time', ...
             'p_w','pfrq','rocof','nadir','dip','settle','f0','vbase','t_nadir'};
cols = [{'sim_version','param_hash','load_type'}, ...
        {'scr','m','dist_dp','dp_mw','dist_time','stop_time','settle_time','p_w','pfrq'}, ...
        {'rocof','nadir','dip','settle','f0','vbase','t_nadir'}, ...
        {'trace_path','created_at'}];

before = row_count(conn);

lits = cell(1, numel(cols));
for i = 1:numel(cols)
    c = cols{i};
    if ~isfield(row, c) || isempty(row.(c)) || (isnumeric(row.(c)) && ~isfinite(row.(c)))
        lits{i} = 'NULL';
    elseif any(strcmp(c, text_cols))
        lits{i} = sql_text(char(row.(c)));
    else  % numeric
        lits{i} = sql_num(double(row.(c)));
    end
end

sql = sprintf('INSERT OR IGNORE INTO results (%s) VALUES (%s)', ...
              strjoin(cols, ','), strjoin(lits, ','));
execute(conn, sql);

inserted = (row_count(conn) > before);
end

% -------------------------------------------------------------------------
function s = sql_text(v)
%SQL_TEXT  Single-quoted SQLite string literal (doubles embedded quotes).
s = ['''' strrep(v, '''', '''''') ''''];
end

function s = sql_num(x)
%SQL_NUM  Numeric literal at full double precision (NULL for non-finite).
if ~isfinite(x)
    s = 'NULL';
else
    s = sprintf('%.17g', x);
end
end

function n = row_count(conn)
r = fetch(conn, 'SELECT COUNT(*) AS n FROM results');
if istable(r)
    n = r.n(1);
elseif iscell(r)
    n = r{1,1};
else
    n = r(1);
end
end
