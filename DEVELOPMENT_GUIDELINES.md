# Novastorm - Project Guidelines & Architecture Rules

## 1. Dual Platform Architecture (PC Ultra vs Mobile 60 FPS)
- **Developer Request Workflow:** The user describes game features, mechanics, bosses, levels, and VFX naturally in full quality. The AI must NOT require the user to specify platform-specific restrictions per prompt.
- **Behind-the-scenes Implementation:** Always write features in maximum visual quality for PC. Simultaneously, branch on `GameConfig.is_mobile` (see section 5 — do NOT scatter `OS.has_feature(...)` across scripts) for mobile performance:
  - **PC:** Full resolution (1.0), 4000m camera far, 4096 shadow map with 4 cascades at 800m, full Triplanar materials, unlocked framerate (`max_fps = 0`).
  - **Mobile:** FSR 1.0 at 75% render scale, 3500m camera far, 512 shadow map with 100m Orthogonal focal shadow box around ship, lightweight direct UV materials (`terrain_detailed_mobile.tres`), object pooling for bullets/VFX, locked 60 FPS (`max_fps = 60`).

## 2. Git Push Policy
- **DO NOT auto-push to GitHub on every prompt.**
- Local commits (`git commit`) are encouraged per feature/step.
- Remote push (`git push`) must ONLY be performed once per day or when explicitly requested by the user.

## 3. APK Export Policy
- **DO NOT auto-compile APKs** on every prompt unless explicitly requested by the user.
- Export toolchain: OpenJDK 17 (`C:\Users\ronal\android_jdk\jdk-17.0.10+7`), Android SDK (`C:\Users\ronal\AppData\Local\Android\Sdk`), debug keystore in place.

## 4. Single Source of Truth for Game Objects
- **Player Ship:** `res://scenes/player.tscn` is the standalone master player scene. GameController instantiates `player_scene` dynamically on `PathFollower`.
- **Mothership:** `res://scenes/world/mothership.tscn` is the reusable master scene for the Mothership.
- **BigRock:** `res://scenes/world/big_rock.tscn` is the reusable procedural rock with terrain material and collision.
- **Main Menu:** `res://scenes/main_menu.tscn` is the project's entry scene (main scene). Its buttons: "START GAME" (loads `res://scenes/game.tscn`) and "GRAPHICS SETTINGS" (opens the `SettingsMenu`).

## 5. GameConfig — Single Source of Truth (Platform & Quality)
- **`res://scripts/config/game_config.gd`** is an autoload named `GameConfig` (class `GameConfigClass`). It centralizes, computed once in `_ready`:
  - Platform flags: `GameConfig.is_mobile`, `GameConfig.is_pc`, `GameConfig.is_web`.
  - Quality constants: `CAMERA_FAR_PC/MOBILE`, `MAX_FPS_PC/MOBILE`, `RENDER_SCALE_PC/MOBILE`, `FSR_SHARPNESS_MOBILE`, `SHADOW_MAX_DISTANCE_PC/MOBILE`.
- **RULE:** `OS.has_feature(...)` must ONLY live inside `game_config.gd`. Everywhere else, read `GameConfig.is_mobile` / `GameConfig.is_pc`.
- **Mobile asset variant pattern:** for a full-scene/asset swap (e.g. the player projectile), keep a `_mobile` variant scene (e.g. `bullet_mobile.tscn` — no per-bullet OmniLight, smaller flares, fewer particles) and select it once in `_ready` via `GameConfig.is_mobile` using lazy `load()` (NOT `preload`, to avoid loading it on PC). NOTE: Godot's feature-tag file override (`file.mobile.tscn`) does NOT resolve at runtime `load()`/`preload()` — it is import/export-time only.
- **UID format:** resources use `.uid` sidecar files (Godot 4.4+). Do not hand-write inline `uid="..."` attributes into new `.tscn`/`.tres` headers; let the editor generate the `.uid` file on save.

## 6. UserSettings — User Graphics Options (same menu on all platforms)
- **`res://scripts/config/user_settings.gd`** is an autoload named `UserSettings`. It persists the player's graphics choices to `user://settings.cfg` (via `ConfigFile`).
- The SAME options menu appears on PC and Mobile — accessible from the main menu ("GRAPHICS SETTINGS" button) and in-game (gear ⚙ button / ESC). Each toggle reads `UserSettings.get_<feature>()`, which returns the user's override OR the platform default from `GameConfig` when unset.
- Current toggles: `shadows`, `glow`, `ssao`, `ssil`.
- **Mobile defaults:** `glow` is ON (lighter via `GLOW_INTENSITY_MOBILE`/`GLOW_BLOOM_MOBILE`) because the player projectile's bloom depends on it; `ssao` and `ssil` are OFF on mobile (expensive + subtle). Shadows are ON on both.
- **RULE:** graphics code that the user can control must read from `UserSettings`, NOT `GameConfig.is_mobile` directly. `GameConfig.is_mobile` only supplies platform *defaults* (via `SHADOWS_DEFAULT_*`, `GLOW_DEFAULT_*`, etc.).
- Changing a setting emits `UserSettings.settings_changed`; `game_controller.gd` re-applies graphics on that signal (`_apply_graphics_settings`).
- The menu UI is `res://scripts/ui/settings_menu.gd` (self-contained, built procedurally).