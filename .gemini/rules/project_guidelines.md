# Astro Striker - Project Guidelines & Architecture Rules

## 1. Dual Platform Architecture (PC Ultra vs Mobile 60 FPS)
- **Developer Request Workflow:** The user describes game features, mechanics, bosses, levels, and VFX naturally in full quality. The AI must NOT require the user to specify platform-specific restrictions per prompt.
- **Behind-the-scenes Implementation:** Always write features in maximum visual quality for PC. Simultaneously, insert runtime `if is_mobile` checks (`OS.has_feature("mobile")` / `OS.has_feature("android")` / `OS.has_feature("ios")`) or project setting overrides for mobile performance:
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