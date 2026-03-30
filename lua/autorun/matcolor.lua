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

	hook.Add("InitPostEntity", "matcolor", function()
		net.Start("matcolor_sync")
		net.SendToServer()
	end)
else
	util.AddNetworkString("matcolor_create")
	util.AddNetworkString("matcolor_sync")

	net.Receive("matcolor_sync", function(_, ply)
		local data = {}

		for _, v in pairs(ents.GetAll()) do
			if not IsValid(v) or not v.GetSubMaterial then
				continue
			end

			local model = v:GetModel()

			if v:IsWorld() or not model then
				continue
			end

			local info = util.GetModelInfo(model)

			if not info or not info.MaterialCount then
				continue
			end

			for i = 0, info.MaterialCount - 1 do
				local submat = v:GetSubMaterial(i)

				if submat == "" then
					continue
				end

				if Reverse[submat] then
					table.insert(data, {
						v, i, submat, Colors[submat]
					})
				end
			end
		end

		for _, v in ipairs(data) do
			net.Start("matcolor_create")
				net.WriteEntity(v[1])
				net.WriteUInt(v[2], 7)
				net.WriteString(v[3])
				net.WriteColor(v[4])
			net.Send(ply)
		end
	end)
end
