# Limpid — portage WoW Forever 1.60 (interface 16001)

Portage de Limpid 2.44 (3.3.5a / Ascension) vers le client WoW Forever,
vérifié contre le code d'interface Blizzard du build **1.60.1.70938**.

Forever tourne sur le client moderne (API Mainline 12.x). Ce n'est donc pas un
simple changement de numéro d'interface : tout ce qui touchait au chat natif a
été refait pour ne plus « teinter » le code sécurisé de Blizzard et pour
supporter les valeurs secrètes.

## Ce qui a changé

**Socle**
- TOC `## Interface: 16001`.
- Bibliothèques remplacées par les versions actuelles : Ace3 (officiel, compatible
  Forever) et LibSharedMedia-3.0. AceGUI-3.0-SharedMediaWidgets retiré (le choix
  de police est un menu déroulant standard).
- Tous les polyfills 3.3.5 supprimés (C_Timer maison, modification des
  métatables de widgets, etc.).

**Filtres (butin, XP, réputation, argent, quêtes…)**
- Filtres enregistrés via `ChatFrameUtil.AddMessageEventFilter`.
- Les motifs sont construits à partir des chaînes du client, donc ils
  fonctionnent dans toutes les langues (testé sur les 11 langues du client).
- Liens d'objets au nouveau format `|cnIQ<qualité>:` pris en charge.
- Lignes de jets de butin avec préfixe `[Butin]` prises en charge.
- Hôtel des ventes moderne (`C_AuctionHouse`), sacs (`C_Container`),
  courrier, suppression d'objet (`DELETE_ITEM_CONFIRM`) : crochets sécurisés.
- Filtres « ouverture » et « familier » : basés sur leur événement, plus sur du
  texte anglais.
- Retiré car propre à Ascension : apparences, Gloire, points d'arène, Essence
  de talent, messages « Added as: ».

**Interface Glass**
- Les cadres de chat natifs restent la source des messages mais sont rangés
  sous un cadre caché ; plus aucune fonction Blizzard n'est remplacée.
- Capture des messages par crochet sécurisé sur `AddMessage`.
- Onglets : boutons propres à l'addon, menu contextuel avec le système de
  menus moderne.
- Zone de saisie : seulement repositionnée et restylée (aucune écriture sur le
  cadre), pour que les commandes tapées (/cast, /target…) restent sécurisées.
- Liens cliquables natifs (plus de boutons superposés).
- Messages secrets (verrouillage du chat en rencontre de boss) : affichés tels
  quels, sans filtrage ni horodatage, jamais sauvegardés.
- `ReloadUI()` n'est plus appelé : l'addon demande de taper `/reload`.
- Panneau dans Options > AddOns via l'API `Settings`.

## Bogues d'origine corrigés au passage
- Les filtres *Messages de boss*, *Infos diverses*, *Infos familier* et
  *Messages système* ne pouvaient jamais s'activer (nom de module mal formé).
- Le filtre *Messages de boss* ne marque plus que les vrais événements de boss
  (il aurait étiqueté « [Boss] » toutes les emotes de créatures).
- Les lignes d'honneur pouvaient disparaître selon l'ordre d'activation des
  filtres Butin et Honneur.
- « X reçoit le butin : objet x3 » perdait la quantité.
- Le filtre Quêtes s'appliquait aussi aux canaux et chuchotements.

## Vérifications faites hors jeu
- Syntaxe Lua 5.1 de tous les fichiers.
- Chaque fonction globale, événement et modèle de cadre utilisé existe dans les
  listes extraites du client Forever 1.60.1.70938.
- Chargement complet de l'addon dans un simulateur du client, puis scénarios :
  connexion, ~40 types de messages, messages secrets, options /limpid (893
  options lues), menus d'onglet, fenêtre détachée, fenêtre de chuchotement,
  journal de combat, combat, déconnexion — dans les 11 langues.

## À vérifier en jeu (non testable hors jeu)
1. Le chat natif est bien invisible et la fenêtre Glass apparaît.
2. Entrée ouvre la zone de saisie ; `/cast` et `/target` tapés fonctionnent.
3. Clic, Maj+clic et survol des liens d'objets.
4. Clic droit sur un onglet : renommer, nouvelle fenêtre, réglages du chat.
5. Une rencontre de boss : les messages de raid s'affichent sans erreur.
6. `/limpid` ouvre les options ; `/limpid lock` déverrouille le cadre.

Commandes : `/limpid`, `/limpid lock`, `/copychat`, `/limpiddebug`.

## Popup de butin (ajout, absent de l'original)

Module `Components/Modules/LootPopup.lua`, activé par défaut (`/limpid` > filtres > « Popup de butin »).

- Liste flottante sans fond, indépendante du chat : `+ icône Nom x3 (total en sac)`, nom à la couleur de qualité.
- Flèche verte : niveau d'objet supérieur à la pièce portée dans l'emplacement, objet utilisable (pas de texte rouge dans l'infobulle), jamais un type d'armure plus léger que celui porté.
- Survol d'une ligne : infobulle normale de l'objet (les autres addons y ajoutent leurs lignes).
- Clic sur la liste : elle reste affichée. Clic ailleurs : elle s'efface. Le clic est seulement observé, il atteint toujours le jeu.
- Pièces ramassées cumulées sur une ligne.
- `/limpid loot` : déverrouille le conteneur pour le déplacer ; clic droit dessus pour la taille du texte, l'échelle et le verrouillage.

## Licences

- Code issu de ChatCleaner (Lars Norberg) : licence MIT modifiée, voir `LICENSE-ChatCleaner.txt`. Ses images ne sont pas redistribuables : `Assets/coins.tga` a donc été redessinée (pièces originales, sans motif), l'image d'origine n'est plus dans l'addon.
- Code issu de Glass (Mitchel Cabuloy) : MIT, voir `LICENSE-Glass.txt`.
