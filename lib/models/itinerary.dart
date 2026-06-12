import 'dart:ui';

/// Modes de transport gérés par le graphe intermodal.
enum TransportMode { metro, tram, bus, walk }

/// Un segment d'itinéraire : soit un trajet en véhicule, soit de la marche,
/// soit un point d'arrêt remarquable (départ, correspondance, arrivée).
sealed class Leg {
  const Leg();
}

class StationPoint extends Leg {
  const StationPoint({required this.name, required this.subtitle, required this.color});
  final String name;
  final String subtitle;
  final Color color;
}

class RideLeg extends Leg {
  const RideLeg({
    required this.mode,
    required this.lineLabel,
    required this.lineColor,
    required this.darkText,
    required this.direction,
    required this.subtitle,
  });
  final TransportMode mode;
  final String lineLabel;
  final Color lineColor;
  final bool darkText;
  final String direction;
  final String subtitle;
}

class WalkLeg extends Leg {
  const WalkLeg({required this.label, required this.subtitle});
  final String label;
  final String subtitle;
}

/// Un itinéraire complet proposé à l'utilisateur.
class Itinerary {
  const Itinerary({
    required this.tag,
    required this.tagColor,
    required this.durationLabel,
    required this.detail,
    required this.walkLabel,
    required this.co2Label,
    required this.modes,
    required this.legs,
    required this.summary,
    required this.perfNote,
    this.highlighted = false,
  });

  final String tag;
  final Color tagColor;
  final String durationLabel;
  final String detail;
  final String walkLabel;
  final String co2Label;
  final Set<TransportMode> modes;
  final List<Leg> legs;
  final String summary;

  /// Transparence algorithmique affichée dans l'UI (exigence de l'AO :
  /// démontrer la qualité algorithmique, pas seulement l'interface).
  final String perfNote;
  final bool highlighted;
}
