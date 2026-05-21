# Changelog

## [1.5.0] — 2026-05-20

### Added

- **Share from the note list** — right-click (macOS) or long-press (Android) any note to share, move, or delete without opening it first. Works from All Notes, folder views, Shared by me, and Shared with me.
- **Forward sharing** — collaborators can add additional people to a shared note. Only the note owner can remove collaborators.
- **Safe sign-out** — pending notes and folders are uploaded to Drive before signing out. A progress dialog shows on slow connections with the option to discard unsynced changes.
- **Android adaptive icon** — the app icon now uses Android's adaptive icon system with a separate foreground and background layer, ensuring correct appearance across all launcher shapes (circle, squircle, rounded square).

### Fixed

- Notes created or edited just before logout are no longer lost on the next login.
- Shared notes no longer appear as duplicates in All Notes after logging out and back in.
- Ghost shared notes (revoked shares still in the Drive backup) no longer reappear on every login.
- The "Shared by me" list now accurately reflects the current collaborator state from Firestore.
- The sharing icon no longer appears on notes whose share has been revoked (stale Firestore ID no longer triggers the icon).
- Text fields auto-focus: the username field on the login screen and the email field in the share dialog.

## [1.4.0] — 2026-05-19

### Added

- **Note sharing** — share a note with other Google account users for real-time collaborative viewing and editing. Tap the share icon in the note toolbar to add collaborators by Google email address or copy a web link to the note.
- **Share attribution** — the sharing dialog shows who originally shared a note with you, and tracks the chain when a collaborator re-shares with someone else.
### Fixed

- macOS: copying formatted text from one note and pasting into another now correctly preserves all formatting (bold, italic, headings, lists, colours, and more).
- Google Sign-In on macOS no longer shows a second OAuth permission popup.

### Known limitations

- Shared notes are stored in Firestore and are **not** end-to-end encrypted. Do not share sensitive content.
- Embedded images in shared notes are limited to **600 KB per image** and **800 KB total** per note. Images that exceed the limit are replaced with a placeholder for recipients; the originals on the owner's device are not affected.
