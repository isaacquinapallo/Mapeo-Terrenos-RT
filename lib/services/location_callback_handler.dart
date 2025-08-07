import 'package:background_locator_2/location_dto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Callback que se ejecuta continuamente cuando llega una nueva ubicación
void callback(LocationDto locationDto) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return;

  await Supabase.instance.client.from('locations').upsert({
    'id_user': userId,
    'latitude': locationDto.latitude,
    'longitude': locationDto.longitude,
    'timestamp': DateTime.now().toIso8601String(),
    'status': true,
  }, onConflict: 'id_user');
}

/// Callback que se ejecuta al iniciar el rastreo en segundo plano
void notificationCallback(Map<String, dynamic> params) {
  print('🔔 initCallback ejecutado con params: $params');
}