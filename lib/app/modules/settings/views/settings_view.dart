import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconly/iconly.dart';
import 'package:sms_otp/app/constants/constants.dart';
import 'package:sms_otp/app/modules/home/controllers/home_controller.dart';
import 'package:sms_otp/app/modules/settings/views/agree_button_view.dart';
import 'package:sms_otp/app/modules/settings/views/custom_text_field.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  TextEditingController textEditingController = TextEditingController();

  TextEditingController urlEditingController = TextEditingController();

  TextEditingController heartBeatEditingController = TextEditingController();

  final HomeController homeController = Get.put(HomeController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
              onPressed: () {
                Get.back();
              },
              icon: const Icon(
                IconlyLight.arrow_left_circle,
                color: Colors.white,
              )),
          title: const Text(
            'Settings',
            style: TextStyle(color: Colors.white, fontFamily: gilroySemiBold, fontSize: 20),
          ),
          elevation: 1,
        ),
        body: ListView(
          children: [
            Obx(() {
              return Column(
                children: [
                  CustomTextField(
                    labelName: 'SMS channel',
                    controller: textEditingController,
                  ),
                  CustomTextField(
                    labelName: 'Websocket URL',
                    controller: urlEditingController,
                  ),
                  CustomTextField(
                    labelName: 'HeartBeat URL',
                    controller: heartBeatEditingController,
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  AgreeButton(
                      onTap: () {
                        Get.back();
                      },
                      text: "Agree")
                ],
              );
            }),
            const Text(
              'Created by: G.Dadebay',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontFamily: gilroySemiBold, fontSize: 20),
            )
          ],
        ));
  }
}
