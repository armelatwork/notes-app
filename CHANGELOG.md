# Changelog

## [2.0.0] — 2026-06-01

### Added

- **AI Writing Assistant** — tap the wand icon (✦) in the note editor to generate an AI-powered rewrite of your note. Refine the suggestion with a follow-up prompt, then apply it with one tap. The suggestion is cached for the session so re-opening the sheet is instant. Supported providers: Claude (Anthropic), Perplexity, Gemini (Google), ChatGPT (OpenAI). Configure your provider and API key in Settings → AI Helper.
- **Duplicate note** — right-click a note (macOS) or long-press (Android) and choose Duplicate to create an exact copy. The duplicate is saved with the title *Copy - \<original title\>* in the same folder, without pinned state or sharing settings.

## [1.6.1] — 2026-05-31

### Fixed

- Signing out from the Settings screen now returns to the login screen immediately instead of leaving the Settings page open.
- Fixed a data-loss edge case where a fresh install on one device could generate a new encryption key and overwrite the correct key on Google Drive, making all notes on other devices unreadable. The app now treats the locally stored key as the source of truth and automatically restores it to Drive if the two ever drift apart.

## [1.6.0] — 2026-05-29

### Added

- **Pin notes** — pin any note so it always appears at the top of every view. Pinned notes appear in a sticky group above all others in All Notes, folders, and inbox. Pin state syncs to Google Drive. Pin or unpin via the pin icon in the note title bar, or via the context menu (right-click on macOS, long-press on Android).
- **Theme picker** — choose Light, Dark, or System in Settings → Appearance. The preference is saved and restored on next launch.

### Fixed

- Pasting text from external sources (Google Docs, Sheets, web pages) no longer forces a black colour on the text, causing it to be invisible in dark mode. Near-black and near-white colour attributes are stripped on paste so text inherits the editor's theme colour.

## [1.5.1] — 2026-05-27

### Fixed

- Android: Google Sign-In now works correctly on Play Store installs. The Play Store signing certificate was missing from the Firebase OAuth configuration, causing sign-in to fail with error code 10 on devices that installed the app from the Play Store.

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
