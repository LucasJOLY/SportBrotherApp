# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack
SwiftUI native, iOS 26 minimum (Liquid Glass), SwiftData for local storage, project generated with XcodeGen. Claude API (Haiku) via a minimal URLSession client. Installed on one personal iPhone through Xcode with a paid developer account; never published to the App Store.

## Users
One person (the owner), cooking for themself and sometimes a second person. Used in the kitchen (hands busy, phone on the counter), at the supermarket (one hand, moving through aisles), and on the couch on Sunday when planning the week. Goal: eat clean, balanced, protein-rich meals for muscle gain without thinking about it every day.

## Product Purpose
Store personal recipes, spread them across the week (lunch/dinner, 1 or 2 diners), produce the shopping list for the remaining meals, guide cooking step by step with a timer, and generate new recipes with AI. Success: the week is planned in under a minute, shopping takes one pass, and the end-of-week recap shows the plan was followed.

## Positioning
A personal cooking companion shaped around one person's real routine: leftovers rule (cooking for 2 when alone feeds a later meal), quantities optional (counts like "2 poulets" rather than grams unless given), AI used sparingly and only where it adds value.

## Operating Context
- Week runs Monday to Sunday. Each slot (day × lunch/dinner) has 0 (absent), 1 or 2 diners.
- When alone at a meal, cook for 2; the user chooses which later slot receives the leftover.
- Planning: AI mode (default on) or smart local random; reroll all with exclusions, reroll one slot, lock, swap, pick manually.
- Cooking mode: step-by-step ⇄ list toggle, global stopwatch with pause, per-step timers with notifications, Live Activity, parallel-step hints. Finishing a recipe checks the slot.
- Shopping list grouped by aisle, from remaining meals only; pantry staples always visible, pre-checked "in stock", uncheck when out; manual items; share as text.
- AI generation: pick ingredients + prompt → 2–4 multiple-choice questions → 3 short ideas → full recipe for the chosen one.
- Settings: equipment (oven, microwave, hobs, pan sizes…), excluded foods/allergies (hard constraint), weight and protein/kcal targets, taste profile, export/import JSON backup.

## Capabilities and Constraints
- Everything stored locally; no backend, no account.
- AI consumption must be minimal: Haiku only, short fixed prompts, strict JSON, tight max_tokens, local logic wherever possible.
- Language: French UI.
- Light and dark mode both supported.

## Brand Commitments
- Name: RepasJOLY.
- Standing preference (chosen 2026-10-28 over an editorial/bistro world): the iOS category standard played straight, at the craft level of Apple's own apps (Reminders, Health, Fitness) and the best native recipe apps (Mela, Crouton). Liquid Glass via native components.
- Typography must not read as AI-generated: no editorial serif display. SF Pro family only (Expanded width allowed for display moments, monospaced digits for times).
- Very simple, fluid, fast, with small tasteful animations.

## Evidence on Hand
No recipes, photos or assets exist yet. Do not fabricate user data beyond preview/sample content.

## Product Principles
1. One-handed and glanceable: every frequent action reachable in one or two taps.
2. Local first, AI last: compute locally, call the API only when it clearly adds value.
3. Quantities are optional: the app works equally well with "poulet" and with "200 g de poulet".
4. The week is the heart: planning, cooking and shopping all serve the current week.
5. Calm in the kitchen: large type and no clutter during cooking.

## Accessibility & Inclusion
Dynamic Type, Reduce Motion and VoiceOver labels respected as native iOS defaults.
