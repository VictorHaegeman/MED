import 'dart:math';
import '../core/graph.dart';

/// Calcule l'empreinte CO₂ d'un trajet.
/// Source des facteurs : transilien.com/fr/page-corporate/calcul-emissions-co2
class Co2Service {
  // Voiture particulière — référence ADEME
  static const double voitureGPerKm = 206.0;

  // Facteurs par GTFS routeType (gCO₂eq/voy·km)
  static const Map<int, double> _emissionsGPerKm = {
    0: 2.6,   // Tram RATP
    1: 2.5,   // Métro RATP
    2: 4.09,  // RER / Transilien (ADEME/SNCF)
    3: 68.0,  // Bus RATP
  };

  /// [stepTypes] : type d'arête réel par pas (ride/transfer). Les pas de
  /// marche (transfer) ne comptent aucune émission mais comptent dans la
  /// distance « économisée » vs voiture.
  static Co2Result forPath(
    TransportGraph g,
    List<String> path, [
    List<EdgeType> stepTypes = const [],
  ]) {
    if (path.length < 2) return const Co2Result(distanceKm: 0, savedKg: 0);

    double rideKm = 0; // distance en véhicule (compte pour émissions + éco)
    double emitG = 0;

    for (int i = 0; i < path.length - 1; i++) {
      final a = g.nodes[path[i]];
      final b = g.nodes[path[i + 1]];
      if (a == null || b == null) continue;
      // Seuls les vrais trajets véhicule émettent et sont comparés à la voiture.
      // Sans stepTypes (ex : MapScreen), on vérifie qu'une arête ride existe
      // réellement — sinon ce pas était de la marche.
      final isRide = i < stepTypes.length
          ? stepTypes[i] == EdgeType.ride
          : _hasRideEdge(g, path[i], path[i + 1]);
      if (!isRide) continue;
      final d = _haversineKm(a.lat, a.lon, b.lat, b.lon);
      rideKm += d;
      emitG += (_emissionsGPerKm[a.routeType] ?? 0.0) * d;
    }

    final carG = voitureGPerKm * rideKm;
    return Co2Result(
      distanceKm: rideKm,
      savedKg: (carG - emitG).clamp(0.0, double.infinity) / 1000,
    );
  }

  /// Fun fact — comparaison parlante basée sur le CO₂ total économisé.
  /// Sources : ADEME 2023, RATP Éco-Compteur.
  static String funFact(double totalSavedKg, int tripCount) {
    if (totalSavedKg <= 0) return 'Effectuez votre premier trajet pour voir votre impact ! 🌱';
    final facts = _factsFor(totalSavedKg);
    return facts[tripCount % facts.length];
  }

  static List<String> _factsFor(double kg) {
    // Paris → NYC aller : ~1 000 kg CO₂eq/pers. (ADEME)
    if (kg >= 800) {
      return [
        '${(kg / 1000).toStringAsFixed(2)} vol Paris → New York évité ✈️',
        '${(kg / 400).toStringAsFixed(1)} vols Paris → Barcelone évités ✈️',
        '${(kg / 25).toStringAsFixed(0)} ans d\'absorption d\'un arbre 🌳',
      ];
    }
    // Paris → Barcelone : ~400 kg
    if (kg >= 100) {
      return [
        '${(kg / 25).toStringAsFixed(0)} ans d\'absorption d\'un arbre 🌳',
        '${(kg / 33.4).toStringAsFixed(1)} jeans en coton économisés 👖',
        '${(kg / 3.6).toStringAsFixed(0)} steaks de bœuf non produits 🥩',
      ];
    }
    // Quelques kg
    if (kg >= 5) {
      return [
        '${(kg / 3.6).toStringAsFixed(0)} steaks bœuf non produits 🥩',
        '${(kg / 1.7).toStringAsFixed(0)} pizzas de CO₂ évitées 🍕',
        '${(kg * 1000 / 206).toStringAsFixed(0)} km en voiture non parcourus 🚗',
      ];
    }
    // Moins d\'1 kg
    return [
      '${(kg * 1000 / 36).toStringAsFixed(0)} h de streaming évitées 📺',
      '${(kg / 1.7).toStringAsFixed(1)} pizza de CO₂ évitée 🍕',
      '${(kg * 1000 / 5).toStringAsFixed(0)} recharges de smartphone 📱',
    ];
  }

  static bool _hasRideEdge(TransportGraph g, String from, String to) {
    for (final e in g.neighbors(from)) {
      if (e.to == to && e.type == EdgeType.ride) return true;
    }
    return false;
  }

  static double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}

class Co2Result {
  const Co2Result({required this.distanceKm, required this.savedKg});
  final double distanceKm;
  final double savedKg;
}
