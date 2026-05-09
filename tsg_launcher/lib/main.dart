import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/tsg_auth/server_config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ServerConfigService.init();
  runApp(
    const ProviderScope(
      child: TsgLauncherApp(),
    ),
  );
}

