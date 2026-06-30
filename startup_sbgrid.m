function startup_sbgrid()
%STARTUP_SBGRID  Put sb_grid_lab on the MATLAB path and ensure output dirs exist.
%
%   Run once per session from anywhere:
%       run('<path-to>/sb_grid_lab/startup_sbgrid.m')
%   or  addpath('<path-to>/sb_grid_lab'); startup_sbgrid
%
% Adds the repo root (so the +sb_grid_sim and +sb_grid_testbench packages
% resolve), the user models/ folder, and the tests/ harness; creates the
% git-ignored results/ output dirs.

here = fileparts(mfilename('fullpath'));
addpath(here);                                   % packages resolve from the repo root
addpath(fullfile(here,'models'));                % user-authored .slx models
addpath(fullfile(here,'tests'));                 % regression harness

for d = {fullfile(here,'results'), fullfile(here,'results','raw')}
    if ~isfolder(d{1}), mkdir(d{1}); end
end

fprintf('sb_grid_lab on path (%s)\n  sim_version = %s\n', here, sb_grid_sim.version());
end
