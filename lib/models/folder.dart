import 'package:isar/isar.dart';

part 'folder.g.dart';

@collection
class Folder {
  Id id = Isar.autoIncrement;

  late String name;

  @Index()
  int? parentId;

  late DateTime createdAt;

  late DateTime updatedAt;

  Folder();

  Folder.create({required this.name, this.parentId})
      : createdAt = DateTime.now(),
        updatedAt = DateTime.now();
}
