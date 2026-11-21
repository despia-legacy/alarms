# Alarms for Despia V3

Source preview for Despia V3. The runtime update and automatic discovery rollout are awaiting release. Rebuild and install the native app to include these files; uploading them does not change an installed app.

Add native alarms, timers and challenge workflows to a Despia V3 app. The extension uses Apple's AlarmKit on iOS 26 and later, and Android's AlarmManager with a foreground audio service. Your app supplies its own screen and challenge logic, including progress from a push-up detector, a QR scanner or any other workflow you build.

This extension is being prepared for the Despia V3 runtime. Runtime updates and hosted extension support are pending deployment. Controlled iOS device verification is described below. First-party V4 support comes through the new package registry, with a separate API.

Use the same JavaScript SDK calls from React, Vue, Svelte, Next.js, TanStack, HTML5 or a web app made with Lovable, Base44, Replit or another builder. Despia must wrap the app and include the native extension in its build. In a server-rendered app, call the SDK from a client component, mounted hook or button handler.

## Install

1. Copy this repository's `alarms/` folder to your site's `public/despia/alarms/`.
2. Add `alarms` to `public/despia/extensions.json`:

   ```json
   { "extensions": ["alarms"] }
   ```

3. Edit `ios.app.info_plist.NSAlarmKitUsageDescription` in `alarms/manifest.json` to explain your app's alarms. The V3 extension update under review lets the verified manifest supply this text when the app's build configuration has none. Existing app-configured text takes priority. This extension depends on that update.
4. Rebuild and install the native app with this extension. Replacing files on your website does not modify an installed app.
5. Install the JavaScript SDK in your web app:

   ```sh
   npm install despia-native
   ```

Signed build verification binds source hashes, dependency pins, app identity and final artifacts. It is separate from human code review and does not require a per-app enrollment switch.

The Android module declares its own permissions and private components. Exact alarm access, notification permission and full-screen access have separate system controls. The app must qualify for any applicable store requirements. The iOS countdown widget target is included by the manifest.

[V3 extension setup](https://setup.despia.com/experiments/v3-extensions) and [extension skill](https://github.com/despia-legacy/extension-skill) describe the runtime and packaging contract.

## Create an alarm

Request permission from a user action, then query `permissions` again when the user returns. Permission requests return `pending: true` while the system prompt is open. They do not keep a JavaScript request waiting for the entire dialog.

```js
import despia from 'despia-native';

const permissionReply = await despia(
  'extension://alarms/permissions?request=true&delivery=system',
  ['alarmsPermissions']
);
const permission = permissionReply.alarmsPermissions;
if (!permission?.ok) throw new Error(permission?.error ?? 'No native answer');
```

After permission is granted:

```js
const alarm = {
  label: 'Morning movement',
  body: 'Complete your exercise in the app',
  schedule: { hour: 7, minute: 30, weekdays: [1, 2, 3, 4, 5] },
  snooze_seconds: 300,
  challenge: { kind: 'pushups', target: 10 },
  metadata: { screen: '/morning' }
};
const savedReply = await despia(
  `extension://alarms/save?alarm=${encodeURIComponent(JSON.stringify(alarm))}`,
  ['alarmsSave']
);
const saved = savedReply.alarmsSave;
if (!saved?.ok) throw new Error(saved?.error ?? 'No native answer');
const alarmId = saved.data.alarm.id;
```

The declared output variable is the second SDK argument. SDK 1.0.28 returns an object whose matching property contains the full native envelope: `ok`, `code`, `error` and `data`, with runtime metadata. Native `ok: false` answers resolve the promise, so check `ok` before reading `data`; `code` identifies the failure and `error` contains its message. A single watched value becomes `undefined` after 30 seconds without an answer. Await calls using the same output variable sequentially.

## Routes

All routes use `extension://alarms/<route>`, passed to the Despia SDK. Parameters are URL query parameters. JSON parameters are serialized and URL-encoded.

| Route | Parameters | Answer under `data` | SDK output variable |
| --- | --- | --- | --- |
| `capabilities` | None | Provider and supported operations | `alarmsCapabilities` |
| `permissions` | Optional `request`, `delivery`: `system` or `notification` | Current authorization and optional `pending` | `alarmsPermissions` |
| `save` | `alarm`: JSON definition | `alarm` with generated or supplied id | `alarmsSave` |
| `get` | `id` | Stored alarm and refreshed AlarmKit state where available | `alarmsGet` |
| `list` | Optional `group` | `alarms` | `alarmsList` |
| `cancel` | `id` | Removed alarm | `alarmsCancel` |
| `stop` | `id`, optional `emergency` | Alarm after stopping | `alarmsStop` |
| `snooze` | `id`, optional positive integer `seconds` | Alarm with its next trigger | `alarmsSnooze` |
| `pause` | `id` | Paused alarm | `alarmsPause` |
| `resume` | `id` | Resumed alarm | `alarmsResume` |
| `challenge` | `id`, `progress`: finite decimal numeric text | Updated alarm; reaching target stops it | `alarmsChallenge` |
| `events` | None | Retained event receipts | `alarmsEvents` |
| `events_ack` | `ids`: JSON array of receipt ids | Number `acknowledged` | `alarmsEventsAck` |
| `android_access` | `access`: `exact_alarms`, `full_screen` or `notifications` | Current access and `opened` when a system screen opened | `alarmsAndroidAccess` |

Opening the app from the native alarm screen or AlarmKit action retains an `opened` receipt with the logical alarm id. Definitions and event receipts survive web navigation and process restart. Query them on the next app launch. A `changed` event and a `permission` event also notify the current document, but events are not a substitute for reading the durable state.

## Alarm definitions

An alarm takes a UUID `id`, generated when omitted. Saving the same id replaces that definition. Optional `group` is your own string, used by `list`. `metadata` and the contents of a challenge's optional configuration object belong to your app.

Choose one schedule:

```js
{ at_ms: Date.now() + 60_000 }
{ countdown_seconds: 60 }
{ hour: 7, minute: 30, weekdays: [1, 2, 3, 4, 5] }
```

On iOS, `next_at_ms` for a local schedule is a computed forecast, refreshed when the native state advances or is queried. It is not an exact delivery timestamp reported by AlarmKit.

Weekdays follow ISO numbering, Monday 1 through Sunday 7. Omit `weekdays` or use `[]` for the next single local occurrence. Android also accepts an IANA `timezone` on a local schedule. AlarmKit's relative schedules follow the device's local time zone. DST gaps preserve the minute through the forward transition; repeated local times use the first occurrence in the schedule calculation.

Other fields include `label`, `body`, `enabled`, `sound`, `snooze_seconds`, `stop_label`, `snooze_label`, `open_label` and `challenge`. On iOS, `color` is `#RRGGBB`, and a custom `sound` names a sound already bundled with the app. On Android, `sound` is `default` or an accessible `content:` or `file:` URI. Android also supports per-player `volume` from 0 to 1, `loop`, `vibrate`, `full_screen` and `emergency_label`. The extension does not change the system volume or notification settings. For scheduled custom audio, the app must retain read access to its URI until the alarm fires.

## Challenge workflow

`challenge.kind` is your own name. `target` must be positive. `progress` starts at zero, and the app reports its progress through `challenge`. Fractional targets and progress are supported. The URL parameter is numeric text such as `0.5` or `1e-3`. Encode each parameter with `encodeURIComponent`, as the examples do. Report a value between zero and the target, clamping an overshoot to the target before calling. For a target of 10:

```js
const reply = await despia(
  `extension://alarms/challenge?id=${encodeURIComponent(alarmId)}&progress=10`,
  ['alarmsChallenge']
);
if (!reply.alarmsChallenge?.ok) {
  throw new Error(reply.alarmsChallenge?.error ?? 'No native answer');
}
```

A normal `stop` returns `challenge_incomplete` until the target is met. `stop?emergency=true` always allows stopping. Android's notification and native alarm screen provide an emergency control. Apple's system Stop control remains available and is not blocked by a challenge. This extension does not itself detect push-ups, guarantee that reported exercise occurred, prevent force-stop or stop a person revoking access.

## Platform behavior

On iOS 26 and later, `delivery: "system"` uses AlarmKit, including its authorization, system alarm UI and countdown Live Activity. Native `pause` and `resume` apply to countdowns, including a snooze countdown. Native `snooze` applies while the alarm is alerting and uses the definition's `snooze_seconds`; a different per-call `seconds` override is Android only. The system keeps control of its Stop button. On iOS 26.1 and later, AlarmKit ignores the custom `stop_label` and uses its own system label. A custom secondary action opens the app for a challenge.

On older iOS, system alarms return `unsupported`. You can explicitly choose `delivery: "notification"` for a notification reminder and request its separate permission. This is a notification, with system sound and Focus settings; it is not an AlarmKit alarm, a looping background ringtone or a lock-screen exercise screen. Notification reminders do not support native countdown pause and resume.

Android uses exact alarm special access and a visible foreground service while ringing. Full-screen presentation depends on system access and notification settings. Its native ring screen can open the app, snooze or stop an alarm. A boot receiver re-arms future alarms after the device unlocks. It records a missed one-shot alarm rather than starting media playback from boot. Repeating local alarms are recalculated on boot, clock and time-zone changes. Force-stop, revoked access and manufacturer restrictions can prevent delivery.

Tested on an iPhone 15 running iOS 26.1: authorization, countdown pause/resume, background alarm delivery, native Snooze and Stop, Open app, app-reported fractional challenge progress, recovery after the app process ended, and cleanup. Locked-screen presentation, reboot recovery, weekly/DST timing, custom sound quality, older-iOS fallback and store distribution remain unverified.

## License

Source is available under the [Despia Extension Commercial License](LICENSE). Use in an application requires a valid Despia commercial license for that application and operating system, and a valid Despia project. This is not an open-source license.

## Source and licensing

Browse, clone or fork this source to inspect it. Public GitHub forks remain public. For private development, clone into a private workspace or private repository. Modification, building, execution and deployment require a valid Despia commercial license and a valid Despia project for the application. The standard price is USD 249 per application per operating system. Licensed users may customize the extension or use it as a reference for new functionality in that licensed app. Keep the license and applicable notices. See [LICENSE](LICENSE) for the terms.
