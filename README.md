Player avatars as data, so a dedicated server can check one without ever loading a mesh. An avatar is a schema id, a set of part ids and a set of colours: a few dozen bytes. The server validates it against the schema and the player's entitlements, and a client resolves the part ids to real assets.

## Install

1. Get [Godot 4.7](https://godotengine.org/download).
2. Either use [dot-bootstrap](https://github.com/gamespice-platform/bootstrap), which clones every project and links the addons, or copy `addons/dot_user_avatar/` and [dot-core](https://github.com/gamespice-platform/core)'s `addons/dot_core/` into your project and enable both in *Project > Project Settings > Plugins*.

dot-core is the only dependency. [dot-user](https://github.com/gamespice-platform/user), [dot-cloud](https://github.com/gamespice-platform/cloud), [dot-net](https://github.com/gamespice-platform/net) and [dot-server](https://github.com/gamespice-platform/server) work with it, and none is imported.

## Use

```gdscript
var avatars := DotAvatarManager.new()
avatars.schema = preload("res://avatars/humanoid.tres")
add_child(avatars)

# Server: what should this player look like?
var resolved := await avatars.resolve(user_key, entitlements)

# Server: a client sent us a new one.
var published := await avatars.publish(user_key, incoming, entitlements)
if not published.ok:
    print(published.error)   # "You do not have that item."
```

An avatar names its parts rather than embedding them:

```gdscript
var a := DotAvatar.make(&"humanoid")
a.set_part(&"hair", &"hair_long")
a.set_colour(&"hair", 0, Color("6b4423"))
```

Validation answers four questions from ids alone: does the slot exist, does the part exist and fit that slot, is the player entitled to it, and are the colours within the part's channel count. Nothing is loaded.

## What is in it

| Class | What it is |
| --- | --- |
| `DotAvatar` | The document: versioned, with a stable digest. |
| `DotAvatarSchema` | Slots, parts, and the `validate` and `conform` pair. |
| `DotAvatarSlot`, `DotAvatarPart` | What a game defines: layers, defaults, fallbacks, entitlement. |
| `DotAvatarEntitlements` | What one player may wear. Owns nothing by default. |
| `DotAvatarCatalogue` | Part id to content, through dot-cloud when it is installed. |
| `DotAvatarBuilder` | Plan (pure) and apply (touches nodes). |
| `DotAvatarSync` | Bit-packed wire format and the back end endpoints. |
| `DotAvatarStore` | Where documents live: memory, JSON files or a back end. |
| `DotAvatarActions`, `DotAvatarActionInput` | A player's equipped emotes, poses and gestures, a starter set, and the keys (`,` `;` `/` by default, rebindable) and console commands that play them. |
| `DotAvatarContentCache` | Uploaded avatar and action GLBs, kept by content id after a size and hash check. |
| `DotAvatarManager` | Resolve, conform, validate, publish, cache, rate-limit. |

## Avatars that follow a player between servers

Set the backend to `backbone` and documents live on a web back end instead of the server's disk.

```gdscript
manager.config.backend = "backbone"
manager.config.backbone_url = "https://moddingcommunity.com/api/integration/v1"
manager.config.backbone_token = OS.get_environment("AVATAR_TOKEN")
manager.config.read_only = true    # most servers should read and never publish
```

The protocol is `GET`, `PUT` and `DELETE /user/{key}/avatar`, plus a public `GET /api/avatar/v1/schema`. It is open and anyone can implement their own; the spec is at [docs/api/avatar-protocol.md](https://moddingcommunity.com/docs/api/avatar-protocol.md).

- The server holds its own credential, never the player's.
- `{key}` is a scoped derivation, not an account id, so no two operators can compare logs and follow a player across servers (see dot-user).

## When things go wrong

- **Cosmetics not downloaded.** The player must still be visible. Parts declare a `fallback_id`, the catalogue walks the chain, and the plan reports what was substituted or missing so the game can show a placeholder.
- **Schema changes.** `conform()` repairs old documents instead of refusing them: it drops what no longer exists, fills required slots from defaults, and reports what changed.

## Entitlements

`DotAvatarEntitlements` is a set of part ids. Where they come from (a purchase, a season pass, a site group) is the game's business. A player owns nothing by default; a part is wearable only if it is marked free or is in the set. `enforce_entitlements` can be turned off for a creator sandbox, and warns loudly at startup when it is.

## Testing

Import the project once, then run `examples/avatar_demo.tscn` headless with Godot. It exits non-zero on failure. One `ERR avatar.store an avatar was not saved` line on stderr is expected, because the suite fails a back end write on purpose.

## Status and licence

Part of the TMC **dot-\*** family of Godot addons. Written with Claude Code and maintained by `gamemann`. Every addon has headless tests, but little of this has been played by real users yet, so expect rough edges and please [open an issue](https://github.com/gamespice-platform/user-avatar/issues) when you hit one.

MIT licence, see [LICENSE](LICENSE). The only closed part of the TMC platform is the web back end; you can use your own instead of TMC's.
