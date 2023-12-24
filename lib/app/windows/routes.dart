import 'package:fluent_ui/fluent_ui.dart';
import 'package:get/get.dart';
import 'package:note/app/windows/controller/home/win_home_controller.dart';
import 'package:note/app/windows/settings/settings_controller.dart';
import 'package:note/app/windows/view/home/win_home_page.dart';
import 'package:note/app/windows/view/import/import_controller.dart';
import 'package:note/app/windows/view/import/import_widget.dart';
import 'package:note/service/service_manager.dart';

import 'settings/settings_widget.dart';
import 'view/export/export_controller.dart';
import 'view/export/export_widget.dart';

class WindowsAppRoutes {
  static final routes = [
    GetPage(
      name: "/",
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 200),
      page: () {
        return Builder(
          builder: (context) {
            Get.put(WinHomeController(ServiceManager.of(context)));
            return const WinHomePage();
          },
        );
      },
    ),
    GetPage(
      name: "/settings",
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 200),
      page: () {
        Get.put(SettingsController());
        return const SettingsWidget();
      },
    ),
    GetPage(
      name: "/export",
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 200),
      page: () {
        Get.put(ExportController());
        return const ExportWidget();
      },
    ),
    GetPage(
      name: "/import",
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 200),
      page: () {
        Get.put(ImportController());
        return const ImportWidget();
      },
    ),
  ];
}
