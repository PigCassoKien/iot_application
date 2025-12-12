# Realtime Database Rules (recommended starter)

This is a minimal set of Realtime Database rules to get started. Adjust to your auth model.

```
{
  "rules": {
    "device_tokens": {
      ".read": "auth != null",
      ".write": "auth != null && (newData.child('uid').val() === auth.uid || auth.token.admin === true)"
    },
    "control": {
      // Keep small runtime control fields under `/control` (hasClothes, stepper, mode)
      ".read": "auth != null",
      ".write": "auth != null"
    },
    "commands": {
      // Top-level commands node (devices and simulators consume this)
      ".read": "auth != null",
      ".write": "auth != null",
      "$cmdId": {
        ".validate": "newData.hasChildren(['type','source','timestamp','status'])"
      }
    },
    "status": {
      ".read": true,
      ".write": "auth != null && auth.token.device == true" // device service account or firebase secret
    },
    "notifications": {
      "pending": {
        ".read": "auth != null",
        ".write": "auth != null"
      }
    }
  }
}
```

Notes:
- For production, differentiate device credentials vs user credentials. Devices should authenticate using a service account or restricted credential and allowed to write `/status` and update `/commands/*/status`.
- The app users (normal users) may be allowed to push commands but should not be allowed to mark them `done` (only devices should).
- Cloud Functions run as admin and can read/write any node.
