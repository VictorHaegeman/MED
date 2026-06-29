import 'dart:convert';

class SavedTrip {
  const SavedTrip({
    required this.id,
    required this.date,
    required this.from,
    required this.to,
    required this.distanceKm,
    required this.durationSeconds,
    required this.co2SavedKg,
  });

  final String id;
  final DateTime date;
  final String from;
  final String to;
  final double distanceKm;
  final double durationSeconds;
  final double co2SavedKg;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'from': from,
        'to': to,
        'distanceKm': distanceKm,
        'durationSeconds': durationSeconds,
        'co2SavedKg': co2SavedKg,
      };

  factory SavedTrip.fromJson(Map<String, dynamic> j) => SavedTrip(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        from: j['from'] as String,
        to: j['to'] as String,
        distanceKm: (j['distanceKm'] as num).toDouble(),
        durationSeconds: (j['durationSeconds'] as num).toDouble(),
        co2SavedKg: (j['co2SavedKg'] as num).toDouble(),
      );

  static List<SavedTrip> decodeList(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((e) => SavedTrip.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String encodeList(List<SavedTrip> trips) =>
      jsonEncode(trips.map((t) => t.toJson()).toList());
}
