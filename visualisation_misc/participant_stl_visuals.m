% ==== SETTINGS =============================================================
root        = 'C:\Users\rashm\Documents\opm_pi\participant_001\Neural_Data_001_001\scannercast';
stlFile     = 'FixedSensorPositions_002.stl';

minBoxTriangles = 30;             % this will need adjusting depending on the participant
                                  %  for participant 1, it was 30 triangles
                                  %  for participant 2, it was 7 triangles
redSlots    = [32, 19, 12, 34, 13, 2, 47, 54, 52, 48, 50, 26, 8, 27, 25, 58, 36, 51, 39, 59, 65, 1, 14, 24, 29, 37, 38, 40, 43, 49, 67, 68, 69, 70];
greenSlots  = [3, 4, 5, 6, 7, 9, 10, 11, 15, 16, 17, 18, 20, 22, 28, 30, 31, 33, 35, 41, 42, 44, 46, 53, 55, 57, 60, 61, 62, 63, 64, 66];
yellowSlots = [21, 23, 45, 56];

showNumbers = false;               % false = no numbers on the boxes.
                                  % useful to exclude numbers in manuscript

viewAngle   = [180 10];           % shows front
% viewAngle   = [90 10];           % shows side R
% viewAngle   = [-90 10];           % shows side L
% viewAngle   = [-180 10];           % shows back
% ===========================================================================

% load mesh, then weld corners closer than 0.001 mm into one
TR = stlread(fullfile(root,stlFile));
[V,~,ic] = uniquetol(TR.Points, 1e-3, 'ByRows',true, 'DataScale',1);
F  = ic(TR.ConnectivityList);

% split the mesh into separate pieces
G   = graph([F(:,1);F(:,2)], [F(:,2);F(:,3)]);
bin = conncomp(G)';
[~,~,facePiece] = unique(bin(F(:,1)),'stable');      % piece of every triangle, in file order
nTri = accumarray(facePiece,1);                      % triangles in each piece

% keep only the pieces big enough to be sensor boxes, numbered in file order
isBox            = nTri >= minBoxTriangles;
pieceSlot        = zeros(size(nTri));
pieceSlot(isBox) = 1:nnz(isBox);
faceSlot         = pieceSlot(facePiece);             % 0 = not a sensor box
nS   = nnz(isBox);
slot = (1:nS)';

% colour table, one row per slot
C = repmat([.8 .8 .8], nS, 1);                       % unassigned = grey
C(ismember(slot,redSlots),:)    = repmat([0.85 0.10 0.10], nnz(ismember(slot,redSlots)),1);
C(ismember(slot,greenSlots),:)  = repmat([0.20 0.70 0.20], nnz(ismember(slot,greenSlots)),1);
C(ismember(slot,yellowSlots),:) = repmat([1.00 0.85 0.00], nnz(ismember(slot,yellowSlots)),1);

% draw the sensor boxes only
keep = faceSlot > 0;
figure('Color','w'); hold on; axis equal off; view(viewAngle);
patch('Faces',F(keep,:),'Vertices',V, ...
      'FaceVertexCData',C(faceSlot(keep),:),'FaceColor','flat','EdgeColor','none');
camlight; lighting flat; rotate3d on;

% number on each box: box centre pushed 19 mm outwards
if showNumbers
    cen = zeros(nS,3);
    for s = 1:nS
        cen(s,:) = mean(V(unique(F(faceSlot==s,:)),:),1);
    end
    out = cen - mean(cen,1);  out = out ./ vecnorm(out,2,2);
    lab = cen + 19*out;
    text(lab(:,1),lab(:,2),lab(:,3),string(slot), ...
         'FontSize',9,'FontWeight','bold','Color','k', ...
         'HorizontalAlignment','center','VerticalAlignment','middle');
end
