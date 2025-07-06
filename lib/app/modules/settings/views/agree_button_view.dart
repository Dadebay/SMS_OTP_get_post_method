// ignore_for_file: file_names, must_be_immutable

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sms_otp/app/constants/constants.dart';

class AgreeButton extends StatelessWidget {
  final Function() onTap;
  final String text;

  const AgreeButton({super.key, required this.onTap, required this.text});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap, child: animatedContaner());
  }

  Widget animatedContaner() {
    return Container(
      decoration: const BoxDecoration(borderRadius: borderRadius20, color: kPrimaryColor),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
      width: Get.size.width,
      child: Text(
        text.tr,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontFamily: gilroyBold, fontSize: 22),
      ),
    );
  }
}
