-- Luanti
-- Copyright (C) 2014 sapier
-- SPDX-License-Identifier: LGPL-2.1-or-later

local function get_sorted_servers()
	local servers = {
		fav = {},
		public = {},
		incompatible = {}
	}

	local favs = serverlistmgr.get_favorites()
	local taken_favs = {}
	local result = menudata.search_result or serverlistmgr.servers
	for _, server in ipairs(result) do
		server.is_favorite = false
		for index, fav in ipairs(favs) do
			if server.address == fav.address and server.port == fav.port then
				taken_favs[index] = true
				server.is_favorite = true
				break
			end
		end
		server.is_compatible = is_server_protocol_compat(server.proto_min, server.proto_max)
		if server.is_favorite then
			table.insert(servers.fav, server)
		elseif server.is_compatible then
			table.insert(servers.public, server)
		else
			table.insert(servers.incompatible, server)
		end
	end

	if not menudata.search_result then
		for index, fav in ipairs(favs) do
			if not taken_favs[index] then
				table.insert(servers.fav, fav)
			end
		end
	end

	return servers
end

local function is_selected_fav(server)
	local address = core.settings:get("address")
	local port = tonumber(core.settings:get("remote_port"))

	for _, fav in ipairs(serverlistmgr.get_favorites()) do
		if address == fav.address and port == fav.port then
			return true
		end
	end
	return false
end

-- Persists the selected server in the "address" and "remote_port" settings

local function set_selected_server(server)
	if server == nil then -- reset selection
		core.settings:remove("address")
		core.settings:remove("remote_port")
		return
	end
	local address = server.address
	local port    = server.port

	if address and port then
		core.settings:set("address", address)
		core.settings:set("remote_port", port)
	end
end

local function find_selected_server()
	local address = core.settings:get("address")
	local port = tonumber(core.settings:get("remote_port"))
	for _, server in ipairs(serverlistmgr.servers) do
		if server.address == address and server.port == port then
			return server
		end
	end
	for _, server in ipairs(serverlistmgr.get_favorites()) do
		if server.address == address and server.port == port then
			return server
		end
	end
end

local SAVED_NAMES_SETTING = "kidtown_saved_names"
local SAVED_PASSWORD_PREFIX = "kidtown_password_"

local function get_saved_names()
	local raw = core.settings:get(SAVED_NAMES_SETTING) or ""
	local names = {}
	for name in raw:gmatch("[^\n]+") do
		names[#names + 1] = name
	end
	return names
end

local function remember_name(name)
	name = name:match("^%s*(.-)%s*$")
	if name == "" then
		return
	end
	local names = get_saved_names()
	for i = #names, 1, -1 do
		if names[i] == name then
			table.remove(names, i)
		end
	end
	table.insert(names, 1, name)
	while #names > 12 do
		table.remove(names)
	end
	core.settings:set(SAVED_NAMES_SETTING, table.concat(names, "\n"))
end

local function get_saved_password(name)
	if name == nil or name == "" then
		return ""
	end
	return core.settings:get(SAVED_PASSWORD_PREFIX .. name) or ""
end

local function set_saved_password(name, password)
	if name == nil or name == "" then
		return
	end
	local key = SAVED_PASSWORD_PREFIX .. name
	if password == nil or password == "" then
		core.settings:remove(key)
	else
		core.settings:set(key, password)
	end
end

-- Parent-controlled town list for this phone. The PC can publish several
-- towns; the parent chooses which of those this phone may see. The chosen
-- names are kept here so a later rename on the PC neither reveals a new name
-- nor changes what a locked child sees. All state is in ordinary settings so
-- it survives an app restart and needs no server account or internet.
local is_lan_address
local parent = {}
parent.PIN_HASH = "kidtown_parent_pin_hash"
parent.PIN_SALT = "kidtown_parent_pin_salt"
parent.RECOVERY_HASH = "kidtown_parent_recovery_hash"
parent.RECOVERY_SALT = "kidtown_parent_recovery_salt"
parent.ALLOWED = "kidtown_parent_allowed_towns"
parent.ALLOWED_SAVED = "kidtown_parent_allowed_saved"
parent.MIN_PIN = 4
parent.RECOVERY_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

function parent.hash(pin, salt)
	local text = tostring(salt or "") .. ":" .. tostring(pin or "")
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + text:byte(i)) % 4294967296
	end
	return string.format("%08x", h)
end

function parent.has_pin()
	return (core.settings:get(parent.PIN_HASH) or "") ~= ""
end

function parent.set_pin(pin)
	local salt = tostring(os.time()) .. ":" ..
		tostring(math.random(100000, 999999))
	core.settings:set(parent.PIN_SALT, salt)
	core.settings:set(parent.PIN_HASH, parent.hash(pin, salt))
end

function parent.check_pin(pin)
	local stored = core.settings:get(parent.PIN_HASH) or ""
	local salt = core.settings:get(parent.PIN_SALT) or ""
	return stored ~= "" and stored == parent.hash(pin, salt)
end

function parent.has_recovery_code()
	return (core.settings:get(parent.RECOVERY_HASH) or "") ~= ""
end

function parent.normalise_recovery_code(code)
	return (tostring(code or ""):upper():gsub("[^A-Z0-9]", ""))
end

--- Create a fresh one-time recovery code and keep only its hash.
--- The returned spelling has hyphens for reading aloud or writing down.
function parent.new_recovery_code()
	local chars = {}
	for i = 1, 12 do
		local n = math.random(1, #parent.RECOVERY_ALPHABET)
		chars[i] = parent.RECOVERY_ALPHABET:sub(n, n)
	end
	local plain = table.concat(chars)
	local salt = tostring(os.time()) .. ":" ..
		tostring(math.random(100000, 999999))
	core.settings:set(parent.RECOVERY_SALT, salt)
	core.settings:set(parent.RECOVERY_HASH,
		parent.hash(parent.normalise_recovery_code(plain), salt))
	return plain:sub(1, 4) .. "-" .. plain:sub(5, 8) .. "-" ..
		plain:sub(9, 12)
end

function parent.check_recovery_code(code)
	local stored = core.settings:get(parent.RECOVERY_HASH) or ""
	local salt = core.settings:get(parent.RECOVERY_SALT) or ""
	return stored ~= "" and stored == parent.hash(
		parent.normalise_recovery_code(code), salt)
end

function parent.allowed_towns()
	if core.settings:get(parent.ALLOWED_SAVED) ~= "true" then
		return nil
	end
	local names = {}
	for line in tostring(core.settings:get(parent.ALLOWED) or ""):gmatch(
			"[^\r\n]+") do
		if not line:match("^%s*#") then
			local name, port = line:match("^%s*([^|]+)|%s*(%d+)%s*$")
			port = tonumber(port)
			if name and port and port >= 1 and port <= 65535 then
				name = name:match("^%s*(.-)%s*$")
				if name ~= "" then
					names[#names + 1] = {name = name:sub(1, 48),
						port = port}
				end
			end
		end
	end
	return names
end

function parent.clean_name(name)
	return (tostring(name or ""):gsub("[|\r\n]", " "):match(
		"^%s*(.-)%s*$") or ""):sub(1, 48)
end

function parent.save_allowed(rows)
	local lines = {"# KidTown parent-allowed phone towns"}
	local seen = {}
	for _, row in ipairs(rows or {}) do
		if row.allowed and not row.placeholder then
			local name = parent.clean_name(row.name)
			local port = tonumber(row.port)
			if name ~= "" and port and not seen[port] then
				seen[port] = true
				lines[#lines + 1] = name .. "|" .. tostring(port)
			end
		end
	end
	core.settings:set(parent.ALLOWED, table.concat(lines, "\n"))
	core.settings:set(parent.ALLOWED_SAVED, "true")
end

function parent.merge_towns(current, saved)
	local configured = saved ~= nil
	local by_port = {}
	local seen = {}
	for _, entry in ipairs(saved or {}) do
		by_port[entry.port] = entry
	end
	local rows = {}
	for _, town in ipairs(current or {}) do
		local port = tonumber(town.port)
		if port and not seen[port] then
			seen[port] = true
			local kept = by_port[port]
			rows[#rows + 1] = {
				name = tostring(town.name or (kept and kept.name) or "Town"),
				port = port,
				allowed = (not configured) or kept ~= nil,
				missing = false,
			}
		end
	end
	if configured then
		for _, entry in ipairs(saved) do
			if not seen[entry.port] then
				seen[entry.port] = true
				rows[#rows + 1] = {name = entry.name, port = entry.port,
					allowed = true, missing = true}
			end
		end
	end
	return rows
end

function parent.filter_towns(towns)
	local allowed = parent.allowed_towns()
	if allowed == nil then
		return towns or {}
	end
	local by_port = {}
	for _, entry in ipairs(allowed) do
		by_port[entry.port] = entry
	end
	local visible = {}
	for _, town in ipairs(towns or {}) do
		local port = tonumber(town.port)
		local kept = port and by_port[port]
		if kept then
			visible[#visible + 1] = {name = kept.name, port = port}
		end
	end
	return visible
end

function parent.port_is_allowed(port)
	local allowed = parent.allowed_towns()
	if allowed == nil then
		return true
	end
	port = tonumber(port)
	for _, entry in ipairs(allowed) do
		if entry.port == port then return true end
	end
	return false
end

function parent.enforce_child_address(tabdata)
	local port = tonumber(core.settings:get("remote_port"))
	if not parent.port_is_allowed(port) then
		core.settings:remove("address")
		tabdata.found = nil
	end
end

function parent.ensure_from_settings(tabdata)
	if tabdata.parent_towns == nil then
		tabdata.parent_towns = parent.merge_towns({},
			parent.allowed_towns())
	end
	if tabdata.parent_address == nil then
		tabdata.parent_address = core.settings:get("address") or ""
	end
	if tabdata.parent_port == nil then
		tabdata.parent_port = core.settings:get("remote_port") or "30000"
	end
end

function parent.capture_fields(tabdata, fields)
	if fields.parent_address ~= nil then
		tabdata.parent_address = fields.parent_address
	end
	if fields.parent_port ~= nil then
		tabdata.parent_port = fields.parent_port
	end
end

function parent.save_address(tabdata)
	local address = tostring(tabdata.parent_address or ""):match(
		"^%s*(.-)%s*$") or ""
	local port_text = tostring(tabdata.parent_port or ""):match(
		"^%s*(.-)%s*$") or ""
	local port = tonumber(port_text)
	if address ~= "" and not is_lan_address(address) then
		return false, "Use the town PC's private Wi-Fi address."
	end
	if port_text ~= "" and (not port or port < 1 or port > 65535) then
		return false, "The port must be between 1 and 65535."
	end
	if address ~= "" then
		core.settings:set("address", address)
	end
	if port then
		core.settings:set("remote_port", tostring(port))
	end
	return true
end

function parent.status_text(tabdata)
	if tabdata.parent_unlocked then
		return "Parent settings are unlocked on this phone."
	end
	local allowed = parent.allowed_towns()
	if allowed == nil then
		return "Parent lock is off; all discovered towns are shown."
	end
	return "Parent allows " .. tostring(#allowed) .. " town(s) on this phone."
end

function parent.find_note()
	local allowed = parent.allowed_towns()
	if allowed == nil then
		return "Showing towns this PC publishes."
	end
	return "Showing only towns a parent checked for this phone."
end

-- The town PC's read-only LAN helper (phoneapp.py) serves towns.txt beside the
-- APK. It normally starts on 8791 and moves up when that port is busy.
local TOWN_LIST_PORTS = {8791, 8792, 8793, 8794, 8795, 8796, 8797, 8798, 8799, 8800}

is_lan_address = function(host)
	if type(host) ~= "string" or host:find(":", 1, true) then
		return false
	end
	local a, b, c, d = host:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
	if not (a and b and c and d) or a > 255 or b > 255 or c > 255 or d > 255 then
		return false
	end
	return a == 10 or a == 127 or (a == 192 and b == 168)
		or (a == 172 and b >= 16 and b <= 31)
		or (a == 169 and b == 254)
end

local function parse_town_list(text)
	local towns = {}
	for line in tostring(text or ""):gmatch("[^\r\n]+") do
		if not line:match("^%s*#") then
			local name, port = line:match("^%s*([^|]+)|%s*(%d+)%s*$")
			if name and port then
				name = name:match("^%s*(.-)%s*$")
				port = tonumber(port)
				if name ~= "" and port and port >= 1 and port <= 65535 then
					towns[#towns + 1] = {name = name:sub(1, 48), port = port}
				end
			end
		end
	end
	return towns
end

local function fetch_lan_towns(host)
	-- The picker is LAN-only. Refuse anything that is not a private IPv4
	-- address, even if a discovery reply or a hand-edited setting asks for it.
	if not is_lan_address(host) or not core.get_http_api then
		return nil
	end
	local ok, api = pcall(core.get_http_api)
	if not ok or not api or not api.fetch_sync then
		return nil
	end
	local base = "http://" .. host
	for _, port in ipairs(TOWN_LIST_PORTS) do
		local got, res = pcall(api.fetch_sync, {
			url = base .. ":" .. tostring(port) .. "/towns.txt",
			timeout = 1,
		})
		if got and res and res.succeeded and res.code == 200 and res.data then
			local towns = parse_town_list(res.data)
			if #towns > 0 then
				return towns
			end
		end
	end
	return nil
end

function parent.town_rows(tabdata)
	local rows = tabdata.parent_towns or {}
	local entries = {}
	for _, row in ipairs(rows) do
		local mark = row.allowed and "[x] " or "[ ] "
		local missing = row.missing and " - not on this PC now" or ""
		entries[#entries + 1] = core.formspec_escape(mark .. row.name ..
			" (port " .. tostring(row.port) .. ")" .. missing)
	end
	if #entries == 0 then
		entries[1] = "No towns found yet. Tap Find towns now."
	end
	return entries
end

function parent.gate_formspec(tabdata)
	local has_pin = parent.has_pin()
	local fs = {
		"size[" .. MAIN_TAB_W .. "," .. MAIN_TAB_H .. "]",
		"label[0.6,0.3;Parent settings]",
		"label[0.6,0.9;14.3,0.9;A grown-up can lock the town list and the "
			.. "address and port for this phone. The child side stays read-only.]",
	}
	if not has_pin then
		fs[#fs + 1] = "label[0.6,1.8;Create a parent password (at least "
			.. tostring(parent.MIN_PIN) .. " characters)]"
		fs[#fs + 1] = "pwdfield[0.6,2.1;6.8,0.8;parent_pin;;]"
		fs[#fs + 1] = "label[7.8,1.8;Confirm password]"
		fs[#fs + 1] = "pwdfield[7.8,2.1;6.8,0.8;parent_pin2;;]"
		fs[#fs + 1] = "button[0.6,3.15;4.2,0.9;btn_parent_create;"
			.. "Save password]"
		fs[#fs + 1] = "button[5.1,3.15;3.4,0.9;btn_parent_cancel;Back]"
		fs[#fs + 1] = "label[0.6,4.35;Write down the recovery code on the next screen.]"
	else
		fs[#fs + 1] = "label[0.6,1.8;Parent settings are locked]"
		fs[#fs + 1] = "pwdfield[0.6,2.1;8.0,0.8;parent_pin;;]"
		fs[#fs + 1] = "button[0.6,3.15;3.6,0.9;btn_parent_unlock;Unlock]"
		fs[#fs + 1] = "button[4.5,3.15;3.4,0.9;btn_parent_cancel;Back]"
		fs[#fs + 1] = "button[0.6,4.35;4.4,0.8;btn_parent_forgot;"
			.. "Forgot password?]"
		fs[#fs + 1] = "label[5.2,4.45;Only a parent should enter this password.]"
	end
	if tabdata.parent_error and tabdata.parent_error ~= "" then
		fs[#fs + 1] = "label[0.6,5.05;14.3,0.9;" .. core.formspec_escape(
			tabdata.parent_error) .. "]"
	end
	fs[#fs + 1] = "label[0.6,6.75;The parent password is stored only on this phone.]"
	return table.concat(fs)
end

function parent.settings_formspec(tabdata)
	parent.ensure_from_settings(tabdata)
	local entries = parent.town_rows(tabdata)
	local allowed = 0
	for _, row in ipairs(tabdata.parent_towns or {}) do
		if row.allowed then allowed = allowed + 1 end
	end
	local status = tostring(allowed) .. " of " ..
		tostring(#(tabdata.parent_towns or {})) .. " town(s) allowed."
	if tabdata.parent_host and tabdata.parent_host ~= "" then
		status = status .. " Last found at " .. tostring(tabdata.parent_host) .. "."
	end
	local fs = {
		"size[" .. MAIN_TAB_W .. "," .. MAIN_TAB_H .. "]",
		"label[0.6,0.3;Parent settings -- allowed towns]",
		"label[0.6,1.15;Address]" ..
			"field[0.6,1.45;7.4,0.75;parent_address;;" ..
			core.formspec_escape(tabdata.parent_address or "") .. "]" ..
			"label[8.3,1.15;Port]" ..
			"field[8.3,1.45;2.0,0.75;parent_port;;" ..
			core.formspec_escape(tabdata.parent_port or "") .. "]" ..
			"button[10.6,1.45;4.3,0.75;btn_parent_find;Find towns now]",
		"label[0.6,2.35;Towns this child may see]" ..
			"textlist[0.6,2.65;14.3,2.4;parent_towns;" ..
			table.concat(entries, ",") .. ";0;false]",
		"label[0.6,5.15;Tap a town to allow or block it. [x] means allowed.]",
		"label[0.6,5.45;" .. core.formspec_escape(status) .. "]",
		"button[0.6,5.85;3.8,0.9;btn_parent_save;Save and lock]" ..
			"button[4.6,5.85;3.6,0.9;btn_parent_password;"
			.. "Change password]" ..
			"button[8.4,5.85;3.4,0.9;btn_parent_recovery;" ..
				(parent.has_recovery_code() and "New recovery code"
					or "Create recovery code") .. "]" ..
			"button[12.0,5.85;2.8,0.9;btn_parent_cancel;Back]",
	}
	if tabdata.parent_error and tabdata.parent_error ~= "" then
		fs[#fs + 1] = "label[0.6,6.65;14.3,0.7;" .. core.formspec_escape(
			tabdata.parent_error) .. "]"
	else
		fs[#fs + 1] = "label[0.6,6.75;Changes apply after Save and lock.]"
	end
	return table.concat(fs)
end

function parent.password_formspec(tabdata)
	local fs = {
		"size[" .. MAIN_TAB_W .. "," .. MAIN_TAB_H .. "]",
		"label[0.6,0.3;Parent settings -- change password]",
		"label[0.6,0.95;14.3,0.9;Enter the current parent password, then "
			.. "choose a new one. A new recovery code is shown after saving.]",
		"label[0.6,2.0;Current password]" ..
			"pwdfield[0.6,2.3;6.8,0.8;parent_old_pin;;]",
		"label[0.6,3.35;New password]" ..
			"pwdfield[0.6,3.65;6.8,0.8;parent_new_pin;;]",
		"label[7.8,3.35;Confirm new password]" ..
			"pwdfield[7.8,3.65;6.8,0.8;parent_new_pin2;;]",
		"button[0.6,4.85;4.6,0.9;btn_parent_password_save;"
			.. "Save new password]" ..
			"button[5.4,4.85;3.4,0.9;btn_parent_password_cancel;Back]",
	}
	if tabdata.parent_error and tabdata.parent_error ~= "" then
		fs[#fs + 1] = "label[0.6,6.0;14.3,0.7;" .. core.formspec_escape(
			tabdata.parent_error) .. "]"
	end
	fs[#fs + 1] = "label[0.6,6.65;The new password needs at least "
		.. tostring(parent.MIN_PIN) .. " characters.]"
	return table.concat(fs)
end

function parent.recover_formspec(tabdata)
	local fs = {
		"size[" .. MAIN_TAB_W .. "," .. MAIN_TAB_H .. "]",
		"label[0.6,0.3;Parent settings -- recover password]",
		"label[0.6,0.95;14.3,0.9;Enter the recovery code you saved when the "
			.. "parent password was created, then choose a new password.]",
		"label[0.6,2.0;Recovery code]" ..
			"field[0.6,2.3;7.2,0.8;parent_recovery_input;;]",
		"label[0.6,3.35;New password]" ..
			"pwdfield[0.6,3.65;6.8,0.8;parent_recover_pin;;]",
		"label[7.8,3.35;Confirm new password]" ..
			"pwdfield[7.8,3.65;6.8,0.8;parent_recover_pin2;;]",
		"button[0.6,4.85;4.6,0.9;btn_parent_recover;"
			.. "Reset password]" ..
			"button[5.4,4.85;3.4,0.9;btn_parent_recover_cancel;Back]",
	}
	if tabdata.parent_error and tabdata.parent_error ~= "" then
		fs[#fs + 1] = "label[0.6,6.0;14.3,0.7;" .. core.formspec_escape(
			tabdata.parent_error) .. "]"
	end
	if parent.has_recovery_code() then
		fs[#fs + 1] = "label[0.6,6.65;The recovery code is not the parent "
			.. "password.]"
	else
		fs[#fs + 1] = "label[0.6,6.65;No recovery code is saved on this "
			.. "phone. Unlock with the password and use Change password.]"
	end
	return table.concat(fs)
end

function parent.recovery_code_formspec(tabdata)
	return "size[" .. MAIN_TAB_W .. "," .. MAIN_TAB_H .. "]" ..
		"label[0.6,0.3;Parent recovery code]" ..
		"label[0.6,0.95;14.3,0.9;Write this code down and keep it private. "
			.. "It is the only way to reset the parent password if it is "
			.. "forgotten.]" ..
		"label[0.6,2.15;Recovery code: " ..
			core.formspec_escape(tabdata.parent_recovery_code or "") .. "]" ..
		"label[0.6,2.75;This code will not be shown again.]" ..
		"button[0.6,4.0;3.4,0.9;btn_parent_recovery_done;Done]"
end

function parent.formspec(tabdata)
	if tabdata.parent_recovery_code and tabdata.parent_recovery_code ~= "" then
		return parent.recovery_code_formspec(tabdata)
	end
	if tabdata.parent_password_page then
		return parent.password_formspec(tabdata)
	end
	if tabdata.parent_recover_page then
		return parent.recover_formspec(tabdata)
	end
	if tabdata.parent_unlocked then
		return parent.settings_formspec(tabdata)
	end
	return parent.gate_formspec(tabdata)
end

local function town_picker_formspec(tabdata)
	local entries = {}
	for _, town in ipairs(tabdata.towns or {}) do
		entries[#entries + 1] = core.formspec_escape(town.name)
	end
	local locked = parent.allowed_towns() ~= nil
	local note
	if #entries == 0 then
		entries[1] = locked and "(No towns allowed for this phone)"
			or "(No town found)"
		note = locked and "Ask a grown-up to allow a town in Parent settings."
			or "Check Wi-Fi and Play access, then try again."
	else
		note = locked and "Showing only towns a parent checked for this phone."
			or "Showing towns this PC publishes."
	end
	local selected = tonumber(tabdata.town_index) or 1
	return "size[" .. MAIN_TAB_W .. "," .. MAIN_TAB_H .. "]" ..
		"label[0.6,0.3;Choose a town]" ..
		"label[0.6,0.8;Server: " .. core.formspec_escape(
			tabdata.towns_host or "") .. "]" ..
		"textlist[0.6,1.25;14.3,4.2;towns;" ..
			table.concat(entries, ",") .. ";" .. tostring(selected) .. "]" ..
		"button[0.6,5.75;4.4,0.9;btn_town_use;Use this town]" ..
		"button[5.3,5.75;4.4,0.9;btn_town_back;Back]" ..
		"label[0.6,6.5;" .. core.formspec_escape(note) .. "]" ..
		"label[0.6,6.9;Tap a town, then Use this town.]"
end

local function get_formspec(tabview, name, tabdata)
	-- Update the cached supported proto info,
	-- it may have changed after a change by the settings menu.
	common_update_cached_supp_proto()

	if not tabdata.search_for then
		tabdata.search_for = ""
	end

	-- Phone build: there is no public server list. Keep the one thing the
	-- child actually needs -- the address box -- and explain where to find
	-- the address. The app only accepts local-network addresses anyway.
	if (core.settings:get("serverlist_url") == "") then
		if tabdata.parent_page then
			return parent.formspec(tabdata)
		end
		if tabdata.show_towns then
			return town_picker_formspec(tabdata)
		end
		local saved_names = get_saved_names()
		if tabdata.name == nil then
			tabdata.name = core.settings:get("name") or ""
		end
		if tabdata.password == nil then
			tabdata.password = get_saved_password(tabdata.name)
		end
		if tabdata.remember == nil then
			tabdata.remember = tabdata.password ~= ""
		end

		local saved_names_form
		if #saved_names > 0 then
			local items = {"Choose a name"}
			local selected = 1
			for i, saved_name in ipairs(saved_names) do
				items[#items + 1] = saved_name
				if saved_name == tabdata.name then
					selected = i + 1
				end
			end
			tabdata.dropdown_value = items[selected]
			saved_names_form =
				"label[0.6,3.95;Saved names]" ..
				"dropdown[0.6,4.2;8.8;dd_saved_name;" ..
					table.concat(items, ",") .. ";" .. tostring(selected) .. "]" ..
				"tooltip[dd_saved_name;Choose a name you have used before.]"
		else
			tabdata.dropdown_value = nil
			saved_names_form =
				"label[0.6,3.95;Saved names]" ..
				"label[0.6,4.2;No names saved yet.]"
		end

		local address_value = core.settings:get("address") or ""
		if address_value == "" then address_value = "Not chosen" end
		local port_value = core.settings:get("remote_port") or "30000"
		local address_form
		if tabdata.parent_unlocked then
			address_form =
				"label[0.6,1.35;Town address]" ..
				"field[0.6,1.65;9.2,0.75;te_address;;" ..
				core.formspec_escape(core.settings:get("address") or "") .. "]" ..
				"label[10.0,1.35;Port]" ..
				"field[10.0,1.65;2.0,0.75;te_port;;" ..
				core.formspec_escape(port_value) .. "]"
		else
			address_form =
				"label[0.6,1.35;Town address (set by a parent)]" ..
				"box[0.6,1.65;9.2,0.75;#59695f]" ..
				"label[0.8,1.9;" .. core.formspec_escape(address_value) .. "]" ..
				"label[10.0,1.35;Port]" ..
				"box[10.0,1.65;2.0,0.75;#59695f]" ..
				"label[10.25,1.9;" .. core.formspec_escape(port_value) .. "]"
		end
		local parent_controls =
			"button[0.6,5.35;3.4,0.9;btn_mp_login;Login]" ..
			(tabdata.parent_unlocked and
				"button[4.3,5.35;2.8,0.9;btn_parent_lock;Lock now]" ..
				"button[7.4,5.35;2.5,0.9;btn_parent_photo;ID photo]" ..
				"tooltip[btn_parent_photo;Send one parent-approved photo to the ID Department.]"
				or "") ..
			"button[10.2,5.35;4.7,0.9;btn_parent;Parent settings]" ..
			"tooltip[btn_parent;Lock or change the address, port and allowed towns.]"
		return "size[" .. MAIN_TAB_W .. "," .. MAIN_TAB_H .. "]" ..
			"label[0.6,0.3;Play on your home Wi-Fi]" ..
			"label[0.6,0.8;Tap Find towns. This app never uses the internet.]" ..
			address_form ..
			"button[12.3,1.65;2.9,0.75;btn_mp_find;Find towns]" ..
			"tooltip[btn_mp_find;Look for town PCs on this Wi-Fi]" ..
			"label[0.6,2.55;Your name]" ..
			"field[0.6,2.85;7.0,0.8;te_name;;" ..
				core.formspec_escape(tabdata.name) .. "]" ..
			"label[8.0,2.55;Password]" ..
			"pwdfield[8.0,2.85;7.0,0.8;te_pwd;;" ..
				core.formspec_escape(tabdata.password) .. "]" ..
			saved_names_form ..
			"checkbox[9.7,4.2;chk_remember;Remember password;" ..
				tostring(tabdata.remember == true) .. "]" ..
			"tooltip[chk_remember;Check this to fill in this name's password next time.]" ..
			parent_controls ..
			"label[0.6,6.35;" .. core.formspec_escape(
				tabdata.find_note or
					"Keep this phone on the same Wi-Fi as the town PC.") .. "]" ..
			"label[0.6,6.8;" .. core.formspec_escape(
				parent.status_text(tabdata)) .. "]"
	end

	local retval =
		-- Search
		"field[0.25,0.25;7,0.75;te_search;;" .. core.formspec_escape(tabdata.search_for) .. "]" ..
		"tooltip[te_search;" .. core.formspec_escape(table.concat({
				fgettext("Possible filters"),
				"game:<name>",
				"mod:<name>",
				"player:<name>",
				"sort:[-](name|relevance|players|mods|uptime|ping|lag)",
		}, "\n")) .. "]" ..
		"field_enter_after_edit[te_search;true]" ..
		"container[7.25,0.25]" ..
		"image_button[0,0;0.75,0.75;" .. core.formspec_escape(defaulttexturedir .. "search.png") .. ";btn_mp_search;]" ..
		"image_button[0.75,0;0.75,0.75;" .. core.formspec_escape(defaulttexturedir .. "clear.png") .. ";btn_mp_clear;]" ..
		"image_button[1.5,0;0.75,0.75;" .. core.formspec_escape(defaulttexturedir .. "refresh.png") .. ";btn_mp_refresh;]" ..
		"tooltip[btn_mp_clear;" .. fgettext("Clear") .. "]" ..
		"tooltip[btn_mp_search;" .. fgettext("Search") .. "]" ..
		-- TRANSLATORS: As in 'reload'/'check again'
		"tooltip[btn_mp_refresh;" .. fgettext("Refresh") .. "]" ..
		"container_end[]" ..

		"container[9.75,0]" ..
		"box[0,0;5.75,7.1;#666666]" ..

		-- TRANSLATORS: Network address
		"label[0.25,0.35;" .. fgettext("Address") .. "]" ..
		-- TRANSLATORS: Network port
		"label[4.25,0.35;" .. fgettext("Port") .. "]" ..
		"field[0.25,0.5;4,0.75;te_address;;" ..
			core.formspec_escape(core.settings:get("address")) .. "]" ..
		"field[4.25,0.5;1.25,0.75;te_port;;" ..
			core.formspec_escape(core.settings:get("remote_port")) .. "]" ..

		-- Description Background
		"label[0.25,1.6;" .. fgettext("Server Description") .. "]" ..
		"box[0.25,1.85;5.25,2.7;#999999]"..

		-- Name / Password
		"container[0,4.8]" ..
		"label[0.25,0;" .. fgettext("Name") .. "]" ..
		"label[2.875,0;" .. fgettext("Password") .. "]" ..
		"field[0.25,0.2;2.625,0.75;te_name;;" .. core.formspec_escape(core.settings:get("name")) .. "]" ..
		"pwdfield[2.875,0.2;2.625,0.75;te_pwd;]" ..
		"container_end[]"

	-- Connect
	if core.settings:get_bool("enable_split_login_register") then
		-- TRANSLATORS: Register an account on a server
		retval = retval .. "button[0.25,6;2.5,0.75;btn_mp_register;" .. fgettext("Register") .. "]"
	end
	-- TRANSLATORS: Login to server
	retval = retval .. "button[3,6;2.5,0.75;btn_mp_login;" .. fgettext("Login") .. "]"

	local selected_server = find_selected_server()

	if selected_server then
		if selected_server.description then
			retval = retval .. "textarea[0.25,1.85;5.25,2.7;;;" ..
				core.formspec_escape(selected_server.description) .. "]"
		end

		-- URL button
		if selected_server.url then
			retval = retval .. "tooltip[btn_server_url;" .. fgettext("Open server website") .. "]"
			retval = retval .. "style[btn_server_url;padding=6]"
			retval = retval .. "image_button[3.5,1.3;0.5,0.5;" ..
				core.formspec_escape(defaulttexturedir .. "server_url.png") .. ";btn_server_url;]"
		else
			retval = retval .. "image[3.6,1.4;0.3,0.3;" .. core.formspec_escape(defaulttexturedir ..
				"server_url_unavailable.png") .. "]"
		end

		-- Mods button
		local mods = selected_server.mods
		if mods and #mods > 0 then
			local tooltip = ""
			if selected_server.gameid then
				tooltip = fgettext("Game: $1", selected_server.gameid) .. "\n"
			end
			tooltip = tooltip .. fgettext("Number of mods: $1", #mods)

			retval = retval ..
				"tooltip[btn_view_mods;" .. tooltip .. "]" ..
				"style[btn_view_mods;padding=6]" ..
				"image_button[4,1.3;0.5,0.5;" .. core.formspec_escape(defaulttexturedir ..
				"server_view_mods.png") .. ";btn_view_mods;]"
		else
			retval = retval .. "image[4.1,1.4;0.3,0.3;" .. core.formspec_escape(defaulttexturedir ..
				"server_view_mods_unavailable.png") .. "]"
		end

		-- Clients list button
		local clients_list = selected_server.clients_list
		local can_view_clients_list = clients_list and #clients_list > 0
		if can_view_clients_list then
			table.sort(clients_list, function(a, b)
				return a:lower() < b:lower()
			end)
			local max_clients = 5
			if #clients_list > max_clients then
				retval = retval .. "tooltip[btn_view_clients;" ..
						-- TRANSLATORS: $1 is a list of players
						fgettext("Players:\n$1", table.concat(clients_list, "\n", 1, max_clients)) .. "\n..." .. "]"
			else
				retval = retval .. "tooltip[btn_view_clients;" ..
						fgettext("Players:\n$1", table.concat(clients_list, "\n")) .. "]"
			end
			retval = retval .. "style[btn_view_clients;padding=6]"
			retval = retval .. "image_button[4.5,1.3;0.5,0.5;" .. core.formspec_escape(defaulttexturedir ..
				"server_view_clients.png") .. ";btn_view_clients;]"
		else
			retval = retval .. "image[4.6,1.4;0.3,0.3;" .. core.formspec_escape(defaulttexturedir ..
				"server_view_clients_unavailable.png") .. "]"
		end

		-- Favorites toggle button
		if is_selected_fav() then
			retval = retval .. "tooltip[btn_delete_favorite;" .. fgettext("Remove favorite") .. "]"
			retval = retval .. "style[btn_delete_favorite;padding=6]"
			retval = retval .. "image_button[5,1.3;0.5,0.5;" ..
				core.formspec_escape(defaulttexturedir .. "server_favorite_delete.png") .. ";btn_delete_favorite;]"
		else
			retval = retval .. "tooltip[btn_add_favorite;" .. fgettext("Add favorite") .. "]"
			retval = retval .. "style[btn_add_favorite;padding=6]"
			retval = retval .. "image_button[5,1.3;0.5,0.5;" ..
				core.formspec_escape(defaulttexturedir .. "server_favorite.png") .. ";btn_add_favorite;]"
		end
	end

	retval = retval .. "container_end[]"

	-- Table
	retval = retval .. "tablecolumns[" ..
		-- TRANSLATORS: Also known as "latency"
		"image,tooltip=" .. fgettext("Ping") .. "," ..
		"0=" .. core.formspec_escape(defaulttexturedir .. "blank.png") .. "," ..
		"1=" .. core.formspec_escape(defaulttexturedir .. "server_ping_4.png") .. "," ..
		"2=" .. core.formspec_escape(defaulttexturedir .. "server_ping_3.png") .. "," ..
		"3=" .. core.formspec_escape(defaulttexturedir .. "server_ping_2.png") .. "," ..
		"4=" .. core.formspec_escape(defaulttexturedir .. "server_ping_1.png") .. "," ..
		"5=" .. core.formspec_escape(defaulttexturedir .. "server_favorite.png") .. "," ..
		"6=" .. core.formspec_escape(defaulttexturedir .. "server_public.png") .. "," ..
		"7=" .. core.formspec_escape(defaulttexturedir .. "server_incompatible.png") .. ";" ..
		"color,span=1;" ..
		"text,align=inline;"..
		"color,span=1;" ..
		"text,align=inline,width=4.25;" ..
		"image,tooltip=" .. fgettext("Creative mode") .. "," ..
		"0=" .. core.formspec_escape(defaulttexturedir .. "blank.png") .. "," ..
		"1=" .. core.formspec_escape(defaulttexturedir .. "server_flags_creative.png") .. "," ..
		"align=inline,padding=0.25,width=1.5;" ..
		-- TRANSLATORS: PvP = Player versus Player
		"image,tooltip=" .. fgettext("Damage / PvP") .. "," ..
		"0=" .. core.formspec_escape(defaulttexturedir .. "blank.png") .. "," ..
		"1=" .. core.formspec_escape(defaulttexturedir .. "server_flags_damage.png") .. "," ..
		"2=" .. core.formspec_escape(defaulttexturedir .. "server_flags_pvp.png") .. "," ..
		"align=inline,padding=0.25,width=1.5;" ..
		"color,align=inline,span=1;" ..
		"text,align=inline,padding=1]" ..
		"table[0.25,1;9.25,5.8;servers;"

	local servers = get_sorted_servers()

	local dividers = {
		fav = "5,#ffff00," .. fgettext("Favorites") .. ",,,0,0,,",
		public = "6,#4bdd42," .. fgettext("Public Servers") .. ",,,0,0,,",
		incompatible = "7,"..mt_color_grey.."," .. fgettext("Incompatible Servers") .. ",,,0,0,,"
	}
	local order = {"fav", "public", "incompatible"}

	tabdata.lookup = {} -- maps row number to server
	local rows = {}
	for _, section in ipairs(order) do
		local section_servers = servers[section]
		if next(section_servers) ~= nil then
			rows[#rows + 1] = dividers[section]
			for _, server in ipairs(section_servers) do
				tabdata.lookup[#rows + 1] = server
				rows[#rows + 1] = render_serverlist_row(server)
			end
		end
	end

	retval = retval .. table.concat(rows, ",")

	local selected_row_idx = 0
	if selected_server then
		for i, server in pairs(tabdata.lookup) do
			if selected_server.address == server.address and
					selected_server.port == server.port then
				selected_row_idx = i
				break
			end
		end
	end
	retval = retval .. ";" .. selected_row_idx .. "]"

	return retval
end

--------------------------------------------------------------------------------

local function parse_search_input(input)
	if not input:find("%S") then
		return -- Return nil if nothing to search for
	end

	-- Search is not case sensitive
	input = input:lower()

	local query = {keywords = {}, mods = {}, players = {}}

	-- Process quotation enclosed parts
	input = input:gsub('(%S?)"([^"]*)"(%S?)', function(before, match, after)
		if before == "" and after == "" then -- Also have be separated by spaces
			table.insert(query.keywords, match)
			return " "
		end
		return before..'"'..match..'"'..after
	end)

	-- Separate by space characters and handle special prefixes
	-- (words with special prefixes need an exact match and none of them can contain spaces)
	for word in input:gmatch("%S+") do
		local mod = word:match("^mod:(.*)")
		table.insert(query.mods, mod)
		local player = word:match("^player:(.*)")
		table.insert(query.players, player)
		local game = word:match("^game:(.*)")
		query.game = query.game or game
		local sort = word:match("^sort:(.*)")
		query.sort = query.sort or sort
		if not (mod or player or game or sort) then
			table.insert(query.keywords, word)
		end
	end

	return query
end

-- Prepares the server to be used for searching
local function uncapitalize_server(server)
	local function table_lower(t)
		local r = {}
		for i, s in ipairs(t or {}) do
			r[i] = s:lower()
		end
		return r
	end

	return {
		name = (server.name or ""):lower(),
		description = (server.description or ""):lower(),
		gameid = (server.gameid or ""):lower(),
		mods = table_lower(server.mods),
		clients_list = table_lower(server.clients_list),
	}
end

-- Returns false if the query does not match
-- otherwise returns a number to adjust the sorting priority
local function matches_query(server, query)
	-- Search is not case sensitive
	server = uncapitalize_server(server)

	-- Check if mods found
	for _, mod in ipairs(query.mods) do
		if table.indexof(server.mods, mod) < 0 then
			return false
		end
	end

	-- Check if players found
	for _, player in ipairs(query.players) do
		if table.indexof(server.clients_list, player) < 0 then
			return false
		end
	end

	-- Check if game matches
	if query.game and query.game ~= server.gameid then
		return false
	end

	-- Check if keyword found
	local name_matches = true
	local description_matches = true
	for _, keyword in ipairs(query.keywords) do
		name_matches = name_matches and server.name:find(keyword, 1, true)
		description_matches = description_matches and server.description:find(keyword, 1, true)
	end

	return name_matches and 50 or description_matches and 0
end

-- Sorts the serverlist depending on the query
local function sort_servers(servers, query)
	local sort_by = query.sort or "relevance"

	local reverse = false
	if string.sub(sort_by, 1, 1) == "-" then
		reverse = true
		sort_by = string.sub(sort_by, 2)
	end

	local get_compare_val
	if sort_by == "mods" then
		get_compare_val = function(v)
			return v.mods and #v.mods or 0
		end
	elseif sort_by == "lag" then
		get_compare_val = function(v)
			return v.lag or math.huge
		end
	else
		local sort_indices = {
			players = "clients",
			uptime = "uptime",
			name = "name",
			ping = "ping",
			relevance = "points",
		}
		get_compare_val = function(v)
			return v[sort_indices[sort_by] or "points"]
		end
	end

	-- For those lower is typically better
	local asc = {
		name = true,
		ping = true,
		lag = true,
	}

	table.sort(servers, function(a, b)
		if reverse == (asc[sort_by] or false) then
			return get_compare_val(a) > get_compare_val(b)
		else
			return get_compare_val(a) < get_compare_val(b)
		end
	end)
end

local function search_server_list(input, tabdata)
	menudata.search_result = nil
	if #serverlistmgr.servers < 2 then
		return
	end


	tabdata.pre_search_selection = tabdata.pre_search_selection or find_selected_server()

	-- setup the search query
	local query = parse_search_input(input)
	if not query then
		return
	end

	menudata.search_result = {}

	-- Search the serverlist
	local search_result = {}
	for i, server in ipairs(serverlistmgr.servers) do
		local match = matches_query(server, query)
		if match then
			server.points = #serverlistmgr.servers - i + match
			table.insert(search_result, server)
		end
	end

	if #search_result == 0 then
		return
	end

	local current_server = find_selected_server()

	sort_servers(search_result, query)
	menudata.search_result = search_result

	-- Keep current selection if it's in search results
	if current_server then
	    for _, server in ipairs(search_result) do
			if server.address == current_server.address and
					server.port == current_server.port then
				return
			end
		end
	end

	-- Find first compatible server (favorite or public)
	for _, server in ipairs(search_result) do
		if is_server_protocol_compat(server.proto_min, server.proto_max) then
			set_selected_server(server)
			return
		end
	end
	-- If no compatible server found, clear selection
	set_selected_server(nil)
end

local function main_button_handler(tabview, fields, name, tabdata)
	local old_name = tabdata.name
	local old_saved_password = get_saved_password(old_name)

	-- Parent lock: the password only unlocks this phone's local settings.
	-- The child side never receives editable address, port or town fields.
	if fields.btn_parent_photo then
		if not tabdata.parent_unlocked then
			return true
		end
		if not core.open_url then
			tabdata.find_note = "This build cannot open the phone camera."
		else
			tabdata.find_note = "ID photo: a grown-up approves one picture; "
				.. "only the town PC keeps the generated ID."
			core.open_url("kidtown-photo://send")
		end
		return true
	end

	if fields.btn_parent then
		tabdata.parent_page = true
		tabdata.parent_error = nil
		if tabdata.parent_unlocked then
			parent.ensure_from_settings(tabdata)
		end
		return true
	end

	if fields.btn_parent_forgot then
		tabdata.parent_recover_page = true
		tabdata.parent_error = nil
		return true
	end

	if fields.btn_parent_password then
		tabdata.parent_password_page = true
		tabdata.parent_error = nil
		return true
	end

	if fields.btn_parent_password_cancel then
		tabdata.parent_password_page = false
		tabdata.parent_error = nil
		return true
	end

	if fields.btn_parent_password_save then
		local old_pin = tostring(fields.parent_old_pin or "")
		local new_pin = tostring(fields.parent_new_pin or "")
		local again = tostring(fields.parent_new_pin2 or "")
		if not parent.check_pin(old_pin) then
			tabdata.parent_error = "The current password is not correct."
		elseif #new_pin < parent.MIN_PIN then
			tabdata.parent_error = "Use at least " .. tostring(parent.MIN_PIN)
				.. " characters for the new password."
		elseif new_pin ~= again then
			tabdata.parent_error = "The two new passwords do not match."
		else
			parent.set_pin(new_pin)
			tabdata.parent_recovery_code = parent.new_recovery_code()
			tabdata.parent_password_page = false
			tabdata.parent_unlocked = false
			tabdata.parent_page = true
			tabdata.parent_error = nil
		end
		return true
	end

	if fields.btn_parent_recovery then
		tabdata.parent_recovery_code = parent.new_recovery_code()
		tabdata.parent_error = nil
		return true
	end

	if fields.btn_parent_recover_cancel then
		tabdata.parent_recover_page = false
		tabdata.parent_error = nil
		return true
	end

	if fields.btn_parent_recover then
		local code = tostring(fields.parent_recovery_input or "")
		local new_pin = tostring(fields.parent_recover_pin or "")
		local again = tostring(fields.parent_recover_pin2 or "")
		if not parent.has_recovery_code() then
			tabdata.parent_error = "No recovery code is saved on this phone."
		elseif not parent.check_recovery_code(code) then
			tabdata.parent_error = "That recovery code is not correct."
		elseif #new_pin < parent.MIN_PIN then
			tabdata.parent_error = "Use at least " .. tostring(parent.MIN_PIN)
				.. " characters for the new password."
		elseif new_pin ~= again then
			tabdata.parent_error = "The two new passwords do not match."
		else
			parent.set_pin(new_pin)
			tabdata.parent_recovery_code = parent.new_recovery_code()
			tabdata.parent_recover_page = false
			tabdata.parent_unlocked = false
			tabdata.parent_page = true
			tabdata.parent_error = nil
		end
		return true
	end

	if fields.btn_parent_recovery_done then
		tabdata.parent_recovery_code = nil
		tabdata.parent_password_page = false
		tabdata.parent_recover_page = false
		tabdata.parent_error = nil
		if tabdata.parent_unlocked then
			parent.ensure_from_settings(tabdata)
		else
			tabdata.parent_page = true
		end
		return true
	end

	if fields.btn_parent_lock then
		tabdata.parent_unlocked = false
		tabdata.parent_page = false
		tabdata.parent_error = nil
		tabdata.parent_password_page = false
		tabdata.parent_recover_page = false
		tabdata.parent_recovery_code = nil
		return true
	end

	if fields.btn_parent_cancel then
		tabdata.parent_page = false
		tabdata.parent_error = nil
		tabdata.parent_password_page = false
		tabdata.parent_recover_page = false
		tabdata.parent_recovery_code = nil
		return true
	end

	if fields.btn_parent_create then
		local pin = tostring(fields.parent_pin or "")
		local again = tostring(fields.parent_pin2 or "")
		if #pin < parent.MIN_PIN then
			tabdata.parent_error = "Use at least " .. tostring(parent.MIN_PIN)
				.. " characters."
		elseif pin ~= again then
			tabdata.parent_error = "The two passwords do not match."
		else
			parent.set_pin(pin)
			tabdata.parent_unlocked = true
			tabdata.parent_recovery_code = parent.new_recovery_code()
			tabdata.parent_error = nil
			parent.ensure_from_settings(tabdata)
		end
		return true
	end

	if fields.btn_parent_unlock then
		if parent.check_pin(tostring(fields.parent_pin or "")) then
			tabdata.parent_unlocked = true
			tabdata.parent_error = nil
			parent.ensure_from_settings(tabdata)
		else
			tabdata.parent_error = "That password is not correct."
		end
		return true
	end

	if fields.btn_parent_find then
		parent.capture_fields(tabdata, fields)
		local ok, error_text = parent.save_address(tabdata)
		if not ok then
			tabdata.parent_error = error_text
			return true
		end
		local found = core.find_lan_server and core.find_lan_server()
		if found and found.address and is_lan_address(found.address) then
			tabdata.parent_host = found.address
			local current = fetch_lan_towns(found.address)
			if not current or #current == 0 then
				current = {{name = "Kid Town", port = found.port}}
			end
			tabdata.parent_towns = parent.merge_towns(current,
				parent.allowed_towns())
			tabdata.parent_error = nil
		else
			tabdata.parent_error = "No town found. Check Wi-Fi and Play access."
		end
		return true
	end

	if fields.parent_towns and tabdata.parent_page and
			tabdata.parent_unlocked then
		parent.capture_fields(tabdata, fields)
		local event = core.explode_textlist_event(fields.parent_towns)
		local row = event and event.index and tabdata.parent_towns and
			tabdata.parent_towns[event.index]
		if row and not row.placeholder then
			row.allowed = not row.allowed
		end
		return true
	end

	if fields.btn_parent_save then
		parent.capture_fields(tabdata, fields)
		local ok, error_text = parent.save_address(tabdata)
		if not ok then
			tabdata.parent_error = error_text
			return true
		end
		parent.save_allowed(tabdata.parent_towns)
		parent.enforce_child_address(tabdata)
		tabdata.parent_unlocked = false
		tabdata.parent_page = false
		tabdata.show_towns = false
		tabdata.towns = nil
		tabdata.parent_error = nil
		tabdata.find_note = "Parent settings saved. Only checked towns show now."
		return true
	end

	-- Selecting a saved name fills its password only when it was remembered.
	if fields.dd_saved_name ~= nil and fields.dd_saved_name ~= tabdata.dropdown_value then
		tabdata.dropdown_value = fields.dd_saved_name
		if fields.dd_saved_name == "Choose a name" then
			tabdata.name = ""
			tabdata.password = ""
			tabdata.remember = false
			core.settings:set("name", "")
		else
			tabdata.name = fields.dd_saved_name
			tabdata.password = get_saved_password(tabdata.name)
			tabdata.remember = tabdata.password ~= ""
			core.settings:set("name", tabdata.name)
		end
		return true
	end

	local name_changed = false
	if fields.te_name ~= nil then
		if fields.te_name ~= tabdata.name then
			name_changed = true
			tabdata.name = fields.te_name
			tabdata.password = get_saved_password(fields.te_name)
		end
		gamedata.playername = fields.te_name
		core.settings:set("name", fields.te_name)
	end

	if fields.te_pwd ~= nil then
		-- The password field may still contain the previous name's saved
		-- password. If the name changed, do not copy that stale value.
		if not name_changed or fields.te_pwd ~= old_saved_password then
			tabdata.password = fields.te_pwd
		end
	end

	if fields.chk_remember ~= nil then
		tabdata.remember = fields.chk_remember == "true"
	end

	if fields.servers then
		local event = core.explode_table_event(fields.servers)
		local server = tabdata.lookup[event.row]

		if server then
			if event.type == "DCL" then
				if not is_server_protocol_compat_or_error(
							server.proto_min, server.proto_max) then
					return true
				end

				gamedata.mode       = "join"
				gamedata.address    = server.address
				gamedata.port       = server.port
				gamedata.playername = fields.te_name
				gamedata.selected_world = 0

				if fields.te_pwd then
					gamedata.password = fields.te_pwd
				end

				if gamedata.address and gamedata.port then
					set_selected_server(server)
					core.start()
				end
				return true
			end
			if event.type == "CHG" then
				set_selected_server(server)
				tabdata.pre_search_selection = nil
				return true
			end
		end
	end

	if fields.btn_add_favorite then
		serverlistmgr.add_favorite(find_selected_server())
		return true
	end

	if fields.btn_delete_favorite then
		local idx = core.get_table_index("servers")
		if not idx then return end

		serverlistmgr.delete_favorite(tabdata.lookup[idx])
		set_selected_server(tabdata.lookup[idx+1])
		return true
	end

	if fields.btn_server_url then
		core.open_url_dialog(find_selected_server().url)
		return true
	end

	if fields.btn_view_clients then
		local dlg = create_clientslist_dialog(find_selected_server())
		dlg:set_parent(tabview)
		tabview:hide()
		dlg:show()
		return true
	end

	if fields.btn_view_mods then
		local dlg = create_server_list_mods_dialog(find_selected_server())
		dlg:set_parent(tabview)
		tabview:hide()
		dlg:show()
		return true
	end

	if fields.btn_mp_clear then
		tabdata.search_for = ""
		menudata.search_result = nil
		if tabdata.pre_search_selection then
			set_selected_server(tabdata.pre_search_selection)
			tabdata.pre_search_selection = nil
		end
		return true
	end

	if fields.btn_mp_search or fields.key_enter_field == "te_search" then
		tabdata.search_for = fields.te_search
		search_server_list(fields.te_search, tabdata)
		return true
	end

	if fields.btn_mp_refresh then
		serverlistmgr.sync()
		return true
	end

	if fields.towns then
		local event = core.explode_textlist_event(fields.towns)
		if event and event.index then
			tabdata.town_index = event.index
		end
		return true
	end

	if fields.btn_town_back then
		tabdata.show_towns = false
		return true
	end

	if fields.btn_town_use then
		local idx = core.get_textlist_index("towns") or tabdata.town_index
		local town = tabdata.towns and tabdata.towns[idx]
		if not town then
			tabdata.find_note = "Tap a town first."
			return true
		end
		core.settings:set("address", tabdata.towns_host)
		core.settings:set("remote_port", tostring(town.port))
		tabdata.found = {address = tabdata.towns_host, port = town.port,
			name = town.name}
		tabdata.show_towns = false
		tabdata.find_note = "Selected " .. town.name ..
			" -- enter your password, then tap Login."
		return true
	end

	if fields.btn_mp_find then
		if not core.find_lan_server then
			tabdata.find_note = "This build cannot search for a town."
		else
			local found = core.find_lan_server()
			if found and found.address and is_lan_address(found.address) then
				tabdata.found = found
				tabdata.towns_host = found.address
				local towns = fetch_lan_towns(found.address)
				if not towns or #towns == 0 then
					towns = {{name = "Kid Town", port = found.port}}
				end
				-- The parent's saved check list is the only source of truth
				-- for a locked child. A new or renamed town on the PC does
				-- not enter this list until a parent saves it.
				tabdata.towns = parent.filter_towns(towns)
				tabdata.town_index = 1
				tabdata.show_towns = true
				tabdata.find_note = nil
			else
				tabdata.found = nil
				tabdata.show_towns = false
				tabdata.towns = nil
				tabdata.find_note = "No town found. Check Wi-Fi and Play access."
			end
		end
		return true
	end

	local login_address = fields.te_address
	if login_address == nil or login_address:match("^%s*$") then
		login_address = (tabdata.found and tabdata.found.address) or
			core.settings:get("address") or ""
	end
	local login_port = fields.te_port
	if login_port == nil or login_port:match("^%s*$") then
		login_port = (tabdata.found and tostring(tabdata.found.port)) or
			core.settings:get("remote_port") or "30000"
	end
	local host_filled = (login_address ~= "") and
		login_port:match("^%s*[1-9][0-9]*%s*$")
	local te_port_number = tonumber(login_port)

	if fields.btn_mp_login and not host_filled then
		tabdata.find_note = "Tap Find towns, or type the town address and port."
		return true
	end
	if (fields.btn_mp_login or fields.key_enter) and host_filled and
			not tabdata.parent_unlocked and not parent.port_is_allowed(te_port_number) then
		tabdata.find_note = "Choose a town a parent has allowed first."
		return true
	end

	if (fields.btn_mp_login or fields.key_enter) and host_filled then
		local login_name = tabdata.name or ""
		login_name = login_name:match("^%s*(.-)%s*$")
		local login_password = tabdata.password or ""
		if login_name == "" then
			tabdata.find_note = "Choose a name first."
			return true
		end
		if login_password == "" then
			tabdata.find_note = "This town needs a password. Choose one the first time, or ask a grown-up."
			return true
		end

		tabdata.name = login_name
		remember_name(login_name)
		if tabdata.remember then
			set_saved_password(login_name, login_password)
		else
			set_saved_password(login_name, "")
		end
		core.settings:set("name", login_name)

		gamedata.mode       = "join"
		gamedata.playername = login_name
		gamedata.password   = login_password
		gamedata.address    = login_address
		gamedata.port       = te_port_number

		-- The phone UI has one Login button. Allow the engine to log in a
		-- returning player or create the account on first use.
		gamedata.allow_login_or_register = "any"
		gamedata.selected_world = 0

		local idx = core.get_table_index("servers")
		local server = idx and tabdata.lookup[idx]

		if server and server.address == gamedata.address and
				server.port == gamedata.port then

			pcall(serverlistmgr.add_favorite, server)

			if not is_server_protocol_compat_or_error(
						server.proto_min, server.proto_max) then
				return true
			end
		else
			pcall(serverlistmgr.add_favorite, {
				address = gamedata.address,
				port = gamedata.port,
			})
		end

		core.settings:set("address",     login_address)
		core.settings:set("remote_port", login_port)

		core.start()
		return true
	end

	if fields.btn_mp_register and host_filled then
		local idx = core.get_table_index("servers")
		local server = idx and tabdata.lookup[idx]
		if server and (server.address ~= login_address or server.port ~= te_port_number) then
			server = nil
		end

		if server and not is_server_protocol_compat_or_error(
					server.proto_min, server.proto_max) then
			return true
		end

		local dlg = create_register_dialog(login_address, te_port_number, server)
		dlg:set_parent(tabview)
		tabview:hide()
		dlg:show()
		return true
	end

	return false
end

local function on_change(type)
	if type == "ENTER" then
		mm_game_theme.set_engine()
		serverlistmgr.sync()
	end
end

return {
	name = "online",
	caption = fgettext("Join Game"),
	cbf_formspec = get_formspec,
	cbf_button_handler = main_button_handler,
	on_change = on_change
}
