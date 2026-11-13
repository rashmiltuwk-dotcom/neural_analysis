root = 'C:\Users\rashm\Documents\opm_pi\participant_002\scannercast';

% ---- options ------------------------------------------------------------
redSlots    = [];
greenSlots  = [];
yellowSlots = [];
showNumbers = true;               % false = no numbers on the boxes
% -------------------------------------------------------------------------

% mesh: 64 boxes, 46 triangles each, stored in slot order
TR       = stlread(fullfile(root,'Sensor Placement 007.stl'));
F        = TR.ConnectivityList;
V        = TR.Points;
nS       = 64;
slot     = (1:nS)';
faceSlot = ceil((1:size(F,1))' / (size(F,1)/nS));

% colour table, one row per slot
C = repmat([.8 .8 .8], nS, 1);                      % unassigned = grey
C(ismember(slot,redSlots),:)    = repmat([0.85 0.10 0.10], nnz(ismember(slot,redSlots)),1);
C(ismember(slot,greenSlots),:)  = repmat([0.20 0.70 0.20], nnz(ismember(slot,greenSlots)),1);
C(ismember(slot,yellowSlots),:) = repmat([1.00 0.85 0.00], nnz(ismember(slot,yellowSlots)),1);

figure('Color','w'); hold on; axis equal off; view(180,10);
patch('Faces',F,'Vertices',V, ...
      'FaceVertexCData',C(faceSlot,:),'FaceColor','flat','EdgeColor','none');
camlight; lighting flat; rotate3d on;

% number on top of each box: box centre pushed out past its outer face
if showNumbers
    cen = zeros(nS,3);
    for s = 1:nS
        cen(s,:) = mean(V(unique(F(faceSlot==s,:)),:),1);
    end
    out = cen - mean(cen,1);  out = out ./ vecnorm(out,2,2);
    lab = cen + 19*out;                              % mm
    text(lab(:,1),lab(:,2),lab(:,3),string(slot), ...
         'FontSize',9,'FontWeight','bold','Color','k', ...
         'HorizontalAlignment','center','VerticalAlignment','middle');
end
