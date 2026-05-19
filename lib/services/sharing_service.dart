import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/note.dart';
import 'app_logger.dart';

// Firestore collection: shared_notes/{firestoreId}
// Fields: title, content, preview, ownerId, ownerEmail,
//         collaboratorEmails, collaboratorSharedBy,
//         updatedAt, updatedBy, updatedByEmail
//
// collaboratorSharedBy: {email -> sharedByEmail} — tracks which user
// added each collaborator, enabling the sharing chain UI.

class SharedNoteData {
  final String firestoreId;
  final String title;
  final String content;
  final String preview;
  final String ownerId;
  final String ownerEmail;
  final List<String> collaboratorEmails;
  final Map<String, String> collaboratorSharedBy;
  final DateTime updatedAt;
  final String updatedBy;
  final String updatedByEmail;

  const SharedNoteData({
    required this.firestoreId,
    required this.title,
    required this.content,
    required this.preview,
    required this.ownerId,
    required this.ownerEmail,
    required this.collaboratorEmails,
    required this.collaboratorSharedBy,
    required this.updatedAt,
    required this.updatedBy,
    required this.updatedByEmail,
  });

  factory SharedNoteData.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final sharedByRaw = d['collaboratorSharedBy'] as Map<String, dynamic>? ?? {};
    return SharedNoteData(
      firestoreId: doc.id,
      title: d['title'] as String? ?? '',
      content: d['content'] as String? ?? '[]',
      preview: d['preview'] as String? ?? '',
      ownerId: d['ownerId'] as String? ?? '',
      ownerEmail: d['ownerEmail'] as String? ?? '',
      collaboratorEmails: List<String>.from(
          d['collaboratorEmails'] as List? ?? []),
        // Skip entries whose value is not a String — these result from a prior
      // bug where dot-notation was used with dotted email keys, causing
      // Firestore to create nested maps instead of string values.
      collaboratorSharedBy: Map.fromEntries(
          sharedByRaw.entries
              .where((e) => e.value is String)
              .map((e) => MapEntry(e.key, e.value as String))),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedBy: d['updatedBy'] as String? ?? '',
      updatedByEmail: d['updatedByEmail'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'content': content,
        'preview': preview,
        'ownerId': ownerId,
        'ownerEmail': ownerEmail,
        'collaboratorEmails': collaboratorEmails,
        'collaboratorSharedBy': collaboratorSharedBy,
        'updatedAt': Timestamp.fromDate(updatedAt),
        'updatedBy': updatedBy,
        'updatedByEmail': updatedByEmail,
      };
}

class SharingService {
  static final SharingService instance = SharingService._();
  SharingService._();

  static const _collection = 'shared_notes';

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(_collection);

  // Publish a note to Firestore and add the first collaborator.
  // Returns the Firestore document ID.
  Future<String> shareNote({
    required Note note,
    required String ownerUid,
    required String ownerEmail,
    required String collaboratorEmail,
    String? contentOverride,
  }) async {
    final data = SharedNoteData(
      firestoreId: '',
      title: note.title,
      content: contentOverride ?? note.content,
      preview: note.preview,
      ownerId: ownerUid,
      ownerEmail: ownerEmail,
      collaboratorEmails: [collaboratorEmail],
      collaboratorSharedBy: {collaboratorEmail: ownerEmail},
      updatedAt: DateTime.now(),
      updatedBy: ownerUid,
      updatedByEmail: ownerEmail,
    );
    final ref = await _col.add(data.toMap());
    AppLogger.instance.info('SharingService', 'shared note ${note.id} → ${ref.id}');
    return ref.id;
  }

  // Add a collaborator to an existing shared note.
  // [sharedByEmail] is the email of the user who is doing the sharing.
  Future<void> addCollaborator(
      String firestoreId, String email, String sharedByEmail) async {
    // Use FieldPath for the nested map key so that dots in email addresses
    // are treated as literal characters, not Firestore path separators.
    await _col.doc(firestoreId).update({
      'collaboratorEmails': FieldValue.arrayUnion([email]),
      FieldPath(['collaboratorSharedBy', email]): sharedByEmail,
    });
  }

  // Remove a collaborator from a shared note.
  Future<void> removeCollaborator(String firestoreId, String email) async {
    await _col.doc(firestoreId).update({
      'collaboratorEmails': FieldValue.arrayRemove([email]),
      FieldPath(['collaboratorSharedBy', email]): FieldValue.delete(),
    });
  }

  // Push local note content to Firestore.
  Future<void> pushUpdate({
    required String firestoreId,
    required Note note,
    required String editorUid,
    required String editorEmail,
    String? contentOverride,
  }) async {
    await _col.doc(firestoreId).update({
      'title': note.title,
      'content': contentOverride ?? note.content,
      'preview': note.preview,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
      'updatedBy': editorUid,
      'updatedByEmail': editorEmail,
    });
  }

  // Real-time stream for a single shared note.
  Stream<SharedNoteData?> watchNote(String firestoreId) {
    return _col.doc(firestoreId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return SharedNoteData.fromDoc(snap);
    });
  }

  // Real-time stream of all notes shared with a given email.
  Stream<List<SharedNoteData>> watchSharedWithMe(String email) {
    return _col
        .where('collaboratorEmails', arrayContains: email)
        .snapshots()
        .map((snap) => snap.docs.map(SharedNoteData.fromDoc).toList());
  }

  // Query all notes shared with a given email.
  Future<List<SharedNoteData>> fetchSharedWithMe(String email) async {
    final snap = await _col
        .where('collaboratorEmails', arrayContains: email)
        .get();
    return snap.docs.map(SharedNoteData.fromDoc).toList();
  }

  // Query all notes shared by a given owner UID that have collaborators.
  Future<List<SharedNoteData>> fetchSharedByMe(String ownerUid) async {
    final snap = await _col
        .where('ownerId', isEqualTo: ownerUid)
        .where('collaboratorEmails', isNotEqualTo: [])
        .get();
    return snap.docs.map(SharedNoteData.fromDoc).toList();
  }

  // Fetch a single shared note document by its Firestore ID.
  Future<SharedNoteData?> fetchNote(String firestoreId) async {
    final doc = await _col.doc(firestoreId).get();
    if (!doc.exists) return null;
    return SharedNoteData.fromDoc(doc);
  }

  // Stop sharing a note entirely (owner only).
  Future<void> unshareNote(String firestoreId) async {
    await _col.doc(firestoreId).delete();
    AppLogger.instance.info('SharingService', 'unshared $firestoreId');
  }
}
