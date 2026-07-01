function golden = update_goldens(varargin)
%UPDATE_GOLDENS  (Re)seed the golden metrics for the CURRENT sim_version.
%
%   update_goldens()
%   update_goldens('SimFcn', fh, 'GoldensDir', dir)
%   golden = update_goldens(...)
%
% Runs every canonical case (tests/cases.m) through the sim function, then
% SAVES each case's contract-2 .metrics -- keyed by case name, alongside the
% params it was run with and the sim_version -- into
%
%       <GoldensDir>/golden_<version>.mat
%
% This creates or OVERWRITES only the current version's golden file; goldens
% for other versions are never touched. Run this after you have deliberately
% bumped sb_grid_sim/version.m (so check_regression has a reference for the
% new version), or to establish goldens for the very first time.
%
% Options (name/value):
%   'SimFcn'      function handle params -> contract-2 results struct.
%                 Default @sb_grid_sim.simulate. Pass a stub for testing.
%   'GoldensDir'  output folder. Default tests/goldens (next to this file).
%   'Verbose'     print progress (default true).
%
% Returns (optional) the saved `golden` struct:
%   golden.sim_version           the version tag
%   golden.created_at            ISO-8601 timestamp
%   golden.(case).name           original case name
%   golden.(case).params         params struct used
%   golden.(case).metrics        the saved contract-2 metrics
%   golden.(case).param_hash     dedup hash of the params (if available)

opt = parse_opts(varargin{:});
ver = sb_grid_sim.version();
C   = cases();

if ~isfolder(opt.GoldensDir), mkdir(opt.GoldensDir); end

golden = struct();
golden.sim_version = ver;
golden.created_at  = char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss'));

if opt.Verbose
    fprintf('\n== update_goldens (sim_version = %s) ==\n', ver);
end

for i = 1:numel(C)
    name = C(i).name;
    r    = opt.SimFcn(C(i).params);
    entry = struct();
    entry.name    = name;
    entry.params  = C(i).params;
    entry.metrics = r.metrics;
    entry.param_hash = try_hash(C(i).params);
    golden.(sanitize(name)) = entry;
    if opt.Verbose
        fprintf('   recorded %-22s RoCoF=% .6g nadir=% .6g dip=% .6g settle=% .6g\n', ...
            name, gm(r.metrics,'RoCoF'), gm(r.metrics,'nadir'), ...
            gm(r.metrics,'dip'), gm(r.metrics,'settle'));
    end
end

gfile = fullfile(opt.GoldensDir, sprintf('golden_%s.mat', ver));
save(gfile, 'golden', '-v7.3');

if opt.Verbose
    fprintf('   saved %d case(s) -> %s\n\n', numel(C), gfile);
end
if nargout == 0, clear golden; end
end

% =========================================================================
function v = gm(m, f)
if isfield(m, f), v = double(m.(f)); else, v = NaN; end
end

% -------------------------------------------------------------------------
function h = try_hash(params)
try
    h = sb_grid_testbench.param_hash(params);
catch
    h = '';      % testbench package may not be on path during isolated tests
end
end

% -------------------------------------------------------------------------
function opt = parse_opts(varargin)
opt = struct( ...
    'SimFcn',     @sb_grid_sim.simulate, ...
    'GoldensDir', default_goldens_dir(), ...
    'Verbose',    true);
for k = 1:2:numel(varargin)
    key = validatestring(varargin{k}, fieldnames(opt), mfilename, '', k);
    opt.(key) = varargin{k+1};
end
end

% -------------------------------------------------------------------------
function d = default_goldens_dir()
d = fullfile(fileparts(mfilename('fullpath')), 'goldens');
end

% -------------------------------------------------------------------------
function s = sanitize(name)
%SANITIZE  Turn a case name into a valid struct field name (stable mapping).
% MUST match check_regression's sanitize so keys line up.
s = matlab.lang.makeValidName(char(name));
end
