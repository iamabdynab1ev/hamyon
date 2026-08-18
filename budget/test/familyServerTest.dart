// Проверяет клиент своего сервера семьи против запущенного сервера.
// Запуск:
//   SERVER_URL=http://127.0.0.1:8091 flutter test test/familyServerTest.dart
// Без переменной SERVER_URL тест пропускается, чтобы не падать там, где сервера нет.

import 'package:budget/struct/familyServer.dart';
import 'dart:io';

import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final String serverUrl =
      const String.fromEnvironment("SERVER_URL", defaultValue: "");

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Биндинг тестов подменяет HttpClient заглушкой, которая на всё отвечает 400.
    // Здесь нужен настоящий запрос к серверу, поэтому подмену снимаем.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    appStateSettings = {
      "familyServerUrl": "",
      "familyServerToken": "",
      "familyServerUserId": "",
      "familyServerFamilyId": "",
      "familyServerLogin": "",
      "familyServerName": "",
      "familyServerRole": "",
      "familyServerJoinCode": "",
    };
  });

  test("адрес сервера приводится к единому виду", () {
    expect(FamilyServer.normalizeServerUrl("example.com/"), "https://example.com");
    expect(FamilyServer.normalizeServerUrl("http://localhost:8080//"),
        "http://localhost:8080");
    expect(FamilyServer.normalizeServerUrl("  "), "");
  });

  test("семья, приглашение и обмен файлами", () async {
    final String stamp = DateTime.now().microsecondsSinceEpoch.toString();

    final FamilySession owner = await FamilyServer.registerFamily(
      serverUrl: serverUrl,
      familyName: "Оила $stamp",
      login: "owner-$stamp@example.com",
      name: "Папа",
      password: "parol12345",
    );
    expect(owner.role, FamilyServer.ownerRole);
    expect(owner.joinCode.isNotEmpty, true);
    expect(FamilyServer.isSignedIn, true);
    expect(FamilyServer.isOwner, true);

    // Устройство владельца выкладывает изменения и забирает их обратно.
    final List<int> payload = List<int>.generate(512, (i) => i % 256);
    await FamilyServer.uploadFile("sync-owner-$stamp.sqlite", payload);
    expect(await FamilyServer.downloadFile("sync-owner-$stamp.sqlite"), payload);

    final List<FamilySyncFile> files = await FamilyServer.listFiles();
    expect(files.any((f) => f.ownerName == "Папа"), true);

    // Участник входит по коду и попадает в ту же семью.
    final String joinCode = owner.joinCode;
    final FamilySession member = await FamilyServer.joinFamily(
      serverUrl: serverUrl,
      joinCode: joinCode,
      login: "member-$stamp@example.com",
      name: "Сын",
      password: "parol12345",
    );
    expect(member.role, "member");
    expect(member.familyId, owner.familyId);
    expect(FamilyServer.isOwner, false);

    // Участник видит файл владельца — значит синхронизация общая.
    expect(await FamilyServer.downloadFile("sync-owner-$stamp.sqlite"), payload);

    final List<FamilyMember> members = await FamilyServer.members();
    expect(members.length, 2);
    expect(members.where((m) => m.isOwner).single.name, "Папа");

    // Управлять участниками может только владелец.
    await expectLater(
      FamilyServer.setMemberActive(members.first.id, false),
      throwsA(isA<FamilyServerException>()),
    );

    await FamilyServer.signOut();
    expect(FamilyServer.isSignedIn, false);
  }, skip: serverUrl.isEmpty ? "SERVER_URL не задан" : false);
}
