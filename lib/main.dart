import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:sms_otp/app/constants/constants.dart';
import 'package:sms_otp/app/data/notification_service.dart';
import 'package:sms_otp/app/data/screen_wake_service.dart';
import 'package:sms_otp/app/modules/home/views/connection_check_view.dart';
import 'package:sms_otp/app/utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  await FCMConfig().requestPermission();
  await FCMConfig().initAwesomeNotification();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  runApp(const MyApp());
  // Eklenti, ekranı açık tutan pencere bayrağını uygulayabilmek için bağlı bir
  // Activity'ye ihtiyaç duyuyor; bu yüzden ilk kareden sonra başlatıyoruz.
  WidgetsBinding.instance.addPostFrameCallback((_) => ScreenWakeService.instance.start());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final storage = GetStorage();
  final translations = MyTranslations();

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
        translations: translations,
        defaultTransition: Transition.fade,
        home: const ConnectionCheckView());
  }
}
