# SportBrother

App iOS perso (SwiftUI, iOS 26, SwiftData) en deux sections, avec une bascule en bout de barre d'onglets :

- **Nourriture** : recettes, planning de la semaine, courses, mode cuisson guidé et recettes générées par Claude Haiku. Données uniquement sur le téléphone.
- **Sport** : séances de salle pour 1 à 4 profils (séries, charges, ressenti, repos avec Live Activity), modèles de séance, favoris, records, courbes, pesées et bilan mensuel IA. Données partagées entre les téléphones via Supabase, en temps réel, avec un cache local qui marche hors ligne.

## Installation sur un iPhone

1. `brew install xcodegen` (une seule fois).
2. Copie `Config/Secrets.example.xcconfig` en `Config/Secrets.xcconfig` (déjà fait), puis renseigne :
   - `CLAUDE_API_KEY` : ta clé `sk-ant-…` ;
   - `DEVELOPMENT_TEAM` : l'identifiant de ton équipe Apple payante (visible dans Xcode › Réglages › Comptes) ;
   - `SUPABASE_URL` et `SUPABASE_KEY` : l'URL du projet et sa clé publishable.
3. `xcodegen generate`, puis ouvre `SportBrother.xcodeproj`.
4. Branche l'iPhone (mode développeur activé), choisis-le comme destination, puis **Run**.

Pour le téléphone d'un ami : branche-le sur ce Mac, laisse Xcode l'enregistrer dans l'équipe, puis **Run**. À l'ouverture de Sport, il choisit ou crée son profil et voit tout de suite les mêmes données.

Le profil de signature est valable un an. Pour le renouveler, refais **Run**. `Secrets.xcconfig` n'est jamais versionné.

### Passage de RepasJOLY à SportBrother

Le bundle id a changé : iOS installe SportBrother comme une nouvelle app. Avant de supprimer RepasJOLY, fais Réglages › Exporter, puis Réglages › Importer dans SportBrother.

## Supabase (section Sport)

- Projet `LucasJOLY` (eu-west-3). Schéma dans `supabase/migrations/` : tables `sport_*`, RLS, RPC `sport_pull` / `sport_push`, diffusion temps réel sur le canal privé `sport`, bucket `sport-photos`.
- Le téléphone se connecte en anonyme, sans écran de connexion (Authentication › Sign In / Providers › **Allow anonymous sign-ins** doit rester activé). Toute session connectée voit tout le jeu de données : la protection repose sur le fait que la clé n'est que dans cette app privée.
- Synchro : l'interface ne lit que SwiftData. Chaque écriture part dans une file (`SportOutboxItem`), envoyée en un seul appel `sport_push`. La réception se fait par curseur (`sport_pull`) et en direct (Realtime Broadcast). En cas de conflit, la modification la plus récente gagne, ligne par ligne.
- L'offre gratuite met le projet en pause après 7 jours sans activité ; l'app continue sur son cache local et se resynchronise au réveil.

## Développement

- Tests : `xcodebuild test -project SportBrother.xcodeproj -scheme SportBrother -destination 'platform=iOS Simulator,name=iPhone 17'`
- Données de démo (base en mémoire, synchro coupée) : lance l'app avec l'argument `-sampleData`. Ajoute `-section sport` pour ouvrir le Sport, `-debugSportTab 2` pour un onglet, `-debugSportSession YES` pour une séance de démo.
- Catalogue d'exos : `python3 -I scripts/build_exercise_catalog.py <dossier_de_travail>` régénère `SportBrother/Resources/ExerciseCatalog`. Liste et groupes : free-exercise-db (domaine public). Illustrations 3D animées : API gratuite ExerciseDB V1 (AscendAPI, usage personnel), correspondance exo → animation dans `scripts/exercisedb_media.json`.
- Chaque appel IA affiche ses tokens dans la console en Debug. Le cumul est visible dans Réglages › IA.

## Structure

- `SportBrother/Models` : modèles SwiftData (Nourriture) et miroirs locaux des tables Sport (`Sport.swift`).
- `SportBrother/Services` : planification, courses, client Claude, sauvegarde JSON ; `Services/Sport` : catalogue, records et progression, minuteur de repos, synchro Supabase.
- `SportBrother/Features` : un dossier par écran ; `Features/Sport` : Séance, Exos, Stats, Profils.
- `SportBrotherWidgets` : Live Activities de la cuisson et du repos.
- `Shared` : types partagés entre l'app et le widget.
- `supabase/migrations` : schéma du backend Sport.
