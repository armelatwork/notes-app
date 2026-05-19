import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import '../services/database_service.dart';
import '../services/sharing_service.dart';
import 'app_provider.dart';

// Which sharing section is active in the sidebar:
// null  = no shared section selected
// true  = "Shared with me"
// false = "Shared by me"
final sharedSectionProvider = StateProvider<bool?>((ref) => null);

// Real-time stream of notes shared with the current user.
final sharedWithMeProvider =
    StreamProvider.autoDispose<List<SharedNoteData>>((ref) {
  final user = ref.watch(appUserProvider);
  if (user?.email == null) return Stream.value([]);
  return SharingService.instance.watchSharedWithMe(user!.email!);
});

// Notes the current user has shared with others.
final sharedByMeProvider =
    FutureProvider.autoDispose<List<SharedNoteData>>((ref) async {
  final user = ref.watch(appUserProvider);
  if (user?.id == null) return [];
  return SharingService.instance.fetchSharedByMe(user!.id);
});

// Active real-time stream for the currently open shared note.
// Emits whenever a collaborator saves a change in Firestore.
final sharedNoteStreamProvider =
    StreamProvider.autoDispose.family<SharedNoteData?, String>(
  (ref, firestoreId) => SharingService.instance.watchNote(firestoreId),
);

// Convenience: the firestoreId of the currently selected note (if shared).
final activeFirestoreIdProvider = Provider.autoDispose<String?>((ref) {
  final note = ref.watch(selectedNoteProvider);
  return note?.firestoreId;
});

// Isar-backed list of notes the current user has shared (isSharedByMe == true).
// Watches notesProvider so it re-runs automatically when a note is saved
// (e.g. after removing a collaborator via the Share dialog).
final localSharedByMeProvider = FutureProvider.autoDispose<List<Note>>((ref) {
  ref.watch(notesProvider); // re-run whenever notes change
  return DatabaseService.instance.getSharedByMeNotes();
});
