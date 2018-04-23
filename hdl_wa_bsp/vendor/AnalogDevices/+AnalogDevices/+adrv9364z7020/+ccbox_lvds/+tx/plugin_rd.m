function hRD = plugin_rd
% Reference design definition

%   Copyright 2014-2015 The MathWorks, Inc.

% Call the common reference design definition function
hRD = AnalogDevices.adrv9364z7020.common.plugin_rd('box lvds', 'Tx');
AnalogDevices.adrv9364z7020.ccbox_lvds.tx.add_tx_io(hRD);