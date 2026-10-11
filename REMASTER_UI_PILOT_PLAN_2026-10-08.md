# Battlefield Remaster UI Pilot Plan

Date: 2026-10-08 KST
Revision: pilot-r4 — map reset
Workspace: C:/JP_DF

## Latest decision

The user ordered a complete rebuild of the map side after rejecting the existing textures and remaster-v1. All former maps and their authored geometry are retired. Earlier clauses requiring the original Stage 01 road, objective anchor, placement sites, heights, art registration or spatial drawings are revoked.

`native/maps.json` contains zero playable maps. The art manifest contains no accepted entries. Keep the application usable through its menu and a clear map-reconstruction state, with no fake stage or automatic legacy-map fallback.

## Scope

Retain the existing game's common UI and generic functional systems. The common interface includes HUD, roster cards, selection details, recruitment queue, wave states, learning entry/readout, pause/menu and drag feedback. Labels use actual game state. Deliberate card click and R retain the human-approved legacy commands; held drag preview remains pure.

Historical/campaign identity, language content, army growth and saved progress remain. Old map spatial bindings are discarded and must be authored again. No cutscene concept art, storyboard, voice/subtitle/skip UI, prototype or preparatory work belongs to this MVP.

## Pilot order

1. Verify the retained common UI and the empty-catalog shell at 1440×900 and 1280×800. Show actual Korean, Japanese and furigana. Preserve saves when no map is installed.
2. Complete Marune evidence classification and a new spatial blueprint. Retain fictional withdrawal cover and distinguish historical fort loss from mission success.
3. Establish a materially different realistic visual direction: new forms, weathered materials and readable tactical perspective. Do not reuse the rejected map as the edit base.
4. Integrate the first accepted blueprint, artwork and physical terrain. Verify actual approaches, blocking, deployment, queues, learning and actor ground contact.
5. Extend shared UI to subsequent newly built maps, then repeat history → blueprint → artwork/space → native verification per location.

The existing roadmap still targets 40 maps without expanding MVP scope. Their campaign order is retained independently of the discarded spatial catalog.

## Acceptance and evidence

- Design approval is separate from implementation and native screen confirmation.
- Natural enemy movement/learning return is separate from full-battle completion.
- Painted appearance is separate from physical navigation, placement and foot contact.
- The 325/133 passing functional pilot results belong to the former-map source snapshot. They are historical evidence, not post-reset acceptance.
- `tests/qa_map_reset.gd` checks actual empty-catalog startup and isolated saved-account preservation.
- Retained historical/UI packet: `docs/remaster-pilot-20261008/README.md`.
- Current production decisions: `REMASTER_UX_UI_PRODUCTION_PLAN_2026-10-08.md`.
- Functional behavior and new unit spatial contracts: current development handoff and direct human instructions in the functional development chat.

New map entries may be registered only after new geometry and mission bindings are concrete and verified. No first battlefield is complete at this reset boundary.


Empty-catalog verification: tests/qa_map_reset.gd PASS 44/44, 0 failures; sourceFreezeUnchanged=true. Isolated report: tests/profiles/map-reset-native/run-7d0e15dde1e44c6493054069d8d539b4/Godot/app_userdata/말의 전장/qa-map-reset.json. Actual GPU appearance is a separate gate.

GPU/state verification PASS 59/59, 0 failures, sourceFreezeUnchanged=true; both target home/catalog frames and 1440×900 barracks inspected. Evidence: tests/profiles/map-reset-gpu/run-8c1b05534c73412fa7013e5d07068e8c/Godot/app_userdata/말의 전장/qa-map-reset.json. Battlefield play remains unavailable (0 accepted maps).
