import 'package:budget/colors.dart';
import 'package:budget/struct/familyServer.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

enum FamilyServerFormMode { signIn, createFamily, joinFamily }

class FamilyServerPage extends StatefulWidget {
  const FamilyServerPage({super.key});

  @override
  State<FamilyServerPage> createState() => _FamilyServerPageState();
}

class _FamilyServerPageState extends State<FamilyServerPage> {
  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "family-server".tr(),
      listWidgets: [
        if (FamilyServer.isSignedIn)
          FamilyServerAccount(onChanged: () => setState(() {}))
        else
          FamilyServerSignInForm(onSignedIn: () => setState(() {})),
      ],
    );
  }
}

class FamilyServerSignInForm extends StatefulWidget {
  const FamilyServerSignInForm({required this.onSignedIn, super.key});

  final VoidCallback onSignedIn;

  @override
  State<FamilyServerSignInForm> createState() => _FamilyServerSignInFormState();
}

class _FamilyServerSignInFormState extends State<FamilyServerSignInForm> {
  FamilyServerFormMode mode = FamilyServerFormMode.signIn;
  bool isBusy = false;

  String serverUrl = "";
  String login = "";
  String password = "";
  String name = "";
  String familyName = "";
  String joinCode = "";

  @override
  void initState() {
    super.initState();
    serverUrl = FamilyServer.baseUrl;
  }

  Future<void> submit() async {
    setState(() => isBusy = true);
    try {
      switch (mode) {
        case FamilyServerFormMode.signIn:
          await FamilyServer.login(
              serverUrl: serverUrl, login: login, password: password);
          break;
        case FamilyServerFormMode.createFamily:
          await FamilyServer.registerFamily(
              serverUrl: serverUrl,
              familyName: familyName,
              login: login,
              name: name,
              password: password);
          break;
        case FamilyServerFormMode.joinFamily:
          await FamilyServer.joinFamily(
              serverUrl: serverUrl,
              joinCode: joinCode,
              login: login,
              name: name,
              password: password);
          break;
      }
      widget.onSignedIn();
    } on FamilyServerException catch (e) {
      openSnackbar(SnackbarMessage(
        title: "sign-in-error".tr(),
        description: e.message,
        icon: Icons.error_outline_rounded,
      ));
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool needsProfile = mode != FamilyServerFormMode.signIn;

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          TextFont(
            text: "family-server-description".tr(),
            fontSize: 14,
            maxLines: 5,
            textColor: getColor(context, "textLight"),
          ),
          const SizedBox(height: 15),
          SegmentedButton<FamilyServerFormMode>(
            segments: [
              ButtonSegment(
                value: FamilyServerFormMode.signIn,
                label: Text("login".tr()),
              ),
              ButtonSegment(
                value: FamilyServerFormMode.createFamily,
                label: Text("create-family".tr()),
              ),
              ButtonSegment(
                value: FamilyServerFormMode.joinFamily,
                label: Text("join-family".tr()),
              ),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => mode = selection.first),
          ),
          const SizedBox(height: 15),
          TextInput(
            labelText: "server-address".tr(),
            initialValue: serverUrl,
            onChanged: (value) => serverUrl = value,
            icon: Icons.dns_outlined,
          ),
          const SizedBox(height: 10),
          if (mode == FamilyServerFormMode.createFamily) ...[
            TextInput(
              labelText: "family-name".tr(),
              onChanged: (value) => familyName = value,
              icon: Icons.groups_outlined,
            ),
            const SizedBox(height: 10),
          ],
          if (mode == FamilyServerFormMode.joinFamily) ...[
            TextInput(
              labelText: "invite-code".tr(),
              onChanged: (value) => joinCode = value,
              icon: Icons.key_outlined,
            ),
            const SizedBox(height: 10),
          ],
          if (needsProfile) ...[
            TextInput(
              labelText: "your-name".tr(),
              onChanged: (value) => name = value,
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 10),
          ],
          TextInput(
            labelText: "login-placeholder".tr(),
            onChanged: (value) => login = value,
            icon: Icons.alternate_email_rounded,
          ),
          const SizedBox(height: 10),
          TextInput(
            labelText: "password".tr(),
            onChanged: (value) => password = value,
            obscureText: true,
            icon: Icons.lock_outline_rounded,
          ),
          const SizedBox(height: 20),
          Button(
            label: isBusy ? "loading".tr() : submitLabel(),
            onTap: isBusy ? () {} : submit,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  String submitLabel() {
    switch (mode) {
      case FamilyServerFormMode.signIn:
        return "login".tr();
      case FamilyServerFormMode.createFamily:
        return "create-family".tr();
      case FamilyServerFormMode.joinFamily:
        return "join-family".tr();
    }
  }
}

class FamilyServerAccount extends StatefulWidget {
  const FamilyServerAccount({required this.onChanged, super.key});

  final VoidCallback onChanged;

  @override
  State<FamilyServerAccount> createState() => _FamilyServerAccountState();
}

class _FamilyServerAccountState extends State<FamilyServerAccount> {
  List<FamilyMember>? members;
  String? loadError;

  @override
  void initState() {
    super.initState();
    loadMembers();
  }

  Future<void> loadMembers() async {
    try {
      final List<FamilyMember> loaded = await FamilyServer.members();
      if (mounted) setState(() => members = loaded);
    } on FamilyServerException catch (e) {
      if (mounted) setState(() => loadError = e.message);
    }
  }

  Future<void> toggleMember(FamilyMember member) async {
    try {
      await FamilyServer.setMemberActive(member.id, !member.isActive);
      await loadMembers();
    } on FamilyServerException catch (e) {
      openSnackbar(SnackbarMessage(
        title: "an-error-occured".tr(),
        description: e.message,
        icon: Icons.error_outline_rounded,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final String joinCode =
        (appStateSettings["familyServerJoinCode"] ?? "").toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsContainer(
          title: FamilyServer.currentUserName,
          description: FamilyServer.currentUserLogin +
              " · " +
              (FamilyServer.isOwner ? "role-owner".tr() : "role-member".tr()),
          icon: Icons.person_rounded,
        ),
        SettingsContainer(
          title: "server-address".tr(),
          description: FamilyServer.baseUrl,
          icon: Icons.dns_outlined,
        ),
        // Код приглашения выдаёт сервер только владельцу, поэтому у остальных
        // этой строки просто нет.
        if (FamilyServer.isOwner && joinCode.isNotEmpty)
          SettingsContainer(
            title: "invite-code".tr(),
            description: joinCode,
            icon: Icons.key_outlined,
            onTap: () {
              Clipboard.setData(ClipboardData(text: joinCode));
              openSnackbar(SnackbarMessage(
                title: "copied-to-clipboard".tr(),
                icon: Icons.copy_rounded,
              ));
            },
          ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 13),
          child: TextFont(text: "members".tr(), fontSize: 16, fontWeight: FontWeight.bold),
        ),
        if (loadError != null)
          Padding(
            padding: const EdgeInsetsDirectional.all(13),
            child: TextFont(
                text: loadError!, fontSize: 14, maxLines: 3,
                textColor: getColor(context, "textLight")),
          ),
        for (FamilyMember member in members ?? [])
          SettingsContainer(
            title: member.name,
            description: member.login +
                " · " +
                (member.isOwner ? "role-owner".tr() : "role-member".tr()) +
                (member.isActive ? "" : " · " + "disabled".tr()),
            icon: member.isOwner
                ? Icons.star_rounded
                : Icons.person_outline_rounded,
            onTap: FamilyServer.isOwner && !member.isOwner
                ? () => toggleMember(member)
                : null,
          ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 13),
          child: Button(
            label: "logout".tr(),
            onTap: () async {
              await FamilyServer.signOut();
              widget.onChanged();
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
