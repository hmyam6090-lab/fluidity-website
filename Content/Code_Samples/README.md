# Fluidity: CORE SCRIPTS OVERVIEW

---

## blob-movement.gd

Controls the water-form player. It drives softbody physics movement through horizontal forces, jump buffering, and a stronger fall gravity to keep movement snappy. It also manages the low-pass audio filter on the Master bus while the player is submerged, and rolling SFX that get louder with ground speed.

Zone detection (water, currents, wind, clouds) is handled by a single shared helper that checks whether the blob's center is inside any zone polygon in a given group. All 12 zone types are one-liner public wrappers around that helper, so adding a new zone type takes one line.

Death feedback (knockback burst, mesh stretch, particle pop) and the plant-danger stroke-color warning are self-contained systems the controller calls each frame. Every physics and VFX tuning value is exported so designers can tweak it directly in the inspector without touching code.

---

## vapor_softbody.gd

Controls the vapor-form player. Instead of ground movement, it applies a constant upward float force and lets directional input steer with thrust. It uses the same zone detection pattern as the water form, just with 9 zone types instead of 12.

It spawns a `Trail` node at runtime and updates it each physics frame. Death feedback includes a shader hit-flash and the same knockback burst as the water form. The plant-danger warning works identically. All physics, float speed, and VFX values are exported for inspector tuning.

---

## player_state.gd

The central controller that owns the temperature system and manages switching between forms. Each frame, temperature moves toward the room's base temperature at rest and is limited by a stamina bar to prevent spamming transitions. When temperature crosses a threshold, the current player node is freed, a new scene is instantiated in its place, and the camera is re-wired automatically.

The death sequence saves the current scene path, triggers a camera shake and an optional shader flash, then reloads the scene after a short delay using `LevelTransition`. Surface sticking and plant sticking delegate all force math to the sticky-surface node itself via duck-typed calls, so the controller stays decoupled from any specific surface type. Respawn markers are set in the inspector as room-ID to world-position pairs. All timing, shake strength, flash, and stamina values are exported.

---

## room_state.gd

Registers a level's room layout (centers, bounds, base temperatures) with `Globals` on startup, then detects which room the player is in each frame using axis-aligned bounding box checks. When the player enters a new room it calls `MusicManager.set_context` and saves a checkpoint respawn position.

The design goal is that you fill in the room arrays in the inspector and drop this script into any level scene. No per-level scripting needed.

---

## globals.gd

The autoload singleton that everything else can read from. It handles:

- Room layout registration and position-to-room lookup
- Run progress save and load via a `ConfigFile` at `user://run_progress.cfg`
- Settings loading for audio volumes, video modes, and keybinds
- Achievement and collectible tracking backed by `progress.cfg`
- A per-frame cache of the active player node so any UI or system can read player data without holding a direct reference

All persistent state is written only at explicit checkpoints, never auto-saved on window close.

---

## music_manager.gd

A dual-player crossfade system. Two `AudioStreamPlayer` nodes take turns: when a new track starts, the incoming player fades in while the outgoing one fades out via a tween.

Tracks are organized into three dictionaries: `scene_tracks` maps scene paths to streams, `context_tracks` maps string keys to streams, and `track_chains` maps a stream to the next context key so tracks can queue into each other automatically. Sync groups let a set of tracks always start at the same playback position for seamless switching between loop variants. Adding a new track is one line per relevant dictionary.

---

## sfx_manager.gd

Centralized one-shot SFX. One `AudioStreamPlayer` per event, keyed by `StringName` constants (`EVENT_*`). If a stream is not assigned in the inspector, that event is silently skipped with no code change needed.

Cooldown throttling is handled by a timestamp dictionary so high-frequency events like hover sounds don't stack. On startup, every `BaseButton` in the scene tree gets hover and click SFX connected automatically, so UI sounds work globally without any per-button script. Adding a new sound event takes: one constant, one exported stream variable, one line in `_build_players`, and one public wrapper function.
