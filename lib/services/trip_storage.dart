import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_trip.dart';

class TripStorage {
  static const _key = 'med_saved_trips_v1';

  static Future<List<SavedTrip>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return SavedTrip.decodeList(raw);
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(SavedTrip trip) async {
    final prefs = await SharedPreferences.getInstance();
    final trips = await loadAll();
    trips.add(trip);
    await prefs.setString(_key, SavedTrip.encodeList(trips));
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
