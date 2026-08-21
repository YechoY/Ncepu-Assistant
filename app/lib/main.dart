import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'providers/app_state.dart';
import 'services/cache_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final cache = await CacheService.open(dir.path);
  runApp(
    ProviderScope(
      overrides: [
        cacheServiceProvider.overrideWithValue(cache),
      ],
      child: const HdjwApp(),
    ),
  );
}
