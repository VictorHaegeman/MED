// Transformation des données GTFS en graphe compact
// flutter test lib/data_pipeline/build_graph.dart pour lancer le fichier et refaire le json

import 'dart:convert';
import 'dart:io';
import '../core/graph.dart';

const String gtfsDir = 'assets/data';
const String outputPath = 'assets/graph/idfm_graph.json';
const int defaultTransferSeconds = 240; //4 minutes
const Set<int> allowedRouteTypes = {0, 1, 2, 3}; // 0=tram, 1=métro, 2=RER, 3=bus

List<String> splitTxtLine(String line) {
  final result = <String>[];
  final buffer = StringBuffer();
  bool insideQuotes = false;

  for (int i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      insideQuotes = !insideQuotes;
    } else if (char == ',' && !insideQuotes) {
      result.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  result.add(buffer.toString());
  return result;
} 

List<Map<String, String>> readTxt(String path) {
  final file = File(path);
  final lines = file.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
  final headers = splitTxtLine(lines.first);

  return lines.skip(1).map((line) {
    final values = splitTxtLine(line);
    return Map.fromIterables(headers, values);
  }).toList();
}

int timeToSeconds(String time) { //transformer les horaires en données que l'on peut comparer
  final parts = time.split(':').map(int.parse).toList();
  return parts[0] * 3600 + parts[1] * 60 + parts[2];
}

//type de station : parent_station si renseigné, sinon stop_id
String stationKeyOf(Map<String, String> stop) {
  final parent = stop['parent_station'];
  return (parent != null && parent.isNotEmpty) ? parent : stop['stop_id']!;
}

void main() {
  stdout.writeln('Lecture des fichiers depuis $gtfsDir ...');

  final stops = readTxt('$gtfsDir/stops.txt');
  final trips = readTxt('$gtfsDir/trips.txt');
  final stopTimes = readTxt('$gtfsDir/stop_times.txt');
  final transfers = readTxt('$gtfsDir/transfers.txt');
  final routes = readTxt('$gtfsDir/routes.txt');

  stdout.writeln(
    'stops=${stops.length} trips=${trips.length} '
    'stop_time=${stopTimes.length} transfers=${transfers.length}');

  final stopById = {for (final s in stops) s['stop_id']!: s};
  final routeIdByTripId = {for (final t in trips) t['trip_id']!: t['route_id']!};
  final colorByRouteId = {for (final r in routes) r['route_id']!: r['route_color']}; 
  final shortNameByRouteId = {for (final r in routes) r['route_id']!: r['route_short_name']};
  final typeByRouteId = {for (final r in routes) r['route_id']!: int.tryParse(r['route_type'] ?? '')};
  final headsignByTripId = {for (final t in trips) t['trip_id']!: t['trip_headsign']}; 

  final graph = TransportGraph();

  final byTrip = <String, List<Map<String, String>>>{};
  for (final st in stopTimes) {
    byTrip.putIfAbsent(st['trip_id']!, () => []).add(st);
  }

  // Collecte le meilleur arc (poids minimal) par paire (from, to) — évite les
  // doublons dus aux dizaines de courses qui empruntent le même arc physique.
  final bestRideArc = <String, ({String from, String to, double weight, String? headsign})>{};

  for (final entry in byTrip.entries) {
    final routeId = routeIdByTripId[entry.key];
    if (routeId == null) continue;

    final routeType = typeByRouteId[routeId];
    if (!allowedRouteTypes.contains(routeType)) continue;

    final seq = entry.value
      ..sort((a,b) =>
        int.parse(a['stop_sequence']!).compareTo(int.parse(b['stop_sequence']!)));

    for (int i = 0; i < seq.length; i++) {
      final st = seq[i];
      final stop = stopById[st['stop_id']];
      if (stop == null) continue;

      final locType = int.tryParse(stop['location_type'] ?? '0') ?? 0;
      if (locType != 0) continue; // on ne garde que les vrais arrêts/quais (0)

      final stationKey = stationKeyOf(stop);
      final nodeId = '$stationKey#$routeId';

      graph.addNode(GraphNode(
        id: nodeId,
        stationName: stop['stop_name']!,
        line: routeId,
        lat: double.parse(stop['stop_lat']!),
        lon: double.parse(stop['stop_lon']!),
        lineColor: colorByRouteId[routeId],
        lineShortName: shortNameByRouteId[routeId],
        routeType: typeByRouteId[routeId],
      ));

      if (i > 0) {
        final prevSt = seq[i - 1];
        final prevStop = stopById[prevSt['stop_id']];
        if (prevStop == null) continue;
        final prevLocType = int.tryParse(prevStop['location_type'] ?? '0') ?? 0;
        if (prevLocType != 0) continue;
        final prevNodeId = '${stationKeyOf(prevStop)}#$routeId';
        if (prevNodeId == nodeId) continue;
        final weight = (timeToSeconds(st['departure_time']!) -
          timeToSeconds(prevSt['departure_time']!)).toDouble();
        if (weight <= 0) continue;
        final arcKey = '$prevNodeId|$nodeId';
        final existing = bestRideArc[arcKey];
        if (existing == null || weight < existing.weight) {
          bestRideArc[arcKey] = (
            from: prevNodeId,
            to: nodeId,
            weight: weight,
            headsign: headsignByTripId[entry.key],
          );
        }
      }
    }
  }

  for (final arc in bestRideArc.values) {
    if (graph.nodes.containsKey(arc.from) && graph.nodes.containsKey(arc.to)) {
      graph.addEdge(Edge(
        from: arc.from,
        to: arc.to,
        weightSeconds: arc.weight,
        type: EdgeType.ride,
        headsign: arc.headsign,
      ));
    }
  }

  final nodesByStationKey = <String, List<String>>{};
  for (final node in graph.nodes.values) {
    nodesByStationKey.putIfAbsent(node.id.split('#').first, () => []).add(node.id);
  }

  final seenTransfers = <String>{};

  for (final tr in transfers) {
    final fromStop = stopById[tr['from_stop_id']];
    final toStop = stopById[tr['to_stop_id']];
    if (fromStop == null || toStop == null) continue;

    final fromKey = stationKeyOf(fromStop);
    final toKey = stationKeyOf(toStop);
    final minTime = tr['min_transfer_time'];
    final weight = (minTime != null && minTime.isNotEmpty)
        ? double.parse(minTime)
        : defaultTransferSeconds.toDouble();

    final fromNodes = nodesByStationKey[fromKey] ?? const [];
    final toNodes = nodesByStationKey[toKey] ?? const [];
    for (final f in fromNodes) {
      for (final t in toNodes) {
        if (f == t) continue;
        if (!seenTransfers.add('$f|$t')) continue;
        graph.addEdge(Edge(from: f, to: t, weightSeconds: weight, type: EdgeType.transfer));
      }
    }
  }

  for (final nodeIds in nodesByStationKey.values) {
    for (final f in nodeIds) {
      for (final t in nodeIds) {
        if (f == t) continue;
        if (!seenTransfers.add('$f|$t')) continue;
        graph.addEdge(Edge(
          from: f,
          to: t,
          weightSeconds: defaultTransferSeconds.toDouble(),
          type: EdgeType.transfer,
        ));
      }
    }
  }

  stdout.writeln('Graphe : ${graph.nodeCount} nœuds, ${graph.edgeCount} arêtes.');

  final outFile = File(outputPath)..createSync(recursive: true);
  outFile.writeAsStringSync(jsonEncode({
    'nodes': graph.nodes.values
        .map((n) => {
              'id': n.id,
              'stationName': n.stationName,
              'line': n.line,
              'lat': n.lat,
              'lon': n.lon,
              'lineColor': n.lineColor,
              'lineShortName': n.lineShortName,
              'routeType': n.routeType,
            })
        .toList(),
    'edges': [
      for (final nodeId in graph.nodes.keys)
        for (final edge in graph.neighbors(nodeId))
          {
            'from': edge.from,
            'to': edge.to,
            'weightSeconds': edge.weightSeconds,
            'type': edge.type.name,
            'headsign': edge.headsign
          }
    ],
  }));

  stdout.writeln('Écrit : $outputPath');
}