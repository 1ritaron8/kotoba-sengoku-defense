# Battlefield and UI Remaster Handoff

Date: 2026-10-08 KST
Workspace: C:/JP_DF
Revision: reset-r2

## Latest human instruction

The user rejected the old battlefield graphics and the generated remaster-v1 as an inadequate remaster, requested another production tool, and then ordered all old map work discarded for a full map rebuild. They explicitly approved deleting source/generation/design/test artifacts unused in the remaster.

This instruction supersedes former stop statements and any requirement to preserve old battlefield geometry, artwork, camera registration or exact anchors.

## Current state

- Playable maps: 0. Accepted remaster maps: 0/40.
- `native/maps.json` is empty; old stage-specific traits are empty.
- `src/maps.js` no longer reconstructs the old layouts.
- `assets/battlefields-rendered/manifest.json` is a valid explicit-empty/incomplete manifest.
- Old images, rejected remaster-v1, generated copies, route/placement sources, legacy blueprint drawings, imported map textures and obsolete map previews were deleted. The existing cleanup journal records the affected paths.
- Shared UI/component work remains, including charcoal/ivory/brass/blue materials, live HUD/cards/details/queue/learning/drag feedback and menu material alignment.
- Empty-catalog guards retain a clear reconstruction state, disable map-dependent entry and preserve account data. The independent verification is `tests/qa_map_reset.gd`.
- Historical/campaign/lesson identities remain. The 40 lesson plans and 120 language missions remain; 480 former spatial positions were removed and marked as needing a new map.
- The alternate Canva generation was an unapproved tool experiment using the pre-reset composition constraint. It is not an integration base or completed map.

## Preserve

Existing player saves, growth, currency, language progress/assessments, settings, generic combat/input/navigation systems, unit artwork, reusable materials, campaign outcomes, historical evidence and supplied visual references. Do not restore discarded maps from Git or cleanup snapshots automatically.

The project's AI-to-AI communication rule permits concise mutually understood English or another efficient format. Human-facing replies default to formal Korean.

## Next authorized work

1. Confirm menu startup and save preservation after the reset.
2. Develop a new Stage 01 Marune blueprint from historical evidence, withdrawal-cover mission and the functional team's current unit spatial contracts.
3. Produce genuinely new artwork/physical terrain with materially different forms/textures, using the chosen tool workflow.
4. Verify the first map in real native play at both target resolutions.
5. Build the remaining historical battlefields in campaign order, sharing UI components rather than duplicating fortress/road layouts.

No cutscene work is included. No map is complete merely because an image or SVG exists.

## Ownership and coordination

UX owns presentation, historical evidence, new map design/art and the reset of old map content. The functional development chat owns current combat, unit skills, recruitment, movement/input, progression and persistence; it has acknowledged the map-reset boundary. Its latest human-authorized unit behavior changes take precedence over obsolete proposals.

The functional owner edits `HANDOFF_DEVELOPMENT_2026-10-08.md` and `DEVELOPMENT_PROMPT_REMASTER_UI_PILOT_2026-10-08.md`. Coordinate file ownership before concurrent writes and GPU runs.

## Evidence limits

The former-map pilot passed 325 headless and 133 GPU checks before deletion. Preserve that result as historical source-specific evidence. It does not certify newly generated art, newly designed geometry, the post-reset shell, complete natural battles or resolved physical contact.

Use `REMASTER_UI_PILOT_PLAN_2026-10-08.md`, `REMASTER_UX_UI_PRODUCTION_PLAN_2026-10-08.md` and `docs/remaster-pilot-20261008/README.md` for current reset scope and retained history/UI material.


Empty-catalog verification: tests/qa_map_reset.gd PASS 44/44, 0 failures; sourceFreezeUnchanged=true. Isolated report: tests/profiles/map-reset-native/run-7d0e15dde1e44c6493054069d8d539b4/Godot/app_userdata/말의 전장/qa-map-reset.json. Actual GPU appearance is a separate gate.

GPU/state verification PASS 59/59, 0 failures, sourceFreezeUnchanged=true; both target home/catalog frames and 1440×900 barracks inspected. Evidence: tests/profiles/map-reset-gpu/run-8c1b05534c73412fa7013e5d07068e8c/Godot/app_userdata/말의 전장/qa-map-reset.json. Battlefield play remains unavailable (0 accepted maps).
