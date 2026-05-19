# Changelog

## [1.4.0] — 2026-05-19

### Added

- **Note sharing** — share a note with other Google account users for real-time collaborative viewing and editing. Tap the share icon in the note toolbar to add collaborators by Google email address or copy a web link to the note.
- **Share attribution** — the sharing dialog shows who originally shared a note with you, and tracks the chain when a collaborator re-shares with someone else.
- **Clipboard formatting preserved on macOS** — copying rich text from one note and pasting into another now preserves all formatting (bold, italic, headings, lists, colours, and more).

### Fixed

- Google Sign-In on macOS no longer shows a second OAuth permission popup.

### Known limitations

- Shared notes are stored in Firestore and are **not** end-to-end encrypted. Do not share sensitive content.
- Embedded images in shared notes are limited to **600 KB per image** and **800 KB total** per note. Images that exceed the limit are replaced with a placeholder for recipients; the originals on the owner's device are not affected.
