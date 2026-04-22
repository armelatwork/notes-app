import '../models/note.dart';

/// Returns the next available default title for a new note.
///
/// Treats notes with an empty title as 'New Note' for collision purposes.
/// Excludes [excludeId] (the note being edited) from the collision set.
String computeDefaultNoteTitle(List<Note> notes, {int? excludeId}) {
  final others = notes.where((n) => n.id != excludeId);
  final taken = others
      .map((n) => n.title.trim().isEmpty ? 'New Note' : n.title.trim())
      .toSet();
  if (!taken.contains('New Note')) return 'New Note';
  var i = 2;
  while (taken.contains('New Note $i')) { i++; }
  return 'New Note $i';
}

/// Returns true if [title] is an auto-generated default title
/// ('New Note', 'New Note 2', 'New Note 3', …).
bool isDefaultNoteTitle(String title) =>
    title == 'New Note' || RegExp(r'^New Note \d+$').hasMatch(title);
