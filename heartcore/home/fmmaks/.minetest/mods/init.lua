local initial_max_hp = tonumber(core.settings:get("heartcore_initial_max_hp"))
local storage = core.get_mod_storage()

if initial_max_hp == nil then
	initial_max_hp = 20 -- 20 half hearts
end

core.register_on_newplayer(function(player)
	local name = player:get_player_name()
	storage:set_int(name.."_max_hearts", initial_max_hp)
	player:set_properties({hp_max = initial_max_hp})
	player:set_hp(initial_max_hp)
end)

core.register_on_dieplayer(function(player)
	local name = player:get_player_name()
	local maxHP = storage:get_int(name.."_max_hearts")
	
	maxHP = math.max(maxHP - 1, 0)
	-- player:set_properties({hp_max = maxHP})
	-- player:set_hp(maxHP)
	storage:set_int(name.."_max_hearts", maxHP)
	
	if maxHP == 0 then
		core.log("action", name.." lost all his lives and was banned from server")
		core.chat_send_all(name.." lost all his lives and was banned from server")
		core.ban_player(name)
	else
		core.log("action", name.." lost one of his lives and has "..maxHP.." left")
		core.chat_send_all(name.." lost one of his lives and has "..maxHP.." left")
	end
end)

core.register_on_respawnplayer(function(player)
	local name = player:get_player_name()
	local maxHP = storage:get_int(name.."_max_hearts")

	player:set_properties({hp_max = maxHP})
	player:set_hp(maxHP)
end)

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local maxHP = storage:get_int(name.."_max_hearts")
	
	player:set_properties({hp_max = maxHP})
	player:set_hp(maxHP)
	
	if maxHP == 0 then
		-- player has probably been unbaned
		player:set_properties({hp_max = initial_max_hp})
		player:set_hp(initial_max_hp)
		storage:set_int(name.."_max_hearts", initial_max_hp)
	end
end)
