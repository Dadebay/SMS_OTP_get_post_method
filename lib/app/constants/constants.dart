import 'package:flutter/material.dart';
import 'package:get/get.dart';

const String serverURL = 'https://a7-tagam.com.tm/api/v1';

const Color kPrimaryColor = Color(0xff6366f1);
const Color kBlackColor = Color(0xff2b2b2b);

///BorderRadius
const BorderRadius borderRadius5 = BorderRadius.all(Radius.circular(5));
const BorderRadius borderRadius10 = BorderRadius.all(Radius.circular(10));
const BorderRadius borderRadius15 = BorderRadius.all(Radius.circular(15));
const BorderRadius borderRadius20 = BorderRadius.all(Radius.circular(20));
const BorderRadius borderRadius25 = BorderRadius.all(Radius.circular(25));
const BorderRadius borderRadius30 = BorderRadius.all(Radius.circular(30));
const BorderRadius borderRadius40 = BorderRadius.all(Radius.circular(40));
const BorderRadius borderRadius50 = BorderRadius.all(Radius.circular(50));
/////////////////////////////////
const String gilroyBold = 'GilroyBold';
const String gilroySemiBold = 'GilroySemiBold';
const String gilroyMedium = 'GilroyMedium';
const String gilroyRegular = 'GilroyRegular';
//Language icons
const String tmIcon = 'assets/image/tm.png';
const String ruIcon = 'assets/image/ru.png';
const String engIcon = 'assets/image/uk.png';
///////////////////
const String logo = 'assets/icons/logo.png';
const String noData = 'assets/lottie/noData.json';
const String appName = 'OTP CONNECTION WEBSOCKET';
const String loremImpsum =
    'Lorem ipsum, yaygın olarak kullanılan bir yer tutucu metne verilen isimdir. Dolgu veya sahte metin olarak da bilinen bu tip yer tutucu metinler, aslında anlamlı bir şey söylemeden bir alanı doldurmaya yarayan metinlerdir,Lorem ipsum, yaygın olarak kullanılan bir yer tutucu metne verilen isimdir. Dolgu veya sahte metin olarak da bilinen bu tip yer tutucu metinler, aslında anlamlı bir şey söylemeden bir alanı doldurmaya yarayan metinlerdir,Lorem ipsum, yaygın olarak kullanılan bir yer tutucu metne verilen isimdir. Dolgu veya sahte metin olarak da bilinen bu tip yer tutucu metinler, aslında anlamlı bir şey söylemeden bir alanı doldurmaya yarayan metinlerdir,Lorem ipsum, yaygın olarak kullanılan bir yer tutucu metne verilen isimdir. Dolgu veya sahte metin olarak da bilinen bu tip yer tutucu metinler, aslında anlamlı bir şey söylemeden bir alanı doldurmaya yarayan metinlerdir';
/////////////////////////////////////////////////
const String loadingLottie = 'assets/lottie/loading.json';
const String noDataLottie = 'assets/lottie/noData.json';
/////////////////////////////////////////////////

// Plain ScaffoldMessenger, not Get.snackbar: GetX 4.6.6's snackbar overlay
// resolution (Get.overlayContext!) crashes with a null-check error on recent
// Flutter versions, so every snackbar in the app goes through here instead.
void showSnackBar(
  BuildContext context,
  String title,
  String subtitle,
  Color color,
) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: borderRadius20),
        margin: const EdgeInsets.all(8),
        duration: const Duration(milliseconds: 1800),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(
                title.tr,
                style: const TextStyle(
                    fontFamily: gilroySemiBold,
                    fontSize: 16,
                    color: Colors.white),
              ),
            Text(
              subtitle.tr,
              style: const TextStyle(
                  fontFamily: gilroyRegular,
                  fontSize: 14,
                  color: Colors.white),
            ),
          ],
        ),
      ),
    );
}
