function out = load_types(load_type)
%SB_GRID_SIM.LOAD_TYPES  Registry mapping a load type to a model file name.
%
%   names = sb_grid_sim.load_types()            % cell array of known load types
%   name  = sb_grid_sim.load_types('static')    % model name (no extension) to load
%
% EDIT THIS as you author models: map each load type to the base name of your
% hand-authored .slx in models/ (resolved on the path by sb_grid_sim.simulate).
% The engine never builds these — you do.
%
% The four study load types (mirroring the legacy T1-T4):
%   static       - constant-PQ static load            (legacy T1)
%   full_cmld    - full CMLD, 3 motors                 (legacy T2)
%   reduced_cmld - reduced CMLD, 2 motors              (legacy T3)
%   tx_direct    - motors/load direct to tx bus        (legacy T4)

reg = struct( ...
    'static',       'T1_static', ...      % hand-authored model in models/
    'full_cmld',    'T2_fullcmld', ...    % hand-authored model in models/
    'reduced_cmld', 'reduced_cmld', ...   % not yet authored
    'tx_direct',    'tx_direct');         % not yet authored

if nargin == 0
    out = fieldnames(reg);
    return;
end

lt = char(load_type);
assert(isfield(reg, lt), 'sb_grid_sim:unknownLoadType', ...
    'unknown load_type "%s" (known: %s)', lt, strjoin(fieldnames(reg), ', '));
out = reg.(lt);
end
