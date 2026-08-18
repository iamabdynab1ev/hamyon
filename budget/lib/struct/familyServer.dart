import 'dart:convert';

import 'package:budget/struct/settings.dart';
import 'package:http/http.dart' as http;

// Клиент своего сервера семьи. Заменяет Google Drive как место, где устройства
// обмениваются файлами синхронизации, и заодно знает, кто вошёл и с какой ролью.
// Адрес сервера задаётся в настройках, поэтому одно и то же приложение работает
// и с локальным сервером при разработке, и с рабочим.

class FamilyServerException implements Exception {
  FamilyServerException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

class FamilySession {
  FamilySession({
    required this.token,
    required this.userId,
    required this.familyId,
    required this.login,
    required this.name,
    required this.role,
    this.joinCode = "",
  });

  final String token;
  final String userId;
  final String familyId;
  final String login;
  final String name;
  final String role;
  final String joinCode;

  factory FamilySession.fromResponse(Map<String, dynamic> body) {
    final Map<String, dynamic> user = body["user"] ?? {};
    return FamilySession(
      token: body["token"]?.toString() ?? "",
      userId: user["id"]?.toString() ?? "",
      familyId: user["familyId"]?.toString() ?? "",
      login: user["login"]?.toString() ?? "",
      name: user["name"]?.toString() ?? "",
      role: user["role"]?.toString() ?? "member",
      joinCode: body["joinCode"]?.toString() ?? "",
    );
  }
}

class FamilyMember {
  FamilyMember({
    required this.id,
    required this.login,
    required this.name,
    required this.role,
    required this.isActive,
  });

  final String id;
  final String login;
  final String name;
  final String role;
  final bool isActive;

  bool get isOwner => role == FamilyServer.ownerRole;

  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
        id: json["id"]?.toString() ?? "",
        login: json["login"]?.toString() ?? "",
        name: json["name"]?.toString() ?? "",
        role: json["role"]?.toString() ?? "member",
        isActive: json["isActive"] == true,
      );
}

class FamilySyncFile {
  FamilySyncFile({
    required this.name,
    required this.kind,
    required this.sizeBytes,
    required this.ownerId,
    required this.ownerName,
    required this.updatedAt,
  });

  final String name;
  final String kind;
  final int sizeBytes;
  final String ownerId;
  final String ownerName;
  final DateTime updatedAt;

  factory FamilySyncFile.fromJson(Map<String, dynamic> json) => FamilySyncFile(
        name: json["name"]?.toString() ?? "",
        kind: json["kind"]?.toString() ?? "sync",
        sizeBytes: (json["sizeBytes"] as num?)?.toInt() ?? 0,
        ownerId: json["ownerId"]?.toString() ?? "",
        ownerName: json["ownerName"]?.toString() ?? "",
        updatedAt:
            DateTime.tryParse(json["updatedAt"]?.toString() ?? "")?.toLocal() ??
                DateTime.now(),
      );
}

class FamilyServer {
  static const String ownerRole = "owner";
  static const Duration _timeout = Duration(seconds: 30);

  static String get baseUrl =>
      (appStateSettings["familyServerUrl"] ?? "").toString().trim();

  static String get token =>
      (appStateSettings["familyServerToken"] ?? "").toString();

  static String get currentUserName =>
      (appStateSettings["familyServerName"] ?? "").toString();

  static String get currentUserLogin =>
      (appStateSettings["familyServerLogin"] ?? "").toString();

  static String get currentUserRole =>
      (appStateSettings["familyServerRole"] ?? "").toString();

  static bool get isSignedIn => baseUrl.isNotEmpty && token.isNotEmpty;

  static bool get isOwner => currentUserRole == ownerRole;

  static Future<FamilySession> registerFamily({
    required String serverUrl,
    required String familyName,
    required String login,
    required String name,
    required String password,
  }) async {
    return _authenticate(serverUrl, "auth/register-family", {
      "familyName": familyName,
      "login": login,
      "name": name,
      "password": password,
    });
  }

  static Future<FamilySession> joinFamily({
    required String serverUrl,
    required String joinCode,
    required String login,
    required String name,
    required String password,
  }) async {
    return _authenticate(serverUrl, "auth/join-family", {
      "joinCode": joinCode,
      "login": login,
      "name": name,
      "password": password,
    });
  }

  static Future<FamilySession> login({
    required String serverUrl,
    required String login,
    required String password,
  }) async {
    return _authenticate(serverUrl, "auth/login", {
      "login": login,
      "password": password,
    });
  }

  static Future<void> signOut() async {
    await _storeSession(null, "");
  }

  static Future<List<FamilyMember>> members() async {
    final dynamic body = await _request("GET", "family/members");
    final List<dynamic> raw = body?["members"] ?? [];
    return raw
        .map((entry) => FamilyMember.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  static Future<void> setMemberActive(String userId, bool isActive) async {
    await _request("POST", "family/members/$userId/active",
        body: {"isActive": isActive});
  }

  static Future<List<FamilySyncFile>> listFiles({String kind = ""}) async {
    final String query = kind.isEmpty ? "" : "?kind=$kind";
    final dynamic body = await _request("GET", "sync/files$query");
    final List<dynamic> raw = body?["files"] ?? [];
    return raw
        .map((entry) => FamilySyncFile.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  static Future<void> uploadFile(String name, List<int> bytes) async {
    await _request("PUT", "sync/files/${Uri.encodeComponent(name)}",
        rawBody: bytes);
  }

  static Future<List<int>> downloadFile(String name) async {
    final http.Response response = await _send(
        "GET", "sync/files/${Uri.encodeComponent(name)}",
        expectJson: false);
    return response.bodyBytes;
  }

  static Future<void> deleteFile(String name) async {
    await _request("DELETE", "sync/files/${Uri.encodeComponent(name)}");
  }

  static Future<FamilySession> _authenticate(
      String serverUrl, String path, Map<String, dynamic> payload) async {
    final String normalized = normalizeServerUrl(serverUrl);
    final http.Response response = await _send("POST", path,
        body: payload, overrideBaseUrl: normalized, withAuth: false);

    final FamilySession session =
        FamilySession.fromResponse(json.decode(utf8.decode(response.bodyBytes)));
    await _storeSession(session, normalized);
    return session;
  }

  static Future<dynamic> _request(String method, String path,
      {Map<String, dynamic>? body, List<int>? rawBody}) async {
    final http.Response response =
        await _send(method, path, body: body, rawBody: rawBody);
    if (response.bodyBytes.isEmpty) return null;
    return json.decode(utf8.decode(response.bodyBytes));
  }

  static Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    List<int>? rawBody,
    String? overrideBaseUrl,
    bool withAuth = true,
    bool expectJson = true,
  }) async {
    final String base = overrideBaseUrl ?? baseUrl;
    if (base.isEmpty) {
      throw FamilyServerException("Адрес сервера не указан");
    }

    final Uri url = Uri.parse("$base/api/v1/$path");
    final Map<String, String> headers = {};
    if (withAuth) {
      if (token.isEmpty) {
        throw FamilyServerException("Вход не выполнен", statusCode: 401);
      }
      headers["Authorization"] = "Bearer $token";
    }
    if (body != null) headers["Content-Type"] = "application/json";
    if (rawBody != null) headers["Content-Type"] = "application/octet-stream";

    final http.Request request = http.Request(method, url);
    request.headers.addAll(headers);
    if (body != null) request.bodyBytes = utf8.encode(json.encode(body));
    if (rawBody != null) request.bodyBytes = rawBody;

    http.Response response;
    try {
      response =
          await http.Response.fromStream(await request.send()).timeout(_timeout);
    } catch (e) {
      throw FamilyServerException("Сервер недоступен: $e");
    }

    if (response.statusCode >= 400) {
      throw FamilyServerException(_errorMessage(response),
          statusCode: response.statusCode);
    }
    return response;
  }

  static String _errorMessage(http.Response response) {
    try {
      final dynamic decoded = json.decode(utf8.decode(response.bodyBytes));
      final String message = decoded?["error"]?.toString() ?? "";
      if (message.isNotEmpty) return message;
    } catch (_) {}
    return "Ошибка сервера (${response.statusCode})";
  }

  static Future<void> _storeSession(
      FamilySession? session, String serverUrl) async {
    // Пишем напрямую и сохраняем один раз: обновление глобального состояния на
    // каждом ключе перерисовывало бы приложение по пять раз подряд.
    appStateSettings["familyServerUrl"] = serverUrl;
    appStateSettings["familyServerToken"] = session?.token ?? "";
    appStateSettings["familyServerUserId"] = session?.userId ?? "";
    appStateSettings["familyServerLogin"] = session?.login ?? "";
    appStateSettings["familyServerName"] = session?.name ?? "";
    appStateSettings["familyServerRole"] = session?.role ?? "";
    appStateSettings["familyServerJoinCode"] = session?.joinCode ?? "";
    await updateSettings("familyServerFamilyId", session?.familyId ?? "",
        updateGlobalState: true);
  }

  // Приводим то, что ввёл пользователь, к виду https://host:port без хвостового
  // слэша: иначе "example.com/" превратится в путь с двойным слэшем.
  static String normalizeServerUrl(String raw) {
    String value = raw.trim();
    if (value.isEmpty) return "";
    if (!value.startsWith("http://") && !value.startsWith("https://")) {
      value = "https://$value";
    }
    while (value.endsWith("/")) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
