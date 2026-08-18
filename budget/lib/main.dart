import 'package:hamyon/functions.dart';
import 'package:hamyon/pages/accountsPage.dart';
import 'package:hamyon/pages/autoTransactionsPageEmail.dart';
import 'package:hamyon/struct/currencyFunctions.dart';
import 'package:hamyon/struct/iconObjects.dart';
import 'package:hamyon/struct/keyboardIntents.dart';
import 'package:hamyon/struct/logging.dart';
import 'package:hamyon/widgets/fadeIn.dart';
import 'package:hamyon/struct/languageMap.dart';
import 'package:hamyon/struct/tajikLocaleData.dart';
import 'package:hamyon/struct/initializeBiometrics.dart';
import 'package:hamyon/widgets/util/appLinks.dart';
import 'package:hamyon/widgets/util/onAppResume.dart';
import 'package:hamyon/widgets/util/watchForDayChange.dart';
import 'package:hamyon/widgets/watchAllWallets.dart';
import 'package:hamyon/database/tables.dart';
import 'package:hamyon/struct/databaseGlobal.dart';
import 'package:hamyon/struct/settings.dart';
import 'package:hamyon/struct/notificationsGlobal.dart';
import 'package:hamyon/widgets/navigationSidebar.dart';
import 'package:hamyon/widgets/globalLoadingProgress.dart';
import 'package:hamyon/struct/scrollBehaviorOverride.dart';
import 'package:hamyon/widgets/globalSnackbar.dart';
import 'package:hamyon/struct/initializeNotifications.dart';
import 'package:hamyon/widgets/navigationFramework.dart';
import 'package:hamyon/widgets/restartApp.dart';
import 'package:hamyon/struct/customDelayedCurve.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hamyon/colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:device_preview/device_preview.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'firebase_options.dart';
import 'package:easy_localization/easy_localization.dart';

// Requires hot restart when changed
bool enableDevicePreview = false && kDebugMode;
bool allowDebugFlags = true || kIsWeb;
bool allowDangerousDebugFlags = kDebugMode;

void main() async {
  captureLogs(() async {
    WidgetsFlutterBinding.ensureInitialized();
    registerTajikLocaleData();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await EasyLocalization.ensureInitialized();
    sharedPreferences = await SharedPreferences.getInstance();
    database = await constructDb('db');
    notificationPayload = await initializeNotifications();
    entireAppLoaded = false;
    await loadCurrencyJSON();
    await loadLanguageNamesJSON();
    await initializeSettings();
    tz.initializeTimeZones();
    final String? locationName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(locationName ?? "America/New_York"));
    iconObjects.sort((a, b) => (a.mostLikelyCategoryName ?? a.icon)
        .compareTo((b.mostLikelyCategoryName ?? b.icon)));
    setHighRefreshRate();
    runApp(
      DevicePreview(
        enabled: enableDevicePreview,
        builder: (context) => InitializeLocalizations(
          child: RestartApp(
            child: InitializeApp(key: appStateKey),
          ),
        ),
      ),
    );
  });
}

GlobalKey<_InitializeAppState> appStateKey = GlobalKey();
GlobalKey<PageNavigationFrameworkState> pageNavigationFrameworkKey =
    GlobalKey();

class InitializeApp extends StatefulWidget {
  InitializeApp({Key? key}) : super(key: key);

  @override
  State<InitializeApp> createState() => _InitializeAppState();
}

class _InitializeAppState extends State<InitializeApp> {
  void refreshAppState() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return App(key: ValueKey("Main App"));
  }
}

class App extends StatelessWidget {
  const App({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    print("Rebuilt Material App");
    return MaterialApp(
      showPerformanceOverlay: kProfileMode,
      localizationsDelegates: localizationDelegatesWithFallback(context),
      supportedLocales: context.supportedLocales,
      locale:
          enableDevicePreview ? DevicePreview.locale(context) : context.locale,
      shortcuts: shortcuts,
      actions: keyboardIntents,
      themeAnimationDuration: Duration(milliseconds: 400),
      themeAnimationCurve: CustomDelayedCurve(),
      key: ValueKey('HamyonAppMain'),
      title: 'Hamyon',
      theme: getLightTheme(),
      darkTheme: getDarkTheme(),
      scrollBehavior: ScrollBehaviorOverride(),
      themeMode: getSettingConstants(appStateSettings)["theme"],
      home: HandleWillPopScope(
        child: Stack(
          children: [
            Row(
              children: [
                NavigationSidebar(key: sidebarStateKey),
                Expanded(
                    child: Stack(
                  children: [
                    InitialPageRouteNavigator(),
                    GlobalSnackbar(key: snackbarKey),
                  ],
                )),
              ],
            ),
            EnableSignInWithGoogleFlyIn(),
            GlobalLoadingIndeterminate(key: loadingIndeterminateKey),
            GlobalLoadingProgress(key: loadingProgressKey),
          ],
        ),
      ),
      builder: (context, child) {
        if (kReleaseMode) {
          ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
            return Container(color: Colors.transparent);
          };
        }

        Widget mainWidget = OnAppResume(
          updateGlobalAppLifecycleState: true,
          onAppResume: () async {
            await setHighRefreshRate();
          },
          child: InitializeBiometrics(
            child: InitializeNotificationService(
              child: InitializeAppLinks(
                child: WatchForDayChange(
                  child: WatchSelectedWalletPk(
                    child: WatchAllWallets(
                      child: child ?? SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        if (kIsWeb) {
          return FadeIn(
              duration: Duration(milliseconds: 1000), child: mainWidget);
        } else {
          return mainWidget;
        }
      },
      // ),
    );
  }
}
