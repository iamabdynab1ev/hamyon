import 'package:budget/struct/familyServer.dart';
import 'package:budget/widgets/accountAndBackup.dart';
import 'package:googleapis/drive/v3.dart' as drive;

// Файлы синхронизации могут лежать в двух местах: в Google Drive пользователя
// или на своём сервере семьи. Обмен устроен одинаково — выложить свой файл
// изменений и забрать чужие, — поэтому остальной код работает через эти функции
// и не знает, какое хранилище используется.
//
// Свой сервер имеет приоритет: если на него выполнен вход, значит семья
// сознательно перешла на него, и лезть в Drive уже не нужно.

bool get isUsingFamilyServer => FamilyServer.isSignedIn;

class RemoteBackupFile {
  RemoteBackupFile({
    required this.name,
    required this.id,
    required this.modifiedTime,
    this.ownerName = "",
  });

  final String name;

  // В Drive файл адресуется идентификатором, на своём сервере — именем.
  // Для остального кода это просто непрозрачная ссылка на файл.
  final String id;

  final DateTime modifiedTime;
  final String ownerName;
}

Future<List<RemoteBackupFile>> listRemoteBackupFiles() async {
  if (isUsingFamilyServer) {
    final List<FamilySyncFile> files = await FamilyServer.listFiles();
    return [
      for (FamilySyncFile file in files)
        RemoteBackupFile(
          name: file.name,
          id: file.name,
          modifiedTime: file.updatedAt,
          ownerName: file.ownerName,
        )
    ];
  }

  final (drive.DriveApi? driveApi, List<drive.File>? files) =
      await getDriveFiles();
  if (driveApi == null || files == null) return [];
  return [
    for (drive.File file in files)
      if (file.name != null && file.id != null)
        RemoteBackupFile(
          name: file.name!,
          id: file.id!,
          modifiedTime: file.modifiedTime?.toLocal() ?? DateTime(0),
        )
  ];
}

Future<List<int>> downloadRemoteBackupFile(RemoteBackupFile file) async {
  if (isUsingFamilyServer) {
    return await FamilyServer.downloadFile(file.name);
  }

  final (drive.DriveApi? driveApi, _) = await getDriveFiles();
  if (driveApi == null) throw "Failed to login to Google Drive";

  final drive.Media response = await driveApi.files
          .get(file.id, downloadOptions: drive.DownloadOptions.fullMedia)
      as drive.Media;

  final List<int> bytes = [];
  await for (final List<int> chunk in response.stream) {
    bytes.addAll(chunk);
  }
  return bytes;
}

Future<void> uploadRemoteBackupFile(String name, List<int> bytes) async {
  if (isUsingFamilyServer) {
    await FamilyServer.uploadFile(name, bytes);
    return;
  }
  throw "uploadRemoteBackupFile is only used by the family server transport";
}

Future<void> deleteRemoteBackupFile(RemoteBackupFile file) async {
  if (isUsingFamilyServer) {
    await FamilyServer.deleteFile(file.name);
    return;
  }

  final (drive.DriveApi? driveApi, _) = await getDriveFiles();
  if (driveApi == null) return;
  await deleteBackup(driveApi, file.id);
}
