# Race Track Tycoon : refonte complète

## 1. Installation dans Roblox Studio

| Fichier | Type d'objet | Où le mettre |
|---|---|---|
| `GameBuilderTycoon.lua` | **Script** | ServerScriptService |
| `Geometrie`, `Circuits`, `Utils`, `Batiments`, `TrackBuilder`, `Vehicules` | **ModuleScript** (même nom, sans `.lua`) | ServerScriptService (à côté du Script, pas dedans) |
| `Config.lua` | **ModuleScript** nommé `Config` | ReplicatedStorage |
| `HudClient.lua` (ton HUD, patché) et `HudExtras.lua` (nouveau) | **LocalScript** | StarterPlayer > StarterPlayerScripts |

Réglages obligatoires :
1. Supprimer le **Baseplate** et tout **SpawnLocation** du workspace (chaque joueur reçoit son propre circuit, le jeu fait apparaître le joueur dessus).
2. Workspace > **StreamingEnabled = true** (très important : un circuit fait ~4 000 pièces).
3. Game Settings > **Max Players = 6 à 8** et activer **Enable Studio Access to API Services** (DataStore).
4. Supprimer l'ancien script serveur et l'ancien HUD avant de coller les nouveaux.

## 2. Ce qui a été trouvé dans ton ancien code
- `regenererReliefArbresEtPneus()` était **appelée mais jamais définie** : le script plantait dès le chargement d'un circuit.
- Tout l'état (flotte, achats, circuit, grille) était **global** : le 2e joueur écrasait celui du 1er. Impossible à publier tel quel. Maintenant : **un plot (circuit + bâtiments + flotte) par joueur**.
- Sauvegarde uniquement à la sortie, sans réessai ni `BindToClose` (perte de progression). Remplacée par chargement/sauvegarde robustes (réessais, autosave 60 s, sauvegarde à la fermeture du serveur, le joueur est expulsé plutôt que d'écraser sa sauvegarde si le DataStore est en panne). Ta sauvegarde `RaceTrackTycoon_MasterFinal_v1` est **migrée automatiquement**.
- Le revenu était mis à jour par des variables globales ; il est maintenant **recalculé** à partir du profil (plus de désynchronisation).
- Le créateur recevait 999 999 999 $ en jeu publié ; les commandes dev ne marchent plus qu'en Studio ou pour les `Config.ADMINS`.

## 3. Ce qui a été fait, point par point

**Bâtiments mal placés (bacs sur l'asphalte, etc.)** : plus aucune coordonnée en dur autour de la piste. Le tracé est calculé (`Geometrie`), puis chaque bac à gravier, commissaire, caméra, arbre, arche, restaurant, hôtel… passe par un **solveur de placement** qui teste l'empreinte contre la ligne centrale de TOUT le circuit et contre les objets déjà posés. Vérifié par test sur les 8 circuits : 0 objet sur l'asphalte (cf. `apercus/`).

**Circuits refaits** : chaque circuit est une liste de points `{x, z, altitude, rayon, banking°}` dans `Circuits.lua`. Le moteur arrondit les virages avec de vrais arcs, lisse l'altitude, incline progressivement les virages (banking, jusqu'à 30° au Karussell), et construit des **remblais en terrain** sous la piste, des collines (relocalisées automatiquement si trop proches) et un plateau pour le paddock. Pentes max ~20 %, rayons mini 20-45 studs.

**Ligne des stands** : voie des stands, entrée et sortie sont calculées à partir de la vraie ligne droite de CHAQUE circuit (longueur variable), raccordées à la piste, avec nombre de garages adapté, mur, poste ingénieurs, feu de sortie.

**Améliorations** : 20 bâtiments (7 nouveaux : Salon VIP, Simulateur, Hôtel, Musée, Karting, Écran géant, Tribune Premium) + 9 améliorations **répétables** à l'Atelier (revenu, chance, cases, recharge roulette, VIP x3, gains hors-ligne x2) + grille jusqu'à 24 places. Les prix des bâtiments x2,6 à chaque prestige : 8 circuits puis la boucle continue.

**Véhicules** : 20 modèles (6 raretés dont « Secret »), chacun avec un **prix fixe**. 

**Roulette** : le tirage est **gratuit** (recharge 40 s, réductible à 8 s). Il propose N cases (3 au départ, jusqu'à 12) : chaque case est un véhicule que tu peux **acheter à son prix**. L'amélioration « Chance » augmente les poids des raretés élevées, « Cases » en ajoute.

**Invités de marque** : le Salon VIP fait arriver un invité (Influenceur, Pilote, Star, Président, Cheikh) sur le tapis rouge. On l'accueille (ProximityPrompt, frais = secondes de revenu) pour un **bonus de revenu temporaire** (x1,5 à x6, durée/puissance/fréquence améliorables).

**Autres fonctions** : récompense quotidienne (série de 7 jours), codes promo, gains hors-ligne, véhicules vendables (35 %), vitesse des voitures liée aux virages (freinage anticipé, banking), notifications, boutique Robux.

## 4. Monétiser
Dans `Config.lua` : remplace les `Id = 0` des `GAMEPASS` (x2 Cash, VIP+, Roulette auto) et les clés de `PRODUITS` par tes vrais IDs (Creator Hub > Monétisation). `ProcessReceipt` est idempotent (reçus enregistrés, sauvegarde avant validation). `AutoSpin` est déclaré mais pas encore branché.

## 5. À savoir avant de publier
- **Testé** avec un faux moteur Roblox : géométrie des 8 circuits, placement, construction complète, véhicules, tout le flux serveur (achats, roulette, VIP, prestige, sauvegarde avec contrôle de sérialisation). **Pas testé dans Studio** : rendu visuel, rendu du terrain, performances réelles, interface client. Prévois une vraie session de test (idéalement à 2-3 joueurs).
- Les circuits sont **inspirés** des tracés réels (simplifiés, sens antihoraire, ligne des stands fixe en z = 0). Les affiner = éditer les points de `Circuits.lua`. Pas de croisement type Suzuka pour l'instant.
- **Noms réels** (Porsche, Ferrari, Michelin, Rolex, TAG Heuer, Scuderia…) : risque de marque pour un jeu monétisé. Renomme-les (fictifs) dans `Config.lua`, `Batiments.lua` (sponsors, équipes) avant publication.
- Les voitures sont des assemblages de pièces déplacés à 30 Hz : prévois de limiter la flotte visible si les performances mobiles souffrent.
- Équilibrage : tout est dans `Config.lua` (prix, revenus, raretés, VIP, paliers).
