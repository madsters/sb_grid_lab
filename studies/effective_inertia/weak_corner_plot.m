function weak_corner_plot(dp)
%WEAK_CORNER_PLOT  Re-draw the weak-corner 3-panel from saved traces (no re-sim).
%
%   weak_corner_plot(0.30)
%
% Panel 1 frequency (Hz, fixed 49-51; traces run off if beyond). Panels 2 & 3 in
% pu (/P_W) on a SHARED y-scale: load active power and accelerating power
% (P_gen,ref - P_elec)/P_W. Reads weak_raw/weak_dp<..>.mat (from weak_corner).
scdir=fileparts(mfilename('fullpath')); repo=fileparts(fileparts(scdir));
addpath(scdir); Pw=2405e6;
Sd=load(fullfile(scdir,'weak_raw',sprintf('weak_dp%02.0f.mat',100*abs(dp)))); tr=Sd.tr;
ord={'static','A0','HB25','JMAX'}; co=lines(3);
allv=[];
for i=1:numel(tr)
  x=tr{i}; if ~isfield(x,'P'), continue; end
  sel=(x.t-x.td)>=-0.5 & (x.t-x.td)<=8;
  acc=x.Pref-(x.P+x.Pdist*(x.t>=x.td));
  allv=[allv; x.P(sel)/Pw; acc(sel)/Pw]; %#ok<AGROW>
end
lo=min(allv); hi=max(allv); pad=0.05*(hi-lo); yl=[lo-pad hi+pad];
fig=figure('Visible','off','Color','w','Position',[100 100 950 900]);
tl=tiledlayout(fig,3,1,'TileSpacing','compact','Padding','compact');
ax1=nexttile(tl); hold(ax1,'on'); grid(ax1,'on');
ax2=nexttile(tl); hold(ax2,'on'); grid(ax2,'on');
ax3=nexttile(tl); hold(ax3,'on'); grid(ax3,'on');
ci=0;
for k=1:numel(ord)
  i=find(cellfun(@(x)strcmp(x.id,ord{k}),tr),1); if isempty(i), continue; end
  x=tr{i}; t=x.t-x.td;
  if strcmp(x.id,'static'), c=[0 0 0]; sty='--'; lw=1.3; nm='static (grid only)';
  else, ci=ci+1; c=co(ci,:); sty='-'; lw=1.6; nm=sprintf('%s (H_{load}=%.2f)',x.id,x.H_load); end
  acc=x.Pref-(x.P+x.Pdist*(x.t>=x.td));
  plot(ax1,t,x.f,sty,'Color',c,'LineWidth',lw,'DisplayName',nm);
  plot(ax2,t,x.P/Pw,sty,'Color',c,'LineWidth',lw);
  plot(ax3,t,acc/Pw,sty,'Color',c,'LineWidth',lw);
end
xline(ax1,0,':','disturbance','HandleVisibility','off'); xline(ax2,0,':'); xline(ax3,0,':');
ylim(ax1,[49 51]); ylabel(ax1,'frequency (Hz)');
ylim(ax2,yl); ylabel(ax2,'load active power (pu)');
ylim(ax3,yl); ylabel(ax3,'accel. power  (P_{gen,ref}-P_{elec})/P_W  (pu)'); xlabel(ax3,'time since disturbance (s)');
arrayfun(@(a) xlim(a,[-0.5 8]), [ax1 ax2 ax3]);
title(tl,['Weak corner (M_{g1}=1, grid H\approx2.6 s, SCR=5),  \DeltaP = ' sprintf('%+.0f',100*dp) '% of P_W'],'FontSize',12);
legend(ax1,'Location','southeast','FontSize',9);
fn=fullfile(repo,'results','fig',sprintf('weak_freq_dp%02.0f.png',100*abs(dp)));
exportgraphics(fig,fn,'Resolution',150); close(fig);
fprintf('WEAK_PLOT -> %s\n',fn);
end
