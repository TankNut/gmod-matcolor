TOOL.Category = "Render"
TOOL.Name = "Material Color"

TOOL.ClientConVar["index"] = 0

TOOL.ClientConVar["r"] = 255
TOOL.ClientConVar["g"] = 255
TOOL.ClientConVar["b"] = 255

function TOOL:LeftClick(trace)
	local ent = trace.Entity

	if not IsValid(ent) then
		return
	end

	if SERVER then
		local index = self:GetClientNumber("index", 0)
		local r = self:GetClientNumber("r", 255)
		local g = self:GetClientNumber("g", 255)
		local b = self:GetClientNumber("b", 255)

		local color = Color(r, g, b)

		local mat = matcolor.CreateFromEntity(ent, index, color)

		net.Start("matcolor_create")
			net.WriteEntity(ent)
			net.WriteUInt(index, 7)
			net.WriteString(mat)
			net.WriteColor(color)
		net.Broadcast()

		self:StoreEntityModifier(ent)
	end

	return true
end

function TOOL:RightClick(trace)
	local ent = trace.Entity

	if not IsValid(ent) then
		return
	end

	if SERVER then
		local index = self:GetClientNumber("index", 0)

		local reverse = matcolor.Reverse[ent:GetSubMaterial(index)]

		if reverse then
			ent:SetSubMaterial(index, reverse)

			self:StoreEntityModifier(ent)
		end
	end

	return true
end

function TOOL:Reload(trace)
	local ent = trace.Entity

	if not IsValid(ent) then
		return
	end

	if SERVER then
		local index = self:GetClientNumber("index", 0)

		local mat = ent:GetMaterials()[index + 1]
		local submat = ent:GetSubMaterial(index)

		if submat != "" then
			mat = submat
		end

		local color = Material(mat):GetVector("$color2"):ToColor()
		local ply = self:GetOwner()

		ply:ConCommand("matcolor_r " .. color.r)
		ply:ConCommand("matcolor_g " .. color.g)
		ply:ConCommand("matcolor_b " .. color.b)
	end

	return true
end

if CLIENT then
	function TOOL:Scroll(dir)
		if not IsValid(self.TargetEntity) then
			return
		end

		local ent = self.TargetEntity
		local index = self:GetClientNumber("index", 0) + dir
		local max = #ent:GetMaterials() - 1

		if index < 0 then
			index = max
		elseif index > max then
			index = 0
		end

		RunConsoleCommand("submaterial_index", index)

		if CLIENT then
			self.ModelCache[ent:GetModel()] = index
		end

		return true
	end

	function TOOL:ScrollUp()
		return self:Scroll(-1)
	end

	function TOOL:ScrollDown()
		return self:Scroll(1)
	end

	local function getActiveTool(ply, tool)
		local weapon = ply:GetActiveWeapon()

		if not IsValid(weapon) or weapon:GetClass() != "gmod_tool" or weapon.Mode != tool then
			return
		end

		return weapon:GetToolObject(tool)
	end

	local function playerBindPress(ply, bind, pressed)
		if not pressed then
			return
		end

		if bind == "invnext" then
			local tool = getActiveTool(ply, "matcolor")

			if not tool then
				return
			end

			return tool:ScrollDown()
		elseif bind == "invprev" then
			local tool = getActiveTool(ply, "matcolor")

			if not tool then
				return
			end

			return tool:ScrollUp()
		end
	end

	if game.SinglePlayer() then
		timer.Simple(5, function()
			hook.Add("PlayerBindPress", "matcolor", playerBindPress)
		end)
	else
		hook.Add("PlayerBindPress", "matcolor", playerBindPress)
	end

	function TOOL:Think()
		self.ModelCache = self.ModelCache or {}

		local ent = LocalPlayer():GetEyeTrace().Entity

		if ent:IsWorld() then
			ent = NULL
		end

		if IsValid(ent) then
			local mdl = ent:GetModel()

			if self.ModelCache[mdl] then
				if self.ModelCache[mdl] != self:GetClientNumber("index", 0) then
					RunConsoleCommand("matcolor_index", self.ModelCache[mdl])
				end
			elseif self:GetClientNumber("index", 0) != 0 then
				RunConsoleCommand("matcolor_index", 0)
			end
		end

		self.TargetEntity = ent
	end

	function TOOL:DrawHUD()
		if IsValid(self.TargetEntity) then
			local ent = self.TargetEntity
			local materials = ent:GetMaterials()

			local offset = ScrW() * 0.5 - 50
			local maxWidth = 0
			local textHeight = 0

			surface.SetFont("ChatFont")

			local header = string.format("%s: %s materials", ent, #materials)

			maxWidth, textHeight = surface.GetTextSize(header)

			maxWidth = maxWidth + textHeight + 2

			for _, v in ipairs(materials) do
				local width = surface.GetTextSize(v)

				maxWidth = math.max(maxWidth, width + textHeight + 2)
			end

			local listHeight = 13 + textHeight * (#materials + 1)
			local listWidth = 8 + maxWidth
			local listX = offset - listWidth
			local listY = ScrH() * 0.5 - listHeight * 0.5

			surface.SetDrawColor(64, 64, 95, 191)
			surface.DrawRect(listX, listY, listWidth, listHeight)

			surface.SetTextColor(255, 255, 255, 255)
			surface.SetTextPos(listX + 4, listY + 4)
			surface.DrawText(header)

			local r = self:GetClientNumber("r", 255)
			local g = self:GetClientNumber("g", 255)
			local b = self:GetClientNumber("b", 255)

			surface.SetDrawColor(r, g, b)
			surface.DrawRect(offset - textHeight - 3, listY + 4, textHeight, textHeight)

			surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawLine(listX + 2.5, listY + textHeight + 7, offset - 3.5, listY + textHeight + 7)

			surface.SetDrawColor(0, 127, 0, 191)
			surface.DrawRect(listX + 3, listY + textHeight + 9 + self:GetClientNumber("index", 0) * textHeight, listWidth - 6, textHeight)

			for k, mat in ipairs(materials) do
				local submat = ent:GetSubMaterial(k - 1)

				if submat != "" then
					mat = submat
				end

				local name = mat
				local reverse = matcolor.Reverse[mat]

				if reverse then
					name = reverse
				end

				surface.SetTextPos(listX + 4, listY + 9 + textHeight * k)
				surface.DrawText(name)

				local color2 = Material(mat):GetVector("$color2"):ToColor()

				surface.SetDrawColor(color2)
				surface.DrawRect(offset - textHeight - 3, listY + 9 + textHeight * k, textHeight, textHeight)
			end
		end
	end

	local default = TOOL:BuildConVarList()

	function TOOL.BuildCPanel(panel)
		panel:AddControl("Header", {Description = "#tool.matcolor.desc"})

		panel:ToolPresets("matcolor", default)

		panel:ColorPicker("#tool.matcolor.color", "matcolor_r", "matcolor_g", "matcolor_b").Mixer:SetAlphaBar(false)
	end
else
	function TOOL:StoreEntityModifier(ent)
		local data = {}

		for i = 0, #ent:GetMaterials() - 1 do
			local submat = ent:GetSubMaterial(i)

			if submat == "" or not matcolor.Reverse[submat] then
				continue
			end

			table.insert(data, {
				Material = matcolor.Reverse[submat],
				Index = i,
				Color = Material(submat):GetVector("$color2"):ToColor()
			})
		end

		if #data == 0 then
			duplicator.ClearEntityModifier(ent, "matcolor")
		else
			duplicator.StoreEntityModifier(ent, "matcolor", data)
		end
	end

	duplicator.RegisterEntityModifier("matcolor", function(ply, ent, data)
		timer.Simple(1, function()
			for _, v in ipairs(data) do
				local mat = v.Material
				local index = v.Index
				local color = v.Color

				color = Color(color.r, color.g, color.b)

				local newMat = matcolor.Create(mat, color)

				ent:SetSubMaterial(index, newMat)

				net.Start("matcolor_create")
					net.WriteEntity(ent)
					net.WriteUInt(index, 7)
					net.WriteString(mat)
					net.WriteColor(color)
				net.Broadcast()
			end
		end)
	end)
end
