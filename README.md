# RepasJOLY

App iOS perso (SwiftUI, iOS 26, SwiftData) : recettes, planning de la semaine, courses, mode cuisson guidé et recettes générées par Claude Haiku. Toutes les données restent sur le téléphone.

## Installation sur l'iPhone

1. `brew install xcodegen` (une seule fois).
2. Copie `Config/Secrets.example.xcconfig` en `Config/Secrets.xcconfig` (déjà fait), puis renseigne :
   - `CLAUDE_API_KEY` : ta clé `sk-ant-…` ;
   - `DEVELOPMENT_TEAM` : l'identifiant de ton équipe Apple payante (visible dans Xcode › Réglages › Comptes).
3. `xcodegen generate`, puis ouvre `RepasJOLY.xcodeproj`.
4. Branche l'iPhone (mode développeur activé), choisis-le comme destination, puis **Run**.

Le profil de signature est valable un an. Pour le renouveler, refais **Run**. `Secrets.xcconfig` n'est jamais versionné.

## Développement

- Tests : `xcodebuild test -project RepasJOLY.xcodeproj -scheme RepasJOLY -destination 'platform=iOS Simulator,name=iPhone 17'`
- Données de démo (base en mémoire) : lance l'app avec l'argument `-sampleData`.
- Chaque appel IA affiche ses tokens dans la console en Debug. Le cumul est visible dans Réglages › IA.

## Structure

- `RepasJOLY/Models` : modèles SwiftData (Recipe, WeekPlan, MealSlot, CookingSession, profil, courses).
- `RepasJOLY/Services` : planification locale et IA, règles des restes, liste de courses, client Claude, sauvegarde JSON.
- `RepasJOLY/Features` : un dossier par écran (Semaine, Recettes, Génération, Cuisson, Courses, Réglages).
- `RepasJOLYWidgets` : Live Activity du mode cuisson.
- `Shared` : types partagés entre l'app et le widget.
