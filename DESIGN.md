---
name: RepasJOLY
description: A personal week-of-meals companion built as the iOS category standard, played straight.
colors:
  tint-orange: "#FF8D28"
  tint-orange-dark: "#FF9230"
  icon-orange: "#FF9500"
  grouped-background: "#F2F2F7"
  grouped-background-dark: "#000000"
  row-surface: "#FFFFFF"
  row-surface-dark: "#1C1C1E"
  label: "#000000"
  label-dark: "#FFFFFF"
  secondary-label: "rgba(60, 60, 67, 0.6)"
  secondary-label-dark: "rgba(235, 235, 245, 0.6)"
  tertiary-label: "rgba(60, 60, 67, 0.3)"
  tertiary-label-dark: "rgba(235, 235, 245, 0.3)"
  quaternary-fill: "rgba(116, 116, 128, 0.08)"
  quaternary-fill-dark: "rgba(118, 118, 128, 0.18)"
  category-poultry: "#AC7F5E"
  category-beef: "#FF383C"
  category-pork: "#FF2D55"
  category-fish: "#0088FF"
  category-eggs: "#00C3D0"
  category-veg: "#34C759"
  category-other: "#8E8E93"
  swipe-eaten-out: "#6155F5"
typography:
  display-large:
    fontFamily: "SF Pro Expanded, -apple-system, system-ui"
    fontSize: "34px"
    fontWeight: 700
    fontFeature: "\"tnum\""
  display:
    fontFamily: "SF Pro Expanded, -apple-system, system-ui"
    fontSize: "22px"
    fontWeight: 700
  display-small:
    fontFamily: "SF Pro Expanded, -apple-system, system-ui"
    fontSize: "20px"
    fontWeight: 700
  step:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "28px"
    fontWeight: 500
  headline:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "17px"
    fontWeight: 600
  body:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "17px"
    fontWeight: 400
  body-emphasis:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "17px"
    fontWeight: 500
  subheadline:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "15px"
    fontWeight: 400
    fontFeature: "\"tnum\""
  caption:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "12px"
    fontWeight: 600
rounded:
  hint: "14px"
  hero: "22px"
  thumbnail: "12.5px"
  capsule: "9999px"
spacing:
  hair: "2px"
  xs: "4px"
  sm: "6px"
  md: "8px"
  row: "12px"
  lg: "14px"
  xl: "16px"
  margin: "20px"
  page: "24px"
components:
  button-prominent:
    backgroundColor: "{colors.tint-orange}"
    textColor: "{colors.row-surface}"
    typography: "{typography.headline}"
    rounded: "{rounded.capsule}"
    height: "40px"
  button-glass-circle:
    textColor: "{colors.tint-orange}"
    rounded: "{rounded.capsule}"
    size: "52px"
  chip:
    backgroundColor: "{colors.quaternary-fill}"
    textColor: "{colors.label}"
    typography: "{typography.subheadline}"
    rounded: "{rounded.capsule}"
    padding: "0 14px"
    height: "36px"
  chip-selected:
    backgroundColor: "{colors.tint-orange}"
    textColor: "{colors.row-surface}"
    rounded: "{rounded.capsule}"
  list-row:
    backgroundColor: "{colors.row-surface}"
    textColor: "{colors.label}"
    typography: "{typography.body-emphasis}"
  parallel-hint:
    textColor: "{colors.tint-orange}"
    rounded: "{rounded.hint}"
    padding: "12px"
  recipe-thumbnail:
    rounded: "{rounded.thumbnail}"
    size: "52px"
---

# Design System: RepasJOLY

## Overview

**Creative North Star: "The Kitchen Drawer App"**

RepasJOLY looks like an app Apple might have shipped next to Reminders and Fitness: inset grouped lists on the system grouped background, semantic labels, native Liquid Glass only where the system puts it (tab bar, toolbars, glass buttons). The content is the specificity: this week's meals, today's next dish, aisles of a shopping list. Nothing is drawn that the platform already draws.

One tint, system orange, carries every action and every completed state. Recipe categories speak quietly through small SF Symbols in muted system colours. The only typographic flourish is SF Pro Expanded bold, reserved for recipe titles and the running clock; every duration is set in monospaced digits so numbers never jitter. Motion is small and physical: `.snappy` springs, symbol replace transitions, numeric-text counters, and haptics on every state change.

The world rejects custom chrome, editorial serif display type and card-stack theatrics (PRODUCT.md brand commitment). Light and dark modes are both first-class and resolve entirely through system semantic colours.

**Key Characteristics:**
- Inset grouped `List` everywhere; sections are the cards.
- One tint (system orange) for actions and done states only.
- SF Pro only; Expanded bold for display moments; tabular digits for all times and counts.
- Liquid Glass only through native components.
- Reminders-style completion circles, haptics, `.snappy` motion.

## Colors

A system-semantic neutral world with one warm action tint and a muted category spectrum.

### Primary
- **Kitchen Orange** (tint-orange, dark: tint-orange-dark): iOS 26 system orange, set once at the root (`.tint(.orange)`). Prominent glass buttons ("Cuisiner ce soir", "Étape suivante", "Terminer"), toolbar glyphs, selected chips, filled completion circles, filled rating stars, finished-timer state, the cooking progress bar, and the parallel-step hint. Never a category mark, never a background panel larger than the hint.
- **Icon Orange** (icon-orange): the classic system orange field of the app icon (white SF Symbol `fork.knife`, rendered locally). Identity asset only; in-app surfaces use the tint.

### Secondary
- **Category marks** (category-poultry brown, category-beef red, category-pork pink, category-fish blue, category-eggs teal, category-veg green, category-other gray): system colours applied at 85% opacity to the category SF Symbol only, in recipe thumbnails without photos and in recipe metadata.

### Neutral
- **Grouped Background** (grouped-background / -dark): screen ground behind every list.
- **Row Surface** (row-surface / -dark): inset section rows.
- **Label** (label / -dark): titles and primary row text; planned meals.
- **Secondary Label** (secondary-label / -dark): row captions (meal · diners · duration), done or skipped meals, metadata, "Ensuite" preview.
- **Tertiary Label** (tertiary-label / -dark): empty completion circles, unfilled stars, lock glyph, day-header dates.
- **Quaternary Fill** (quaternary-fill / -dark): unselected chip background.

### Semantic system colours
Pink marks a favourite (heart glyph, leading swipe). Red marks excluded foods, excluded recipes and errors. Swipe actions use indigo for "Dehors" (swipe-eaten-out) and gray for "Sauter". These are iOS conventions, not accents.

### Named Rules
**The Tint Is a Verb Rule.** Orange means "do this" or "done". If an element is neither an action nor a completed state, it is not orange.

**The Muted Category Rule.** A category is a small SF Symbol in its system colour at 85% opacity. Never a colour band, fill, stripe or tinted row.

## Typography

**Display Font:** SF Pro Expanded, bold (`Font.display(_:)` = `.system(style, weight: .bold).width(.expanded)`)
**Body Font:** SF Pro (system text styles, Dynamic Type)
**Label/Mono Font:** SF Pro with `.monospacedDigit()`

**Character:** Plain system text everywhere, with one wide, heavy voice for the moments that matter: the dish you are about to cook and the clock running while you cook it.

### Hierarchy
- **Display Large** (700 expanded, largeTitle 34pt, tabular): the cooking stopwatch; Live Activity clock at `.title`.
- **Display** (700 expanded, title2 22pt): recipe title on detail, week recap title, full-size step countdown.
- **Display Small** (700 expanded, title3 20pt): recipe title in cooking mode and the Live Activity.
- **Navigation titles**: system large titles ("Semaine 44", "Recettes") with `navigationSubtitle` for range and counts.
- **Step** (500, title 28pt): the current cooking step, readable from the counter.
- **Headline** (600, 17pt): button labels, compact timers.
- **Body Emphasis** (500, 17pt): meal and recipe row titles, two lines max.
- **Subheadline** (400 or 500/600, 15pt): row captions joined with " · ", day headers (semibold), chips (medium), metadata; always tabular when it holds a number.
- **Caption** (600, 12pt): "En pause", Live Activity status label.

### Named Rules
**The Expanded Moment Rule.** SF Pro Expanded bold appears only on a recipe title being viewed or cooked, a recap title, and running clocks. Never on navigation titles, section headers or buttons.

**The Steady Clock Rule.** Every duration, count and quantity uses `.monospacedDigit()`; live counters add `.contentTransition(.numericText())` (counting down for step timers).

## Layout

Every primary screen is a `NavigationStack` over an inset grouped `List`: day sections on Semaine, aisle sections on Courses, form sections in Réglages and editors. Rows breathe with 2-4pt vertical padding and 12-14pt gaps between glyph and text. The native tab bar (Semaine, Recettes, Courses, Réglages) minimizes on scroll down. Cooking mode is a full-screen cover with 20pt horizontal margins, a 24pt step page, and its controls pinned to the bottom for thumb reach. Chips wrap through `FlowLayout` at 8pt (16pt for recipe metadata labels). Touch targets hold to at least 44pt tall (completion circle 32×44, rating star 36×44, day menu 44×32 inside a header).

## Elevation & Depth

Flat by default, layered by the system. Depth comes from the grouped background against row surfaces and from Liquid Glass on the tab bar, toolbars and glass buttons. No shadow is authored in code; the only shadows are those the system draws under glass.

### Named Rules
**The Glass Belongs to the System Rule.** Liquid Glass enters only through `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`, the tab bar and toolbars. No custom `glassEffect` panels.

## Shapes

Continuous corners throughout. Buttons and chips are capsules; icon-only glass buttons are circles (52-56pt). Recipe photos clip at 22pt on the detail hero and 14pt in the editor; thumbnails clip at 24% of their size (12.5pt at 52pt). The parallel-step hint is a 14pt rounded rectangle. List sections take the system inset-grouped radius.

## Components

### Buttons
- **Prominent:** native `.glassProminent`, orange glass capsule, white headline label, full width at 34-40pt minimum height. One per context: "Cuisiner ce soir" under today's section, "Étape suivante"/"Terminer" in cooking, "Préparer la semaine" in the empty state.
- **Glass circle:** native `.glass` with `.circle` border shape, orange glyph; pause/play (56pt), previous step (52pt), stop timer.
- **Toolbar:** system toolbar items with SF Symbols (shuffle, ellipsis menu, xmark, list.bullet).
- **Swipe actions:** leading orange "Fait", trailing indigo "Dehors" and gray "Sauter".

### Chips
- **Style:** capsule, 14pt horizontal padding, 36pt minimum height, subheadline medium, optional small SF Symbol.
- **State:** unselected quaternary fill with primary label; selected orange tint with white label; `.snappy(0.2)` animation and selection haptic.

### Cards / Containers
- **Corner Style:** system inset grouped sections; no custom cards.
- **Background:** row surface on grouped background.
- **Shadow Strategy:** none (see Elevation & Depth).
- **Internal Padding:** system row insets; recipe detail header goes edge-clear (`listRowBackground(.clear)`, 20pt insets).

### Inputs / Fields
- **Style:** native `Form` rows, `TextField`, steppers, segmented pickers ("Étape par étape / Liste").
- **Focus / Error:** system behaviour; errors as a red `Label` with `exclamationmark.triangle`.

### Navigation
- **Style:** native `TabView` with four SF Symbol tabs, orange selection, minimize on scroll; large titles with subtitles; menus and context menus for secondary actions.

### Completion Circle (signature)
The Reminders circle: `circle` → `checkmark.circle.fill` via symbol replace, tertiary when open, orange when done, title strikethrough in secondary. Used on meal rows (title2), shopping rows and cooking list steps (title3). Success haptic on completion, selection haptic on shopping toggles.

### Recipe Thumbnail
The photo when present (52pt, 24% continuous corners); otherwise the category SF Symbol at 42% of the size, medium weight, in its muted category colour. No placeholder plate.

### Parallel Hint
An inline orange `Label` (`arrow.triangle.branch`, callout medium) on an orange wash at 12% opacity, 12pt padding, 14pt corners. The only tinted surface in the app.

### Rating Control
Five stars, tinted fill up to the rating, tertiary outlines beyond; tap the current star to clear; bounce symbol effect, selection haptic, adjustable for VoiceOver.

### Live Activity
Lock Screen and Dynamic Island mirror cooking: orange flame/timer glyphs, recipe title and clock in expanded bold, tabular digits, dimmed to 50% when paused, system activity background.

## Do's and Don'ts

### Do:
- **Do** set orange once with `.tint(.orange)` and reach it through `.tint` on actions and done states.
- **Do** build every screen from inset grouped `List` sections on system semantic colours, in both light and dark.
- **Do** use `Font.display(_:)` for recipe titles in detail, cooking and recap, and for running clocks.
- **Do** apply `.monospacedDigit()` to every duration, count and quantity, with numeric-text transitions on live counters.
- **Do** mark categories with their SF Symbol in system colour at 85% opacity.
- **Do** animate state with `.snappy`, symbol replace and bounce effects, and pair each state change with a haptic.
- **Do** keep touch targets at least 44pt tall.

### Don't:
- **Don't** use serif or non-SF display type (PRODUCT.md brand commitment).
- **Don't** draw custom chrome, card stacks or custom glass panels; Liquid Glass comes only from native components.
- **Don't** colour a category as a band, fill or row tint, and don't make a category mark orange.
- **Don't** use orange for decoration, headers or static information.
- **Don't** author shadows; depth is the grouped background and system glass.
