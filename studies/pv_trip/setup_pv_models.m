function setup_pv_models()
%SETUP_PV_MODELS  Phase-2 prep: register "no custom libraries" gate config and
% create the study-local model copies pv_cmld.slx / pv_static.slx (Save-As
% semantics: internal block-diagram name renamed to match the filename, so the
% engine resolves <name>.slx <-> system name <name>). Copies only -- the
% reducing_cmld source models are never touched. Run once before building the
% PV-trip subsystem.
projectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % sb_grid_lab

% --- gate: declare no custom Simulink block libraries (built-ins only) --------
akit = '/Users/madeleineneaves/.matlab/agentic-toolkits/simulink/tools/model_edit';
if isfolder(akit), addpath(akit); end
try
    library.LibraryConfig.save(projectRoot, [], struct('confirmedNone', true));
    fprintf('gate: .satk/reuse-libraries.json saved (confirmedNone=true)\n');
catch e
    fprintf('gate save FAILED (%s) -- continuing; model_edit gate is advisory\n', e.message);
end

% --- study-local copies with internal rename ---------------------------------
src = fullfile(projectRoot,'studies','reducing_cmld','models');
dst = fullfile(projectRoot,'studies','pv_trip','models');
pairs = {'cmld_3m','pv_cmld'; 'true_static','pv_static'};
for i = 1:size(pairs,1)
    s = pairs{i,1}; d = pairs{i,2};
    if bdIsLoaded(s), close_system(s,0); end
    load_system(fullfile(src,[s '.slx']));
    save_system(s, fullfile(dst,[d '.slx']));    % save copy under the new name
    close_system(s,0);
    load_system(fullfile(dst,[d '.slx']));       % reopen to verify the rename
    fprintf('%-12s -> %-10s : bdroot = %s\n', s, d, bdroot);
    close_system(d,0);
end
fprintf('SETUP_PV_MODELS_DONE\n');
end
