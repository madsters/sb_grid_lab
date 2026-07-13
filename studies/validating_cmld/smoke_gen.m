function smoke_gen()
%SMOKE_GEN  Run the generated model end-to-end through the engine (settle+step).
repo='C:\Users\mnea0003\dev\sb_grid_lab'; cd(repo); startup_sbgrid;
gen = fullfile(repo,'studies','validating_cmld','T2_fullcmld_generated.slx');
p = sb_grid_sim.default_params('full_cmld');
p.solver.SettleTime = 8; p.solver.StopTime = 6;   % short smoke
try
    r = sb_grid_sim.simulate(p, 'ModelPath', gen);
    m = r.metrics;
    fprintf('SMOKE_OK  baseHz=%.4f  RoCoF=%.4f Hz/s  dip=%.4f Hz  nadir=%.4f  Vterm=%.4f pu\n', ...
        r.meta.baseline_Hz, m.RoCoF, m.dip, m.nadir, m.Vbase);
catch ME
    fprintf('SMOKE_FAIL: %s\n', ME.message);
    for i=1:numel(ME.stack), fprintf('   at %s:%d\n', ME.stack(i).name, ME.stack(i).line); end
end
end
