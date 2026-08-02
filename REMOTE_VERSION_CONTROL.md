# Remote version control

Parchís Pop checks Firebase Remote Config at launch on iOS, Android and macOS.
It uses cached values if the device has no connection. The default is always to
let the player enter the game.

## Parameters to create in Firebase Remote Config

| Parameter | Default | Use |
| --- | --- | --- |
| `app_enabled` | `true` | Emergency global shutdown. Keep `true` in normal operation. |
| `minimum_supported_version` | `0.0.0` | The lowest version allowed to play. Use this for a replacement release. |
| `update_message` | `Download the new app to keep playing.` | Message shown when an installed version is blocked. |
| `update_url` | empty | App Store / Google Play page for the new app or current update. |

## Recommended replacement process

1. Publish the new app version, for example `1.1.0`.
2. Confirm it is live in the stores and set `update_url` to its store page.
3. In Firebase Remote Config, set `minimum_supported_version` to `1.1.0`.
4. Publish the Remote Config change.

Older installations will show **Download the new app** and cannot enter the
game. Version `1.1.0` and newer continue normally.

Do not set `app_enabled` to `false` for a normal update: it blocks every
version, including the new one. Reserve it for an emergency shutdown.
