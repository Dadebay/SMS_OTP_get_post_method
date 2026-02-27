import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconly/iconly.dart';
import 'package:sms_otp/app/constants/constants.dart';
import 'package:sms_otp/app/modules/settings/controllers/settings_controller.dart';
import 'package:sms_otp/app/modules/settings/views/agree_button_view.dart';
import 'package:sms_otp/app/modules/settings/views/custom_text_field.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final SettingsController settingsController;

  @override
  void initState() {
    super.initState();
    settingsController = Get.isRegistered<SettingsController>() ? Get.find<SettingsController>() : Get.put(SettingsController());
  }

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
        body: Form(
          key: settingsController.formKey,
          child: ListView(
            children: [
              CustomTextField(
                labelName: 'GET SMS URL',
                controller: settingsController.getSmsUrlController,
                maxLines: 4,
                keyboardType: TextInputType.url,
                validator: settingsController.validateUrl,
              ),
              CustomTextField(
                labelName: 'SEND SMS URL',
                controller: settingsController.sendSmsUrlController,
                maxLines: 4,
                keyboardType: TextInputType.url,
                validator: settingsController.validateUrl,
              ),
              Container(
                padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
                child: Obx(
                  () => DropdownButtonFormField<int>(
                    value: settingsController.selectedInterval.value,
                    dropdownColor: Colors.black,
                    style: const TextStyle(color: Colors.white, fontFamily: gilroyMedium),
                    decoration: InputDecoration(
                      labelText: 'Fetch interval (seconds)',
                      labelStyle: TextStyle(color: Colors.grey.shade400, fontFamily: gilroyMedium),
                      border: const OutlineInputBorder(
                        borderRadius: borderRadius20,
                        borderSide: BorderSide(color: Colors.grey, width: 2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: borderRadius20,
                        borderSide: BorderSide(color: Colors.grey.shade200, width: 2),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: borderRadius20,
                        borderSide: BorderSide(color: kPrimaryColor, width: 2),
                      ),
                    ),
                    items: settingsController.intervalOptions
                        .map(
                          (int value) => DropdownMenuItem<int>(
                            value: value,
                            child: Text('$value seconds'),
                          ),
                        )
                        .toList(),
                    onChanged: (int? newValue) {
                      if (newValue == null) {
                        return;
                      }
                      settingsController.selectedInterval.value = newValue;
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // SIM Slot Selector
              Container(
                padding: const EdgeInsets.only(top: 0, left: 20, right: 20),
                child: Obx(
                  () => DropdownButtonFormField<int>(
                    value: settingsController.selectedSimSlot.value,
                    dropdownColor: Colors.black,
                    style: const TextStyle(color: Colors.white, fontFamily: gilroyMedium),
                    decoration: InputDecoration(
                      labelText: 'SIM Kart (SMS ibermek üçin)',
                      labelStyle: TextStyle(color: Colors.grey.shade400, fontFamily: gilroyMedium),
                      border: const OutlineInputBorder(
                        borderRadius: borderRadius20,
                        borderSide: BorderSide(color: Colors.grey, width: 2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: borderRadius20,
                        borderSide: BorderSide(color: Colors.grey.shade200, width: 2),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: borderRadius20,
                        borderSide: BorderSide(color: kPrimaryColor, width: 2),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem<int>(value: 0, child: Text('SIM 1 (Slot 1)')),
                      DropdownMenuItem<int>(value: 1, child: Text('SIM 2 (Slot 2)')),
                    ],
                    onChanged: (int? newValue) {
                      if (newValue == null) return;
                      settingsController.selectedSimSlot.value = newValue;
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Message Template Toggle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Obx(
                  () => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'SMS shablon ishlatish',
                      style: TextStyle(color: Colors.white, fontFamily: gilroySemiBold, fontSize: 16),
                    ),
                    subtitle: Text(
                      settingsController.useTemplate.value ? 'Shablon: kod {code} bilen almashtyrylýar' : 'Diňe kody iberer',
                      style: TextStyle(color: Colors.grey.shade400, fontFamily: gilroyMedium, fontSize: 12),
                    ),
                    activeColor: kPrimaryColor,
                    value: settingsController.useTemplate.value,
                    onChanged: (bool value) {
                      settingsController.useTemplate.value = value;
                    },
                  ),
                ),
              ),
              // Message Template Field
              Obx(
                () => settingsController.useTemplate.value
                    ? CustomTextField(
                        labelName: 'SMS Shablon ({code} = kod)',
                        controller: settingsController.messageTemplateController,
                        maxLines: 3,
                        keyboardType: TextInputType.text,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 20),
              AgreeButton(
                onTap: () async {
                  print('Save button tapped'); // Debug
                  try {
                    final bool isSaved = await settingsController.saveSettings();
                    print('Save result: $isSaved'); // Debug
                    if (isSaved) {
                      Get.back();

                      showSnackBar('Done', 'Settings saved', Colors.green);
                    } else {
                      showSnackBar('Error', 'Please check your inputs', Colors.red);
                    }
                  } catch (e) {
                    print('Error saving: $e'); // Debug
                    showSnackBar('Error', 'Failed to save: $e', Colors.red);
                  }
                },
                text: 'Save',
              ),
              const SizedBox(height: 12),
              const Text(
                'Created by: G.Dadebay',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontFamily: gilroySemiBold, fontSize: 20),
              )
            ],
          ),
        ));
  }
}
