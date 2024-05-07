--[[
Author: 132nd.Sly / SlyGuy / VicTroX
Filename: DCS-Apache-DTU.lua
Description: Controls logic and behavior of "data transfer unit" by loading a .json, then actioning
------------ the appropriate buttons in-pit to fill in the data as determined by the user.
Initial Release: 2024-04-24

Current Version: 1.0.2.0
Current Version Release: 2024-05-06
Changes: Addition of PRIMARY selection for COM presets.
--]]

--[[
TODO: Undo button presses if data isn't accepted by KU.
	- if _indicators.KU["Standby_text"] > 1 then the data wasn't accepted after pressing ENTER
	- have to keep a running record of btn/device/map through CycleButton function (table.insert)
	- reference button press that got us into the situation. Something like: #btnPressRecords - _string:len() - 1

TODO: Most fields validate data to some extent. Ensure *all* fields are validating data; better yet, remove bloat from
	- DCS lua end (here) by adding input validation to web interface.

TODO: Add validation check to TSD RTM subpage... currently doesn't check if user is out-of-range with route selection

TODO: Exporting of current AC settings. A lot of work involved in that... later problem.
	- Will probably end up refactoring the entire code at this point.

TODO: .json Presets; User should be able to do something like: "LOAD-DTC1", then the program looks for DTC1.json in the
	- Apache-DTU directory.

TODO: Add mode code on/off settings
--]]

local ApacheDTU = {
	dataReady = true, -- state tracking
	dataLoadCoroutine = nil, -- for actioning the load coroutine
	dataSaveCoroutine = nil -- same as above... but for save.
}
local JSON = loadfile("Scripts\\JSON.lua")() -- didn't know this existed... thanks SRS!
ApacheDTU.JSON = JSON

local _devices = { -- for actioning buttons with performClickableAction
	leftMPD = nil,
	rightMPD = nil,
	KU = nil
}

local _indicators = { -- displays for pulling data
	leftMPD = nil,
	rightMPD = nil,
	KU = nil
}

local _mapKU = { -- command_defs.lua
	["0"] = 3043,	["1"] = 3033,	["2"] = 3034,	["3"] = 3035,	["4"] = 3036,
	["5"] = 3037,	["6"] = 3038,	["7"] = 3039,	["8"] = 3040,	["9"] = 3041,	
	["."] = 3042,	["A"] = 3007,	["B"] = 3008,	["C"] = 3009,	["D"] = 3010,	
	["E"] = 3011,	["F"] = 3012,	["G"] = 3013,	["H"] = 3014,	["I"] = 3015,	
	["J"] = 3016,	["K"] = 3017,	["L"] = 3018,	["M"] = 3019,	["N"] = 3020,	
	["O"] = 3021,	["P"] = 3022,	["Q"] = 3023,	["R"] = 3024,	["S"] = 3025,	
	["T"] = 3026,	["U"] = 3027,	["V"] = 3028,	["W"] = 3029,	["X"] = 3030,	
	["Y"] = 3031,	["Z"] = 3032,	["CLR"] = 3001,	[" "] = 3003,	["ENTER"] = 3006,
	["-"] = 3047
}

local _mapMPD = {
	["T1"] = 3001, ["T2"] = 3002, ["T3"] = 3003, ["T4"] = 3004, ["T5"] = 3005, ["T6"] = 3006,
	["R1"] = 3007, ["R2"] = 3008, ["R3"] = 3009, ["R4"] = 3010, ["R5"] = 3011, ["R6"] = 3012,
	["B6"] = 3013, ["B5"] = 3014, ["B4"] = 3015, ["B3"] = 3016, ["B2"] = 3017, ["B1"] = 3018, -- B1 = M (Menu)
	["L6"] = 3019, ["L5"] = 3020, ["L4"] = 3021, ["L3"] = 3022, ["L2"] = 3023, ["L1"] = 3024,
	["COM"] = 3027, ["AC"] = 3028, ["TSD"] = 3029, ["WPN"] = 3030
}

local DTU = {
	COM = {
		Preset1 = { -- Can add and remove Preset1 thru Preset10 as desired
			UNIT_ID = "FLIGHT", -- Max 8 char
			CALLSIGN = "FLT", -- Max 5 char
			VHF = "126.2",
			UHF = "237",
			UHF_Cipher = false,
			UHF_CNV = "1",
			FM1 = "32.9",
			FM1_Cipher = false,
			FM1_CNV = "2",
			FM2 = "36.25",
			FM2_Cipher = false,
			FM2_CNV = "3",
			PRI_FREQ = "FM1",
			deleteExistingNET = true,
			NET = {
				[1] = {
					CS = "CRO12", -- lower limit 3 char / upper limit 5 char
					SUB = "12", -- lower limit 1 char / upper limit 2 char
					TEAM = true,
					PRI = true -- max 7 a/c can be PRI
				},
				[2] = {
					CS = "CRO13",
					SUB = "13",
					TEAM = true,
					PRI = true
				}
			}
		},
		Preset3 = { -- Can add and remove Preset1 thru Preset10 as desired
			UNIT_ID = "TACTICAL", -- Max 8 char
			CALLSIGN = "TACT3", -- Max 5 char
			VHF = "132.75",
			UHF = "243.75",
			UHF_Cipher = false,
			UHF_CNV = "1",
			FM1 = "32.9",
			FM1_Cipher = false,
			FM1_CNV = "2",
			FM2 = "36.25",
			FM2_Cipher = false,
			FM2_CNV = "3",
			PRI_FREQ = "FM1",
			deleteExistingNET = true
		},
		Preset4 = { -- Can add and remove Preset1 thru Preset10 as desired
			UNIT_ID = "ALPHA", -- Max 8 char
			CALLSIGN = "ALPHA", -- Max 5 char
			VHF = "126.1",
			UHF = "237",
			UHF_Cipher = false,
			UHF_CNV = "1",
			FM1 = "32.9",
			FM1_Cipher = false,
			FM1_CNV = "2",
			FM2 = "36.25",
			FM2_Cipher = false,
			FM2_CNV = "3",
			PRI_FREQ = "FM2",
			deleteExistingNET = true
		},
		XPNDR = {
			Mode1 = "01", -- must be 2 char
			Mode3 = "3001", -- must be 4 char
			Mode4 = true
		},
		DL = {
			CALLSIGN = "CRO11", -- lower limit 3 char / upper limit 5 char
			ORIG_ID = "11" -- lower limit 1 char / upper limit 2 char
		},
		HF = "3.5" -- Setting through preset is currently broken on ED's end; this gets set through MAN subpage
	},
	AC = {
		FLT = {
			HI = "500", -- 0 to 1428
			LO = "25", -- 0 to 1428
			DIST_UNIT = "KM", -- OR NM
			RDR_ALT = true,
			PRESSURE = "2992", -- (no "."[decimal]) IN: lower limit 2810 / upper limit 3099 -- MB: 9515 lower limit / 10494 upper limit
			PRES_UNIT = "IN" -- or MB
		},
		PERF = {
			MAX = {
				PA = "5000", -- lower limit -2300 / upper limit 20000
				FAT = "20", -- lower limit -60 / upper limit 60
				GWT = "19000" -- lower limit 10000 / upper limit 25000
			},
			PLAN = {
				PA = "3000", -- lower limit -2300 / upper limit 20000
				FAT = "15", -- lower limit -60 / upper limit 60
				GWT = "17000" -- lower limit 10000 / upper limit 25000
			}
		}
	},
	TSD = {
		WAYPOINTS = { -- if any field is non-existent for the given point, it accepts the default.
			[1] = {
				IDENT = "SP",
				-- FREE = "", -- MAX 3, MIN 0
				MGRS = "40RCP52150150",
				-- ALT = ""
			},
			[2] = {
				IDENT = "WP",
				-- FREE = "", -- MAX 3, MIN 0
				MGRS = "40RCP98064055",
				-- ALT = ""
			}
		},
		CONTROLMEASURES = {
			[1] = {
				IDENT = "HA",
				-- FREE = "EWR", -- MAX 3, MIN 0
				MGRS = "40RDP06544747",
				-- ALT = ""
			},
			[2] = {
				IDENT = "BP",
				FREE = "BP1", -- MAX 3, MIN 0
				MGRS = "40RDP08776135",
				-- ALT = ""
			},
			[3] = {
				IDENT = "BP",
				FREE = "BP2", -- MAX 3, MIN 0
				MGRS = "40RDP11616752",
				-- ALT = ""
			},
			[4] = {
				IDENT = "BP",
				FREE = "BP3", -- MAX 3, MIN 0
				MGRS = "40RDP19187454",
				-- ALT = ""
			},
			[5] = {
				IDENT = "BP",
				FREE = "BP4", -- MAX 3, MIN 0
				MGRS = "40RDP17017965",
				-- ALT = ""
			},
			[6] = {
				IDENT = "BP",
				FREE = "BP5", -- MAX 3, MIN 0
				MGRS = "40RDP17468519",
				-- ALT = ""
			},
			[7] = {
				IDENT = "F1",
				FREE = "T1W", -- MAX 3, MIN 0
				MGRS = "40RDP06995304",
				-- ALT = ""
			},
			[8] = {
				IDENT = "F1",
				FREE = "T2W", -- MAX 3, MIN 0
				MGRS = "40RCP97365401",
				-- ALT = ""
			},
			[9] = {
				IDENT = "F1",
				FREE = "T3W", -- MAX 3, MIN 0
				MGRS = "40RDP11085617",
				-- ALT = ""
			},
			[10] = {
				IDENT = "F1",
				FREE = "T4W", -- MAX 3, MIN 0
				MGRS = "40RDP01926082",
				-- ALT = ""
			},
			[11] = {
				IDENT = "F1",
				FREE = "T5W", -- MAX 3, MIN 0
				MGRS = "40RDP05646836",
				-- ALT = ""
			},
			[12] = {
				IDENT = "F1",
				FREE = "T6W", -- MAX 3, MIN 0
				MGRS = "40RDP19677212",
				-- ALT = ""
			},
			[13] = {
				IDENT = "F1",
				FREE = "T7W", -- MAX 3, MIN 0
				MGRS = "40RDP09607967",
				-- ALT = ""
			},
			[14] = {
				IDENT = "F1",
				FREE = "T8W", -- MAX 3, MIN 0
				MGRS = "40RDP09988448",
				-- ALT = ""
			},
			[15] = {
				IDENT = "F1",
				FREE = "T9W", -- MAX 3, MIN 0
				MGRS = "40RDP13648772",
				-- ALT = ""
			},
			[16] = {
				IDENT = "F1",
				FREE = "T1E", -- MAX 3, MIN 0
				MGRS = "40RDP22196041",
				-- ALT = ""
			},
			[17] = {
				IDENT = "F1",
				FREE = "T6E", -- MAX 3, MIN 0
				MGRS = "40RDP33768139",
				-- ALT = ""
			},
			[18] = {
				IDENT = "F1",
				FREE = "T7E", -- MAX 3, MIN 0
				MGRS = "40RDP25778590",
				-- ALT = ""
			}
		},
		ROUTES = { -- NOTE: Skips CHARLIE, FOX, GOLF, JULIET, KILO, MIKE, NOVEMBER, PAPA, QUEBEC, SIERRA; Starts at ALPHA, stops at TANGO
			ALPHA = { -- Available routes are: A, B, D, E, H, I, L, O, R, T
				[1] = "W01", -- There is currently no input validation for this. The user must ensure these are points that do (or will) exist in the TSD
				[2] = "W02",
				[3] = "C51",
				[4] = "C57",
				[5] = "C59",
				[6] = "C52",
				[7] = "C53",
				[8] = "C54"
			},
			BRAVO = {
				[1] = "W01",
				[2] = "W02",
				[3] = "C51",
				[4] = "C57",
				[5] = "C59",
				[6] = "C52",
				[7] = "C53"
			}
		},
		SETTINGS = {
			MAP = {
				TYPE = "DIG", -- DIG / CHART / SAT / STICK
				COLOR_BAND = "AC", -- AC / ELEV / NONE
				ORIENT = "TRK_UP", -- HDG_UP / TRK_UP / N_UP
				CTR = true, -- (Center TSD on A/C)
				GRID = true,
			},
			SHOW = {
				ATK = {
					HSI = true,
					ENDR = true,
					WIND = true,
					CURRENT_ROUTE = true,
					INACTIVE_ZONES = true,
					FCR_TGTS_OBSTACLES = true,
					CPG_CURSOR = false,
					CURSOR_INFO = false,
					THREAT_SHOW = {
						ASE_THREATS = true,
						ACQ = true,
						TRN_PT = false,
						FCR_RFI = true,
						THREATS = false,
						TARGETS = false
					},
					COORD_SHOW = {
						CONTROL_MEASURES = true,
						FRIENDLY_UNITS = false,
						ENEMY_UNITS = false,
						PLANNED_TGTS_THREATS = false,
					}
				},
				NAV = {
					HSI = true,
					ENDR = true,
					WIND = true,
					WP_DATA = true,
					INACTIVE_ZONES = false,
					OBSTACLES = true,
					CPG_CURSOR = false,
					CURSOR_INFO = false,
					THREAT_SHOW = {
						ASE_THREATS = true,
						ACQ = true,
						TRN_PT = false,
						FCR_RFI = true,
						THREATS = false,
						TARGETS = false
					},
					COORD_SHOW = {
						CONTROL_MEASURES = true,
						FRIENDLY_UNITS = false,
						ENEMY_UNITS = false,
						PLANNED_TGTS_THREATS = false,
					}
				}
			},
			DEFAULT_PHASE = "NAV" -- What phase you want the TSD on by default?
		},
		deleteExisting = true -- This is for deleting all existing COORD from TSD
	},
	WPN = {
		FREQ = { -- A thru R (excluding I and O)
			A = "1511",
			B = "1512",
			C = "1513",
			D = "1514"
		},
		CHANNEL = { -- there's only 4 channels, don't go adding more like a goof.
			[1] = "A",
			[2] = "B",
			[3] = "C",
			[4] = "D"
		},
		LRFD = "A",
		LST = "B"
	}
}

-- 29 = KU_PLT, 30 = KU_CPG, 42 = PLT_LEFT_MPD, 43 = PLT_RIGHT_MPD, 44 = CPG_LEFT_MPD, 45 = CPG_RIGHT_MPD
function ApacheDTU.ah64()
	local _seat = get_param_handle("SEAT"):get()
	local _T1_L = nil -- Left MPD T1
	local _T1_R = nil -- Right MPD T1

	if _seat == 0 then -- PLT
		_indicators.leftMPD = ApacheDTU.getListIndicatorValue(6)
		_indicators.rightMPD = ApacheDTU.getListIndicatorValue(8)
		_indicators.KU = ApacheDTU.getListIndicatorValue(15)
		_T1_L = GetDevice(0):get_argument_value(20)
		_T1_R = GetDevice(0):get_argument_value(54)
		_devices.KU = 29
		_devices.leftMPD = 42
		_devices.rightMPD = 43
	else -- CPG
		_indicators.leftMPD = ApacheDTU.getListIndicatorValue(10)
		_indicators.rightMPD = ApacheDTU.getListIndicatorValue(12)
		_indicators.KU = ApacheDTU.getListIndicatorValue(14)
		_T1_L = GetDevice(0):get_argument_value(88)
		_T1_R = GetDevice(0):get_argument_value(122)
		_devices.KU = 30
		_devices.leftMPD = 44
		_devices.rightMPD = 45
	end

	if _indicators.leftMPD["PB1_1"] == "DTU" then
		if _T1_L > 0 and ApacheDTU.dataReady and _indicators.KU["Standby_text"] == "SAVE" then
			ApacheDTU.dataSaveCoroutine = coroutine.create(ApacheDTU.SaveDTC)
		end

		if _T1_L > 0 and ApacheDTU.dataReady and _indicators.KU["Standby_text"] == "LOAD" then
			ApacheDTU.dataReady = false
			ApacheDTU.dataLoadCoroutine = coroutine.create(ApacheDTU.LoadDTC)
		end
	end

	if _indicators.rightMPD["PB1_1"] == "DTU" then
		if _T1_R > 0 and ApacheDTU.dataReady and _indicators.KU["Standby_text"] == "SAVE" then
			ApacheDTU.dataSaveCoroutine = coroutine.create(ApacheDTU.SaveDTC)
		end

		if _T1_R > 0 and ApacheDTU.dataReady and _indicators.KU["Standby_text"] == "LOAD" then
			ApacheDTU.dataReady = false
			ApacheDTU.dataLoadCoroutine = coroutine.create(ApacheDTU.LoadDTC)
		end
	end

	-- COROUTINE HANDLER
	if ApacheDTU.dataLoadCoroutine ~= nil then
		if coroutine.status(ApacheDTU.dataLoadCoroutine) ~= "dead" then
			coroutine.resume(ApacheDTU.dataLoadCoroutine)
		end
	end

	if ApacheDTU.dataSaveCoroutine ~= nil then
		if coroutine.status(ApacheDTU.dataSaveCoroutine) ~= "dead" then
			coroutine.resume(ApacheDTU.dataSaveCoroutine)
		end
	end
	-- COROUTINE HANDLER
end

function ApacheDTU.LoadDTC()
	--
	dtc = io.open(lfs.writedir() .. [[Mods\Services\DCS-Apache-DTU\DTC\DTC.json]], "r")

	if dtc then
		--
		DTU = ApacheDTU.JSON:decode(dtc:read())
		dtc:close()
		ApacheDTU.CycleButton("CLR", _devices.KU, _mapKU) -- CLR KU (Would currently say "LOAD")

		if next(DTU) ~= nil then -- Check DTC.json actually has something in it
			if DTU.COM then
				ApacheDTU.Load_COM()
			end

			if DTU.AC then
				ApacheDTU.Load_AC()
			end

			if DTU.TSD then
				ApacheDTU.Load_TSD()
			end

			if DTU.WPN then
				ApacheDTU.Load_WPN()
			end

			ApacheDTU.KU_Data_Enter("1LOAD COMPLETE")
			ApacheDTU.CycleButton("AC", _devices.leftMPD, _mapMPD)
			ApacheDTU.CycleButton("TSD", _devices.rightMPD, _mapMPD)
		else
			ApacheDTU.KU_Data_Enter("NO DTC DATA")
		end
	else
		ApacheDTU.KU_Data_Enter("NO DTC.JSON")
	end

	ApacheDTU.dataReady = true -- Let the user perform another action if they want
	--
end

function ApacheDTU.Load_WPN()
	local _mapSlot = { -- The "where the hell am I going" table
		A = "L1", B = "L2", C = "L3", D = "L4", E = "L5", F = "L6",
		G = "B2", H = "B3", J = "B4", K = "B5",
		R = "R1", Q = "R2", P = "R3", N = "R4", M = "R5", L = "R6"
	}

	ApacheDTU.CycleButton("WPN", _devices.leftMPD, _mapMPD) -- WPN
	if DTU.WPN.FREQ then
		ApacheDTU.CycleButton("T4", _devices.leftMPD, _mapMPD) -- CODE
		ApacheDTU.CycleButton("T5", _devices.leftMPD, _mapMPD) -- FREQ
		for slot,freq in pairs(DTU.WPN.FREQ) do
			local slotByte = slot:byte()
			if slotByte >= 65 and slotByte <= 82 and slotByte ~= 73 and slotByte ~= 79 then -- valid slot?
				ApacheDTU.log("Verified slot.")
				if ApacheDTU.Validate_PRF(tonumber(freq)) then -- valid freq?
					ApacheDTU.log("Validated PRF")
					ApacheDTU.CycleButton(_mapSlot[slot], _devices.leftMPD, _mapMPD) -- Select appropriate slot in FREQ table
					ApacheDTU.KU_Data_Enter(freq)
				end
			end
		end
	end

	if DTU.WPN.CHANNEL then
		ApacheDTU.CycleButton("T1", _devices.leftMPD, _mapMPD) -- CHAN

		for chan,slot in ipairs(DTU.WPN.CHANNEL) do
			if chan > 4 then
				break -- "Someone" added too many channels, there's only 4
			end
			local channelBtn = chan + 1 -- T2 thru T5

			ApacheDTU.CycleButton("T"..channelBtn, _devices.leftMPD, _mapMPD) -- Select appropriate channel
			ApacheDTU.CycleButton(_mapSlot[slot], _devices.leftMPD, _mapMPD) -- Select desired slot/prf for this channel
		end
	end

	if DTU.WPN.LRFD then
		ApacheDTU.CycleButton("WPN", _devices.leftMPD, _mapMPD) -- WPN
		ApacheDTU.CycleButton("T4", _devices.leftMPD, _mapMPD) -- CODE
		if _indicators.leftMPD["PB2_11"] ~= "LRFD" then -- PB2_11
			ApacheDTU.CycleButton("T2", _devices.leftMPD, _mapMPD) -- Get us to LRFD
		end
		ApacheDTU.CycleButton(_mapSlot[DTU.WPN.LRFD], _devices.leftMPD, _mapMPD) -- Select appropriate channel for LRFD
	end

	if DTU.WPN.LST then
		ApacheDTU.CycleButton("WPN", _devices.leftMPD, _mapMPD) -- WPN
		ApacheDTU.CycleButton("T4", _devices.leftMPD, _mapMPD) -- CODE
		if _indicators.leftMPD["PB2_11"] ~= "LST" then -- PB2_11
			ApacheDTU.CycleButton("T2", _devices.leftMPD, _mapMPD) -- Get us to LST
		end
		ApacheDTU.CycleButton(_mapSlot[DTU.WPN.LST], _devices.leftMPD, _mapMPD) -- Select appropriate channel for LST
	end
end

function ApacheDTU.Validate_PRF(_prf)
	-- There's probably a better way to accomplish this, but someone with more smarts will need to come along (and care enough)
	if _prf >= 1111 and _prf <= 5888 then
		if _prf <= 1788 then
			return true
		elseif _prf >= 2111 and _prf <= 2888 then
			return true
		elseif _prf >= 4111 and _prf <= 4288 or _prf >= 4311 and _prf <= 4488 or _prf >= 4511 and _prf <= 4688 or _prf >= 4711 and _prf <= 4888 then
			return true
		elseif _prf >= 5111 and _prf <= 5288 or _prf >= 5311 and _prf <= 5488 or _prf >= 5511 and _prf <= 5688 or _prf >= 5711 and _prf <= 5888 then
			return true
		else
			return false
		end
	else
		return false
	end

	-- local _prfValidity = {
	-- 	[1] = 1111, [2] = 1788, [3] = 2111, [4] = 2888,
	-- 	[5] = 4311, [6] = 4488, [7] = 4511, [8] = 4688,
	-- 	[9] = 4711, [10] = 4888, [11] = 5111, [12] = 5288,
	-- 	[13] = 5311, [14] = 5488, [15] = 5511, [16] = 5688,
	-- 	[17] = 5711, [18] = 5888
	-- } -- I was going to loop through this table to verify range... but(t) fuck it.
	-- Basically, iterate through the table and on every i%2==0 check the PRF is within that range...
	-- if it hits the end of the table, it's definitely not in range.
end

function ApacheDTU.Load_TSD()
	--
	if DTU.TSD.deleteExisting then
		ApacheDTU.CycleButton("TSD", _devices.rightMPD, _mapMPD) -- TSD page
		ApacheDTU.CycleButton("B6", _devices.rightMPD, _mapMPD) -- POINT
		while _indicators.rightMPD["PB24_27"] ~= "?" do -- Keep going until POINT reads "?" (indicating no existing points)
			ApacheDTU.CycleButton("L4", _devices.rightMPD, _mapMPD) -- DEL
			ApacheDTU.CycleButton("L3", _devices.rightMPD, _mapMPD) -- YES
			ApacheDTU.CycleButton("B6", _devices.rightMPD, _mapMPD) -- POINT (exit) (REFRESH)
			ApacheDTU.CycleButton("B6", _devices.rightMPD, _mapMPD) -- POINT (entry) (REFRESH)
		end
	end

	if DTU.TSD.WAYPOINTS then
		ApacheDTU.Enter_TSD_Points(DTU.TSD.WAYPOINTS, "WP")
	end

	if DTU.TSD.CONTROLMEASURES then
		ApacheDTU.Enter_TSD_Points(DTU.TSD.CONTROLMEASURES, "CM")
	end

	if DTU.TSD.TARGETS then
		ApacheDTU.Enter_TSD_Points(DTU.TSD.TARGETS, "TG")
	end

	if DTU.TSD.ROUTES then
		local _mapRTE = {
			A = "T1",	B = "T2",	D = "T3",	E = "T4",	H = "T5",
			I = "T1",	L = "T2",	O = "T3",	R = "T4",	T = "T5"
		}

		ApacheDTU.CycleButton("TSD", _devices.rightMPD, _mapMPD) -- TSD
		ApacheDTU.CycleButton("B5", _devices.rightMPD, _mapMPD) -- RTE
		for key,route in pairs(DTU.TSD.ROUTES) do
			local firstLetterRTE = key:sub(1,1)
			-- TODO: Need to add check to make sure user hasn't input a route name such as "C/F/G/J/K/L/M/N/P/Q/S" that doesn't exist.
			if firstLetterRTE ~= _indicators.rightMPD["LABEL 1"] then -- Correct RTE currently selected?
				-- Need to select correct route
				ApacheDTU.CycleButton("B6", _devices.rightMPD, _mapMPD) -- RTM
				if firstLetterRTE:byte() > 72 then -- next page?
					ApacheDTU.CycleButton("B3", _devices.rightMPD, _mapMPD) -- Page 2
				end
				ApacheDTU.CycleButton(_mapRTE[firstLetterRTE], _devices.rightMPD, _mapMPD) -- Select correct RTE
				ApacheDTU.CycleButton("B6", _devices.rightMPD, _mapMPD) -- RTM (Get out)
			end

			ApacheDTU.CycleButton("L2", _devices.rightMPD, _mapMPD) -- ADD
			for i,point in ipairs(route) do -- Adding points to RTE
				local btn = 6 - i
				ApacheDTU.CycleButton("L1", _devices.rightMPD, _mapMPD) -- POINT
				ApacheDTU.KU_Data_Enter(point) -- Whichever point
				if btn < 2 then -- need to scroll up
					ApacheDTU.CycleButton("R1", _devices.rightMPD, _mapMPD) -- Scroll up
					ApacheDTU.CycleButton("R2", _devices.rightMPD, _mapMPD) -- Add to RTE
				else
					ApacheDTU.CycleButton("R"..btn, _devices.rightMPD, _mapMPD) -- Add to RTE
				end
			end
		end
	end

	if DTU.TSD.SETTINGS then
		local setting = DTU.TSD.SETTINGS
		if setting.MAP then
			ApacheDTU.CycleButton("TSD", _devices.rightMPD, _mapMPD) -- TSD
			ApacheDTU.CycleButton("B4", _devices.rightMPD, _mapMPD) -- MAP

			if setting.MAP.TYPE then
				local _mapType = {
					DIG = "L2", CHART = "L3", SAT = "L4", STICK = "L5"
				}
				ApacheDTU.CycleButton("L2", _devices.rightMPD, _mapMPD) -- TYPE
				ApacheDTU.CycleButton(_mapType[setting.MAP.TYPE], _devices.rightMPD, _mapMPD) -- Select appropriate map type from submenu
			end

			if setting.MAP.COLOR_BAND and setting.MAP.TYPE == "DIG" then -- Color band only works on DIG
				local _mapColorBand = {
					AC = "L3", ELEV = "L4", NONE = "L5"
				}
				ApacheDTU.CycleButton("L4", _devices.rightMPD, _mapMPD) -- COLOR BAND
				ApacheDTU.CycleButton(_mapColorBand[setting.MAP.COLOR_BAND], _devices.rightMPD, _mapMPD) -- Select appropriate color band from submenu
			end

			if setting.MAP.ORIENT then
				local _mapOrient = {
					HDG_UP = "R4", TRK_UP = "R5", N_UP = "R6"
				}
				ApacheDTU.CycleButton("R5", _devices.rightMPD, _mapMPD) -- ORIENT
				ApacheDTU.CycleButton(_mapOrient[setting.MAP.ORIENT], _devices.rightMPD, _mapMPD) -- Select appropriate orientation from submenu
			end

			ApacheDTU.CycleArg(setting.MAP.CTR, _indicators.rightMPD, "PB9_1_b", "R3", _devices.rightMPD, _mapMPD)
			ApacheDTU.CycleArg(setting.MAP.GRID, _indicators.rightMPD, "PB5_23_b", "T5", _devices.rightMPD, _mapMPD)
			ApacheDTU.CycleButton("B4", _devices.rightMPD, _mapMPD) -- MAP (exit)
		end

		if setting.SHOW then
			if setting.SHOW.ATK then
				ApacheDTU.CycleButton("TSD", _devices.rightMPD, _mapMPD) -- TSD
				ApacheDTU.CycleButton("T3", _devices.rightMPD, _mapMPD) -- SHOW

				if _indicators.rightMPD["PB17_21"] ~= "ATK" then
					ApacheDTU.CycleButton("B2", _devices.rightMPD, _mapMPD) -- PHASE
				end
				ApacheDTU.CycleArg(setting.SHOW.ATK.HSI, _indicators.rightMPD, "PB10_23_b", "R4", _devices.rightMPD, _mapMPD) -- HSI
				ApacheDTU.CycleArg(setting.SHOW.ATK.ENDR, _indicators.rightMPD, "PB11_25_b", "R5", _devices.rightMPD, _mapMPD) -- ENDR
				ApacheDTU.CycleArg(setting.SHOW.ATK.WIND, _indicators.rightMPD, "PB12_27_b", "R6", _devices.rightMPD, _mapMPD) -- WIND
				ApacheDTU.CycleArg(setting.SHOW.ATK.CURRENT_ROUTE, _indicators.rightMPD, "PB23_11_b", "L2", _devices.rightMPD, _mapMPD) -- CURRENT ROUTES
				ApacheDTU.CycleArg(setting.SHOW.ATK.INACTIVE_ZONES, _indicators.rightMPD, "PB22_13_b", "L3", _devices.rightMPD, _mapMPD) -- INACTIVE ZONES
				ApacheDTU.CycleArg(setting.SHOW.ATK.FCR_TGTS_OBSTACLES, _indicators.rightMPD, "PB21_31_b", "L4", _devices.rightMPD, _mapMPD) -- FCR TGTS/OBSTACLES
				ApacheDTU.CycleArg(setting.SHOW.ATK.CPG_CURSOR, _indicators.rightMPD, "PB20_15_b", "L5", _devices.rightMPD, _mapMPD) -- CPG CURSOR
				ApacheDTU.CycleArg(setting.SHOW.ATK.CURSOR_INFO, _indicators.rightMPD, "PB19_17_b", "L6", _devices.rightMPD, _mapMPD) -- CURSOR INFO

				if setting.SHOW.ATK.THREAT_SHOW then
					ApacheDTU.CycleButton("T5", _devices.rightMPD, _mapMPD) -- THRT SHOW subpage
					ApacheDTU.CycleArg(setting.SHOW.ATK.THREAT_SHOW.ASE_THREATS, _indicators.rightMPD, "PB23_15_b", "L2", _devices.rightMPD, _mapMPD) -- ASE THREATS
					ApacheDTU.CycleArg(setting.SHOW.ATK.THREAT_SHOW.ACQ, _indicators.rightMPD, "PB8_37_b", "R2", _devices.rightMPD, _mapMPD) -- ACQ
					ApacheDTU.CycleArg(setting.SHOW.ATK.THREAT_SHOW.TRN_PT, _indicators.rightMPD, "PB9_39_b", "R3", _devices.rightMPD, _mapMPD) -- TRN PT
					ApacheDTU.CycleArg(setting.SHOW.ATK.THREAT_SHOW.FCR_RFI, _indicators.rightMPD, "PB10_41_b", "R4", _devices.rightMPD, _mapMPD) -- FCR RFI
					ApacheDTU.CycleArg(setting.SHOW.ATK.THREAT_SHOW.THREATS, _indicators.rightMPD, "PB11_43_b", "R5", _devices.rightMPD, _mapMPD) -- THREATS
					ApacheDTU.CycleArg(setting.SHOW.ATK.THREAT_SHOW.TARGETS, _indicators.rightMPD, "PB12_45_b", "R6", _devices.rightMPD, _mapMPD) -- TARGETS
				end

				if setting.SHOW.ATK.COORD_SHOW then
					ApacheDTU.CycleButton("T6", _devices.rightMPD, _mapMPD) -- COORD SHOW subpage
					ApacheDTU.CycleArg(setting.SHOW.ATK.COORD_SHOW.CONTROL_MEASURES, _indicators.rightMPD, "PB23_11_b", "L2", _devices.rightMPD, _mapMPD) -- CONTROL MEASURES
					ApacheDTU.CycleArg(setting.SHOW.ATK.COORD_SHOW.FRIENDLY_UNITS, _indicators.rightMPD, "PB22_13_b", "L3", _devices.rightMPD, _mapMPD) -- FRIENDLY UNITS
					ApacheDTU.CycleArg(setting.SHOW.ATK.COORD_SHOW.ENEMY_UNITS, _indicators.rightMPD, "PB21_15_b", "L4", _devices.rightMPD, _mapMPD) -- ENEMY UNITS
					ApacheDTU.CycleArg(setting.SHOW.ATK.COORD_SHOW.PLANNED_TGTS_THREATS, _indicators.rightMPD, "PB20_17_b", "L5", _devices.rightMPD, _mapMPD) -- PLANNED TGTS/THREATS
				end
			end

			if setting.SHOW.NAV then
				ApacheDTU.CycleButton("TSD", _devices.rightMPD, _mapMPD) -- TSD
				ApacheDTU.CycleButton("T3", _devices.rightMPD, _mapMPD) -- SHOW

				if _indicators.rightMPD["PB17_21"] ~= "NAV" then
					ApacheDTU.CycleButton("B2", _devices.rightMPD, _mapMPD) -- PHASE
				end

				ApacheDTU.CycleArg(setting.SHOW.NAV.HSI, _indicators.rightMPD, "PB10_23_b", "R4", _devices.rightMPD, _mapMPD) -- HSI
				ApacheDTU.CycleArg(setting.SHOW.NAV.ENDR, _indicators.rightMPD, "PB11_25_b", "R5", _devices.rightMPD, _mapMPD) -- ENDR
				ApacheDTU.CycleArg(setting.SHOW.NAV.WIND, _indicators.rightMPD, "PB12_27_b", "R6", _devices.rightMPD, _mapMPD) -- WIND
				ApacheDTU.CycleArg(setting.SHOW.NAV.WP_DATA, _indicators.rightMPD, "PB23_9_b", "L2", _devices.rightMPD, _mapMPD) -- WAYPOINT DATA
				ApacheDTU.CycleArg(setting.SHOW.NAV.INACTIVE_ZONES, _indicators.rightMPD, "PB22_13_b", "L3", _devices.rightMPD, _mapMPD) -- INACTIVE ZONES
				ApacheDTU.CycleArg(setting.SHOW.NAV.OBSTACLES, _indicators.rightMPD, "PB21_29_b", "L4", _devices.rightMPD, _mapMPD) -- OBSTACLES
				ApacheDTU.CycleArg(setting.SHOW.NAV.CPG_CURSOR, _indicators.rightMPD, "PB20_15_b", "L5", _devices.rightMPD, _mapMPD) -- CPG CURSOR
				ApacheDTU.CycleArg(setting.SHOW.NAV.CURSOR_INFO, _indicators.rightMPD, "PB19_17_b", "L6", _devices.rightMPD, _mapMPD) -- CURSOR INFO

				if setting.SHOW.NAV.THREAT_SHOW then
					ApacheDTU.CycleButton("T5", _devices.rightMPD, _mapMPD) -- THRT SHOW subpage
					ApacheDTU.CycleArg(setting.SHOW.NAV.THREAT_SHOW.ASE_THREATS, _indicators.rightMPD, "PB23_15_b", "L2", _devices.rightMPD, _mapMPD) -- ASE THREATS
					ApacheDTU.CycleArg(setting.SHOW.NAV.THREAT_SHOW.ACQ, _indicators.rightMPD, "PB8_37_b", "R2", _devices.rightMPD, _mapMPD) -- ACQ
					ApacheDTU.CycleArg(setting.SHOW.NAV.THREAT_SHOW.TRN_PT, _indicators.rightMPD, "PB9_39_b", "R3", _devices.rightMPD, _mapMPD) -- TRN PT
					ApacheDTU.CycleArg(setting.SHOW.NAV.THREAT_SHOW.FCR_RFI, _indicators.rightMPD, "PB10_41_b", "R4", _devices.rightMPD, _mapMPD) -- FCR RFI
					ApacheDTU.CycleArg(setting.SHOW.NAV.THREAT_SHOW.THREATS, _indicators.rightMPD, "PB11_43_b", "R5", _devices.rightMPD, _mapMPD) -- THREATS
					ApacheDTU.CycleArg(setting.SHOW.NAV.THREAT_SHOW.TARGETS, _indicators.rightMPD, "PB12_45_b", "R6", _devices.rightMPD, _mapMPD) -- TARGETS
				end

				if setting.SHOW.NAV.COORD_SHOW then
					ApacheDTU.CycleButton("T6", _devices.rightMPD, _mapMPD) -- COORD SHOW subpage
					ApacheDTU.CycleArg(setting.SHOW.NAV.COORD_SHOW.CONTROL_MEASURES, _indicators.rightMPD, "PB23_11_b", "L2", _devices.rightMPD, _mapMPD) -- CONTROL MEASURES
					ApacheDTU.CycleArg(setting.SHOW.NAV.COORD_SHOW.FRIENDLY_UNITS, _indicators.rightMPD, "PB22_13_b", "L3", _devices.rightMPD, _mapMPD) -- FRIENDLY UNITS
					ApacheDTU.CycleArg(setting.SHOW.NAV.COORD_SHOW.ENEMY_UNITS, _indicators.rightMPD, "PB21_15_b", "L4", _devices.rightMPD, _mapMPD) -- ENEMY UNITS
					ApacheDTU.CycleArg(setting.SHOW.NAV.COORD_SHOW.PLANNED_TGTS_THREATS, _indicators.rightMPD, "PB20_17_b", "L5", _devices.rightMPD, _mapMPD) -- PLANNED TGTS/THREATS
				end
			end
		end
		if setting.DEFAULT_PHASE then
			ApacheDTU.CycleButton("TSD", _devices.rightMPD, _mapMPD) -- TSD
			if _indicators.rightMPD["PB17_19"] ~= setting.DEFAULT_PHASE then
				ApacheDTU.CycleButton("B2", _devices.rightMPD, _mapMPD) -- PHASE btn (cycle to opposite)
			end
		end
	end
end

function ApacheDTU.Load_AC()
	ApacheDTU.CycleButton("AC", _devices.rightMPD, _mapMPD) -- AC page

	if DTU.AC.FLT then
		ApacheDTU.CycleButton("T2", _devices.rightMPD, _mapMPD) -- FLT page
		ApacheDTU.CycleButton("B6", _devices.rightMPD, _mapMPD) -- SET page

		if DTU.AC.FLT.HI then
			local HI_num = tonumber(DTU.AC.FLT.HI) -- Honestly, such a minor performance impact that it doesn't matter... but I care.
			if HI_num > 0 and HI_num <= 1428 then -- 0 to 1428 is the acceptable range
				ApacheDTU.CycleButton("T1", _devices.rightMPD, _mapMPD) -- HI select
				ApacheDTU.KU_Data_Enter(DTU.AC.FLT.HI) -- Enter HI data
			end
		end

		if DTU.AC.FLT.LO then
			local LO_num = tonumber(DTU.AC.FLT.LO)
			if LO_num > 0 and LO_num <= 1428 then -- 0 to 1428 is the acceptable range
				ApacheDTU.CycleButton("T3", _devices.rightMPD, _mapMPD) -- LO select
				ApacheDTU.KU_Data_Enter(DTU.AC.FLT.LO) -- Enter LO data
			end
		end

		if DTU.AC.FLT.DIST_UNIT then
			if _indicators.rightMPD["PB17_23"] ~= DTU.AC.FLT.DIST_UNIT then
				ApacheDTU.CycleButton("B2", _devices.rightMPD, _mapMPD) -- Cycle to opposite distance selection
			end
		end

		if DTU.AC.FLT.PRES_UNIT then
			if _indicators.rightMPD["PB4_11"] ~= DTU.AC.FLT.PRES_UNIT then
				ApacheDTU.CycleButton("T4", _devices.rightMPD, _mapMPD) -- Cycle to opposite pressure selection
			end
		end

		if DTU.AC.FLT.PRESSURE then
			local PRESSURE_num = tonumber(DTU.AC.FLT.PRESSURE)
			if _indicators.rightMPD["PB4_11"] == "MB" then
				if PRESSURE_num >= 9515 and PRESSURE_num <= 10494 then -- is the user input within range?
					ApacheDTU.CycleButton("T6", _devices.rightMPD, _mapMPD) -- PRES select
					ApacheDTU.KU_Data_Enter(DTU.AC.FLT.PRESSURE) -- Enter PRES data
				end
			else -- IN
				if PRESSURE_num >= 2810 and PRESSURE_num <= 3099 then -- is the user input within range?
					ApacheDTU.CycleButton("T6", _devices.rightMPD, _mapMPD) -- PRES select
					ApacheDTU.KU_Data_Enter(DTU.AC.FLT.PRESSURE) -- Enter PRES data
				end
			end
		end

		if DTU.AC.FLT.RDR_ALT ~= nil then -- Need this extra step because it's a true/false value; nil would normally turn off RDR ALT if it's on, which is not desired behavior.
			if DTU.AC.FLT.RDR_ALT then
				if _indicators.rightMPD["PB12_25"] ~= "RDR ALT{" then
					ApacheDTU.CycleButton("R6", _devices.rightMPD, _mapMPD) -- Cycle RDR ALT opposite selection
				end
			else
				if _indicators.rightMPD["PB12_25"] ~= "RDR ALT}" then
					ApacheDTU.CycleButton("R6", _devices.rightMPD, _mapMPD) -- Cycle RDR ALT opposite selection
				end
			end
		end
	end

	if DTU.AC.PERF then
		ApacheDTU.CycleButton("AC", _devices.rightMPD, _mapMPD) -- AC page
		ApacheDTU.CycleButton("T4", _devices.rightMPD, _mapMPD) -- PERF page

		for page,perfSetting in pairs(DTU.AC.PERF) do
			--
			if page == "MAX" then
				ApacheDTU.CycleButton("B3", _devices.rightMPD, _mapMPD) -- MAX subpage
			else -- PLAN
				ApacheDTU.CycleButton("B4", _devices.rightMPD, _mapMPD) -- PLAN page
			end

			if perfSetting.PA then
				local PA_num = tonumber(perfSetting.PA)
				if PA_num >= -2300 and PA_num <= 20000 then -- in range?
					ApacheDTU.CycleButton("L1", _devices.rightMPD, _mapMPD) -- PA select
					ApacheDTU.KU_Data_Enter(perfSetting.PA) -- Enter PA data
				end
			end

			if perfSetting.FAT then
				local FAT_num = tonumber(perfSetting.FAT)
				if FAT_num >= -60 and FAT_num <= 60 then -- in range?
					ApacheDTU.CycleButton("L2", _devices.rightMPD, _mapMPD) -- FAT select
					ApacheDTU.KU_Data_Enter(perfSetting.FAT) -- Enter FAT data
				end
			end

			if perfSetting.GWT then
				local GWT_num = tonumber(perfSetting.GWT)
				if GWT_num >= 10000 and GWT_num <= 25000 then -- in range?
					ApacheDTU.CycleButton("L3", _devices.rightMPD, _mapMPD) -- GWT select
					ApacheDTU.KU_Data_Enter(perfSetting.GWT) -- Enter GWT data
				end
			end
			--
		end
	end
end

function ApacheDTU.Load_COM()
	for k,preset in pairs(DTU.COM) do
		if k:find("Preset") then
			ApacheDTU.CycleButton("COM", _devices.leftMPD, _mapMPD) -- COM Page

			local k_str = k:sub(7,-1)
			local k_num = tonumber(k_str) -- remove "Preset" to determine L1 thru L5 or R1 thru R5
			local presetBtn = nil
			if k_num <= 5 then
				presetBtn = "L" .. k_str
			else
				presetBtn = "R" .. tostring(k_num-5)
			end

			ApacheDTU.CycleButton(presetBtn, _devices.leftMPD, _mapMPD) -- Select PRESET "x" on COM page
			ApacheDTU.CycleButton("B6", _devices.leftMPD, _mapMPD) -- PRESET EDIT

			if preset.PRI_FREQ then
				local _mapPRIFreq = {
					VHF = "L1", UHF = "L3", FM1 = "L5", FM2 = "R2"
				}
				ApacheDTU.CycleButton("L4", _devices.leftMPD, _mapMPD) -- PRIMARY
				ApacheDTU.CycleButton(_mapPRIFreq[preset.PRI_FREQ], _devices.leftMPD, _mapMPD) -- Select correct primary
			end

			if preset.UNIT_ID then
				if string.len(preset.UNIT_ID) <= 8 then
					ApacheDTU.CycleButton("L1", _devices.leftMPD, _mapMPD) -- UNIT ID (Max 8 char)
					ApacheDTU.KU_Data_Enter(preset.UNIT_ID) -- Enter UNIT ID
				else
					ApacheDTU.log(k .. " UNIT_ID greater than 8 characters!")
				end
			end

			if preset.CALLSIGN then
				if string.len(preset.CALLSIGN) <= 5 then
					ApacheDTU.CycleButton("L2", _devices.leftMPD, _mapMPD) -- CALLSIGN (Max 5 char)
					ApacheDTU.KU_Data_Enter(preset.CALLSIGN) -- Enter CALLSIGN
				else
					ApacheDTU.log(k .. " CALLSIGN greater than 5 characters!")
				end
			end

			if preset.VHF or preset.UHF or preset.UHF_Cipher then
				ApacheDTU.CycleButton("T3", _devices.leftMPD, _mapMPD) -- V/UHF Tab
			end

			if preset.VHF then
				if GetDevice(58):is_frequency_in_range(tonumber(preset.VHF) * 10 ^ 6) then
					ApacheDTU.CycleButton("L1", _devices.leftMPD, _mapMPD) -- VHF FREQ
					ApacheDTU.KU_Data_Enter(preset.VHF) -- Enter VHF FREQ
				else
					ApacheDTU.log(k .. " VHF frequency not in range!")
				end
			end

			if preset.UHF then
				if GetDevice(57):is_frequency_in_range(tonumber(preset.UHF) * 10 ^ 6) then
					ApacheDTU.CycleButton("R4", _devices.leftMPD, _mapMPD) -- UHF FREQ
					ApacheDTU.KU_Data_Enter(preset.UHF) -- Enter UHF FREQ
				else
					ApacheDTU.log(k .. " UHF frequency not in range!")
				end
			end

			if preset.UHF_Cipher then
				if _indicators.leftMPD["PB7_25"] == "PLAIN" then
					ApacheDTU.CycleButton("R1", _devices.leftMPD, _mapMPD) -- UHF Cipher (ON)
				end
				if preset.UHF_CNV then
					if tonumber(preset.UHF_CNV) <= 6 then
						ApacheDTU.CycleButton("R2", _devices.leftMPD, _mapMPD) -- UHF CNV Select
						ApacheDTU.CycleButton("R"..preset.UHF_CNV, _devices.leftMPD, _mapMPD) -- UHF CNV SELECTED
					else
						ApacheDTU.log(k .. " UHF_CNV greater than 6!")
					end
				end
			else
				if _indicators.leftMPD["PB7_25"] == "CIPHER" then
					ApacheDTU.CycleButton("R1", _devices.leftMPD, _mapMPD) -- UHF Cipher (OFF)
				end
			end

			if preset.FM1 or preset.FM2 or preset.FM1_Cipher or preset.FM2_Cipher then
				ApacheDTU.CycleButton("T4", _devices.leftMPD, _mapMPD) -- FM Tab
			end

			if preset.FM1 then
				if GetDevice(59):is_frequency_in_range(tonumber(preset.FM1) * 10 ^ 6) then
					ApacheDTU.CycleButton("L4", _devices.leftMPD, _mapMPD) -- FM1 FREQ
					ApacheDTU.KU_Data_Enter(preset.FM1) -- Enter FM1 FREQ
				else
					ApacheDTU.log(k .. " FM1 frequency not in range!")
				end
			end

			if preset.FM2 then
				if GetDevice(60):is_frequency_in_range(tonumber(preset.FM2) * 10 ^ 6) then
					ApacheDTU.CycleButton("R4", _devices.leftMPD, _mapMPD) -- FM2 FREQ
					ApacheDTU.KU_Data_Enter(preset.FM2) -- Enter FM2 FREQ
				else
					ApacheDTU.log(k .. " FM2 frequency not in range!")
				end
			end

			if preset.FM1_Cipher then
				if _indicators.leftMPD["PB24_21"] == "PLAIN" then
					ApacheDTU.CycleButton("L1", _devices.leftMPD, _mapMPD) -- FM1 Cipher (ON)
				end
				if preset.FM1_CNV then
					if tonumber(preset.FM1_CNV) <= 6 then
						ApacheDTU.CycleButton("L2", _devices.leftMPD, _mapMPD) -- FM1 CNV Select
						ApacheDTU.CycleButton("L"..preset.FM1_CNV, _devices.leftMPD, _mapMPD) -- FM1 CNV SELECTED
					else
						ApacheDTU.log(k .. " FM1_CNV greater than 6!")
					end
				end
			else
				if _indicators.leftMPD["PB24_21"] == "CIPHER" then
					ApacheDTU.CycleButton("L1", _devices.leftMPD, _mapMPD) -- FM1 Cipher (OFF)
				end
			end

			if preset.FM2_Cipher then
				if _indicators.leftMPD["PB7_39"] == "PLAIN" then
					ApacheDTU.CycleButton("R1", _devices.leftMPD, _mapMPD) -- FM2 Cipher (ON)
				end
				if preset.FM2_CNV then
					if tonumber(preset.FM2_CNV) <= 6 then
						ApacheDTU.CycleButton("R2", _devices.leftMPD, _mapMPD) -- FM2 CNV Select
						ApacheDTU.CycleButton("R"..preset.FM2_CNV, _devices.leftMPD, _mapMPD) -- FM2 CNV SELECTED
					else
						ApacheDTU.log(k .. " FM2_CNV greater than 6!")
					end
				end
			else
				if _indicators.leftMPD["PB7_39"] == "CIPHER" then
					ApacheDTU.CycleButton("R1", _devices.leftMPD, _mapMPD) -- FM2 Cipher (OFF)
				end
			end

			if preset.NET then
				ApacheDTU.CycleButton("B4", _devices.leftMPD, _mapMPD) -- NET

				if preset.deleteExistingNET then -- this is over-engineered, but it'll buff.
					local _keyList = {
						PB24_31 = "L1",	PB23_35 = "L2",	PB22_39 = "L3",	PB21_43 = "L4",	PB20_47 = "L5", 
						PB7_51 = "R1",	PB8_55 = "R2",	PB9_59 = "R3",	PB10_63 = "R4",	PB11_67 = "R5"
					}
					for i=1,2 do -- two pages of shit
						for label,mpdBtn in pairs(_keyList) do
							if mpdBtn:sub(1,-2) == "R" and i == 2 then -- only goes to L5 on 2nd page
								-- continue
							else
								if _indicators.leftMPD[label] ~= "?" then
									ApacheDTU.CycleButton(mpdBtn, _devices.leftMPD, _mapMPD) -- Select whichever subscriber is set
									ApacheDTU.CycleButton("T2", _devices.leftMPD, _mapMPD) -- DEL
									ApacheDTU.CycleButton("T1", _devices.leftMPD, _mapMPD) -- "YES"
								end
							end
						end
						if i == 1 then
							ApacheDTU.CycleButton("B3", _devices.leftMPD, _mapMPD) -- NEXT PAGE (2)
						else
							ApacheDTU.CycleButton("B2", _devices.leftMPD, _mapMPD) -- PREV PAGE (1)
						end
					end
				end

				for i,NET in ipairs(preset.NET) do
					-- Although PRI max is 7, don't need to track it... because the AH-64D natively won't permit more.
					if i > 15 then
						break -- too many damn subscribers - evade! evade! evade!
					end
					local netBtn = nil
					local netCS_num = NET.CS:len()
					local netSUB_num = NET.SUB:len()
					if i <= 5 then
						netBtn = "L" .. tostring(i)
					elseif i >= 11 then
						netBtn = "L" .. tostring(i-10)
						ApacheDTU.CycleButton("B3", _devices.leftMPD, _mapMPD) -- NEXT PAGE (2)
					else
						netBtn = "R" .. tostring(i-5)
					end

					if netCS_num >= 3 and netCS_num <= 5 and netSUB_num >= 1 and netSUB_num <= 2 then -- validate user input within range
						ApacheDTU.CycleButton(netBtn, _devices.leftMPD, _mapMPD) -- Select appropriate member
						ApacheDTU.CycleButton("T5", _devices.leftMPD, _mapMPD) -- C/S
						ApacheDTU.KU_Data_Enter(NET.CS) -- Enter CALL SIGN
						ApacheDTU.CycleButton("T6", _devices.leftMPD, _mapMPD) -- SUB
						ApacheDTU.KU_Data_Enter(NET.SUB) -- Enter Subscriber ID

						if NET.TEAM then
							ApacheDTU.CycleButton("T3", _devices.leftMPD, _mapMPD) -- TEAM
						end

						if NET.PRI then
							ApacheDTU.CycleButton("T4", _devices.leftMPD, _mapMPD) -- PRI
						end
					end
				end
			end
		end
	end

	if DTU.COM.XPNDR then
		ApacheDTU.CycleButton("COM", _devices.leftMPD, _mapMPD) -- COM Page
		ApacheDTU.CycleButton("T3", _devices.leftMPD, _mapMPD) -- XPNDR Page

		if DTU.COM.XPNDR.Mode1 then
			if string.len(DTU.COM.XPNDR.Mode1) <= 2 then
				ApacheDTU.CycleButton("R1", _devices.leftMPD, _mapMPD) -- Mode 1
				ApacheDTU.KU_Data_Enter(DTU.COM.XPNDR.Mode1) -- Enter Mode 1
				if _indicators.leftMPD["PB24_9"] == "}1" then
					ApacheDTU.CycleButton("L1", _devices.leftMPD, _mapMPD) -- Mode 1 (ON)
				end
			else
				ApacheDTU.log(k .. " Mode1 greater than 2 characters!")
			end
		else
			if _indicators.leftMPD["PB24_9"] == "{1" then
				ApacheDTU.CycleButton("L1", _devices.leftMPD, _mapMPD) -- Mode 1 (OFF)
			end
		end

		if DTU.COM.XPNDR.Mode3 then
			if string.len(DTU.COM.XPNDR.Mode3) <= 4 then
				ApacheDTU.CycleButton("R3", _devices.leftMPD, _mapMPD) -- Mode 3
				ApacheDTU.KU_Data_Enter(DTU.COM.XPNDR.Mode3) -- Enter Mode 3
				if _indicators.leftMPD["PB22_13"] == "}3/A" then
					ApacheDTU.CycleButton("L3", _devices.leftMPD, _mapMPD) -- Mode 3 (ON)
				end
			else
				ApacheDTU.log(k .. " Mode3 greater than 4 characters!")
			end
		else
			if _indicators.leftMPD["PB22_13"] == "{3/A" then
				ApacheDTU.CycleButton("L3", _devices.leftMPD, _mapMPD) -- Mode 3 (OFF)
			end
		end

		if DTU.COM.XPNDR.Mode4 then
			if _indicators.leftMPD["PB20_17"] == "}4" then
				ApacheDTU.CycleButton("L5", _devices.leftMPD, _mapMPD) -- Mode 4 (ON)
			end
		else
			if _indicators.leftMPD["PB20_17"] == "{4" then
				ApacheDTU.CycleButton("L5", _devices.leftMPD, _mapMPD) -- Mode 4 (OFF)
			end
		end
	end

	if DTU.COM.DL then -- Datalink
		ApacheDTU.CycleButton("COM", _devices.leftMPD, _mapMPD) -- COM Page
		ApacheDTU.CycleButton("B4", _devices.leftMPD, _mapMPD) -- ORIG ID (on COM page)

		if DTU.COM.DL.CALLSIGN then
			if string.len(DTU.COM.DL.CALLSIGN) > 2 and string.len(DTU.COM.DL.CALLSIGN) <= 5 then
				ApacheDTU.CycleButton("L1", _devices.leftMPD, _mapMPD) -- CALL SIGN select
				ApacheDTU.KU_Data_Enter(DTU.COM.DL.CALLSIGN) -- CALL SIGN on ORIG ID subpage (max 5 chars, min 3)
			end
		end

		if DTU.COM.DL.ORIG_ID then
			if string.len(DTU.COM.DL.ORIG_ID) <= 2 then
				ApacheDTU.CycleButton("R1", _devices.leftMPD, _mapMPD) -- DL ORIG ID select
				ApacheDTU.KU_Data_Enter(DTU.COM.DL.ORIG_ID) -- DL ORIG ID on ORIG ID subpage (max 2 chars)
			end
		end
	end

	if DTU.COM.HF then -- must set HF in MAN subpage currently (presets broken)
		ApacheDTU.CycleButton("COM", _devices.leftMPD, _mapMPD) -- COM Page
		if GetDevice(61):is_frequency_in_range(tonumber(DTU.COM.HF) * 10 ^ 6) then
			ApacheDTU.CycleButton("B2", _devices.leftMPD, _mapMPD) -- MAN subpage
			ApacheDTU.CycleButton("R1", _devices.leftMPD, _mapMPD) -- HF FREQ select
			ApacheDTU.KU_Data_Enter(DTU.COM.HF) -- HF FREQ enter data
		end
	end
end

function ApacheDTU.Enter_TSD_Points(_pointTable, _type)
	local _mapPointType = {
		WP = "L3", CM = "L5", TG = "L6"
	}

	ApacheDTU.CycleButton("TSD", _devices.rightMPD, _mapMPD) -- TSD
	ApacheDTU.CycleButton("B6", _devices.rightMPD, _mapMPD) -- POINT
	for i,point in ipairs(_pointTable) do
		--
		ApacheDTU.CycleButton("L2", _devices.rightMPD, _mapMPD) -- ADD
		ApacheDTU.CycleButton(_mapPointType[_type], _devices.rightMPD, _mapMPD) -- point type selection
		ApacheDTU.CycleButton("L1", _devices.rightMPD, _mapMPD) -- IDENT (ADDING ON KU)

		if point.IDENT then
			ApacheDTU.KU_Data_Enter(point.IDENT)
		else
			ApacheDTU.KU_Data_Enter("")
		end

		if point.FREE then
			ApacheDTU.KU_Data_Enter(point.FREE)
		else
			ApacheDTU.KU_Data_Enter("")
		end

		if point.MGRS then
			ApacheDTU.CycleButton("CLR", _devices.KU, _mapKU) -- CLR default (ownship) MGRS
			ApacheDTU.KU_Data_Enter(point.MGRS)
		else
			ApacheDTU.KU_Data_Enter("")
		end

		if point.ALT then
			ApacheDTU.KU_Data_Enter(point.ALT)
		else
			ApacheDTU.KU_Data_Enter("")
		end
		--
	end
end

function ApacheDTU.SaveDTC()
	ApacheDTU.dataReady = false
	-- ApacheDTU.log("Exporting DTC to " .. lfs.writedir() .. [[AH64D-DTU\DTC.json]])
	dtc = io.open(lfs.writedir() .. [[Mods\Services\DCS-Apache-DTU\DTC\DTC.json]], "w")
	if dtc then
		dtc:write(ApacheDTU.JSON:encode(DTU))
		dtc:flush()
	end
	dtc:close()
	ApacheDTU.dataReady = true
	ApacheDTU.CycleButton("CLR", _devices.KU, _mapKU)
	ApacheDTU.KU_Data_Enter("SAVE SUCCESS")
end

function ApacheDTU.KU_Data_Enter(_string)
	for key in _string:gmatch"." do
		ApacheDTU.CycleButton(key, _devices.KU, _mapKU)
	end
	ApacheDTU.CycleButton("ENTER", _devices.KU, _mapKU) -- Enter on KU
end

function ApacheDTU.CycleArg(_argSet, _indicator, _label, _action, _device, _map)
	-- if nil (not set), we just accept the default value
	if _argSet ~= nil then
		if _argSet then
			if not _indicator[_label] then -- XXX not active?
				ApacheDTU.CycleButton(_action, _device, _map) -- XXX
			end
		else
			if _indicator[_label] then -- XXX already active?
				ApacheDTU.CycleButton(_action, _device, _map) -- XXX
			end
		end
	end
end

function ApacheDTU.CycleButton(_btn, _deviceID, _map)
	local startTime = LoGetModelTime()
	GetDevice(_deviceID):performClickableAction(_map[_btn], 1) -- Depress
	while true do
		local currentTime = LoGetModelTime()
		if (currentTime - startTime) > 0.2 then -- 0.2 is the delay in seconds
			break
		end
		coroutine.yield()
	end
	GetDevice(_deviceID):performClickableAction(_map[_btn], 0) -- Release
	-- The below is time between button presses:
	-- startTime = LoGetModelTime() -- reset
	-- while true do
	-- 	local currentTime = LoGetModelTime()
	-- 	if (currentTime - startTime) > 0.1 then
	-- 		break
	-- 	end
	-- 	coroutine.yield()
	-- end
end

function LuaExportStart()
	file = io.open(lfs.writedir() .. [[Logs\DCS-Apache-DTU.log]], "w")
	function ApacheDTU.log(str)
		if file then
			file:write(str .. "\n")
			file:flush()
		end
	end

	ApacheDTU.log("---- Started Apache DTU ----\n")
end

function LuaExportAfterNextFrame()
	if LoGetSelfData().Name == "AH-64D_BLK_II" then
		ApacheDTU.ah64()
	end
end

function ApacheDTU.getListIndicatorValue(IndicatorID) -- Sourced from SRS
    local ListIindicator = list_indication(IndicatorID)
    local TmpReturn = {}

    if ListIindicator == "" then
        return nil
    end

    local ListindicatorMatch = ListIindicator:gmatch("-----------------------------------------\n([^\n]+)\n([^\n]*)\n")
    while true do
        local Key, Value = ListindicatorMatch()
        if not Key then
            break
        end
        TmpReturn[Key] = Value
    end

    return TmpReturn
end

-- {
--     ["keyE"] = 3011,
--     ["BrightnessKnob_KB"] = 3051,
--     ["key9"] = 3041,
--     ["keyB"] = 3008,
--     ["keyMinus"] = 3047,
--     ["keyP"] = 3022,
--     ["keyD"] = 3010,
--     ["keyM"] = 3019,
--     ["keyLeft"] = 3004,
--     ["key8"] = 3040,
--     ["keyX"] = 3030,
--     ["keyW"] = 3029,
--     ["keyY"] = 3031,
--     ["keyN"] = 3020,
--     ["keyA"] = 3007,
--     ["BrightnessKnob_AXIS"] = 3052,
--     ["keyS"] = 3025,
--     ["keyV"] = 3028,
--     ["keyDot"] = 3042,
--     ["keyC"] = 3009,
--     ["keyBKS"] = 3002,
--     ["keyRight"] = 3005,
--     ["BrightnessKnob"] = 3050,
--     ["keyL"] = 3018,
--     ["key1"] = 3033,
--     ["key5"] = 3037,
--     ["keyJ"] = 3016,
--     ["keyDivide"] = 3048,
--     ["keyU"] = 3027,
--     ["keyI"] = 3015,
--     ["key6"] = 3038,
--     ["keySign"] = 3044,
--     ["key0"] = 3043,
--     ["keyCLR"] = 3001,
--     ["keyEnter"] = 3006,
--     ["key7"] = 3039,
--     ["keyH"] = 3014,
--     ["keySlash"] = 3045,
--     ["keyMultiply"] = 3049,
--     ["key4"] = 3036,
--     ["keyK"] = 3017,
--     ["key3"] = 3035,
--     ["key2"] = 3034,
--     ["keyG"] = 3013,
--     ["keyO"] = 3021,
--     ["keyZ"] = 3032,
--     ["keyPlus"] = 3046,
--     ["keyT"] = 3026,
--     ["keyR"] = 3024,
--     ["keyQ"] = 3023,
--     ["keyF"] = 3012,
--     ["keySPC"] = 3003,
-- }

-- {
--     ["T2"] = 3002,
--     ["T6"] = 3006,
--     ["VID"] = 3026,
--     ["T4"] = 3004,
--     ["B5"] = 3014,
--     ["TSD"] = 3029,
--     ["BRT_KNOB_ITER"] = 3035,
--     ["B1"] = 3018,
--     ["B3"] = 3016,
--     ["L2"] = 3023,
--     ["R4"] = 3010,
--     ["R6"] = 3012,
--     ["L6"] = 3019,
--     ["R2"] = 3008,
--     ["L4"] = 3021,
--     ["T3"] = 3003,
--     ["T1"] = 3001,
--     ["MODE_KNOB"] = 3034,
--     ["T5"] = 3005,
--     ["BRT_KNOB_AXIS"] = 3036,
--     ["B4"] = 3015,
--     ["B6"] = 3013,
--     ["B2"] = 3017,
--     ["MODE_KNOB_ITER"] = 3039,
--     ["VID_KNOB_ITER"] = 3037,
--     ["WPN"] = 3030,
--     ["VID_KNOB_AXIS"] = 3038,
--     ["VID_KNOB"] = 3033,
--     ["BRT_KNOB"] = 3032,
--     ["FCR"] = 3031,
--     ["AC"] = 3028,
--     ["R5"] = 3011,
--     ["L3"] = 3022,
--     ["Asterisk"] = 3025,
--     ["L1"] = 3024,
--     ["COM"] = 3027,
--     ["R1"] = 3007,
--     ["L5"] = 3020,
--     ["R3"] = 3009,
-- }