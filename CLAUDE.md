# GameSpice User Avatar

Player avatars as data, validated by a server that never loads a mesh: a schema of slots and parts, entitlements, conform-then-validate, a digest a profile carries, a packed wire form, and memory, local and backbone stores.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to avatars. Most of this addon's reasoning is current rules rather than history, so its docs are mostly design.

**The distributable is `addons/gs_user_avatar/`.** GameSpice Core and [GameSpice Save](../gs-save) (`ln -s ../../gs-save/addons/gs_save addons/gs_save`, gitignored) are the dependencies; GameSpice Cloud, GameSpice User and GameSpice Net are reached through `GSRegistry` or duck typing and named nowhere.

## Read before

| Read | Before |
| --- | --- |
| [docs/document.md](docs/document.md) | `GSAvatar`, `GSAvatarSchema`, `GSAvatarSlot`, `GSAvatarPart`, `GSAvatarEntitlements`, `GSAvatarKey`, `GSAvatarSync`'s reader, `GSAvatarManager.publish` |
| [docs/integration.md](docs/integration.md) | `resolve` defaults and translation, `GSAvatarStoreBackbone`, `tools/export_avatar_manifest.gd`, `GSAvatarBuilder`, the GameSpice Cloud / GameSpice User / GameSpice Net couplings |
| [docs/history.md](docs/history.md) | the failures, and how each looked |

## Layout

| Path | What |
| --- | --- |
| `addons/gs_user_avatar/core/` | `GSAvatar` (the document), `GSAvatarSchema`, `GSAvatarSlot`, `GSAvatarPart`, `GSAvatarEntitlements`, `GSAvatarKey` |
| `addons/gs_user_avatar/gs_avatar_manager.gd` | `GSAvatarManager`: the trust boundary (`publish`) and `resolve` |
| `addons/gs_user_avatar/catalogue/` | `GSAvatarCatalogue`: part id to content, client-side only, with bounded fallback |
| `addons/gs_user_avatar/runtime/` | `GSAvatarBuilder`: `plan()` (pure), `plan_dicts()`, `apply()` |
| `addons/gs_user_avatar/net/` | `GSAvatarSync`: the packed wire form and the backbone fetch |
| `addons/gs_user_avatar/store/` | `GSAvatarStore` and its memory, local and backbone stores |
| `addons/gs_user_avatar/actions/` | `GSAvatarActions` (equipped emotes, poses, gestures; the starter set's ids match the site's `BUILTIN_AVATAR_ACTIONS`), `GSAvatarActionInput` (`,` `;` `/`, rebindable, and console commands), `GSAvatarContentCache` (uploaded GLBs by content id, verified, loaded with `GLTFDocument`), `GSAvatarContentFetcher` (before connecting: reads the site's `/api/avatar/v1/library`, downloads the content ids a server requires into the cache, holds a `GSLoadGate` until all are verified; failure keeps the gate held and the caller must not connect) |
| `addons/gs_user_avatar/wearables/` | `GSAvatarWearables`: the site's equipped wearables (rigid GLBs, one per slot) hung on a figure's `Skeleton3D` with a `BoneAttachment3D` each; slot, bone and offset re-checked against the site's tables (`src/types/avatar/wearables.ts`), humanoid bone names resolved through aliases (the built-in figure, rig prefixes). Rows come from `GSAvatarSync.fetch_wearables`, files from `GSAvatarContentCache` |
| `addons/gs_user_avatar/rules/` | `GSAvatarAppRules`: a game's per-app switches (actionsEnabled, emotesEnabled, posesEnabled, gesturesEnabled, wearablesEnabled) and per-wearable rules from the site; `GSAvatarActions.from_backbone(actions, max, rules)` and `GSAvatarWearables.rules` honour them (an off kind is empty, an off wearable is not hung). The site's answer is taken as given: no built-in fallback, max 0 = unlimited, over a nonzero max fails with CODE_QUOTA, never trimmed |
| `addons/gs_user_avatar/net/gs_avatar_library_client.gd` | `GSAvatarLibraryClient`: the player-token `/api/app/v1/avatar/actions` and `/wearables` calls; every GET and PUT carries `appId`, equips are checked against the site's max locally first |
| `tools/export_avatar_manifest.gd` | `EditorScript`: parts to `.glb` and the website editor's manifest |
| `examples/avatar_demo.tscn` | the suite; all offline, non-zero on failure |

## Running and testing

- The family's two steps ([family CLAUDE.md](../../CLAUDE.md#validating-anything)), then `godot --headless --path . res://examples/avatar_demo.tscn`, `res://examples/avatar_fetch.tscn` (the fetcher, offline) and `res://examples/avatar_wearables.tscn` and `res://examples/avatar_app_rules.tscn`.
- `_test_store_contract` runs one sequence against every store and requires the same answers. **Add any new store to it.**
- **Add a case for any change to `GSAvatarSchema.validate`, `GSAvatarSync.read` or the entitlement path**: there a bug is a vulnerability rather than a crash.

## Rules that bite

- **`GSAvatarSchema.validate` loads nothing**: no `load()`, no `ResourceLoader.exists()`, no scene path. Ids only; content resolves only on a client through `GSAvatarCatalogue` and GameSpice Cloud. [document](docs/document.md#the-one-idea)
- `publish` checks structure, schema, entitlements, then stores; stores check structure only and never pretend to check entitlements. [document](docs/document.md#the-trust-boundary-is-dotavatarmanagerpublish)
- Entitlements default to nothing and `GSAvatarPart.free` to false; `everything()` stays conspicuous. [document](docs/document.md#why-entitlements-default-to-nothing)
- Conform before validate; `conform` refuses only another schema; a required slot needs a default. [document](docs/document.md#conform-before-validate-always)
- `from_dict` caps while reading; ids are base64url plus `.`; `GSAvatarKey` is a deliberate duplicate of GameSpice User's check. [document](docs/document.md#bounds-and-where-they-are-enforced)
- Colours quantise to 8 bits in `set_colour`, alpha dropped; `filled_slots()` sorts **by text** (`sort_custom`, never `sort()`: StringNames sort by interning), so the digest matches across machines and the site. [document](docs/document.md#the-digest-and-why-a-profile-carries-it)
- Fallback chains are walked bounded; nothing resolving is a `missing` step, never a hang. [document](docs/document.md#a-player-who-cannot-be-seen)
- No stored avatar: `default_avatar_fn` (null is silent, a misfit WARNs and falls back). Another schema's document: `translate_fn`, before conform. `saved: false` is no avatar. [integration](docs/integration.md)
- The backbone store sends `to_dict()`, never the packed form; keys are scoped derivations; a digest mismatch warns and the server's digest wins. [integration](docs/integration.md#the-backbone-store-and-why-the-wire-format-is-not-the-packed-one)
- The backbone store parents the `GSHttp` it builds to the root on `open` (an orphan fails every request with engine error 3) and frees only that one on `close`; `open()` runs one attempt at a time. [integration](docs/integration.md#the-backbone-store-and-why-the-wire-format-is-not-the-packed-one)
- Fakes extend the real `GSHttp` and are no more forgiving than it, including refusing outside the tree; the transport section uses the real client. [integration](docs/integration.md#the-backbone-store-and-why-the-wire-format-is-not-the-packed-one)
- `plan()` stays here; general node building is GameSpice Player Char's `GSPlayerModelBuilder` via `plan_dicts()`; neither imports the other. Tint per instance, never by editing a material. [integration](docs/integration.md#building-nodes-plan-here-apply-in-gs-player-char)
- The manifest exporter never guesses a palette or which parts are free. [integration](docs/integration.md#exporting-for-a-web-editor)

Deliberately not here: the editor UI, commerce, rigging, skinned user-made clothing (wearables are rigid), animation playback (actions are data here; the figure in GameSpice Player Char plays them). [document](docs/document.md#deliberately-not-here)
