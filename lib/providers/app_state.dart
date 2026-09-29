import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging_http_client.dart';
import '../services/api_client.dart';
import '../services/cache_service.dart';

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(client: LoggingHttpClient()),
);

final cacheServiceProvider = Provider<CacheService>(
  (ref) => throw UnimplementedError('在 main.dart 覆盖注入'),
);

final onlineProvider = FutureProvider<bool>((ref) => ref.watch(apiClientProvider).online());
