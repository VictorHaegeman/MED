import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/search_result.dart';

/// Géocodage dual-source :
/// - api-adresse.data.gouv.fr  → adresses postales françaises (précision IGN)
/// - Nominatim (OpenStreetMap) → lieux, POI, établissements (EFREI, hôpitaux…)
class GeocodingService {
  static const _adresseBase = 'https://api-adresse.data.gouv.fr';
  static const _nominatimBase = 'https://nominatim.openstreetmap.org';

  // Bounding box Île-de-France pour restreindre Nominatim
  static const _idfViewbox = '1.4,48.1,3.6,49.4';

  static const _userAgent = 'MED-EFREI-App/1.0';

  /// Recherche combinée : adresses + POI (lieux, écoles, landmarks…)
  static Future<List<SearchResult>> searchAddress(
    String query, {
    int limit = 5,
  }) async {
    if (query.trim().length < 2) return [];

    // Lancement en parallèle des deux sources
    final futures = await Future.wait([
      _searchAdresseGouv(query, limit: 4),
      _searchNominatim(query, limit: 4),
    ]);

    final adresse = futures[0];
    final nominatim = futures[1];

    // Fusion : adresses en premier (plus précises), puis POI OSM
    // Déduplication par proximité (<200m)
    final merged = <SearchResult>[...adresse];
    for (final poi in nominatim) {
      final isDuplicate = merged.any((r) =>
          r.lat != null &&
          r.lon != null &&
          _distM(r.lat!, r.lon!, poi.lat!, poi.lon!) < 200);
      if (!isDuplicate) merged.add(poi);
    }

    return merged.take(limit).toList();
  }

  /// Géocodage inverse (coordonnées → adresse humaine).
  static Future<SearchResult?> reverseGeocode(double lat, double lon) async {
    // On essaie d'abord l'API gouvernementale (plus précise en France)
    try {
      final uri =
          Uri.parse('$_adresseBase/reverse/').replace(queryParameters: {
        'lat': lat.toStringAsFixed(6),
        'lon': lon.toStringAsFixed(6),
        'limit': '1',
      });
      final response =
          await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List<dynamic>;
        if (features.isNotEmpty) {
          final props = features[0]['properties'] as Map<String, dynamic>;
          return SearchResult.address(props['label'] as String, lat, lon);
        }
      }
    } catch (_) {}

    // Fallback Nominatim
    try {
      final uri =
          Uri.parse('$_nominatimBase/reverse').replace(queryParameters: {
        'lat': lat.toStringAsFixed(6),
        'lon': lon.toStringAsFixed(6),
        'format': 'json',
        'zoom': '17',
      });
      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent}).timeout(
              const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final label = data['display_name'] as String?;
        if (label != null) {
          return SearchResult.address(_shortNominatimLabel(label), lat, lon);
        }
      }
    } catch (_) {}

    return null;
  }

  // ---------------------------------------------------------------------------
  // Sources privées
  // ---------------------------------------------------------------------------

  static Future<List<SearchResult>> _searchAdresseGouv(
      String query, {required int limit}) async {
    try {
      final uri =
          Uri.parse('$_adresseBase/search/').replace(queryParameters: {
        'q': query,
        'limit': '$limit',
      });
      final response =
          await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>;
      return features.map((f) {
        final props = f['properties'] as Map<String, dynamic>;
        final coords = (f['geometry']['coordinates'] as List).cast<num>();
        return SearchResult.address(
          props['label'] as String,
          coords[1].toDouble(),
          coords[0].toDouble(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<SearchResult>> _searchNominatim(
      String query, {required int limit}) async {
    try {
      final uri =
          Uri.parse('$_nominatimBase/search').replace(queryParameters: {
        'q': query,
        'format': 'json',
        'limit': '$limit',
        'viewbox': _idfViewbox,
        'bounded': '0', // 0 = cherche aussi hors viewbox si pas de résultat
        'addressdetails': '0',
      });
      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent}).timeout(
              const Duration(seconds: 4));
      if (response.statusCode != 200) return [];
      final List<dynamic> data = jsonDecode(response.body);
      return data
          .map((item) {
            final lat = double.tryParse(item['lat'] as String? ?? '');
            final lon = double.tryParse(item['lon'] as String? ?? '');
            final name = item['display_name'] as String?;
            if (lat == null || lon == null || name == null) return null;
            return SearchResult.address(_shortNominatimLabel(name), lat, lon);
          })
          .whereType<SearchResult>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Raccourcit le label Nominatim verbeux :
  // "EFREI Paris, 30 Avenue du Président Wilson, Villejuif, Val-de-Marne, ..."
  // → "EFREI Paris, 30 Avenue du Président Wilson, Villejuif"
  static String _shortNominatimLabel(String full) {
    final parts = full.split(', ');
    return parts.take(3).join(', ');
  }

  static double _distM(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * 3.14159 / 180;
    final dLon = (lon2 - lon1) * 3.14159 / 180;
    final a = dLat * dLat + dLon * dLon; // approximation plate pour ~200m
    return r * a;
  }
}
