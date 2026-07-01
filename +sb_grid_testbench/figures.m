function varargout = figures(action, varargin)
%SB_GRID_TESTBENCH.FIGURES  Shared plotting helpers for the analysis layer.
%
% A small dispatch of plotting utilities so report/compare share one consistent
% palette and one save path. Call by action name:
%
%   c   = sb_grid_testbench.figures('color', load_type)
%         Stable RGB triplet for a load type ('static','full_cmld',
%         'reduced_cmld','tx_direct'); unknown types get a deterministic colour.
%
%   lab = sb_grid_testbench.figures('label', load_type)
%         Human-readable legend label for a load type (e.g. 'full CMLD').
%
%   out = sb_grid_testbench.figures('save', fig, name)
%         Save fig to results/fig/<name>.png (mkdir -p), via exportgraphics at
%         150 dpi, then close(fig). Returns the absolute path written. <name>
%         may include a .png extension or not.
%
%   d   = sb_grid_testbench.figures('figdir')
%         The results/fig directory (created if missing).
%
%   f   = sb_grid_testbench.figures('newfig', name, position)
%         A new off-screen ('Visible','off') white figure; position optional.
%
% All figures are created with 'Visible','off' so headless -batch runs never
% pop a window. Saving always routes through results/fig/ (git-ignored).

switch lower(char(action))
    case 'color'
        varargout{1} = local_color(varargin{:});
    case 'label'
        varargout{1} = local_label(varargin{:});
    case 'figdir'
        varargout{1} = local_figdir();
    case 'save'
        varargout{1} = local_save(varargin{:});
    case 'newfig'
        varargout{1} = local_newfig(varargin{:});
    otherwise
        error('sb_grid_testbench:figures:unknownAction', ...
            'unknown action "%s" (color|label|figdir|save|newfig)', char(action));
end
end

% ---------------------------------------------------------------------------
function c = local_color(load_type)
% Consistent per-load-type colour. Keys match sb_grid_sim.load_types plus the
% legacy T1-T4 aliases so ported tables/structs still resolve.
lt = char(load_type);
pal = struct( ...
    'static',       [0.20 0.40 0.85], ...   % blue
    'full_cmld',    [0.85 0.25 0.20], ...   % red
    'reduced_cmld', [0.20 0.60 0.30], ...   % green
    'tx_direct',    [0.50 0.30 0.70], ...   % purple
    'T1',           [0.20 0.40 0.85], ...
    'T2',           [0.85 0.25 0.20], ...
    'T3',           [0.20 0.60 0.30], ...
    'T4',           [0.50 0.30 0.70]);
key = matlab.lang.makeValidName(lt);
if isfield(pal, key)
    c = pal.(key);
else
    % Deterministic fallback colour from the name's hash, kept mid-saturation.
    h = mod(sum(double(lt)) * 2654435761, 2^32) / 2^32;
    c = hsv2rgb([h, 0.6, 0.75]);
end
end

% ---------------------------------------------------------------------------
function lab = local_label(load_type)
lt = char(load_type);
map = struct( ...
    'static',       'static', ...
    'full_cmld',    'full CMLD', ...
    'reduced_cmld', 'reduced CMLD', ...
    'tx_direct',    'tx-direct', ...
    'T1',           'static', ...
    'T2',           'full CMLD', ...
    'T3',           'reduced CMLD', ...
    'T4',           'tx-direct');
key = matlab.lang.makeValidName(lt);
if isfield(map, key), lab = map.(key); else, lab = lt; end
end

% ---------------------------------------------------------------------------
function d = local_figdir()
% results/fig under the package root (parent of +sb_grid_testbench).
pkgdir = fileparts(mfilename('fullpath'));        % .../+sb_grid_testbench
root   = fileparts(pkgdir);                        % .../sb_grid_lab
d = fullfile(root, 'results', 'fig');
if ~isfolder(d), mkdir(d); end
end

% ---------------------------------------------------------------------------
function out = local_save(fig, name)
d = local_figdir();
[~, base, ext] = fileparts(char(name));
if isempty(ext), ext = '.png'; end
out = fullfile(d, [base ext]);
try
    exportgraphics(fig, out, 'Resolution', 150);
catch
    saveas(fig, out);                              % fallback for old releases
end
close(fig);
fprintf('wrote %s\n', out);
end

% ---------------------------------------------------------------------------
function f = local_newfig(name, position)
if nargin < 1 || isempty(name), name = ''; end
if nargin < 2 || isempty(position), position = [100 100 1000 360]; end
f = figure('Color','w', 'Position',position, 'Visible','off', 'Name',char(name));
end
