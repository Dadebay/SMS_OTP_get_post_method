import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

class HomeController extends GetxController {
  RxList<Map<String, dynamic>> data = <Map<String, dynamic>>[].obs;
  RxString url = "".obs;
  RxBool login = false.obs;

  GetStorage storage = GetStorage();

  @override
  void onInit() {
    super.onInit();
    findAllNumbersAndRetrieveThem();
  }

  addData({required String phone, required String message, required String status}) {
    bool exists = data.any((element) => element['phone'] == phone && element['message'] == message);

    if (!exists) {
      data.add({"phone": phone, "message": message, "status": status, 'date': DateTime.now().toString()});
      storage.write('data', jsonEncode(data));
    }
  }

  changeStatus({required String message, required String status}) {
    for (var element in data) {
      if (element['message'] == message) {
        element['status'] = status;
      }
    }
    data.refresh();
    //sort data by date
    data.sort((a, b) => DateTime.parse(b['date']).compareTo(DateTime.parse(a['date'])));
    storage.write('data', jsonEncode(data));
  }

  findAllNumbersAndRetrieveThem() {
    var storedData = storage.read('data') ?? '[]';
    List<dynamic> list = jsonDecode(storedData);
    data.value = list.map((e) => e as Map<String, dynamic>).toList();
  }
}
