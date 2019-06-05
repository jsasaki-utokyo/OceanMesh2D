classdef geodata
    %   GEODATA: Geographical data class
    %   Handles geographical data describing coastlines or other features in
    %   the form of a shapefile and topobathy in the form of a DEM
    %   Copyright (C) 2018  Keith Roberts & William Pringle
    %
    %   This program is free software: you can redistribute it and/or modify
    %   it under the terms of the GNU General Public License as published by
    %   the Free Software Foundation, either version 3 of the License, or
    %   (at your option) any later version.
    %
    %   This program is distributed in the hope that it will be useful,
    %   but WITHOUT ANY WARRANTY; without even the implied warranty of
    %   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    %   GNU General Public License for more details.
    %
    %   You should have received a copy of the GNU General Public License
    %   along with this program.  If not, see <http://www.gnu.org/licenses/>.
    properties
        bbox  % bounding coordinates
        boubox % bbox coordinates as a CCW polygon
        mainland % mainland boundary.
        outer % outer boundary.
        inner % island boundary(ies)
        mainlandb % height of mainland
        innerb    % height of inner
        mainlandb_type % type of mainland (lake or river or ocean)
        innerb_type    % type of inner (lake or river or ocean)
        weirs % weir crestlines
        weirPfix % boundaries of weir
        weirEgfix % edges of weir
        ibconn_pts % cell-array of paired weir nodes
        inpoly_flip % reverse the notion of "in"
        contourfile %  cell-array of shapefile
        demfile % filename of dem
        BACKUPdemfile % filename of dem
        h0 % min. edgelength (meters)
        window  % smoothing window on boundary (default 5 points)
        fp % deprecated but kept for backwards capability
        Fb % linear gridded interpolant of DEM
        Fb2 % linear gridded interpolant of backup DEM
        x0y0 % bottom left of structure grid or position (0,0)
        pslg % piecewise liner straight line graph
        spacing = 2 ; %Relative spacing along polygon, large effect on computational efficiency of signed distance.
        gridspace
        % Define well-known variables for longitude and latitude
        % coordinates in Digital Elevation Model NetCDF file (CF
        % compliant).
        wkv_x = {'x','Longitude','longitude','lon'} ;
        wkv_y = {'y','Latitude', 'latitude','lat'} ;
    end
    
    methods
        
        function obj = geodata(varargin)
            % Class constructor to parse NetCDF DEM data, NaN-delimited vector,
            % or shapefile that defines polygonal boundary of meshing
            % domain.
          
            p = inputParser;
            
            defval = 0; % placeholder value if arg is not passed.
            % add name/value pairs
            addOptional(p,'bbox',defval);
            addOptional(p,'shp',defval);
            addOptional(p,'h0',defval);
            addOptional(p,'dem',defval);
            addOptional(p,'backupdem',defval);
            addOptional(p,'fp',defval);
            addOptional(p,'weirs',defval);
            addOptional(p,'pslg',defval);
            addOptional(p,'boubox',defval);
            addOptional(p,'window',defval);
            
            % parse the inputs
            parse(p,varargin{:});
            % store the inputs as a struct
            inp=p.Results;
            % get the fieldnames of the edge functions
            fields = fieldnames(inp);
            % loop through and determine which args were passed.
            % also, assign reasonable default values if some options were
            % not assigned.
            obj.boubox = [] ;
            for i = 1 : numel(fields)
                type = fields{i};
                switch type
                    % parse aux options first
                    case('bbox')
                        obj.bbox = inp.(fields{i});
                        if any(obj.bbox ~=0)
                            obj.bbox = inp.(fields{i});
                            %elseif ~ischar(inp.(fields{contains(fields,'dem')}))
                            %    error('No bbox specified!');
                        end
                    case('h0')
                        obj.h0= inp.(fields{i});
                        if obj.h0 ~=0
                            obj.h0 = inp.(fields{i});
                        else
                            error('No h0 specified!');
                        end
                    case('shp')
                        obj.contourfile = inp.(fields{i});
                        if ~iscell(obj.contourfile) && ~ischar(obj.contourfile)
                            obj.contourfile = [];
                        end
                    case('dem')
                        obj.demfile= inp.(fields{i});
                        if obj.demfile ~=0
                            obj.demfile = inp.(fields{i});
                        else
                            obj.demfile = [];
                        end
                    case('backupdem')
                        obj.BACKUPdemfile= inp.(fields{i});
                        if obj.BACKUPdemfile ~=0
                            obj.BACKUPdemfile = inp.(fields{i});
                        else
                            obj.BACKUPdemfile = [];
                        end
                    case('fp')
                        obj.fp= inp.(fields{i});
                        if obj.fp ~=0
                            obj.fp = inp.(fields{i});
                        end
                    case('outer')
                        obj.outer = inp.(fields{i});
                        if obj.outer(1) ~=0
                            obj.outer = inp.(fields{i});
                        end
                    case('pslg')
                        obj.pslg = inp.(fields{i});
                        if obj.pslg(1) ~=0
                            obj.pslg = inp.(fields{i});
                        end
                    case('mainland')
                        obj.mainland = inp.(fields{i});
                        if obj.mainland(1) ~=0
                            obj.mainland = inp.(fields{i});
                        end
                    case('inner')
                        obj.inner = inp.(fields{i});
                        if obj.inner(1) ~=0
                            obj.inner = inp.(fields{i});
                        end
                    case('boubox')
                        obj.boubox = inp.(fields{i}) ;
                    case('window')
                        obj.window = inp.(fields{i}) ;
                        if obj.window == 0
                            % Default value
                            obj.window = 5;
                        end
                    case('weirs')
                        if ~iscell(inp.(fields{i})), continue; end
                        obj.weirs = inp.(fields{i}) ;
                        noWeirs   = length(obj.weirs) ;
                        disp(['INFO: User has passed ',num2str(noWeirs),' weir crestlines.']) ;
                        obj.weirPfix = [] ; obj.weirEgfix = [] ;
                        if obj.weirs{1}(1) ~= 0
                            for ii = 1 : noWeirs
                                crestlines = obj.weirs{ii}(:,1:2) ;
                                width      = obj.weirs{ii}(1,3) ;
                                [tempPfix,tmpEgfix,obj.ibconn_pts{ii}] = GenerateWeirGeometry(crestlines,width,2*(obj.h0/111e3),0) ;
                                [tmpEgfix]=renumberEdges(tmpEgfix) ;
                                weirLength(ii) = length(tempPfix) ;
                                if ii~=1
                                    tmpEgfix = tmpEgfix + length(obj.weirPfix) ;
                                end
                                obj.weirPfix = [obj.weirPfix; tempPfix] ;
                                obj.weirEgfix = [obj.weirEgfix; tmpEgfix] ;
                            end
                        end
                end
            end
           

            % Basic error handling should go here. 
            % if not bbox and no dem, you're outta luck
            if size(obj.bbox,1) == 1 && isempty(obj.demfile) && isempty(obj.pslg)
               error('No DEM supplied and no bbox supplied, sorry pal'); 
            end
          
            obj.gridspace    = abs(obj.h0)/111e3; %point spacing along polygon,
            
            % Get bbox information from demfile if not supplied
            if size(obj.bbox,1) == 1 && isempty(obj.pslg) 
                for i = 1 : length(obj.wkv_x)
                    try
                        x = double(ncread(obj.demfile,obj.wkv_x{i}));
                        y = double(ncread(obj.demfile,obj.wkv_y{i}));
                    catch
                        if i == length(obj.wkv_x)
                           error('Could not locate x/y coordinate in DEM') ; 
                        end
                    end
                end
                obj.bbox = [min(x) max(x); min(y) max(y)];
            end
            
            if size(obj.bbox,1) == 2
                % Typical square bbox type
                % Make the bounding box 5 x 2 matrix in clockwise order
                obj.boubox = [obj.bbox(1,1) obj.bbox(2,1);
                    obj.bbox(1,1) obj.bbox(2,2); ...
                    obj.bbox(1,2) obj.bbox(2,2);
                    obj.bbox(1,2) obj.bbox(2,1); ...
                    obj.bbox(1,1) obj.bbox(2,1); NaN NaN];
            else
                % Handle non-square bbox type regions
                obj.boubox = obj.bbox;
                if ~isnan(obj.boubox(end,1))
                    obj.boubox(end+1,:) = [NaN NaN];
                end
                obj.bbox = [min(obj.boubox(:,1)) max(obj.boubox(:,1))
                    min(obj.boubox(:,2)) max(obj.boubox(:,2))] ;
            end
            
            obj = ParseShoreline(obj) ;
            
            % kjr Add the weir faux islands to the inner geometry
            if ~isempty(obj.weirPfix)
                idx = [0; cumsum(weirLength)']+1 ;
                tmp = [] ;
                for ii = 1 : noWeirs
                    tmp =  [tmp;
                        [obj.weirPfix(idx(ii):idx(ii+1)-1,:)
                        obj.weirPfix(idx(ii),:)]
                        NaN NaN] ;
                end
                obj.inner = [obj.inner ; NaN NaN ;  tmp ] ;
            end
            
            % Ensure inpoly flip is correct
            obj = check_connectedness_inpoly(obj);
            
            disp(['Read in meshing boundary: ',obj.contourfile]);
            
            if obj.BACKUPdemfile~=0 
              obj = ParseDEM(obj,1) ;   
            end
            
            obj = ParseDEM(obj) ;
            
        end
        
        function obj = ParseShoreline(obj)
            % Read in the geometric meshing boundary information from a
            % ESRI-shapefile
            if ~isempty(obj.contourfile)
                if ~iscell(obj.contourfile)
                    obj.contourfile = {obj.contourfile};
                end
                
                polygon_struct = Read_shapefile( obj.contourfile, [], ...
                    obj.bbox, obj.gridspace, obj.boubox, 0 );
                
                % Unpack data from function Read_Shapefile()s
                obj.outer     = polygon_struct.outer;
                obj.mainland  = polygon_struct.mainland;
                obj.inner     = polygon_struct.inner;
                obj.mainlandb = polygon_struct.mainlandb;
                obj.innerb    = polygon_struct.innerb;
                obj.mainlandb_type = polygon_struct.mainlandb_type;
                obj.innerb_type    = polygon_struct.innerb_type;

                % Read in the geometric meshing boundary information from a
                % NaN-delimited vector.
            elseif obj.pslg(1)~=0
                
                % Handle the case for user defined mesh boundary information
                polygon_struct = Read_shapefile( [], obj.pslg, ...
                    obj.bbox, obj.gridspace, obj.boubox, 0 );
                
                % Unpack data from function Read_Shapefile()s
                obj.outer     = polygon_struct.outer;
                obj.mainland  = polygon_struct.mainland;
                obj.inner     = polygon_struct.inner;
                obj.mainlandb = polygon_struct.mainlandb;
                obj.innerb    = polygon_struct.innerb;
                obj.mainlandb_type = polygon_struct.mainlandb_type;
                obj.innerb_type    = polygon_struct.innerb_type; 

            else
                % set outer to the boubox
               obj.outer = obj.boubox;
            end
            obj = ClassifyShoreline(obj) ;
        end
        
        function obj = ClassifyShoreline(obj)
            % Helper function to...
            % 1) Read the data from supplied file
            % 2) Classify segments as either inner, outer, or mainland.
            % 3) Ensure point spacing is adequate to support mesh sizes
            %    and ensure computational efficiency when calculating the
            %    signed distance function.
            
            % Check if no mainland segments, set outer
            % to the boubox.
            if isempty(obj.mainland)
                obj.outer = [ ];
                obj.outer = obj.boubox;
            end
            
            % Make sure the shoreline components have spacing of
            % gridspace/spacing
            [la,lo] = my_interpm(obj.outer(:,2),obj.outer(:,1),...
                obj.gridspace/obj.spacing);
            obj.outer = [];  obj.outer(:,1) = lo; obj.outer(:,2) = la;
            outerbox = obj.outer(1:find(isnan(obj.outer(:,1)),1,'first'),:);
            
            if ~isempty(obj.mainland)
                [la,lo] = my_interpm(obj.mainland(:,2),obj.mainland(:,1),...
                    obj.gridspace/obj.spacing);
                obj.mainland = []; obj.mainland(:,1) = lo; obj.mainland(:,2) = la;
            end
            
            if ~isempty(obj.inner)
                [la,lo]=my_interpm(obj.inner(:,2),obj.inner(:,1),...
                    obj.gridspace/obj.spacing);
                obj.inner = []; obj.inner(:,1) = lo; obj.inner(:,2) = la;
            end
            clearvars lo la
            
            % Smooth the coastline (apply moving average filter).
            if obj.window > 1
                disp(['Smoothing coastline with ' ...
                    num2str(obj.window) ' point window'])
                if ~isempty(obj.outer)
                    obj.outer = smooth_coastline(obj.outer,obj.window,0);
                end
                if ~isempty(obj.mainland)
                    obj.mainland = smooth_coastline(obj.mainland,obj.window,0);
                end
                if ~isempty(obj.inner)
                    obj.inner = smooth_coastline(obj.inner,obj.window,0);
                end
            else
                disp('No smoothing of coastline enabled')
            end
            
            % KJR: Coarsen portions of outer, mainland
            % and inner outside bbox.
            iboubox = obj.boubox;
            iboubox(:,1) = 1.10*iboubox(:,1)+(1-1.10)*mean(iboubox(1:end-1,1));
            iboubox(:,2) = 1.10*iboubox(:,2)+(1-1.10)*mean(iboubox(1:end-1,2));
            
            % Coarsen outer
            obj.outer = coarsen_polygon(obj.outer,iboubox);
            
            % Coarsen inner and move parts that overlap with bounding box
            % to mainland
            if ~isempty(obj.inner)
                obj.inner = coarsen_polygon(obj.inner,iboubox);
                id_del = ismembertol(obj.inner,outerbox,1e-4,'ByRows',true);      
                if sum(id_del) > 0
                   % need to change parts of inner to mainland...
                   isnan1 = find(isnan(obj.inner(:,1))); ns = 1;
                   innerdel = []; mnadd = [];
                   for ii = 1:length(isnan1)
                       ne = isnan1(ii);
                       sumdel = sum(id_del(ns:ne));
                       if sumdel > 0
                           mnadd = [mnadd; obj.inner(ns:ne,:)];
                           innerdel = [innerdel ns:ne];
                       end
                       ns = ne + 1;
                   end
                   obj.inner(innerdel,:) = [];
                   obj.outer = [obj.outer; mnadd];
                   obj.mainland = [obj.mainland; mnadd];
                end
            end
            
            % Coarsen mainland and remove parts that overlap with bounding
            % box (note this doesn't change the polygon used for inpoly,
            % only changes the distance function used for edgefx)
            if ~isempty(obj.mainland)
                obj.mainland = coarsen_polygon(obj.mainland,iboubox);
                id_del = ismembertol(obj.mainland,outerbox,1e-4,'ByRows',true);      
                obj.mainland(id_del,:) = []; 
                while ~isempty(obj.mainland) && isnan(obj.mainland(1))
                    obj.mainland(1,:) = []; 
                end                
            end
           
            
        end
        
        function obj = ParseDEM(obj,backup)
            if nargin < 2 
              backup = 0 ;
              fname = obj.demfile ; 
            else
              backup = 1 ;   
              fname = obj.BACKUPdemfile ;
            end
            % Process the DEM for the meshing region. 
            if ~isempty(fname)
                
               for i = 1 : length(obj.wkv_x)
                    try
                        x = double(ncread(obj.demfile,obj.wkv_x{i}));
                        y = double(ncread(obj.demfile,obj.wkv_y{i}));
                    catch
                        if i == length(obj.wkv_x)
                           error('Could not locate x/y coordinate in DEM') ; 
                        end
                    end
                end
                
                % Find name of z value (use one that has 2 dimensions)
                finfo = ncinfo(fname);
                for ii = 1:length(finfo.Variables)
                    if length(finfo.Variables(ii).Size) == 2
                        zvarname = finfo.Variables(ii).Name;
                        break
                    end
                end
                modbox = [0 0];
                if obj.bbox(1,2) > 180 && obj.bbox(1,1) < 180 && min(x) < 0
                    % bbox straddles 180/-180 line
                    loop = 2;
                else
                    loop = 1;
                    if max(x) > 180
                        if obj.bbox(1,1) < 0; modbox(1) = 1; end
                        if obj.bbox(1,2) < 0; modbox(2) = 1; end
                    elseif min(x) < 0
                        if obj.bbox(1,1) > 180; modbox(1) = -1; end
                        if obj.bbox(1,2) > 180; modbox(2) = -1; end
                    end
                end
                J = find(y >= obj.bbox(2,1) & y <= obj.bbox(2,2));
                I = []; demz = [];
                for nn = 1:loop
                    bboxt = obj.bbox;
                    bboxt(1,:) =  bboxt(1,:) + modbox.*360;
                    if loop == 2
                        if nn == 1
                            bboxt(1,2) = 180;
                        else
                            bboxt(1,1) = -180;
                            bboxt(1,2) = bboxt(1,2) - 360;
                        end
                    end
                    It = find(x >= bboxt(1,1) & x <= bboxt(1,2));
                    I = [I; It];
                    demzt = single(ncread(fname,zvarname,...
                        [It(1) J(1)],[length(It) length(J)]));
                    if isempty(demz)
                        demz = demzt;
                    else
                        demz = cat(1,demz,demzt);
                    end
                end
                x = x(I); y = y(J);
                if obj.bbox(1,2) > 180
                    x(x < 0) = x(x < 0) + 360;
                    [x1,IA] = unique(x);
                    if length(x) > length(x1)
                        x = x1; demz = demz(IA,:);
                    end
                end
                % handle DEMS from packed starting from the bottom left 
                if y(2) < y(1) 
                  y = flipud(y) ; 
                  demz = fliplr(demz) ; 
                end
                
                % check for any invalid values 
                bad = abs(demz) > 10e3 ;
                if ~isempty(find(bad)) > 0 & ~backup
                    warning('ALERT: Invalid and/or missing DEM values detected..check DEM');
                    if obj.BACKUPdemfile(1)~=0
                        disp('Replacing invalid values with back-up DEMfile');
                        [demx,demy] = ndgrid(x,y) ;
                        demz(bad) = obj.Fb2(demx(bad),demy(bad)) ;
                    else
                        % just replace it with NaNs
                        demz(bad) = NaN ;
                    end
                end
                
                % creating back up interpolant
                if backup
                    obj.Fb2   = griddedInterpolant({x,y},demz,...
                        'linear','nearest');
                    % clear data from memory
                    clear x y demz
                else
                 % main interpolant 
                    obj.Fb   = griddedInterpolant({x,y},demz,...
                        'linear','nearest');
                    obj.x0y0 = [x(1),y(1)];
                    % clear data from memory
                    clear x y demz
                end
                
                disp(['Read in demfile ',fname]);
            end
            
            % Handle the case of no dem
            if isempty(obj.x0y0)
                obj.x0y0 = [obj.bbox(1,1), obj.bbox(2,1)];
            end
            
        end
        
        function obj = check_connectedness_inpoly(obj)
            % Check for connected polygons and if not connected,
            %  whether to flip the inpoly result to ensure meshing
            %  on the coastal side of the polygon.
            
            obj.inpoly_flip = 0;
            % return if outer polygon is connected
            shpEnd = find(isnan(obj.outer(:,1)));
            [~,loc] = max(diff(shpEnd));
            shpEnd = vertcat(0,shpEnd); loc = loc+1;
            if abs(sum(obj.outer(shpEnd(loc)+1,:)) - ...
                    sum(obj.outer(shpEnd(loc+1)-1,:))) > eps
               disp('Warning: Shapefile is unconnected... continuing anyway')
            end
            
            % check for inpoly goodness read the GSHHS checker
            ps = Read_shapefile( {'GSHHS_l_L1'}, [], ...
                obj.bbox, obj.gridspace, obj.boubox, 0 );
            
            % make a "fake" tester grid
            x = linspace(obj.bbox(1,1),obj.bbox(1,2),100);
            y = linspace(obj.bbox(2,1),obj.bbox(2,2),100);
            edges = Get_poly_edges( [ps.outer; ps.inner] );
            in_Test = inpoly([x',y'],[ps.outer; ps.inner],edges);
            polytester = [obj.outer; obj.inner];
            edges = Get_poly_edges( polytester );
            in_Shpf = inpoly([x',y'],polytester,edges);
            % if more than half of thepoints disagree between Test and Shpf
            % lets flip the inpoly
            if length(find(xor(in_Shpf,in_Test))) > 50
                obj.inpoly_flip = 1;
                disp(['Shapefile inpoly is inconsistent ' ...
                      'with GHSSS test file, flipping the inpoly test'])
            end
            
            % if flooplaind meshing, flip the inpoly test
            if obj.fp
                obj.inpoly_flip = mod(1,obj.inpoly_flip);
            end
        end
        
        function obj = close(obj)
            % Clips the mainland segment with the boubox.
            % Performs a breadth-first search given a seed position
            % of the piecewise-straight line graph (PSLG) that is used to define the meshing boundary.
            % This returns back an updated geodata class instance with the outer boundary clipped with the boubox.
            % kjr,und,chl 2018
            
            if isempty(obj.Fb)
                warning('ALERT: Meshing boundary is not a polygon!')
                warning('ALERT: DEM is required to clip line segment with polygon')
                seed=input('Enter coordinate of seed location to clip: ');
            else
                % Guess seed location: submerged portion of domain within
                % bbox?
                [demx,demy] = ndgrid(obj.x0y0(1):obj.h0/111e3:obj.bbox(1,2), ...
                    obj.x0y0(2):obj.h0/111e3:obj.bbox(2,2));
                demz = obj.Fb(demx,demy);
                [idx]=find(demz(:) < -10) ; % find points deeper than -10 m below sea level
                allpts=[demx(:),demy(:)] ;
                cands = allpts(idx,:);
                if(isnan(obj.boubox(end,1)))
                    edges=Get_poly_edges(obj.boubox) ;
                    [in]=inpoly(cands,obj.boubox,edges) ; %  determine which of these points is in the domain
                else
                    [in]=inpoly(cands,obj.boubox) ;       %  determine which of these points is in the domain
                end
                cands2=cands(in,:) ;
                seed = cands2(50,:) ;
            end
            
            geom = [obj.mainland; obj.boubox] ;
            
            [NODE,PSLG]=getnan2(geom) ;
            
            [NODE2,PSLG2,PART2] = bfsgeo2(NODE,PSLG,seed) ;
            
            POLY = extdom_polygon(PSLG2(PART2{1},:),NODE2,-1) ;
            
            new_outer = cell2mat(POLY') ;
            
            [la,lo] = my_interpm(new_outer(:,2),new_outer(:,1),((obj.h0/2)/111e3))  ;
            
            new_outer = [lo la] ;
            
            obj.outer = new_outer ;
            
            % reset this to default
            obj.inpoly_flip = 0 ;
        end
                
        function obj = extractContour(obj,ilev)
            % Extract a geometric contour from the DEM at elevation ilev.
            [node,edge] = ...
                getiso2( obj.Fb.GridVectors{1},obj.Fb.GridVectors{2},...
                double(obj.Fb.Values),ilev) ;
            
            polyline = cell2mat(extdom_polygon(edge,node,-1,1,10)') ;
            
            obj = geodata('pslg',polyline,'h0',obj.h0,'dem',obj.demfile) ;
            
        end
        
        function plot(obj,type,projection)
            % Plot mesh boundary
            if nargin == 1
                type = 'shp';
            end
            
            if nargin < 3
                projection = 'Mercator';
            end
            bufx = 0.2*(obj.bbox(1,2) - obj.bbox(1,1));
            bufy = 0.2*(obj.bbox(2,2) - obj.bbox(2,1));
            if startsWith(projection,'ste')
                m_proj(projection,'lat',min(obj.bbox(2,:)),...
                    'long',mean(obj.bbox(1,:)),'radius',...
                    min(179.9,1.20*max(diff(obj.bbox(2,:)))));
            else
                lon1 = max(-180,obj.bbox(1,1) - bufx);
                lon2 = min(+180,obj.bbox(1,2) + bufx);
                lat1 = max(- 90,obj.bbox(2,1) - bufy);
                lat2 = min(+ 90,obj.bbox(2,2) + bufy);                
                m_proj(projection,...
                    'long',[lon1, lon2],'lat',[lat1, lat2]);
            end
            
            switch type
                case('dem')
                    % interpolate DEM's bathy linearly onto our edgefunction grid.
                    [demx,demy] = ndgrid(obj.x0y0(1):obj.h0/111e3:obj.bbox(1,2), ...
                        obj.x0y0(2):obj.h0/111e3:obj.bbox(2,2));
                    demz = obj.Fb(demx,demy);
                    if ~isempty(obj.inner) && obj.inner(1) ~= 0
                        poly = [obj.outer; obj.inner];
                    else
                        poly = obj.outer;
                    end
                    edges = Get_poly_edges( poly );
                    in = inpoly([demx(:),demy(:)],poly, edges);
                    if obj.inpoly_flip
                        in = ~in;
                    end
                    hold on; m_fastscatter(demx(in),demy(in),demz(in));
                    cb = colorbar; ylabel(cb,'topo-bathy depth [m]')
                case('omega')
                    % hatch the meshing domain, Omega
                    [demx,demy] = ndgrid(obj.x0y0(1):obj.h0/111e3:obj.bbox(1,2), ...
                        obj.x0y0(2):obj.h0/111e3:obj.bbox(2,2));
                    edges = Get_poly_edges( [obj.outer; obj.inner] );
                    in = inpoly([demx(:),demy(:)],[obj.outer; obj.inner], edges);
                    long = demx(~in); lati = demy(~in);
                    hold on; m_hatch(obj.boubox(1:end-1,1),...
                        obj.boubox(1:end-1,2),'cross',45,0.05);
                    m_plot(long,lati,'.','Color','white')
            end
            if ~isempty(obj.mainland) && obj.mainland(1) ~= 0
                h1 = m_plot(obj.mainland(:,1),obj.mainland(:,2),...
                    'r-','linewi',1); hold on;
            end
            if ~isempty(obj.inner) && obj.inner(1) ~= 0
                h2 = m_plot(obj.inner(:,1),obj.inner(:,2),...
                    'g-','linewi',1); hold on;
            end
            if ~isempty(obj.weirs)
                for ii =1 : length(obj.weirs)
                    h3 = m_plot(obj.weirs{ii}(:,1),obj.weirs{ii}(:,2),...
                        'm-','linewi',1); hold on;
                end
            end
            [la,lo] = my_interpm(obj.boubox(:,2),obj.boubox(:,1),...
                0.5*obj.h0/111e3);
            m_plot(lo,la,'k--','linewi',2);
            m_grid('xtick',10,'tickdir','out','yaxislocation','left','fontsize',10);
            if exist('h1','var') && exist('h2','var') && exist('h3','var')
                legend([h1 h2,h3],{'mainland' 'inner' 'weirs'},'Location','NorthWest')
            elseif exist('h1','var')
                legend(h1,'mainland','Location','NorthWest')
            elseif exist('h2','var')
                legend(h2,'inner','Location','NorthWest')
            elseif exist('h1','var') && exist('h3','var')
                legend([h1,h3],'mainland','weirs','Location','NorthWest')
            elseif exist('h2','var')  && exist('h3','var')
                legend([h2,h3],'inner','weirs','Location','NorthWest')
            end
            %set(gcf, 'Units', 'Normalized', 'OuterPosition', [0 0 1 1]);
                end
        
    end
end

