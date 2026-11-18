--!nonstrict
-- Config.lua (ModuleScript, dans ReplicatedStorage) : TOUT l'équilibrage du jeu est ici.
-- Pour changer un prix, un revenu, une rareté, une amélioration : modifie ce fichier uniquement.
local Config = {}

Config.VERSION_DATA = 2
Config.DATASTORE = "RaceTrackTycoon_v2"
Config.MAX_FLOTTE = 24
Config.SPACING_X, Config.SPACING_Z = 2600, 3400   -- distance entre deux plots joueurs
Config.PRIX_REVENDRE_RATIO = 0.35                  -- revente d'un véhicule du garage = 35% de son prix
Config.COUT_CIRCUIT_FACTEUR = 2.6                  -- les prix des bâtiments x2.6 à chaque circuit (prestige)
Config.PRIX_PRESTIGE = 12000000                    -- x facteur circuit
Config.BONUS_PRESTIGE = 0.5                        -- +50% de revenu permanent par prestige

-- ===== MONÉTISATION (remplace les 0 par tes vrais IDs Roblox, voir le guide) =====
Config.GAMEPASS = {
	DoubleCash = { Id = 0, Nom = "x2 Cash", Mult = 2 },
	VIP_Plus   = { Id = 0, Nom = "VIP+ (invités + fréquents)", Mult = 1 },
	AutoSpin   = { Id = 0, Nom = "Roulette auto", Mult = 1 },
}
Config.PRODUITS = { -- Developer Products
	[0] = { Nom = "Pack Cash S", Type = "Cash", Minutes = 15 },  -- = 15 min de ton revenu actuel
	[1] = { Nom = "Pack Cash M", Type = "Cash", Minutes = 60 },
	[2] = { Nom = "Pack Cash L", Type = "Cash", Minutes = 240 },
	[3] = { Nom = "Relance roulette immédiate", Type = "Spin" },
}

-- ===== ADMIN & CODES PROMO =====
Config.ADMINS = {}  -- ex : { 123456789 } (UserIds autorisés à utiliser les commandes dev en jeu publié ; en Studio c'est automatique)
Config.CODES = {    -- code -> récompense (minutes de revenu actuel). Usage unique par joueur.
	BIENVENUE = { Minutes = 30 },
	LANCEMENT = { Minutes = 120 },
}

-- ===== RARETÉS =====
Config.RARETES = { "Commun", "Rare", "Epique", "Legendaire", "Mythique", "Secret" }
Config.POIDS_RARETE = { Commun = 55, Rare = 28, Epique = 12, Legendaire = 4, Mythique = 0.9, Secret = 0.08 }
Config.COULEUR_RARETE = {
	Commun = Color3.fromRGB(160, 170, 185), Rare = Color3.fromRGB(50, 175, 255), Epique = Color3.fromRGB(185, 75, 255),
	Legendaire = Color3.fromRGB(255, 165, 30), Mythique = Color3.fromRGB(255, 65, 85), Secret = Color3.fromRGB(40, 255, 200),
}

-- ===== VÉHICULES (20) : Style = archétype 3D, Prix = prix d'achat après tirage =====
local function V(Id, Nom, Type, Rarete, Style, Mult, Vitesse, Prix, r, g, b)
	return { Id = Id, Nom = Nom, Type = Type, Rarete = Rarete, Style = Style, Mult = Mult, Vitesse = Vitesse, Prix = Prix, Couleur = Color3.fromRGB(r, g, b) }
end
Config.VEHICULES = {
	V("GT_Base", "Clio Cup IV", "Voiture", "Commun", "Berline", 0.20, 86, 800, 225, 230, 235),
	V("GT_Tourisme", "Peugeot 208 Rally4", "Voiture", "Commun", "Berline", 0.22, 88, 1500, 235, 120, 30),
	V("Moto_Base", "Yamaha MT-07 Cup", "Moto", "Commun", "MotoBase", 0.20, 92, 800, 45, 135, 220),
	V("Moto_Trophee", "Honda CBR500 Cup", "Moto", "Commun", "MotoBase", 0.22, 94, 1500, 220, 40, 40),
	V("GT_Sport", "Mégane 3 RS Trophy", "Voiture", "Rare", "Sport", 0.45, 98, 6000, 245, 195, 20),
	V("GT_Rally", "Subaru WRX Rally", "Voiture", "Rare", "Rally", 0.50, 100, 9000, 30, 80, 190),
	V("Moto_Sport", "Yamaha R6 Race", "Moto", "Rare", "MotoR6", 0.45, 104, 6000, 35, 195, 95),
	V("Moto_Classic", "Kawasaki Ninja 400 Pro", "Moto", "Rare", "MotoR6", 0.50, 106, 9000, 90, 220, 60),
	V("GT_GT3", "Porsche 911 GT3 RS", "Voiture", "Epique", "GT3", 0.85, 114, 45000, 30, 115, 235),
	V("GT_Proto", "Audi R8 LMS", "Voiture", "Epique", "GT3", 0.95, 116, 70000, 200, 200, 210),
	V("Moto_SBK", "Ducati Panigale V4R", "Moto", "Epique", "MotoSBK", 0.85, 120, 45000, 220, 30, 40),
	V("Moto_Superstock", "BMW M1000RR", "Moto", "Epique", "MotoSBK", 0.95, 122, 70000, 240, 240, 245),
	V("GT_Hyper", "Ferrari 499P Hypercar", "Voiture", "Legendaire", "Hyper", 1.70, 132, 400000, 205, 25, 30),
	V("GT_LMP", "Toyota GR010 Hybrid", "Voiture", "Legendaire", "Hyper", 1.90, 134, 600000, 235, 235, 240),
	V("F1_Classic", "Formule 1 Turbo 1988", "Voiture", "Legendaire", "F1", 2.20, 140, 900000, 245, 245, 245),
	V("Moto_GP", "KTM RC16 MotoGP", "Moto", "Legendaire", "MotoGP", 1.70, 138, 400000, 255, 95, 10),
	V("Moto_E", "LiveWire Électrique GP", "Moto", "Legendaire", "MotoGP", 1.90, 140, 600000, 20, 220, 255),
	V("F1_Mythic", "Monoplace F1 V10", "Voiture", "Mythique", "F1", 3.50, 156, 3000000, 255, 210, 40),
	V("Hyper_Zero", "Concept Zéro-G", "Voiture", "Mythique", "Hyper", 4.50, 165, 6000000, 90, 20, 160),
	V("Secret_Phantom", "Phantom X (Secret)", "Voiture", "Secret", "F1", 12.0, 190, 25000000, 20, 255, 190),
}

-- ===== ROULETTE =====
Config.ROULETTE = {
	CasesBase = 3,          -- nombre de cases (véhicules proposés par tirage) au départ
	CasesMax = 12,
	RechargeBase = 40,      -- secondes entre deux tirages gratuits
	RechargeMin = 8,
}

-- ===== GRILLE (places en piste) =====
Config.PALIERS_GRILLE = {
	{ Places = 3, Prix = 0 }, { Places = 6, Prix = 2500 }, { Places = 10, Prix = 25000 }, { Places = 14, Prix = 180000 },
	{ Places = 18, Prix = 1200000 }, { Places = 21, Prix = 9000000 }, { Places = 24, Prix = 60000000 },
}

-- ===== AMÉLIORATIONS RÉPÉTABLES (niveaux permanents, conservés au prestige) =====
-- Prix(niveau) = PrixBase * Croissance^niveau ; Valeur(niveau) = Base + Pas*niveau
Config.AMELIORATIONS = {
	{ Id = "Revenu",   Nom = "Boost de revenu",       Desc = "+10% de revenu par niveau",           Max = 30, PrixBase = 500,   Croissance = 1.42, Base = 1.0,  Pas = 0.10, Fmt = "x%.2f" },
	{ Id = "Chance",   Nom = "Chance roulette",       Desc = "Véhicules rares plus fréquents",      Max = 25, PrixBase = 1500,  Croissance = 1.48, Base = 0,    Pas = 0.06, Fmt = "+%.0f%%", Pct = true },
	{ Id = "Cases",    Nom = "Cases de roulette",     Desc = "+1 véhicule proposé par tirage",      Max = 9,  PrixBase = 8000,  Croissance = 2.3,  Base = 3,    Pas = 1,    Fmt = "%d cases" },
	{ Id = "Recharge", Nom = "Recharge roulette",     Desc = "-3 s entre deux tirages gratuits",    Max = 10, PrixBase = 3000,  Croissance = 1.75, Base = 40,   Pas = -3,   Fmt = "%d s" },
	{ Id = "VipFreq",  Nom = "Invités plus fréquents", Desc = "Un invité arrive plus souvent (Salon VIP)", Max = 10, PrixBase = 40000, Croissance = 1.6, Base = 300, Pas = -15, Fmt = "%d s", Requis = "Salon_VIP" },
	{ Id = "VipDuree", Nom = "Bonus VIP plus longs",  Desc = "+12 s de durée par niveau",           Max = 10, PrixBase = 40000, Croissance = 1.6,  Base = 90,   Pas = 12,   Fmt = "%d s", Requis = "Salon_VIP" },
	{ Id = "VipForce", Nom = "Bonus VIP plus forts",  Desc = "+8% de puissance par niveau",         Max = 10, PrixBase = 60000, Croissance = 1.7,  Base = 1.0,  Pas = 0.08, Fmt = "x%.2f", Requis = "Salon_VIP" },
	{ Id = "Offline",  Nom = "Gains hors-ligne",      Desc = "+5% de rendement hors-ligne",         Max = 12, PrixBase = 5000,  Croissance = 1.5,  Base = 0.10, Pas = 0.05, Fmt = "%.0f%%", Pct = true },
	{ Id = "OfflineH", Nom = "Durée hors-ligne max",  Desc = "+30 min de gains hors-ligne max",     Max = 10, PrixBase = 12000, Croissance = 1.6,  Base = 2,    Pas = 0.5,  Fmt = "%.1f h" },
}

-- ===== INVITÉS DE MARQUE (Salon VIP) : bonus de revenu temporaires =====
-- Poids = chance d'arrivée ; Mult = bonus de base (x revenu pendant la durée) ; Frais = coût d'accueil (x revenu/s)
Config.VIPS = {
	{ Id = "Influenceur", Nom = "Influenceur Auto",     Poids = 40, Mult = 1.5, Frais = 20,  Couleur = Color3.fromRGB(255, 120, 200) },
	{ Id = "Pilote",      Nom = "Pilote Légendaire",    Poids = 28, Mult = 2.0, Frais = 40,  Couleur = Color3.fromRGB(230, 40, 40) },
	{ Id = "Chanteur",    Nom = "Star de la Chanson",   Poids = 18, Mult = 2.5, Frais = 70,  Couleur = Color3.fromRGB(180, 80, 255) },
	{ Id = "President",   Nom = "Président de Marque",  Poids = 10, Mult = 3.5, Frais = 120, Couleur = Color3.fromRGB(40, 120, 235) },
	{ Id = "Sheikh",      Nom = "Cheikh Collectionneur", Poids = 4, Mult = 6.0, Frais = 250, Couleur = Color3.fromRGB(255, 200, 40) },
}
Config.VIP = { ArriveeBase = 300, DureeBase = 90, DelaiAccueil = 60, SlotsBase = 1 }

-- ===== BÂTIMENTS (chaîne d'achat linéaire) =====
local B = function(Id, Nom, Prix, Revenu) return { Id = Id, Nom = Nom, Prix = Prix, Revenu = Revenu, Type = "Infra" } end
Config.BATIMENTS = {
	B("Vibreurs", "Poser les Vibreurs FIA", 150, 5),
	B("Bacs_Gravier", "Bacs à Gravier (Échappatoires)", 260, 5),
	B("Parking_Visiteurs", "Parking Visiteurs", 440, 6),
	B("Gradins_1", "Grandes Tribunes (Spectateurs)", 760, 7),
	B("Marshals_Cameras", "Commissaires & Caméras TV", 1300, 10),
	B("Tour_Controle", "Tour de Direction (Visitable)", 2300, 15),
	B("Paddocks", "Stands, Pit Lane & Garages", 3900, 22),
	B("Bannieres_Sponsors", "Arches & Bannières Sponsors", 6700, 33),
	B("Boutique_Souvenirs", "Boutique Paddock (Visitable)", 11000, 48),
	B("Salon_VIP", "Salon des Invités de Marque", 20000, 78),
	B("Passerelle_Gradins_Int", "Passerelle & Tribunes VIP", 34000, 121),
	B("Simulateur_Course", "Centre de Simulation", 58000, 190),
	B("Restaurant", "Restaurant Panoramique", 100000, 303),
	B("Hotel_Circuit", "Hôtel du Circuit", 170000, 479),
	B("Grande_Roue", "Grande Roue Fan Zone", 300000, 789),
	B("Musee_Course", "Musée de la Course", 510000, 1259),
	B("Karting_Fan", "Karting Fan Zone", 880000, 2047),
	B("Helicoptere_TV", "Hélicoptère TV de Diffusion", 1500000, 3297),
	B("Ecran_Geant", "Écran Géant du Circuit", 2600000, 5417),
	B("Tribune_Premium", "Tribune Premium Couverte", 4500000, 8911),
	{ Id = "Prestige_Circuit", Nom = "PRESTIGE : Circuit Suivant (+50%)", Prix = 12000000, Revenu = 0, Type = "Prestige" },
}
for i, b in ipairs(Config.BATIMENTS) do
	b.Index = i
	b.Prerequis = (i > 1) and Config.BATIMENTS[i - 1].Id or nil
end

-- ===== helpers partagés client/serveur =====
function Config.trouverVehicule(id)
	for _, v in ipairs(Config.VEHICULES) do if v.Id == id then return v end end
	return Config.VEHICULES[1]
end
function Config.ameliorationParId(id)
	for _, a in ipairs(Config.AMELIORATIONS) do if a.Id == id then return a end end
end
function Config.valeurAmelioration(a, niveau)
	return a.Base + a.Pas * niveau
end
function Config.prixAmelioration(a, niveau)
	return math.floor(a.PrixBase * a.Croissance ^ niveau)
end
function Config.facteurCircuit(indexCircuit)
	return Config.COUT_CIRCUIT_FACTEUR ^ (indexCircuit - 1)
end

return Config
