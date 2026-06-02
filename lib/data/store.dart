import 'dart:io';
import 'models.dart';

abstract class WorkspaceStore {
  Workspace? load();
  void save(Workspace workspace);
  String get location;
}

class FileWorkspaceStore implements WorkspaceStore {
  FileWorkspaceStore(this.directory);
  final Directory directory;
  File get file => File('${directory.path}/workspace.json');
  File get backup => File('${directory.path}/workspace.backup.json');
  @override
  String get location => directory.path;
  @override
  Workspace? load() =>
      file.existsSync() ? Workspace.decode(file.readAsStringSync()) : null;

  @override
  void save(Workspace workspace) {
    directory.createSync(recursive: true);
    final source = workspace.encode();
    // Validate before replacing anything, including during a backup restore.
    Workspace.decode(source);
    final staging = File('${file.path}.tmp');
    staging.writeAsStringSync(source, flush: true);
    if (file.existsSync()) {
      final previous = file.readAsStringSync();
      try {
        Workspace.decode(previous);
        final backupStaging = File('${backup.path}.tmp');
        backupStaging.writeAsStringSync(previous, flush: true);
        backupStaging.renameSync(backup.path);
      } on FormatException {
        // Preserve damaged bytes and the last known valid backup for recovery.
        file.copySync(
          '${file.path}.damaged-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
    }
    staging.renameSync(file.path);
  }

  Workspace restorePrevious() {
    final restored = Workspace.decode(backup.readAsStringSync());
    save(restored);
    return restored;
  }
}

class MemoryWorkspaceStore implements WorkspaceStore {
  String? contents;
  @override
  String get location => 'Temporary test workspace';
  @override
  Workspace? load() => contents == null ? null : Workspace.decode(contents!);
  @override
  void save(Workspace workspace) {
    contents = workspace.encode();
  }
}
