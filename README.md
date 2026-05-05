# Notes

A cross-platform rich text notes app for macOS and Android with folder organisation, Google Drive sync, and end-to-end encryption.

---

## Features

### Authentication

Two sign-in methods are available on the login screen:

- **Google Sign-In** — uses your Google account. Silent sign-in restores your session automatically on restart.
- **Local account** — username and password stored on-device. A password is required every session (the encryption key is derived from it and never stored).

Sign out via the user menu at the bottom of the sidebar.

### Notes

- Create, edit, and delete notes from the notes list panel.
- Notes are sorted by last-modified date (most recent first).
- New notes get unique auto-incremented default titles: *New Note*, *New Note 2*, *New Note 3*, and so on.
- A preview of the note body is shown beneath each title in the list.
- Search across all notes using the search bar at the top of the notes panel. Results match on title and body preview.
- The default view on login is **All Notes**.

### Organising Notes

- **Move to folder (macOS):** right-click a note and choose **Move to Folder**, or drag it from the notes list onto any folder or the Notes inbox in the sidebar.
- **Move to folder (Android):** long-press a note and choose **Move to Folder** from the bottom sheet.
- **Delete (macOS):** right-click a note and choose **Delete Note**.
- **Delete (Android):** long-press a note and choose **Delete** from the bottom sheet.

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

Tab key inserts a fixed-width indent character inside the editor.

### Images

- **Gallery picker** — click the image button in the toolbar to pick an image from the file system.
- **Drag and drop** — drag an image file from Finder or the file manager and drop it anywhere on the editor (macOS/desktop only). Supported formats: PNG, JPG, JPEG, GIF, WebP, BMP.
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
- **All Notes** shows every note regardless of folder.
- **Notes (inbox)** shows only notes not assigned to a folder.
- On Android, tapping a folder in the drawer closes it automatically and shows the folder contents.

### Google Drive Sync

Available for Google accounts only. All synced data is end-to-end encrypted before leaving the device.

#### How it works

Sync uses an incremental log (`sync_log.json` on Drive). Every change appends a log entry; devices poll the log's last-modified timestamp every 5 seconds and only download the full log when something has changed.

| Operation | Push delay |
|---|---|
| Note editing (text / images) | 15 s after the last keystroke |
| Moving notes | 5 s after the last move; all moves in the window are batched |
| Folder create / rename / delete | 5 s |
| Note delete | Immediate |

#### Sync icon

The icon in the sidebar header reflects the current state:

| Icon | Meaning |
|---|---|
| ↻ (neutral) | Idle — changes pending or no recent sync |
| ⏳ Spinner | Syncing in progress |
| ✓ Green | Last sync completed successfully |
| ✗ Red | Persistent sync error — tap to retry |

Tap the icon at any time to trigger an immediate sync.

#### First login

When signing in to Google on a device that has no local data, the app checks Drive for existing notes. If found, a dialog offers **Sync now** or **Later** (notes appear automatically within 5 seconds either way).

### Settings

Accessible via the user menu (bottom of the sidebar → your name):

- Account name and email
- Google Drive sync location (*Notes app/*)
- Sign out

### Encryption

All note content is encrypted at rest using **AES-256-GCM**:

- **Google accounts** — a random 256-bit key is generated on first sign-in, uploaded to Drive, and shared across all your devices so every device can decrypt your notes.
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
| Notes and folders | Isar local database in the app's documents directory |
| Embedded images | `note_images/` folder inside the app's documents directory |
| Encryption key (Google) | Google Drive (`encryption_key.b64` in the *Notes app* folder) |
| Encryption key (local) | Derived at runtime from password; never persisted |
| Last open folder / note | Shared preferences (restored on next launch) |
| Sync log position | Shared preferences (per device, per user) |

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

### Regenerate the app icon

```bash
flutter test test/generate_icon_test.dart   # renders icon via Flutter engine
dart run flutter_launcher_icons             # stamps out all platform sizes
```
