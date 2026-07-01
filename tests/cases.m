function C = cases()
%CASES  Canonical regression cases for the sb_grid_lab engine.
%
%   C = cases()
%
% Returns a struct array of small, fast regression cases. Each element has:
%   .name    a unique, stable case identifier (the key under which goldens
%            are stored, so DO NOT rename a case without re-seeding goldens)
%   .params  a contract-1 params struct: sb_grid_sim.default_params(load_type)
%            with a few field overrides
%
% These are the cases check_regression / update_goldens iterate over. They
% span the load types plus a couple of grid-axis points (M, SCR), and use
% MODERATE solver timing so the suite stays quick. Keep this list SMALL.
%
% NOTE on timing: SettleTime / StopTime are trimmed well below the engine
% defaults (40 s / 60 s). The regression guard only needs the metrics to be
% REPRODUCIBLE run-to-run for a given version, not physically settled, so
% short runs are fine and fast. If a real engine needs longer to produce
% stable metrics, lengthen these and re-seed the goldens.

C = struct('name', {}, 'params', {});

% --- 1. static load, all defaults ------------------------------------------
C(end+1) = mk('static_default', tweak('static'));

% --- 2. full CMLD, all defaults --------------------------------------------
C(end+1) = mk('full_cmld_default', tweak('full_cmld'));

% --- 3. full CMLD, higher swing inertia (grid.M = 4) -----------------------
%   (an axis point off the default M = 8)
C(end+1) = mk('full_cmld_M4', tweak('full_cmld', {'grid','M'}, 4));

% --- 4. static load, weaker grid (grid.SCR = 5) ----------------------------
%   (an axis point off the default SCR = 10)
C(end+1) = mk('static_scr5', tweak('static', {'grid','SCR'}, 5));

end

% ---------------------------------------------------------------------------
function s = mk(name, params)
s = struct('name', name, 'params', params);
end

% ---------------------------------------------------------------------------
function p = tweak(load_type, varargin)
%TWEAK  default_params(load_type) with moderate timing + optional overrides.
%
%   tweak('static')                       -> trimmed defaults
%   tweak('full_cmld', {'grid','M'}, 4)   -> ... with p.grid.M = 4
%
% Override args come in (path, value) pairs, where path is a cellstr of the
% nested field names, e.g. {'grid','M'}.
p = sb_grid_sim.default_params(load_type);

% moderate timing so the suite is quick (engine defaults are 40/60 s)
p.solver.SettleTime = 5;
p.solver.StopTime   = 8;
p.disturbance.dist_time = 2;     % step 2 s into the post-settle run

for k = 1:2:numel(varargin)
    path = varargin{k};
    val  = varargin{k+1};
    p    = setfield(p, path{:}, val);     %#ok<SFLD> nested set by path
end
end
