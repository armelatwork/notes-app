import 'package:isar/isar.dart';

part 'note.g.dart';

@collection
class Note {
  Id id = Isar.autoIncrement;

  late String title;

  // Quill Delta JSON serialized as string
  late String content;

  // Plain text excerpt for the list preview
  late String preview;

  @Index()
  int? folderId;

  late DateTime updatedAt;

  late DateTime createdAt;

  // Drive file ID for sync tracking
  String? driveFileId;

  // Firestore document ID — set when this note is shared via Firestore
  String? firestoreId;

  // Emails of collaborators this note has been shared with (owner view)
  List<String> sharedWithEmails = [];

  // Email of the owner who shared this note with the current user
  String? sharedByEmail;

  bool get isSharedByMe => sharedWithEmails.isNotEmpty;
  bool get isSharedWithMe => firestoreId != null && !isSharedByMe;
  bool get isShared => isSharedByMe || isSharedWithMe;

  Note();

  Note.create({
    required this.title,
    required this.content,
    this.preview = '',
    this.folderId,
    this.driveFileId,
  })  : createdAt = DateTime.now(),
        updatedAt = DateTime.now();
}
