function [ok, details] = check_regression(varargin)
%CHECK_REGRESSION  Guard that tells you when sb_grid_sim.version() must bump.
%
%   [ok, details] = check_regression()
%   [ok, details] = check_regression('SimFcn', fh, 'GoldensDir', dir, ...)
%
% Runs the canonical regression cases (tests/cases.m), extracts the
% contract-2 .metrics from each result, and compares them to the stored
% golden for the CURRENT sb_grid_sim.version(). If the metrics still match
% the golden, the engine behaviour is unchanged for this version (PASS). If
% they drift, that is your signal to bump version.m and re-seed the goldens.
%
% Options (name/value):
%   'SimFcn'      function handle  params -> contract-2 results struct.
%                 Default @sb_grid_sim.simulate. Pass a stub for testing.
%   'GoldensDir'  folder holding golden_<version>.mat.
%                 Default tests/goldens (next to this file).
%   'AbsTol'      absolute tolerance per metric. Default 1e-3.
%   'RelTol'      relative tolerance per metric. Default 1e-3.
%   'Metrics'     cellstr of metric fields to compare.
%                 Default {'RoCoF','nadir','dip','settle'}.
%   'Verbose'     print a summary (default true).
%
% A metric matches if  |g - a| <= AbsTol  OR  |g - a| <= RelTol*|g|.
%
% Returns:
%   ok       logical: true iff every case PASSed (no FAIL, no NEEDS GOLDEN).
%   details  struct array, one per case, with fields:
%              name, status ('PASS'|'FAIL'|'NEEDS GOLDEN'|'ERROR'),
%              metrics (struct of golden/actual/abs_err/rel_err/pass per
%              metric), message.

opt = parse_opts(varargin{:});
ver = sb_grid_sim.version();
C   = cases();
n   = numel(C);

% ---- load the golden bundle for the current version ----------------------
gfile  = fullfile(opt.GoldensDir, sprintf('golden_%s.mat', ver));
golden = [];
if isfile(gfile)
    S = load(gfile);
    if isfield(S, 'golden'), golden = S.golden; end
end
have_golden = ~isempty(golden);

details = repmat(struct('name','', 'status','', 'metrics',struct(), ...
                        'message',''), n, 1);
ok = true;

for i = 1:n
    name = C(i).name;
    details(i).name = name;

    % run the sim
    try
        r = opt.SimFcn(C(i).params);
        a = r.metrics;
    catch err
        details(i).status  = 'ERROR';
        details(i).message = sprintf('sim/extract failed: %s', err.message);
        ok = false;
        continue;
    end

    % no golden at all -> NEEDS GOLDEN
    if ~have_golden || ~isfield(golden, sanitize(name))
        details(i).status  = 'NEEDS GOLDEN';
        details(i).message = sprintf('no golden for case "%s" at v%s', name, ver);
        ok = false;
        continue;
    end

    g = golden.(sanitize(name)).metrics;

    % compare each requested metric
    mres = struct();
    all_pass = true;
    fail_fields = {};
    for k = 1:numel(opt.Metrics)
        f = opt.Metrics{k};
        if ~isfield(g, f) || ~isfield(a, f)
            mres.(f) = mk_metric(NaN, NaN, false);
            all_pass = false;
            fail_fields{end+1} = f; %#ok<AGROW>
            continue;
        end
        gv = double(g.(f));
        av = double(a.(f));
        abserr = abs(gv - av);
        relerr = abserr / max(abs(gv), realmin);
        pass = (abserr <= opt.AbsTol) || (abserr <= opt.RelTol * abs(gv));
        mr = mk_metric(gv, av, pass);
        mr.abs_err = abserr; mr.rel_err = relerr;
        mres.(f) = mr;
        if ~pass
            all_pass = false;
            fail_fields{end+1} = f; %#ok<AGROW>
        end
    end

    details(i).metrics = mres;
    if all_pass
        details(i).status  = 'PASS';
        details(i).message = '';
    else
        details(i).status  = 'FAIL';
        details(i).message = sprintf('metric drift: %s', strjoin(fail_fields, ', '));
        ok = false;
    end
end

if opt.Verbose
    print_summary(ver, gfile, have_golden, details, opt);
end
end

% =========================================================================
function mr = mk_metric(golden, actual, pass)
mr = struct('golden',golden, 'actual',actual, ...
            'abs_err',abs(golden-actual), 'rel_err',NaN, 'pass',logical(pass));
end

% -------------------------------------------------------------------------
function print_summary(ver, gfile, have_golden, details, opt)
fprintf('\n== check_regression (sim_version = %s) ==\n', ver);
if have_golden
    fprintf('   golden: %s\n', gfile);
else
    fprintf('   golden: (none for v%s) -> %s\n', ver, gfile);
end
fprintf('   tol: abs %.3g | rel %.3g | metrics: %s\n', ...
        opt.AbsTol, opt.RelTol, strjoin(opt.Metrics, ', '));
fprintf('   %-22s %-13s %s\n', 'case', 'status', 'detail');
fprintf('   %s\n', repmat('-',1,64));
nfail = 0;
for i = 1:numel(details)
    d = details(i);
    fprintf('   %-22s %-13s %s\n', d.name, d.status, d.message);
    if ~strcmp(d.status,'PASS'), nfail = nfail + 1; end
    % on FAIL, show the offending metrics
    if strcmp(d.status,'FAIL')
        fn = fieldnames(d.metrics);
        for k = 1:numel(fn)
            mr = d.metrics.(fn{k});
            if ~mr.pass
                fprintf('       %-10s golden=% .6g  actual=% .6g  |abs=%.3g rel=%.3g|\n', ...
                    fn{k}, mr.golden, mr.actual, mr.abs_err, mr.rel_err);
            end
        end
    end
end
fprintf('   %s\n', repmat('-',1,64));
if nfail == 0
    fprintf('   ALL PASS (%d cases) -- engine matches v%s golden.\n\n', numel(details), ver);
else
    fprintf('   %d of %d case(s) not PASS -- see above.\n', nfail, numel(details));
    if any(strcmp({details.status}, 'FAIL'))
        fprintf('   If the change was intended: bump sb_grid_sim/version.m, then run update_goldens.\n');
    end
    if any(strcmp({details.status}, 'NEEDS GOLDEN'))
        fprintf('   NEEDS GOLDEN: run update_goldens to seed golden_%s.mat.\n', ver);
    end
    fprintf('\n');
end
end

% -------------------------------------------------------------------------
function opt = parse_opts(varargin)
opt = struct( ...
    'SimFcn',     @sb_grid_sim.simulate, ...
    'GoldensDir', default_goldens_dir(), ...
    'AbsTol',     1e-3, ...
    'RelTol',     1e-3, ...
    'Metrics',    {{'RoCoF','nadir','dip','settle'}}, ...
    'Verbose',    true);
for k = 1:2:numel(varargin)
    key = validatestring(varargin{k}, fieldnames(opt), mfilename, '', k);
    opt.(key) = varargin{k+1};
end
if ischar(opt.Metrics) || isstring(opt.Metrics)
    opt.Metrics = cellstr(opt.Metrics);
end
end

% -------------------------------------------------------------------------
function d = default_goldens_dir()
d = fullfile(fileparts(mfilename('fullpath')), 'goldens');
end

% -------------------------------------------------------------------------
function s = sanitize(name)
%SANITIZE  Turn a case name into a valid struct field name (stable mapping).
s = matlab.lang.makeValidName(char(name));
end
