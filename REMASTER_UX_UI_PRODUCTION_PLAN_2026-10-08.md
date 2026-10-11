# UX/UI and Battlefield Production Plan

Date: 2026-10-08 KST
Revision: production-plan-r2 — full map reset
Workspace: C:/JP_DF

The user rejected the old battlefield graphics and the first remaster-v1 candidate, then explicitly requested that the entire map side be rebuilt. This decision supersedes every earlier instruction to preserve the previous route, terrain, placement anchors, map camera registration, or first-map spatial drawings.

## Current state

- Playable battlefield catalog: **0**. `native/maps.json` is empty.
- Accepted new maps: **0/40**. The artwork manifest is explicitly incomplete with no entries.
- Old battlefield artwork, rejected remaster-v1, original/generated copies, authored route sources, map-specific drawings and associated imported textures have been removed from the working tree. Deletion is recorded in `output/cleanup-review/deletion-history.jsonl`.
- Shared HUD, roster, selection, queue, learning, drag feedback and menu presentation remain implemented.
- Before the reset, the functional owner recorded 325 headless checks and 133 GPU checks passing on the former Stage 01. Those results certify that historical source snapshot only; they do not certify the empty-catalog changes or future maps.
- Empty-catalog startup and saved-progress preservation passed 44/44 headless checks and 59/59 GPU/state checks using isolated fixtures. Actual home/catalog at both resolutions and barracks at 1440×900 were inspected; no clipping/overlap was observed.
- Historical evidence and campaign/lesson identities remain. The 40 lesson plans and 120 language missions remain; 480 obsolete spatial positions were removed. Their spatial bindings require a new map.
- Canva produced an alternate-tool art experiment before the full-reset clarification. It used the former composition constraint and is **not an accepted map, integration baseline or artwork manifest entry**.

## Required production sequence

1. Finish common UI verification in the empty-catalog shell. Preserve actual state binding, Korean/Japanese/furigana, 1440×900 and 1280×800, and existing deliberate click/R behavior. Do not create a fake playable battlefield.
2. Reassess Stage 01 Marune from historical facts and its withdrawal-cover mission. Create a new spatial blueprint from scratch: continuous enemy approach, interception space, defense objective, unit-specific positions, physical terrain, camera and HUD safety. Old normalized anchors are discarded.
3. Make the first genuinely new battlefield from the accepted blueprint. Choose the production/rendering workflow based on the resulting materials, forms, tactical readability and physical integration. Editing the old image or changing its color does not satisfy the visual requirement.
4. Integrate the first battlefield with the existing gameplay systems. Verify real enemy approach, friendly interception, actor standing/contact, selection/drag feedback, learning transitions, queue and menus at both resolutions.
5. Apply the common UI components to newly built maps. Produce the remaining maps in the campaign order in `native/campaign_story.json`, using the location evidence in `BATTLEFIELD_HISTORY_WEATHER_PLAN.md`. For each location: evidence → new blueprint → artwork/physical space → native verification. Repeated locations may share a newly accepted geographical base with situation-specific differences.

The overall target remains 40 battlefields. This reset does not expand the MVP or authorize cutscene work.

## Visual acceptance

- Replace vegetation, rock, fort and landform silhouettes; do not retain the old rounded bright-green forms.
- Use weathered irregular timber, exposed layered earth, compacted/rutted ground, restrained grasses and fractured stone with convincing surface variation and contact shadows.
- Keep the road and standing grounds readable against small dark-armored actors.
- Use a high tactical camera showing incoming waves and the defended objective together. No horizon or cinematic depth of field obscuring play.
- Marune is a small earth/timber field fort, not a monumental stone castle. Its site's reported 35 m elevation is absolute elevation, not a local 35 m cliff.
- A generated image is a candidate. It cannot establish terrain collision, walkability, actor contact, route registration or final acceptance.

## Functional handoff

UX supplies screen composition, actual state labels, drag/select/cancel feedback, unit-specific spatial proposals, camera/HUD safety, screen transitions and evidence classification. Functional development owns combat, production, navigation, physical terrain, input lifecycle, progress and persistence.

New maps must explicitly provide the spatial contracts required by the current unit roles. Coordinate those contracts with the functional owner's latest direct human instructions; do not restore obsolete ninja or defense-zone proposals from earlier handoffs.

Retain campaign/history outcomes and language identities. Rebind retired mission target/action positions to the new geometry and revalidate mission-wave timing before enabling a stage. The empty catalog must not erase existing saved wins, learning receipts, army growth, currency or settings.

## Reporting gates

Report separately: design complete; implementation complete; actual screen inspection; natural combat progression; terrain/actor contact; full mission completion. Record files, source snapshot and real evidence. Never count old artwork, illustrative SVGs, generated trials or prior-map tests as new maps completed.

Retained evidence packet: [Marune historical brief and UI interaction sheet](docs/remaster-pilot-20261008/README.md).


Empty-catalog verification: tests/qa_map_reset.gd PASS 44/44, 0 failures; sourceFreezeUnchanged=true. Isolated report: tests/profiles/map-reset-native/run-7d0e15dde1e44c6493054069d8d539b4/Godot/app_userdata/말의 전장/qa-map-reset.json. Actual GPU appearance is a separate gate.

## UX/UI team receipt and handoff

TEAM_CHARTER.md, TEAM_BRIEFS.md and MASTER_WORKBOARD.md were read. UX/UI owns battlefield space/art, HUD, menus, unit cards, deployment/selection feedback, typography/colors and readability. Historical/campaign direction and blueprint integration review belong to the historical planning lead; functional and motion behavior belong to their respective teams. Shared source files require one writer.

This report records prior directly authorized implementation/deletion and its necessary verification. Receiving the organization brief did not start another game/GPU run or new mechanics change. No automatic reply was sent to another chat for the organization request.

Current authored-content status: 0 playable/accepted new maps; 1,271 obsolete files deleted (1,733,559,226 bytes), plus old spatial catalog and 480 obsolete lesson positions reset. Common UI/learning language content and isolated save roundtrips remain.

GPU evidence: tests/profiles/map-reset-gpu/run-8c1b05534c73412fa7013e5d07068e8c/Godot/app_userdata/말의 전장/qa-map-reset.json, 59 checks / 0 failures, sourceFreezeUnchanged=true. Home/catalog at both1280×800/1440×900 and barracks1440×900 were captured and inspected. This verifies the empty shell, not battlefield combat or future maps.

Minor UI follow-up: BarracksTraining still appears enabled while Main correctly rejects unit-practice entry with no maps. Permanent unit upgrades remain separate. Coordinate the visual disabled state with the functional owner's map-availability contract; no new behavior change was made for the organization request.

Next dependency: historical/planning lead's new Stage01 spatial requirements and the functional team's latest unit spatial contracts. UX will turn these into a new blueprint and art direction without restoring old geometry. Ninja policy is owned by functional/direct human decisions; no automatic rollback or new policy is made here. No deletion remains blocked.

Latest UI wording alignment: Main deployment summary/briefing and Barracks ninja basics now describe the functional owner's consumable tower-assassination state instead of concealment return/reuse. Only presentation strings changed. Barracks Check passed (ux-role-label-parse/run-7ecef95c5e764311b332b2477c933f84). Main Check encountered a concurrently introduced motion dependency compile error: native/troop_action_presentation.gd:39–40 references undefined event in _sync_generation (run-709ffbdc26834812978de75968b82c6c). Reported to the authorized functional coordination chat for its motion owner; UX did not modify that owned file. The earlier 59/59 GPU report applies to its recorded source hashes, before these latest concurrent edits.

Dependency issue resolved by the motion owner; latest Main Check PASS: tests/profiles/ux-role-label-parse/run-085e24bdb8eb4e4c9ef8484c629b5bbc/godot.log. Latest presentation text passed independent static UX review. No new GPU run followed the wording changes; the earlier 59/59 evidence remains source-specific. Current remaining UX follow-up is the visually enabled BarracksTraining button when maps are empty; functional entry is already blocked. No critical compile blocker remains.

## Functional team evidence received — subsequent snapshot

Read and confirmed the functional owner's GPU report at tests/profiles/unit-behavior-gpu-final/run-02b4a7f7e6d04534b4fff9b7248219b2/Godot/app_userdata/말의 전장/qa_unit_behavior_motion_gpu.json: 26 checks / 0 failures, 10 PNG captures, 16 recorded source hashes unchanged within that run. Controlled guard approach/strike/return and ninja tower damage/consumption used actual Game actor states and existing actor meshes on a synthetic QA plane. The natural interval observed 23 automatically spawned/moving enemy IDs over approximately30.25wall seconds. No manual advancement or enemy injection occurred during that observation.

This evidence supplies functional state contracts for future UX/spatial design; it does not certify a new battlefield, real terrain foot contact, camera/HUD integration or all-wave mission completion. Final CPU regression is still pending in the functional team's received report. UX did not rerun game/GPU or change functional/motion files for this receipt.

Map/UX interface: guards expose defenseZone, recognitionRadius and occupancyRadius; recognize the target separately from the movement boundary. Ninjas expose consumable, consumed, consumeReason and priorityTargetId. Display one mission's assigned tower attacker and its termination state, not reusable concealment-return. Read combat values from actual data; current ninja base attack51/HP160 does not establish a new map layout or extra late-unit access in Stage01. Unit-training behavior is functional-team-owned; UX preserves its presentation boundary. Playable/accepted map count remains0.
