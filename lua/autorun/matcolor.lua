module("matcolor", package.seeall)

Cache = Cache or {}
Reverse = Reverse or {}
Colors = Colors or {}

local flags = {
	[0x00000001] = "$debug",
	[0x00000002] = "$no_fullbright",
	[0x00000004] = "$no_draw",
	[0x00000008] = "$use_in_fillrate_mode",
	[0x00000010] = "$vertexcolor",
	[0x00000020] = "$vertexalpha",
	[0x00000040] = "$selfillum",
	[0x00000080] = "$additive",
	[0x00000100] = "$alphatest",
	[0x00000200] = "$multipass",
	[0x00000400] = "$znearer",
	[0x00000800] = "$model",
	[0x00001000] = "$flat",
	[0x00002000] = "$nocull",
	[0x00004000] = "$nofog",
	[0x00008000] = "$ignorez",
	[0x00100000] = "$basealphaenvmapmask",
	[0x00200000] = "$translucent",
	[0x00400000] = "$normalmapalphaenvmapmask ",
	[0x00800000] = "$softwareskin",
	[0x01000000] = "$opaquetexture",
	[0x02000000] = "$envmapmode",
	[0x04000000] = "$nodecal",
	[0x08000000] = "$halflambert",
	[0x10000000] = "$wireframe",
	[0x20000000] = "$allowalphatocoverage"
}

function Create(mat, color)
	if isstring(mat) then
		mat = Material(mat)
	end

	local reverse = Reverse["!" .. mat:GetName()]

	if reverse then
		mat = Material(reverse)
	end

	local hex = "#" .. bit.tohex(color.r, 2) .. bit.tohex(color.g, 2) .. bit.tohex(color.b, 2)
	local name = util.CRC(mat:GetName()) .. hex
	local matName = "!" .. name

	if not Reverse[matName] then
		Reverse[matName] = mat:GetName()
		Colors[matName] = color
	end

	if Cache[name] or SERVER then
		return matName
	end

	local params = {}

	for k in pairs(mat:GetKeyValues()) do
		params[k] = mat:GetString(k)
	end

	for k, v in pairs(flags) do
		if bit.band(params["$flags"], k) == k then
			params[v] = 1
		end
	end

	params["$flags"] = nil
	params["$flags2"] = nil

	params["$flags_defined"] = nil
	params["$flags_defined2"] = nil

	local newMat = CreateMaterial(name, mat:GetShader(), params)

	newMat:SetVector("$color2", color:ToVector())

	Cache[name] = newMat

	return matName
end

function FindIndex(ent, base, occurrence)
	local count = 0

	for i, mat in ipairs(ent:GetMaterials()) do
		if mat == base then
			count = count + 1

			if count == occurrence then
				return i - 1
			end
		end
	end

	return nil
end

function GetOccurrence(ent, index)
	local materials = ent:GetMaterials()
	local targetMat = materials[index + 1]

	if not targetMat then
		return nil, nil
	end

	local occurrence = 0

	for i = 1, index + 1 do
		if materials[i] == targetMat then
			occurrence = occurrence + 1
		end
	end

	return targetMat, occurrence
end

function CreateFromEntity(ent, index, color)
	local material = ent:GetMaterials()[index + 1]
	local submat = ent:GetSubMaterial(index)

	if submat != "" then
		material = submat
	end

	ent:SetSubMaterial(index, Create(material, color))

	return material
end

if CLIENT then
	net.Receive("matcolor_create", function()
		local ent = net.ReadEntity()
		local index = net.ReadUInt(16)
		local mat = net.ReadString()
		local color = net.ReadColor(false)

		local newMat = Create(mat, color)

		if IsValid(ent) then
			ent:SetSubMaterial(index, newMat)
		end
	end)

	hook.Add("NetworkEntityCreated", "matcolor", function(ent)
		net.Start("matcolor_sync")
			net.WriteEntity(ent)
		net.SendToServer()
	end)
else
	util.AddNetworkString("matcolor_create")
	util.AddNetworkString("matcolor_sync")

	-- PreEntityCopy temporarily clears our !-prefixed submaterials so the engine's
	-- _DuplicatedSubMaterials doesn't capture them (they cause material swaps on load).
	-- PostEntityCopy restores them immediately after the save snapshot is taken.
	function SetupEntityHooks(ent)
		if ent.matcolor_hook then
			return
		end

		ent.matcolor_hook = true

		ent.PreEntityCopy = function(self)
			-- Store current matcolor submaterials and clear them
			self.matcolor_submats = {}

			for i = 0, #self:GetMaterials() - 1 do
				local submat = self:GetSubMaterial(i)

				if submat != "" and matcolor.Reverse[submat] then
					self.matcolor_submats[i] = submat
					self:SetSubMaterial(i, "")
				end
			end
		end

		ent.PostEntityCopy = function(self)
			-- Restore the matcolor submaterials after save snapshot
			if self.matcolor_submats then
				for i, submat in pairs(self.matcolor_submats) do
					self:SetSubMaterial(i, submat)
				end

				self.matcolor_submats = nil
			end
		end
	end

	net.Receive("matcolor_sync", function(_, ply)
		local ent = net.ReadEntity()

		if not IsValid(ent) or not ent.GetSubMaterial then
			return
		end

		local model = ent:GetModel()

		if ent:IsWorld() or not model or model[1] == "*" then
			return
		end

		for i = 0, #ent:GetMaterials() - 1 do
			local submat = ent:GetSubMaterial(i)

			if submat == "" then
				continue
			end

			if Reverse[submat] then
				net.Start("matcolor_create")
					net.WriteEntity(ent)
					net.WriteUInt(i, 16)
					net.WriteString(submat)
					net.WriteColor(Colors[submat])
				net.Send(ply)
			end
		end
	end)

	function LoadEntityModifier(ent, data)
		for _, v in ipairs(data) do
			local mat = v.Material
			local color = v.Color

			if not mat or not color then
				continue
			end

			-- Find the correct index using name+occurrence matching,
			-- since the engine may reorder materials after save/load.
			local index

			if v.Base and v.Occurrence then
				index = matcolor.FindMaterialIndex(ent, v.Base, v.Occurrence) or v.Index
			end

			if index == nil then
				continue
			end

			color = Color(color.r, color.g, color.b)

			local newMat = matcolor.Create(mat, color)

			ent:SetSubMaterial(index, newMat)

			net.Start("matcolor_create")
				net.WriteEntity(ent)
				net.WriteUInt(index, 16)
				net.WriteString(mat)
				net.WriteColor(color)
			net.Broadcast()
		end
	end

	function RestoreFromEntityMods()
		for _, ent in pairs(ents.GetAll()) do
			if not IsValid(ent) then
				continue
			end

			local mods = ent.EntityMods

			if not mods or not mods.matcolor then
				continue
			end

			-- Clear any stale !-prefixed submaterial overrides the engine
			-- may have restored from _DuplicatedSubMaterials
			for i = 0, #ent:GetMaterials() - 1 do
				local submat = ent:GetSubMaterial(i)

				if submat[1] == "!" then
					ent:SetSubMaterial(i, "")
				end
			end

			ent.matcolor_hook = nil

			LoadEntityModifier(ent, mods.matcolor)

			-- Re-install hooks for future saves
			matcolor.SetupEntityHooks(ent)
		end
	end

	hook.Add("Restore", "matcolor", function()
		timer.Simple(1, matcolor.RestoreFromEntityMods)
	end)
end
