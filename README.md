# Apache-DTU
DCS Modification that handles loading of JSON configuration for the AH-64D "Apache."

[Apache-DTU.io Web Interface](http://www.apache-dtu.io/)

## Install
- Download latest release.
- Extract/Unzip.
- Drag/Drop "Mods" file structure from the extracted release folder to your DCS Saved Games directory. E.g., C:/Users/*your_username*/Saved Games/DCS.openbeta/**Mods**
- Add the following code to "**Export.lua**" within the "**Scripts**" directory under DCS's Saved Games folder. E.g., C:/Users/*your_username*/Saved Games/DCS.openbeta/**Scripts/Export.lua**
`pcall(function() local dcsApacheDtu=require('lfs');dofile(dcsApacheDtu.writedir()..[[Mods\Services\DCS-Apache-DTU\Scripts\DCS-Apache-DTU.lua]]); end,nil);`

## Usage
Apache-DTU is designed to be utilized from within the cockpit. Loading JSON data is carried out by navigating to the **DMS** page by pressing **B1** (M) twice. On this page, **DTU** should be displayed under **L1**. Users must type "**LOAD**" into the Keyboard Unit (KU), then press **L1** while on the DMS page. The script will immediately clear the KU screen and begin loading data into the Apache as defined in *DTC.json* from within C:/Users/*your_username*/Saved Games/DCS.openbeta/Mods/Services/DCS-Apache-DTU/**DTC**

All fields and settings are *optional*, if you desire skipping a section of data, simply omit it from the DTC.json file.
Although [the web interface](http://www.apache-dtu.io/) will generate DTC.json, the json may also be created by manually editing the DTU array within the *DCS-Apache-DTU.lua* file directly (prior to loading into mission), then typing **SAVE** into the KU and actioning the **DTU** button (*L1*) from within the cockpit. If successful, the KU screen will display "*SAVE SUCCESS*." Once generated, the mission does not need to be reloaded; simply clear the KU screen and type "**LOAD**" followed by actioning **L1** (DTU) whilst on the **DMS** page on the MPD. Not needing to reload the mission applies to making real-time changes to DTC.json as well. If something is wrong with your configuration, you may edit the DTC.json file without exiting mission.

## Bug Reporting
Please report bugs and issues with either the web interface or the DCS modification here on GitHub.

### The "To-Do" List:
- Implement post-input data validation and correction/rewind feature (DCS-end)
- Implement input validation on web interface, remove input validation bloat on DCS-end
- Implement "**SAVE**" feature that permits export of current aircraft settings (DCS-end)
- Presets (capability to load different .json files other than DTC.json) (DCS-end)
- COM Preset PRI frequency setting (DCS-end)
- TSD SHOW subpage settings (Implemented on DCS-end, need to implement on web interface)
- Other stuff that I'll remember later (both ends)