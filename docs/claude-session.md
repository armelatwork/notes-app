# Claude Session Notes

## 2026-04-22

### Bugs fixed this session

**Bug 1 – Sidebar shows "New Note" for all untitled notes**
- Root cause: `createNote` saved `title: ''`; sidebar rendered all empty-titled notes as "New Note".
- Fix: `createNote` now calls `computeDefaultNoteTitle(state.valueOrNull ?? [])` and stores the unique title (e.g. "New Note 2") in the DB immediately, so the sidebar reflects the correct name without requiring the note to be opened.
- `_loadNote` treats any stored default title (`isDefaultNoteTitle`) as a hint: clears the title field and shows the stored title as grey hint text, preserving the "click to clear" UX.

**Bug 2 – New note lands at second position in the list**
- Root cause: `_loadNote` called `_saveCurrentNote` for the previously-open note when switching, updating its `updatedAt` timestamp and pushing it above the freshly-created note.
- Fix: Added `_isDirty` flag to `_NoteEditorState`. `_saveCurrentNote` bails out early when `_isDirty == false` (no user edits since last load), so an unchanged note's timestamp is not touched when switching away from it.

### New files
- `lib/utils/note_utils.dart` – `computeDefaultNoteTitle`, `isDefaultNoteTitle`
- `test/utils/note_utils_test.dart` – 13 unit tests
- `test/providers/notes_notifier_test.dart` – 5 unit tests for `NotesNotifier.createNote`
- `docs/claude-session.md` – this file

### Key invariants
- Notes with a default title ("New Note", "New Note 2", …) show the title as hint text in the editor; real titles show as editable text.
- `_saveCurrentNote` only writes to the DB when `_isDirty == true`.
- `_isDirty` is reset to `false` on every `_loadNote` and set to `true` by `_scheduleSave` (which fires on any editor or title change).
