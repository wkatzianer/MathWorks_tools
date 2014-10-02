classdef iio_sys_obj_source < matlab.System & matlab.system.mixin.Propagates ...
							& matlab.system.mixin.CustomIcon
    % iio_sys_obj_source Source System Object block for IIO devices
    
    properties
        % Public, tunable properties.
    end
    
    properties (Nontunable)
        % Public, non-tunable properties.
        
        % ip_address IP address
        ip_address = '';
        
        %dev_name Device name
        dev_name = '';
        
        %ch_size Channel size [samples]
        ch_size = 8192;
        
        %ch_no Number of active channels
        ch_no = 1;
    end
    
    properties (Access = protected)
        % Protected class properties.
      
        %iio_dev_cfg Device configuration structure
        iio_dev_cfg = [];
    end
    
    properties (Access = private)
        % Private class properties.
        libiio_data_dev = {};
		libiio_ctrl_dev  = {};
    end
    
    properties (DiscreteState)
        % Discrete state properties.
        num_cfg_in;
        str_cfg_in;
    end
    
    methods
        % Constructor
        function obj = iio_sys_obj_source(varargin)
			% Support name-value pair arguments when constructing the object.
            setProperties(obj,nargin,varargin{:});
        end
    end
 
    methods (Access = protected)
        %% Utility functions
        
        function config = getObjConfig(obj)
			% Read the selected device's configuration
			
            % Open the configuration file
            fname = sprintf('%s_source.cfg', obj.dev_name);
            fp_cfg = fopen(fname);
            if(fp_cfg < 0)
                config = {};
                return;
            end
            
            % Build the object configuration structure
            config = struct('data_device', '',... % Pointer to the data device 
                            'ctrl_device', '',... % Pointer to the control device
                            'cfg_ch', [],...      % Configuration channels list 
                            'mon_ch', []);        % Monitoring channels list
            
            % Build the configuration/monitoring channel configuration structure
            ch_cfg = struct('port_name', '',...   % Name of the port to be displayed on the object block    
                            'port_attr', '',...   % Associated device attribute name
                            'dev', 0,...          % Pointer to the control device
                            'ch', 0,...           % Pointer to the attributes device channel
                            'attr', 0);           % Pointer to the device attribute structure
                        
            % Read the object's configuration
            while(~feof(fp_cfg))
                line = fgets(fp_cfg);
                if(strfind(line,'#'))
                    continue;
                end				
                if(~isempty(strfind(line, 'data_device')))
                    % Get the associated data device
                    idx = strfind(line, '=');
                    tmp = line(idx+1:end);
                    tmp = strtrim(tmp);
                    config.data_device = tmp;
                elseif(~isempty(strfind(line, 'ctrl_device')))
                    % Get the associated control device
                    idx = strfind(line, '=');
                    tmp = line(idx+1:end);
                    tmp = strtrim(tmp);
                    config.ctrl_device = tmp;
                elseif(~isempty(strfind(line, 'channel')))
                    % Get the associated configuration/monitoring channels
                    idx = strfind(line, '=');
                    line = line(idx+1:end);
                    line = strsplit(line, ',');				
                    ch_cfg.port_name = strtrim(line{1}); 
                    ch_cfg.port_attr = strtrim(line{3}); 
                    if(strcmp(strtrim(line{2}), 'IN'))
                        config.cfg_ch = [config.cfg_ch ch_cfg];
                    elseif(strcmp(strtrim(line{2}), 'OUT'))
                        config.mon_ch = [config.mon_ch ch_cfg];
                    end
                end
            end
            fclose(fp_cfg);
        end
        
    end
        
    methods (Access = protected)
        %% Common functions
		function setupImpl(obj)
            % Implement tasks that need to be performed only once.
                        
            % Read the object's configuration from the associated configuration file
            obj.iio_dev_cfg = getObjConfig(obj);
            if(isempty(obj.iio_dev_cfg))
                msgbox('Could not read device configuration!', 'Error','error');
                return;
            end
            
            % Initialize discrete-state properties.
            obj.num_cfg_in = zeros(1, length(obj.iio_dev_cfg.cfg_ch));
            obj.str_cfg_in = zeros(length(obj.iio_dev_cfg.cfg_ch), 64);
           
            % Initialize the libiio data device
			obj.libiio_data_dev = libiio_if();			
            [ret, err_msg, msg_log] = init(obj.libiio_data_dev, obj.ip_address, ...
										   obj.iio_dev_cfg.data_device, 'IN', ...
										   obj.ch_no, obj.ch_size);
			fprintf('%s', msg_log);
            if(ret < 0)
				msgbox(err_msg, 'Error','error');
                return;
            end

			% Initialize the libiio control device
            obj.libiio_ctrl_dev = libiio_if();
			[ret, err_msg, msg_log] = init(obj.libiio_ctrl_dev, obj.ip_address, ...
										   obj.iio_dev_cfg.ctrl_device, '', ...
										   0, 0);
			fprintf('%s', msg_log);
            if(ret < 0)
				msgbox(err_msg, 'Error','error');
                return;
            end						
        end
        
        function releaseImpl(obj)
            % Release any resources used by the system object.            
            obj.iio_dev_cfg = {};
			delete(obj.libiio_data_dev);
			delete(obj.libiio_ctrl_dev);			
        end        
        
        function varargout = stepImpl(obj, varargin)
            % Implement the system object's processing flow.
            in_data_ch_no = 0;
            out_data_ch_no = obj.ch_no;
			varargout = cell(1, out_data_ch_no + length(obj.iio_dev_cfg.mon_ch));
			
            % Implement the data capture flow
			[ret, data] = readData(obj.libiio_data_dev);
            for i = 1 : obj.ch_no 
                varargout{i} = data{i};
            end
              
			% Implement the parameters monitoring flow
			for i = 1 : length(obj.iio_dev_cfg.mon_ch)
				[ret, val] = readAttribute(obj.libiio_ctrl_dev, obj.iio_dev_cfg.mon_ch(i).port_attr);
				varargout{out_data_ch_no + i} = val;
			end

			% Implement the device configuration flow
			for i = 1 : length(obj.iio_dev_cfg.cfg_ch)
				if(~isempty(varargin{i + in_data_ch_no}))
					if(length(varargin{i + in_data_ch_no}) == 1)
						new_data = (varargin{i + in_data_ch_no} ~= obj.num_cfg_in(i));
					else
						new_data = ~strncmp(char(varargin{i + in_data_ch_no}'), char(obj.str_cfg_in(i,:)), length(varargin{i + in_data_ch_no}));
					end
					if(new_data == 1)
						if(length(varargin{i + in_data_ch_no}) == 1)
							obj.num_cfg_in(i) = varargin{i + in_data_ch_no};
							str = num2str(obj.num_cfg_in(i));
						else
							for j = 1:length(varargin{i + in_data_ch_no})
								obj.str_cfg_in(i,j) = varargin{i + in_data_ch_no}(j);
							end
							obj.str_cfg_in(i,j+1) = 0;
							str = char(obj.str_cfg_in(i,:));
						end
						ret = writeAttribute(obj.libiio_ctrl_dev, obj.iio_dev_cfg.cfg_ch(i).port_attr, str);						
					end
				end
			end
        end
        
        function resetImpl(obj)
            % Initialize discrete-state properties.
            obj.num_cfg_in = zeros(1, length(obj.iio_dev_cfg.cfg_ch));
            obj.str_cfg_in = zeros(length(obj.iio_dev_cfg.cfg_ch), 64);
        end
        
        function num = getNumInputsImpl(obj)
            % Get number of inputs.            
            num = 0;
            %num = obj.ch_no;
			
			config = getObjConfig(obj);
            if(~isempty(config))
                num = num + length(config.cfg_ch);
            end
        end
        
        function varargout = getInputNamesImpl(obj)
			% Get input names

            % Get the number of input data channels
            data_ch_no = 0;
            %data_ch_no = obj.ch_no;
            
            % Get number of control channels
            cfg_ch_no = 0;
            config = getObjConfig(obj);
            if(~isempty(config))
                cgf_ch_no = length(config.cfg_ch);
            end
            
            if(data_ch_no + cgf_ch_no ~= 0)
                varargout = cell(1, data_ch_no + cgf_ch_no);
                for i = 1 : data_ch_no
                    varargout{i} = sprintf('In%d', i);
                end
                for i = data_ch_no + 1 : data_ch_no + cgf_ch_no
                    varargout{i} = config.cfg_ch(i - data_ch_no).port_name;
                end
            else
                varargout = {};
            end
		end
        
        function num = getNumOutputsImpl(obj)
            % Get number of outputs.
            %num = 0;
            num = obj.ch_no;

            config = getObjConfig(obj);
            if(~isempty(config))
                num = num + length(config.mon_ch);
            end
        end
		
		function varargout = getOutputNamesImpl(obj)
			% Get output names
            
            % Get the number of output data channels
            %data_ch_no = 0;
            data_ch_no = obj.ch_no;
            
            % Get number of monitoring channels
            mon_ch_no = 0;
            config = getObjConfig(obj);
            if(~isempty(config))
                mon_ch_no = length(config.mon_ch);
            end
            
            if(data_ch_no + mon_ch_no ~= 0)
                varargout = cell(1, data_ch_no + mon_ch_no);
                for i = 1 : data_ch_no
                    varargout{i} = sprintf('Out%d', i);
                end
                for i = data_ch_no + 1 : data_ch_no + mon_ch_no
                    varargout{i} = config.mon_ch(i - data_ch_no).port_name;
                end
            else
                varargout = {};
            end
		end
        
        function varargout = isOutputFixedSizeImpl(obj)
            % Get outputs fixed size.
            varargout = cell(1, getNumOutputs(obj));
            for i = 1 : getNumOutputs(obj)
                varargout{i} = true;
            end            
        end
        
        function varargout = getOutputDataTypeImpl(obj)
            % Get outputs data types.
            varargout = cell(1, getNumOutputs(obj));
            for i = 1 : getNumOutputs(obj)
                varargout{i} = 'double';
            end
        end
         
        function varargout = isOutputComplexImpl(obj)
            % Get outputs data types.
            varargout = cell(1, getNumOutputs(obj));
            for i = 1 : getNumOutputs(obj)
                varargout{i} = false;
            end
        end
        
		function varargout = getOutputSizeImpl(obj)
            % Implement if input size does not match with output size.
            varargout = cell(1, getNumOutputs(obj));
            for i = 1:obj.ch_no
                varargout{i} = [obj.ch_size 1];
            end
            for i = obj.ch_no + 1 : length(varargout)
                varargout{i} = [1 1];
            end
        end
        
        function icon = getIconImpl(obj)
            % Define a string as the icon for the System block in Simulink.
            if(~isempty(obj.dev_name))               
                icon = strcat(obj.dev_name, ' source');                
            else
                icon = mfilename('class');
            end
        end
		
        %% Backup/restore functions
        function s = saveObjectImpl(obj)
            % Save private, protected, or state properties in a
            % structure s. This is necessary to support Simulink
            % features, such as SimState.
        end
        
        function loadObjectImpl(obj,s,wasLocked)
            % Read private, protected, or state properties from
            % the structure s and assign it to the object obj.
        end
        
        %% Simulink functions
        function z = getDiscreteStateImpl(obj)
            % Return structure of states with field names as
            % DiscreteState properties.
            z = struct([]);
        end
    end
	
	methods(Static, Access = protected)
        %% Simulink customization functions
        function header = getHeaderImpl(obj)
            % Define header for the System block dialog box.
            header = matlab.system.display.Header(mfilename('class'));
        end
        
        function group = getPropertyGroupsImpl(obj)
            % Define section for properties in System block dialog box.
            group = matlab.system.display.Section(mfilename('class'));
        end
    end
end
