--!nonstrict
-- GameBuilderTycoon.lua (Script, dans ServerScriptService)
-- Un plot par joueur (circuit complet, bâtiments, flotte), économie recalculée depuis le profil,
-- roulette gratuite + achat de véhicules, atelier d'améliorations, invités VIP, récompense quotidienne,
-- gains hors-ligne, sauvegarde robuste, gamepasses / developer products.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Circuits = require(script.Parent:WaitForChild("Circuits"))
local TB = require(script.Parent:WaitForChild("TrackBuilder"))
local Veh = require(script.Parent:WaitForChild("Vehicules"))
local Bat = require(script.Parent:WaitForChild("Batiments"))
local U = require(script.Parent:WaitForChild("Utils"))
local creerPiece = U.creerPiece

Players.CharacterAutoLoads = false -- on fait apparaître le joueur sur SON plot une fois celui-ci construit

local store = DataStoreService:GetDataStore(Config.DATASTORE)
local ancienStore = DataStoreService:GetDataStore("RaceTrackTycoon_MasterFinal_v1")
local rng = Random.new()

-- ===== Remotes =====
local function obtenirRemote(classe, nom)
	local r = ReplicatedStorage:FindFirstChild(nom)
	if not r then
		r = Instance.new(classe)
		r.Name = nom
		r.Parent = ReplicatedStorage
	end
	return r
end
local categorieEvent = obtenirRemote("RemoteEvent", "ChangerCategorieEvent")
local devCommandEvent = obtenirRemote("RemoteEvent", "DevCommandEvent")
local rouletteFunc = obtenirRemote("RemoteFunction", "TirageRouletteFunc")
local etatGrilleEvent = obtenirRemote("RemoteEvent", "EtatGrilleEvent")
local gestionFlotteEvent = obtenirRemote("RemoteEvent", "GestionFlotteEvent")
obtenirRemote("RemoteEvent", "OuvrirRouletteEvent") -- conservé pour compatibilité
local etatJeuEvent = obtenirRemote("RemoteEvent", "EtatJeuEvent")
local notifEvent = obtenirRemote("RemoteEvent", "NotifEvent")
local ouvrirPanelEvent = obtenirRemote("RemoteEvent", "OuvrirPanelEvent")
local ameliorationFunc = obtenirRemote("RemoteFunction", "AmeliorationFunc")
local dailyFunc = obtenirRemote("RemoteFunction", "DailyFunc")
local codeFunc = obtenirRemote("RemoteFunction", "CodeFunc")
local etatFunc = obtenirRemote("RemoteFunction", "GetEtatFunc")

local sessions = {}   -- [player] = session
local slotsUtilises = {}
local batParId = {}
for _, b in ipairs(Config.BATIMENTS) do batParId[b.Id] = b end

-- ===== Profil =====
local function profilParDefaut()
	return {
		Version = Config.VERSION_DATA, Cash = 300, TotalGagne = 0, Prestige = 0, Achats = {}, Palier = 1,
		Flotte = { "GT_Base" }, Garage = {}, Ameliorations = {}, ProchainTirage = 0, Offre = {}, OffreAchetes = {},
		Streak = 0, DernierDaily = 0, Codes = {}, Receipts = {}, DernierQuit = 0, Filtre = "Mixte",
	}
end

local function completer(base, data)
	for k, v in pairs(base) do
		if data[k] == nil then data[k] = v end
	end
	return data
end

local function migrerAncien(old)
	local p = profilParDefaut()
	p.Cash = old.Cash or p.Cash
	p.Prestige = math.max(0, math.floor(((old.PrestigeBonus or 1) - 1) / 0.5 + 0.5))
	p.Palier = math.clamp(old.PalierGrille or 1, 1, #Config.PALIERS_GRILLE)
	if old.Flotte and #old.Flotte > 0 then p.Flotte = old.Flotte end
	if old.Reserve then p.Garage = old.Reserve end
	for _, id in ipairs(old.Achats or {}) do
		if batParId[id] then table.insert(p.Achats, id) end
	end
	return p
end

local function appelAvecRetry(fn)
	for essai = 1, 4 do
		local ok, res = pcall(fn)
		if ok then return true, res end
		task.wait(1.5 * essai)
	end
	return false, nil
end

local function charger(player)
	local cle = tostring(player.UserId)
	local ok, data = appelAvecRetry(function() return store:GetAsync(cle) end)
	if not ok then return nil end -- on NE remplace PAS un profil existant si le DataStore est en panne
	if data then return completer(profilParDefaut(), data) end
	local okOld, old = appelAvecRetry(function() return ancienStore:GetAsync(cle) end)
	if okOld and old then return migrerAncien(old) end
	return profilParDefaut()
end

local function sauvegarder(sess, quitter)
	if not sess.Chargee or not sess.Profil then return false end
	local p = sess.Profil
	if quitter then p.DernierQuit = os.time() end
	local ok = appelAvecRetry(function()
		return store:UpdateAsync(tostring(sess.Player.UserId), function() return p end)
	end)
	return ok
end

-- ===== Calculs économiques =====
local function niveau(p, id) return p.Ameliorations[id] or 0 end
local function valeurAmelio(p, id)
	local a = Config.ameliorationParId(id)
	return Config.valeurAmelioration(a, niveau(p, id))
end
local function facteur(p) return Config.COUT_CIRCUIT_FACTEUR ^ p.Prestige end
local function indexCircuit(p) return (p.Prestige % #Circuits) + 1 end
local function placesMax(p) return Config.PALIERS_GRILLE[p.Palier].Places end

local function multFlotte(p)
	local m = 1
	for _, id in ipairs(p.Flotte) do m += Config.trouverVehicule(id).Mult end
	return m * (1 + p.Prestige * Config.BONUS_PRESTIGE)
end
local function revenuBase(p)
	local somme = 3
	for _, id in ipairs(p.Achats) do
		local b = batParId[id]
		if b then somme += b.Revenu end
	end
	return somme * facteur(p)
end
local function boostVip(sess)
	local total, maintenant = 1, os.time()
	for _, b in ipairs(sess.Boosts) do
		if b.Fin > maintenant then total += (b.Mult - 1) end
	end
	return total
end
local function revenuTotal(sess)
	local p = sess.Profil
	local gp = sess.Gp.DoubleCash and Config.GAMEPASS.DoubleCash.Mult or 1
	return revenuBase(p) * multFlotte(p) * valeurAmelio(p, "Revenu") * gp * boostVip(sess)
end

-- ===== Notifications / état client =====
local function notifier(player, texte, couleur)
	notifEvent:FireClient(player, texte, couleur)
end

local function setCash(sess, valeur)
	sess.Profil.Cash = valeur
	local ls = sess.Player:FindFirstChild("leaderstats")
	if ls then ls.Cash.Value = math.floor(valeur) end
end
local function ajouterCash(sess, delta) setCash(sess, sess.Profil.Cash + delta) end

local function serialiserListe(ids)
	local res = {}
	for idx, id in ipairs(ids) do
		local v = Config.trouverVehicule(id)
		table.insert(res, { Index = idx, Id = v.Id, Nom = v.Nom, Type = v.Type, Rarete = v.Rarete, Mult = v.Mult, Vitesse = v.Vitesse })
	end
	return res
end

local function etatPourClient(sess)
	local p = sess.Profil
	local maintenant = os.time()
	local offre = {}
	for i, id in ipairs(p.Offre) do
		table.insert(offre, { Id = id, Achete = p.OffreAchetes[tostring(i)] == true })
	end
	local boosts = {}
	for _, b in ipairs(sess.Boosts) do
		if b.Fin > maintenant then table.insert(boosts, { Nom = b.Nom, Mult = b.Mult, Reste = b.Fin - maintenant }) end
	end
	local inv = nil
	if sess.Invite then
		inv = { Id = sess.Invite.Def.Id, Nom = sess.Invite.Def.Nom, Mult = sess.Invite.Def.MultFinal, Frais = sess.Invite.Frais, Reste = math.max(0, sess.Invite.Expire - maintenant) }
	end
	local jour = math.floor(maintenant / 86400)
	return {
		Amelio = p.Ameliorations, Achats = p.Achats, Prestige = p.Prestige,
		Offre = offre, Cases = valeurAmelio(p, "Cases"), Chance = valeurAmelio(p, "Chance"),
		RechargeReste = math.max(0, p.ProchainTirage - maintenant), RechargeTotal = valeurAmelio(p, "Recharge"),
		Boosts = boosts, Invite = inv, Streak = p.Streak, DailyDispo = jour > p.DernierDaily,
		Revenu = revenuTotal(sess), RevenuBase = revenuBase(p), MultFlotte = multFlotte(p), Facteur = facteur(p),
		Gp = sess.Gp, Filtre = p.Filtre, Palier = p.Palier, PalierMax = #Config.PALIERS_GRILLE,
	}
end
local function pousserEtat(sess)
	if sess.Pret then etatJeuEvent:FireClient(sess.Player, etatPourClient(sess)) end
end

local function mettreAJourRevenu(sess)
	local p = sess.Profil
	local ls = sess.Player:FindFirstChild("leaderstats")
	if ls then ls["Revenu/s"].Value = math.floor(revenuTotal(sess)) end
	etatGrilleEvent:FireClient(sess.Player, #p.Flotte, placesMax(p), multFlotte(p), Circuits[indexCircuit(p)].Nom, serialiserListe(p.Flotte), serialiserListe(p.Garage))
	pousserEtat(sess)
end

local function respawnFlotte(sess)
	Veh.reapparaitre(sess.Plot, sess.Profil.Flotte, sess.Profil.Filtre)
end

-- ===== Plots =====
local function allouerPlot(player)
	local k = 1
	while slotsUtilises[k] do k += 1 end
	slotsUtilises[k] = true
	local col, row = (k - 1) % 3, math.floor((k - 1) / 3)
	local dossier = Instance.new("Folder")
	dossier.Name = "Plot_" .. k
	local plot = { Slot = k, Owner = player, Origine = Vector3.new(col * Config.SPACING_X, 0, row * Config.SPACING_Z), Dossier = dossier, Pilotes = {} }
	for _, n in ipairs({ "Decor", "Infra", "Boutons", "Vehicules" }) do
		local f = Instance.new("Folder")
		f.Name = n
		f.Parent = dossier
		plot[n] = f
	end
	dossier.Parent = workspace
	local modeles = Instance.new("Folder")
	modeles.Name = "Modeles_" .. k
	modeles.Parent = ServerStorage
	plot.Modeles = modeles
	return plot
end

local function libererPlot(plot)
	TB.demolir(plot)
	if plot.Dossier then plot.Dossier:Destroy() end
	if plot.Modeles then plot.Modeles:Destroy() end
	slotsUtilises[plot.Slot] = nil
end

-- ===== Invités VIP =====
local function freqVip(sess)
	local f = valeurAmelio(sess.Profil, "VipFreq")
	if sess.Gp.VIP_Plus then f *= 0.7 end
	return math.max(60, f)
end
local function planifierInvite(sess) sess.VipProchain = os.time() + freqVip(sess) end

local function retirerInvite(sess)
	if sess.Invite then
		if sess.Invite.Modele then sess.Invite.Modele:Destroy() end
		sess.Invite = nil
	end
end

local function accueillirInvite(sess)
	local inv = sess.Invite
	if not inv then return end
	local p = sess.Profil
	if p.Cash < inv.Frais then
		notifier(sess.Player, "Fonds insuffisants pour accueillir " .. inv.Def.Nom .. " ($" .. math.floor(inv.Frais) .. ")", Color3.fromRGB(255, 90, 90))
		return
	end
	ajouterCash(sess, -inv.Frais)
	local duree = valeurAmelio(p, "VipDuree")
	table.insert(sess.Boosts, { Nom = inv.Def.Nom, Mult = inv.Def.MultFinal, Fin = os.time() + duree })
	notifier(sess.Player, inv.Def.Nom .. " : revenus x" .. string.format("%.1f", inv.Def.MultFinal) .. " pendant " .. math.floor(duree) .. " s !", inv.Def.Couleur)
	retirerInvite(sess)
	planifierInvite(sess)
	mettreAJourRevenu(sess)
end

local function fairePatienterInvite(sess)
	local total = 0
	for _, v in ipairs(Config.VIPS) do total += v.Poids end
	local r, acc, choix = rng:NextNumber() * total, 0, Config.VIPS[1]
	for _, v in ipairs(Config.VIPS) do
		acc += v.Poids
		if r <= acc then choix = v break end
	end
	local def = table.clone(choix)
	def.MultFinal = 1 + (choix.Mult - 1) * valeurAmelio(sess.Profil, "VipForce")
	local frais = math.max(50, choix.Frais * revenuBase(sess.Profil) * (sess.Gp.VIP_Plus and 0.75 or 1))
	local modele, prompt = Bat.creerInvite(sess.Plot.Ctx, def, sess.Plot.Infra)
	sess.Invite = { Def = def, Modele = modele, Frais = frais, Expire = os.time() + Config.VIP.DelaiAccueil }
	prompt.Triggered:Connect(function(plr)
		if plr == sess.Player then accueillirInvite(sess) end
	end)
	notifier(sess.Player, def.Nom .. " arrive au Salon VIP ! Accueille-le avant " .. Config.VIP.DelaiAccueil .. " s.", def.Couleur)
	pousserEtat(sess)
end

-- ===== Bâtiments / boutons =====
local function debloquer(sess, id)
	sess.Debloques[id] = true
	local m = sess.Plot.Modeles:FindFirstChild(id)
	if m then m.Parent = sess.Plot.Infra end
	if id == "Salon_VIP" and not sess.VipProchain then planifierInvite(sess) end
end

local function aAchete(p, id)
	for _, a in ipairs(p.Achats) do if a == id then return true end end
	return false
end

local function formater(n)
	if n >= 1e12 then return string.format("%.2fT", n / 1e12) end
	if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
	if n >= 1e4 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n))
end

local function rafraichirBoutons(sess)
	local p = sess.Profil
	local f = facteur(p)
	for id, pad in pairs(sess.Pads) do
		local b = batParId[id]
		if b then
			local visible = (not aAchete(p, id)) and (b.Prerequis == nil or aAchete(p, b.Prerequis))
			pad.Part.Transparency = visible and 0.1 or 1
			pad.Part.CanTouch = visible
			pad.Gui.Enabled = visible
			if visible then
				pad.Label.Text = b.Nom .. "\n$" .. formater(b.Prix * f) .. ((b.Revenu > 0) and ("  (+" .. formater(b.Revenu * f) .. "/s)") or "")
			end
		end
	end
	local pg = sess.Pads["_Grille"]
	if pg then
		local nxt = Config.PALIERS_GRILLE[p.Palier + 1]
		pg.Label.Text = nxt and ("GRILLE : " .. placesMax(p) .. " → " .. nxt.Places .. " places\n$" .. formater(nxt.Prix)) or "GRILLE MAX"
	end
end

local function creerPad(sess, id, x, z, couleur, texte, action)
	local ctx = sess.Plot.Ctx
	U.Decalage = ctx.orgHome
	local part = creerPiece(sess.Plot.Boutons, "Pad_" .. id, Vector3.new(12, 0.6, 12), Vector3.new(x, 0.4, z), couleur, Enum.Material.Neon, 0.1, false)
	U.Decalage = CFrame.new()
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 230, 0, 58)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.MaxDistance = 90
	gui.Parent = part
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
	lbl.BackgroundTransparency = 0.15
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.Text = texte
	lbl.Parent = gui
	Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 8)
	part.Touched:Connect(function(hit)
		local plr = Players:GetPlayerFromCharacter(hit.Parent)
		if plr ~= sess.Player or not sess.Pret or sess.Debounce[id] then return end
		sess.Debounce[id] = true
		task.delay(0.7, function() sess.Debounce[id] = nil end)
		action()
	end)
	sess.Pads[id] = { Part = part, Gui = gui, Label = lbl }
end

local acheterBatiment, acheterPalier, reconstruire

local function creerBoutons(sess)
	sess.Pads = {}
	for i, b in ipairs(Config.BATIMENTS) do
		local row, col = math.floor((i - 1) / 8), (i - 1) % 8
		local couleur = (b.Type == "Prestige") and Color3.fromRGB(255, 190, 30) or Color3.fromRGB(50, 220, 110)
		creerPad(sess, b.Id, -98 + 28 * col, -108 - 20 * row, couleur, b.Nom, function() acheterBatiment(sess, b.Id) end)
	end
	creerPad(sess, "_Roulette", -63, -88, Color3.fromRGB(170, 70, 255), "ROULETTE GRATUITE\n(véhicules à acheter)", function() ouvrirPanelEvent:FireClient(sess.Player, "Roulette") end)
	creerPad(sess, "_Grille", -21, -88, Color3.fromRGB(60, 140, 255), "GRILLE", function() acheterPalier(sess) end)
	creerPad(sess, "_Atelier", 21, -88, Color3.fromRGB(255, 140, 40), "ATELIER\n(améliorations)", function() ouvrirPanelEvent:FireClient(sess.Player, "Atelier") end)
	creerPad(sess, "_Daily", 63, -88, Color3.fromRGB(255, 220, 60), "RÉCOMPENSE\nQUOTIDIENNE", function() ouvrirPanelEvent:FireClient(sess.Player, "Daily") end)
	rafraichirBoutons(sess)
end

function acheterBatiment(sess, id)
	local p = sess.Profil
	local b = batParId[id]
	if not b or sess.Occupe or aAchete(p, id) then return end
	if b.Prerequis and not aAchete(p, b.Prerequis) then return end
	local prix = (b.Type == "Prestige") and Config.PRIX_PRESTIGE * facteur(p) or b.Prix * facteur(p)
	if p.Cash < prix then
		notifier(sess.Player, "Il te faut $" .. formater(prix), Color3.fromRGB(255, 90, 90))
		return
	end
	if b.Type == "Prestige" then
		reconstruire(sess, true)
		return
	end
	ajouterCash(sess, -prix)
	table.insert(p.Achats, id)
	debloquer(sess, id)
	rafraichirBoutons(sess)
	mettreAJourRevenu(sess)
	notifier(sess.Player, b.Nom .. " construit !", Color3.fromRGB(80, 230, 140))
end

function acheterPalier(sess)
	local p = sess.Profil
	local nxt = Config.PALIERS_GRILLE[p.Palier + 1]
	if not nxt then return end
	if p.Cash < nxt.Prix then
		notifier(sess.Player, "Il te faut $" .. formater(nxt.Prix), Color3.fromRGB(255, 90, 90))
		return
	end
	ajouterCash(sess, -nxt.Prix)
	p.Palier += 1
	rafraichirBoutons(sess)
	mettreAJourRevenu(sess)
	notifier(sess.Player, "Grille agrandie : " .. nxt.Places .. " places !", Color3.fromRGB(80, 160, 255))
end

-- Construit (ou reconstruit au prestige) tout le monde du joueur
function reconstruire(sess, prestige)
	if sess.Occupe then return end
	sess.Occupe = true
	local ancienPret = sess.Pret
	sess.Pret = false
	local p = sess.Profil
	retirerInvite(sess)
	if prestige then
		p.Prestige += 1
		p.Achats = {}
		sess.Boosts = {}
		sess.VipProchain = nil
		setCash(sess, 300 * facteur(p))
	end
	sess.Debloques = {}
	sess.Pads = {}
	TB.demolir(sess.Plot)
	local ctx = TB.construire(sess.Plot, indexCircuit(p))
	if not ctx then
		warn("Construction du plot échouée pour " .. sess.Player.Name)
		sess.Occupe = false
		sess.Pret = ancienPret
		return
	end
	sess.Plot.Ctx = ctx
	Veh.preparer(sess.Plot)
	creerBoutons(sess)
	for _, id in ipairs(p.Achats) do debloquer(sess, id) end
	sess.Pret = true
	sess.Occupe = false
	respawnFlotte(sess)
	rafraichirBoutons(sess)
	mettreAJourRevenu(sess)
	if prestige then
		sauvegarder(sess)
		notifier(sess.Player, "PRESTIGE ! Nouveau circuit : " .. Circuits[indexCircuit(p)].Nom .. " (+50% de revenu permanent)", Color3.fromRGB(255, 200, 40))
		local char = sess.Player.Character
		if char then char:PivotTo(ctx.spawnCF) end
	end
end

-- ===== Roulette / véhicules =====
local function indexRarete(r)
	for i, v in ipairs(Config.RARETES) do if v == r then return i end end
	return 1
end

local function tirerVehicule(p)
	local filtre = p.Filtre
	local chance = valeurAmelio(p, "Chance")
	local candidats, parRarete = {}, {}
	for _, v in ipairs(Config.VEHICULES) do
		if not ((filtre == "Voitures" and v.Type == "Moto") or (filtre == "Motos" and v.Type == "Voiture")) then
			table.insert(candidats, v)
			parRarete[v.Rarete] = (parRarete[v.Rarete] or 0) + 1
		end
	end
	local total, poids = 0, {}
	for i, v in ipairs(candidats) do
		local w = Config.POIDS_RARETE[v.Rarete] / parRarete[v.Rarete] * (1 + chance * (indexRarete(v.Rarete) - 1) * 0.5)
		poids[i] = w
		total += w
	end
	local r, acc = rng:NextNumber() * total, 0
	for i, v in ipairs(candidats) do
		acc += poids[i]
		if r <= acc then return v end
	end
	return candidats[1]
end

local function ajouterVehicule(sess, id)
	local p = sess.Profil
	local enPiste = #p.Flotte < placesMax(p)
	if enPiste then table.insert(p.Flotte, id) else table.insert(p.Garage, id) end
	if enPiste then respawnFlotte(sess) end
	return enPiste
end

local function enRafale(sess)
	local t = os.clock()
	if sess.DernierAppel and t - sess.DernierAppel < 0.15 then return true end
	sess.DernierAppel = t
	return false
end

local function serialiserOffre(p)
	local o = {}
	for i, id in ipairs(p.Offre) do table.insert(o, { Id = id, Achete = p.OffreAchetes[tostring(i)] == true }) end
	return o
end

rouletteFunc.OnServerInvoke = function(player, action, index)
	local sess = sessions[player]
	if not sess or not sess.Pret or enRafale(sess) then return { Succes = false } end
	local p = sess.Profil
	if action == nil or action == "Tirer" then
		local reste = p.ProchainTirage - os.time()
		if reste > 0 then return { Succes = false, Message = "Recharge en cours", Reste = reste } end
		local n = math.clamp(math.floor(valeurAmelio(p, "Cases")), 1, Config.ROULETTE.CasesMax)
		local offre = {}
		for i = 1, n do offre[i] = tirerVehicule(p).Id end
		p.Offre, p.OffreAchetes = offre, {}
		p.ProchainTirage = os.time() + valeurAmelio(p, "Recharge")
		pousserEtat(sess)
		return { Succes = true, Offre = serialiserOffre(p), Reste = valeurAmelio(p, "Recharge") }
	elseif action == "Acheter" then
		if type(index) ~= "number" or index % 1 ~= 0 or not p.Offre[index] or p.OffreAchetes[tostring(index)] then return { Succes = false, Message = "Offre invalide" } end
		local v = Config.trouverVehicule(p.Offre[index])
		if p.Cash < v.Prix then return { Succes = false, Message = "Fonds insuffisants" } end
		ajouterCash(sess, -v.Prix)
		p.OffreAchetes[tostring(index)] = true
		local enPiste = ajouterVehicule(sess, v.Id)
		mettreAJourRevenu(sess)
		notifier(player, v.Nom .. (enPiste and " rejoint la piste !" or " ajouté au garage."), Config.COULEUR_RARETE[v.Rarete])
		return { Succes = true, Offre = serialiserOffre(p), EnPiste = enPiste }
	end
	return { Succes = false }
end

categorieEvent.OnServerEvent:Connect(function(player, mode)
	local sess = sessions[player]
	if not sess or not sess.Pret then return end
	if mode == "Mixte" or mode == "Voitures" or mode == "Motos" then
		sess.Profil.Filtre = mode
		respawnFlotte(sess)
		pousserEtat(sess)
	end
end)

gestionFlotteEvent.OnServerEvent:Connect(function(player, action, index)
	local sess = sessions[player]
	if not sess or not sess.Pret or type(index) ~= "number" or index % 1 ~= 0 then return end
	local p = sess.Profil
	if action == "RetirerDePiste" and p.Flotte[index] then
		table.insert(p.Garage, table.remove(p.Flotte, index))
		respawnFlotte(sess)
	elseif action == "DeployerEnPiste" and p.Garage[index] then
		if #p.Flotte < placesMax(p) then
			table.insert(p.Flotte, table.remove(p.Garage, index))
			respawnFlotte(sess)
		end
	elseif action == "VendreReserve" and p.Garage[index] then
		local v = Config.trouverVehicule(table.remove(p.Garage, index))
		ajouterCash(sess, math.floor(v.Prix * Config.PRIX_REVENDRE_RATIO))
	else
		return
	end
	mettreAJourRevenu(sess)
end)

-- ===== Atelier (améliorations), quotidien, codes =====
ameliorationFunc.OnServerInvoke = function(player, id)
	local sess = sessions[player]
	if not sess or not sess.Pret or enRafale(sess) or type(id) ~= "string" then return { Succes = false } end
	local p = sess.Profil
	local a = Config.ameliorationParId(id)
	if not a then return { Succes = false, Message = "Inconnue" } end
	if a.Requis and not aAchete(p, a.Requis) then return { Succes = false, Message = "Requiert : " .. batParId[a.Requis].Nom } end
	local lvl = niveau(p, id)
	if lvl >= a.Max then return { Succes = false, Message = "Niveau max" } end
	local prix = Config.prixAmelioration(a, lvl)
	if p.Cash < prix then return { Succes = false, Message = "Fonds insuffisants" } end
	ajouterCash(sess, -prix)
	p.Ameliorations[id] = lvl + 1
	mettreAJourRevenu(sess)
	return { Succes = true, Niveau = lvl + 1 }
end

local function reclamerDaily(sess)
	local p = sess.Profil
	local jour = math.floor(os.time() / 86400)
	if jour <= p.DernierDaily then return { Succes = false, Message = "Déjà récupérée aujourd'hui" } end
	p.Streak = (jour == p.DernierDaily + 1) and math.min(p.Streak + 1, 7) or 1
	p.DernierDaily = jour
	local gain = math.max(500, revenuTotal(sess) * 60 * 10 * p.Streak)
	ajouterCash(sess, gain)
	local bonus = ""
	if p.Streak == 7 and sess.Debloques.Salon_VIP and not sess.Invite then
		sess.VipProchain = os.time()
		bonus = " + un invité VIP arrive !"
	end
	mettreAJourRevenu(sess)
	return { Succes = true, Message = "Jour " .. p.Streak .. "/7 : +$" .. formater(gain) .. bonus, Streak = p.Streak }
end
dailyFunc.OnServerInvoke = function(player)
	local sess = sessions[player]
	if not sess or not sess.Pret or enRafale(sess) then return { Succes = false } end
	return reclamerDaily(sess)
end
codeFunc.OnServerInvoke = function(player, code)
	local sess = sessions[player]
	if not sess or not sess.Pret or enRafale(sess) or type(code) ~= "string" then return { Succes = false } end
	code = string.upper(string.sub(code, 1, 24))
	local def = Config.CODES[code]
	if not def then return { Succes = false, Message = "Code invalide" } end
	if sess.Profil.Codes[code] then return { Succes = false, Message = "Code déjà utilisé" } end
	sess.Profil.Codes[code] = true
	local gain = math.max(1000, revenuTotal(sess) * 60 * def.Minutes)
	ajouterCash(sess, gain)
	return { Succes = true, Message = "+$" .. formater(gain) }
end
etatFunc.OnServerInvoke = function(player)
	local sess = sessions[player]
	if sess and sess.Pret then return etatPourClient(sess) end
end

-- ===== Monétisation =====
local function verifierGamepasses(sess)
	for cle, gp in pairs(Config.GAMEPASS) do
		sess.Gp[cle] = false
		if gp.Id ~= 0 then
			local ok, possede = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(sess.Player.UserId, gp.Id) end)
			sess.Gp[cle] = ok and possede or false
		end
	end
end
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _, achete)
	local sess = sessions[player]
	if achete and sess then
		verifierGamepasses(sess)
		mettreAJourRevenu(sess)
	end
end)
MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local sess = player and sessions[player]
	if not sess or not sess.Pret then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local rid = tostring(info.PurchaseId)
	if sess.Profil.Receipts[rid] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local prod = Config.PRODUITS[info.ProductId]
	if not prod then return Enum.ProductPurchaseDecision.NotProcessedYet end
	if prod.Type == "Cash" then
		ajouterCash(sess, math.max(1000, revenuTotal(sess) * 60 * prod.Minutes))
	elseif prod.Type == "Spin" then
		sess.Profil.ProchainTirage = 0
	end
	sess.Profil.Receipts[rid] = os.time()
	local n = 0
	for _ in pairs(sess.Profil.Receipts) do n += 1 end
	if n > 60 then -- on purge les plus anciens reçus
		local plusAncien, t0 = nil, math.huge
		for k, t in pairs(sess.Profil.Receipts) do if t < t0 then plusAncien, t0 = k, t end end
		sess.Profil.Receipts[plusAncien] = nil
	end
	mettreAJourRevenu(sess)
	if not sauvegarder(sess) then return Enum.ProductPurchaseDecision.NotProcessedYet end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ===== Outils développeur (Studio ou admins uniquement) =====
devCommandEvent.OnServerEvent:Connect(function(player, action, param)
	local autorise = RunService:IsStudio() or table.find(Config.ADMINS, player.UserId) ~= nil
	local sess = sessions[player]
	if not autorise or not sess or not sess.Pret then return end
	if action == "AddCash" then
		ajouterCash(sess, 1e9)
		mettreAJourRevenu(sess)
	elseif action == "SelectTrack" and type(param) == "number" then
		sess.Profil.Prestige = math.clamp(math.floor(param), 1, #Circuits) - 1
		sess.Profil.Achats = {}
		reconstruire(sess, false)
	elseif action == "ResetSave" then
		local ancien = sess.Profil
		sess.Profil = profilParDefaut()
		sess.Profil.DernierQuit = ancien.DernierQuit
		setCash(sess, sess.Profil.Cash)
		reconstruire(sess, false)
	end
end)

-- ===== Cycle de vie des joueurs =====
local function placerJoueur(sess)
	local char = sess.Player.Character
	if not char or not sess.Plot.Ctx then return end
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if hrp then char:PivotTo(sess.Plot.Ctx.spawnCF) end
end

local function apparaitre(sess)
	local player = sess.Player
	local ok = pcall(function() player:LoadCharacter() end)
	if ok then
		placerJoueur(sess)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Died:Connect(function()
				task.wait(Players.RespawnTime)
				if sessions[player] then apparaitre(sess) end
			end)
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local cash = Instance.new("NumberValue")
	cash.Name = "Cash"
	cash.Parent = ls
	local rev = Instance.new("NumberValue")
	rev.Name = "Revenu/s"
	rev.Parent = ls
	ls.Parent = player

	local sess = { Player = player, Profil = nil, Plot = nil, Pret = false, Chargee = false, Occupe = false, Boosts = {}, Gp = {}, Debloques = {}, Pads = {}, Debounce = {} }
	sessions[player] = sess

	local profil = charger(player)
	if not profil then
		player:Kick("Impossible de charger ta sauvegarde (service Roblox indisponible). Réessaie dans quelques instants : ta progression est protégée.")
		sessions[player] = nil
		return
	end
	sess.Profil = profil
	sess.Chargee = true
	setCash(sess, profil.Cash)
	verifierGamepasses(sess)
	sess.Plot = allouerPlot(player)
	sess.Occupe = false
	reconstruire(sess, false)
	if not player.Parent then return end
	apparaitre(sess)

	-- gains hors-ligne
	if profil.DernierQuit > 0 then
		local ecoule = math.min(os.time() - profil.DernierQuit, valeurAmelio(profil, "OfflineH") * 3600)
		if ecoule > 120 then
			local gain = revenuTotal(sess) * ecoule * valeurAmelio(profil, "Offline")
			ajouterCash(sess, gain)
			task.delay(4, function()
				notifier(player, "Pendant ton absence : +$" .. formater(gain), Color3.fromRGB(255, 220, 90))
			end)
		end
	end
	mettreAJourRevenu(sess)
end)

Players.PlayerRemoving:Connect(function(player)
	local sess = sessions[player]
	if not sess then return end
	sessions[player] = nil
	sess.Pret = false
	sauvegarder(sess, true)
	if sess.Plot then task.spawn(libererPlot, sess.Plot) end
end)

game:BindToClose(function()
	if RunService:IsStudio() then task.wait(1) end
	local restants = 0
	for _, sess in pairs(sessions) do
		restants += 1
		task.spawn(function()
			sauvegarder(sess, true)
			restants -= 1
		end)
	end
	local t0 = os.clock()
	while restants > 0 and os.clock() - t0 < 25 do task.wait(0.2) end
end)

-- ===== Boucles : simulation (30 Hz), économie (1 Hz), sauvegarde auto =====
local accu = 0
RunService.Heartbeat:Connect(function(dt)
	accu += dt
	if accu < 1 / 30 then return end
	local pas = accu
	accu = 0
	for _, sess in pairs(sessions) do
		local plot = sess.Plot
		if sess.Pret and plot and plot.Ctx then
			Veh.simuler(plot, pas)
			for id, fn in pairs(plot.Ctx.animations) do
				if sess.Debloques[id] then fn(pas) end
			end
		end
	end
end)

task.spawn(function()
	local cpt = 0
	while true do
		task.wait(1)
		cpt += 1
		local maintenant = os.time()
		for _, sess in pairs(sessions) do
			if sess.Pret then
				local gain = revenuTotal(sess)
				ajouterCash(sess, gain)
				sess.Profil.TotalGagne += gain
				-- boosts expirés
				local change = false
				for i = #sess.Boosts, 1, -1 do
					if sess.Boosts[i].Fin <= maintenant then
						table.remove(sess.Boosts, i)
						change = true
					end
				end
				-- invités VIP
				if sess.Debloques.Salon_VIP then
					if sess.Invite and maintenant > sess.Invite.Expire then
						notifier(sess.Player, sess.Invite.Def.Nom .. " est reparti(e)...", Color3.fromRGB(200, 200, 210))
						retirerInvite(sess)
						planifierInvite(sess)
						change = true
					elseif not sess.Invite and sess.VipProchain and maintenant >= sess.VipProchain and sess.Plot.Ctx.vipPos then
						fairePatienterInvite(sess)
					end
				end
				if change then mettreAJourRevenu(sess)
				else
					local ls = sess.Player:FindFirstChild("leaderstats")
					if ls then ls["Revenu/s"].Value = math.floor(gain) end
				end
				if cpt % 5 == 0 then mettreAJourRevenu(sess) end
			end
		end
		if cpt % 60 == 0 then
			for _, sess in pairs(sessions) do
				task.spawn(sauvegarder, sess)
			end
		end
	end
end)
