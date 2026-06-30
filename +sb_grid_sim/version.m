function v = version()
%SB_GRID_SIM.VERSION  Manual engine version tag (MAJOR.MINOR.PATCH).
%
% Every result stored by +sb_grid_testbench is tagged with this string, so a
% change here defines a NEW class of results (old rows are retained).
%
% Bump DELIBERATELY when engine behaviour changes. You do not have to guess
% when: `tests.check_regression` runs the canonical cases and FAILS if the
% metrics drift from the goldens for the current version — that's your signal
% to bump here and then run `tests.update_goldens`.
v = '1.0.0';
end
