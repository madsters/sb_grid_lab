function T = query_results(conn, filters)
%SB_GRID_TESTBENCH.DB.QUERY_RESULTS  Read results rows into a MATLAB table.
%
%   T = sb_grid_testbench.db.query_results(conn)            % all rows
%   T = sb_grid_testbench.db.query_results(conn, filters)   % filtered
%
% `filters` is an optional scalar struct mapping column names to required
% values, ANDed together. Text columns match by equality on the string; numeric
% columns match by exact equality. Recognized columns are the results-table
% columns (sim_version, param_hash, load_type, scr, m, dp_mw, ...). Unknown
% filter fields error out so typos are caught.
%
% Returns a MATLAB table of the matching rows (empty table if none). `conn` is
% an open built-in sqlite connection.

valid = {'id','sim_version','param_hash','load_type','scr','m','dist_dp','dp_mw', ...
         'dist_time','stop_time','settle_time','p_w','pfrq','rocof','nadir','dip', ...
         'settle','f0','vbase','t_nadir','trace_path','created_at'};
text_cols = {'sim_version','param_hash','load_type','trace_path','created_at'};

where = '';
if nargin >= 2 && ~isempty(filters)
    if ~isstruct(filters) || ~isscalar(filters)
        error('sb_grid_testbench:db:query_results:badFilters', ...
              'filters must be a scalar struct of column->value.');
    end
    fn = fieldnames(filters);
    if ~isempty(fn)                         % empty struct() -> no WHERE clause
        clauses = cell(1, numel(fn));
        for i = 1:numel(fn)
            c = fn{i};
            if ~any(strcmp(c, valid))
                error('sb_grid_testbench:db:query_results:unknownColumn', ...
                      'Unknown filter column "%s".', c);
            end
            v = filters.(c);
            if any(strcmp(c, text_cols)) || ischar(v) || isstring(v)
                clauses{i} = sprintf('%s = %s', c, sql_text(char(v)));
            else
                clauses{i} = sprintf('%s = %.17g', c, double(v));
            end
        end
        where = [' WHERE ' strjoin(clauses, ' AND ')];
    end
end

sql = ['SELECT * FROM results' where ' ORDER BY id'];
r = fetch(conn, sql);

if istable(r)
    T = r;
elseif isempty(r)
    T = cell2table(cell(0, numel(valid)), 'VariableNames', valid);
else
    T = cell2table(r, 'VariableNames', valid);
end
end

% -------------------------------------------------------------------------
function s = sql_text(v)
s = ['''' strrep(v, '''', '''''') ''''];
end
