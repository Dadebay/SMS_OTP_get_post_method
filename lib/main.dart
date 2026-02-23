import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:sms_otp/app/constants/constants.dart';
import 'package:sms_otp/app/data/app_settings_service.dart';
import 'package:sms_otp/app/data/notification_service.dart';
import 'package:sms_otp/app/modules/home/views/connection_check_view.dart';
import 'package:sms_otp/app/utils.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  await Get.putAsync<AppSettingsService>(() async => AppSettingsService().init(), permanent: true);
  WakelockPlus.enable();
  await FCMConfig().requestPermission();
  await FCMConfig().initAwesomeNotification();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final storage = GetStorage();

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
        debugShowCheckedModeBanner: false,
        title: "SMS sending app",
        theme: ThemeData(
          brightness: Brightness.light,
          fontFamily: gilroyRegular,
          colorSchemeSeed: kPrimaryColor,
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.black, systemNavigationBarIconBrightness: Brightness.light, statusBarBrightness: Brightness.light, statusBarIconBrightness: Brightness.light),
            titleTextStyle: TextStyle(color: Colors.black, fontFamily: gilroySemiBold, fontSize: 20),
            elevation: 0,
          ),
          bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.transparent),
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        fallbackLocale: const Locale('tm'),
        locale: storage.read('langCode') != null ? Locale(storage.read('langCode')) : const Locale('tm'),
        translations: MyTranslations(),
        defaultTransition: Transition.fade,
        home: const ConnectionCheckView());
  }
}
