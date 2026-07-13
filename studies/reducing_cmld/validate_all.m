function validate_all()
%VALIDATE_ALL  Run sb_grid_sim.validate_model on every reduction-study model.
% Prints one clear PASS/FAIL block per model; never saves a .slx.

repo = fileparts(fileparts(fileparts(mfilename('fullpath'))));
run(fullfile(repo,'startup_sbgrid.m'));
mdir = fullfile(repo,'studies','reducing_cmld','models');

% The single-equivalent-motor models read Motor_* vars that default_params does
% not set; supply them exactly as reduce_cmld does so validation reflects the
% real run path (the 3m models resolve their MotorA/B/C_* baseline themselves).
mv_ct = compose_1mot(0.8, 1.5, 0.5, 0);   % L1 constant-torque candidate
mv_vt = compose_1mot(0.8, 1.5, 0.5, 2);   % L1 variable-torque candidate

% model -> load_type, model_vars (empty = rely on the model's PreLoadFcn baseline)
models = {
    'static',        'static',    struct()
    'cmld_3m',       'full_cmld', struct()
    'cmld_3m_2x',    'full_cmld', struct()
    'cmld_1m_ct',    'full_cmld', mv_ct
    'cmld_1m_vt',    'full_cmld', mv_vt
    'cmld_3m_elec',  'full_cmld', struct()
    'cmld_3m_stat',  'full_cmld', struct()
};

fprintf('\n########## VALIDATE_ALL (reducing_cmld) ##########\n');
summary = {};
for i = 1:size(models,1)
    name = models{i,1}; lt = models{i,2}; mv = models{i,3};
    mp   = fullfile(mdir,[name '.slx']);
    fprintf('\n---------- %s.slx  (load_type=%s) ----------\n', name, lt);
    if ~isfile(mp)
        fprintf('  MISSING FILE\n'); summary(end+1,:) = {name,'MISSING',''}; continue; %#ok<AGROW>
    end
    try
        rep = sb_grid_sim.validate_model(lt, 'ModelPath', mp, 'ModelVars', mv);
        detail = strtrim(sprintf('sig=[%s] tags=[%s] err=[%s]', ...
            strjoin(rep.missing_signals,','), strjoin(rep.missing_tags,','), ...
            strjoin(rep.errors,' | ')));
        summary(end+1,:) = {name, ternary(rep.ok,'OK','FAIL'), detail}; %#ok<AGROW>
    catch ME
        fprintf('  EXCEPTION: %s\n', ME.message);
        summary(end+1,:) = {name,'EXCEPTION', ME.message}; %#ok<AGROW>
    end
    % close if we loaded it, to free memory between models
    if bdIsLoaded(name), close_system(name,0); end
end

fprintf('\n########## SUMMARY ##########\n');
for i = 1:size(summary,1)
    fprintf('  %-14s %-9s %s\n', summary{i,1}, summary{i,2}, summary{i,3});
end
fprintf('########## VALIDATE_ALL_DONE ##########\n');
end

function y = ternary(c,a,b), if c, y=a; else, y=b; end, end

% Mirror of reduce_cmld's compose_1mot (its composers are file-local). Values
% need only resolve the masks for a compile check; kept faithful for realism.
function mv = compose_1mot(phi, H, Rrscale, trqexp)
Pw = 2405e6;
frac=[0.152 0.166 0.129]; Stator={[0.02 0.072],[0.03 0.114],[0.03 0.114]};
Rotor={[0.05955 0.04937],[0.02810 0.07959],[0.02810 0.07959]}; Lm=[1.728 1.686 1.686];
LF=0.75; felec=0.337; fstat=0.216; fm=sum(frac);
Pmec=phi*(frac/fm)*Pw; S=Pmec/LF; w=S/sum(S);
Rs=w*cellfun(@(z)z(1),Stator)'; Lls=w*cellfun(@(z)z(2),Stator)';
Rr=(w*cellfun(@(z)z(1),Rotor)')*Rrscale; Llr=w*cellfun(@(z)z(2),Rotor)';
Lmq=w*Lm'; Pmec_eq=sum(Pmec); Pn=Pmec_eq/LF; s=LF*Rr; for it=1:8, s=(LF/(1-s))*Rr; end
mv=struct('Motor_Nom',[Pn 11000 50],'Motor_Stator',[Rs Lls],'Motor_Rotor',[Rr Llr], ...
    'Motor_Lm',Lmq,'Motor_Mech',[H 0 2],'Motor_Pmec',Pmec_eq,'Motor_Tm',LF/(1-s), ...
    'Motor_TrqExp',trqexp,'Motor_IC',[s 0 0 0 0 0 -120 120]);
Pnm=(1-phi)*Pw; e=felec/(felec+fstat);
mv.CMLD_ElecP=e*Pnm; mv.P0=(1-e)*Pnm; mv.Q0=0.20*mv.P0; mv.CapC=0.037092*(Pw/2405e6);
end
