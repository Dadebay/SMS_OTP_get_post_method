import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sms_otp/app/modules/home/views/home_view.dart';

class ConnectionCheckView extends StatefulWidget {
  const ConnectionCheckView({super.key});

  @override
  State<ConnectionCheckView> createState() => _ConnectionCheckViewState();
}

class _ConnectionCheckViewState extends State<ConnectionCheckView> {
  @override
  void initState() {
    super.initState();
    _openHome();
  }

  Future<void> _openHome() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    Get.offAll(() => const HomeView());
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Color(0xff24264b),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
}
