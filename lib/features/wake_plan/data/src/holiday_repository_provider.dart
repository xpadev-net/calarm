import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'app_wake_plan_repository_provider.dart';
import 'holiday_repository.dart';

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

const _fetchIcsTimeout = Duration(seconds: 15);

Future<String> _fetchIcsBody(http.Client client, Uri uri) async {
  final response = await client.get(uri).timeout(_fetchIcsTimeout);
  if (response.statusCode != 200) {
    throw HttpException('unexpected status ${response.statusCode} for $uri');
  }
  return response.body;
}

class HttpException implements Exception {
  HttpException(this.message);

  final String message;

  @override
  String toString() => 'HttpException: $message';
}

final holidayRepositoryProvider = FutureProvider<HolidayRepository>((
  ref,
) async {
  final database = await ref.watch(appWakePlanDatabaseProvider.future);
  final client = ref.watch(httpClientProvider);
  return HolidayRepository(
    database: database,
    fetchIcs: (uri) => _fetchIcsBody(client, uri),
  );
});
