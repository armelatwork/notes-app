# My Notes

A cross-platform rich text notes app for macOS and Android with folder organisation, Google Drive sync, and end-to-end encryption.

---

## Features

### Authentication

Two sign-in methods are available on the login screen:

- **Google Sign-In** — uses your Google account. Silent sign-in restores your session automatically on restart.
- **Local account** — username and password stored on-device. A password is required every session (the encryption key is derived from it and never stored).

### Notes

- Create, edit, and delete notes from the notes list panel.
- Notes are sorted by last-modified date (most recent first).
- New notes get unique auto-incremented default titles: *New Note*, *New Note 2*, *New Note 3*, and so on — visible in the list immediately without opening the note.
- A preview of the note body is shown beneath each title in the list.
- Right-click (macOS) or long-press (Android) a note in the list to delete it.
- Search across all notes using the search bar at the top of the notes panel. Results match on title and body preview.

### Rich Text Editor

The editor toolbar provides full text formatting:

| Format | Controls |
|---|---|
| Font | Family, size |
| Style | Bold, italic, underline |
| Colour | Text colour, highlight colour |
| Alignment | Left, centre, right |
| Structure | Headings (H1–H6), ordered list, bullet list, checklist, indent |
| History | Undo, redo |

### Images

- **Gallery picker** — click the image button in the toolbar to pick an image from the file system.
- **Drag and drop** — drag an image file from Finder or the file manager and drop it anywhere on the editor. Supported formats: PNG, JPG, JPEG, GIF, WebP, BMP.
- **Clipboard paste** — copy an image from any app, then press **Cmd+V** (macOS) while the editor is focused to paste it inline.
- Right-click an embedded image to delete it.

### Hyperlinks

- Select text and click the link button in the toolbar (or right-click and choose **Insert Link**) to attach a URL.
- The dialog lets you set the display text and URL independently.
- Click a link in the editor to open it in the browser.
- Right-click linked text to choose **Edit Link** and update or remove the link.

### Folders

- Create folders using the **+** button in the sidebar.
- Rename or delete a folder via its context menu (⋮).
- Deleting a folder moves its notes to the root inbox — notes are never lost.
- The **All Notes** view shows every note regardless of folder.

### Google Drive Sync

Available for Google accounts only:

- Notes are automatically synced to Google Drive 5 seconds after the last edit, stored in a folder called *Notes app*.
- A sync status icon in the sidebar header shows the current state: idle, syncing, success, or error.
- Tap the sync icon to trigger a full manual sync at any time.

### Backup & Restore

Available for Google accounts only. Accessible via the **Settings** screen (gear icon in the sidebar):

- **Automatic backup** — toggle backup on or off. When enabled, a backup is recorded every time a note syncs to Google Drive. Backup is on by default for Google accounts.
- **Drive location** — read-only, always `Notes app/`.
- **Last backup time** — shows how long ago the most recent backup completed.
- **Back up now** — triggers an immediate full sync of all notes and folders to Google Drive.
- **Automatic restore on startup** — if your local database is empty and your Google Drive backup contains notes, the app will prompt you to restore from the backup when you sign in.

### Encryption

All note content is encrypted at rest using **AES-256-GCM**:

- **Google accounts** — a random 256-bit key is generated on first sign-in, stored in the app's sandboxed support directory, and uploaded to Google Drive so all your devices share the same key automatically.
- **Local accounts** — the encryption key is derived from your password using **PBKDF2** and never written to disk. Your password is required to unlock your notes each session.

---

## Platforms

| Platform | Status |
|---|---|
| macOS | Supported |
| Android | Supported |

---

## Data Storage

| Data | Location |
|---|---|
| Notes and folders | Per-user Isar database in the app's documents directory |
| Embedded images | `note_images/` folder inside the app's documents directory |
| Encryption keys (Google) | App sandboxed support directory + Google Drive |
| Encryption keys (local) | App sandboxed support directory (derived from password) |
| Last open folder / note | Shared preferences (restored on next launch) |

---

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.11.5
- For Google Sign-In and Drive sync: a Google Cloud project with the Drive API enabled and OAuth credentials configured in `google-services.json` (Android) and the macOS entitlements.

### Run

```bash
flutter pub get
flutter run -d macos   # macOS
flutter run -d android # Android
```
