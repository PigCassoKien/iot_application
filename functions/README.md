# Cloud Functions for Clothesline App

This folder contains a minimal Cloud Function to forward `/notifications/pending` entries to FCM tokens stored in `/device_tokens`.

Deploy:

1. Install Firebase Tools and login:

```bash
npm install -g firebase-tools
firebase login
```

2. Initialize / deploy functions from this folder:

```bash
cd functions
npm install
firebase deploy --only functions
```

Notes:
- The function uses the Admin SDK and reads `/device_tokens` to collect tokens.
- It marks the `delivered` flag on the notification node after sending.
- Handle token cleanup for failed tokens in production.
