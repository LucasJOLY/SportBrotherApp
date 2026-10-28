---
version: 1
slug: "repasjoly-app-roottabview-swift"
primary_target: "RepasJOLY/App/RootTabView.swift"
related_targets: []
---

Scope: the whole iOS app (Semaine, Recettes, Courses, Réglages, Cuisson, Génération). Visitor mode: Operate.

## Direction contract
THESIS: An iOS app indistinguishable in craft from Apple's own, specific in content: the week is the home, and the meal of the moment is always one tap from cooking. It refuses custom chrome, editorial serif and card-stack theatrics.
OWN-WORLD: System grouped backgrounds, semantic labels, one tint (system orange) for actions only. Category marks use small SF Symbols in muted system colors, never color bands. SF Pro only; Expanded bold for display moments (recipe title, stopwatch); monospaced digits for every duration. Liquid Glass only through native tab bar, toolbars and glass buttons.
STORY: Open → see today's two meals and the week at a glance → tap "Cuisiner" → follow steps with the timer → the meal checks itself. Sunday: set who eats when, plan, shop by aisle.
FIRST VIEWPORT: Large title "Semaine" with the date range as subtitle; a "Aujourd'hui" inset section with Midi/Soir rows (state glyph, recipe name, duration in monospaced digits) and a prominent orange glass "Cuisiner" button; below, inset sections per remaining day; toolbar: plan/reroll menu. Native tab bar at the bottom.
FORM: Category standard (canon), user-chosen; references Apple Reminders/Health/Fitness, Mela, Crouton. seed: none (unavailable)
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
