import 'package:flutter/material.dart';

import '../core/router_service.dart';
import '../main.dart'
    show appGraph, pathNotifier, tripFromNotifier, tripSecondsNotifier, tripToNotifier;
import '../models/itinerary.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'detail_screen.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.from, required this.to});

  final String from;
  final String to;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  final _router = RouterService();
  late final Future<List<Itinerary>> _itineraries;
  TransportMode? _filter; // null = Tous

  @override
  void initState() {
    super.initState();
    _itineraries = _router.findItineraries(widget.from, widget.to);
    // Publie le chemin du premier résultat dans le notifier partagé avec MapScreen.
    _itineraries.then((list) {
      if (list.isNotEmpty) {
        pathNotifier.value = list.first.pathNodeIds;
        tripSecondsNotifier.value = list.first.totalSeconds;
        tripFromNotifier.value = widget.from;
        tripToNotifier.value = widget.to;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BackCircle(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${widget.from} → ${widget.to}',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                        const Text('Aujourd’hui · départ maintenant',
                            style: TextStyle(
                                fontSize: 12, color: MedColors.secondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _filterChips(),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<Itinerary>>(
                  future: _itineraries,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: MedColors.accent));
                    }
                    final visible = snapshot.data!
                        .where((it) =>
                            _filter == null || it.modes.contains(_filter))
                        .toList();
                    return ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (_, i) => _itineraryCard(visible[i]),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Graphe intermodal · ${appGraph.nodeCount} stations · ${appGraph.edgeCount} connexions',
                  style: const TextStyle(fontSize: 11, color: MedColors.secondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChips() {
    final filters = <(TransportMode?, String)>[
      (null, 'Tous'),
      (TransportMode.metro, '🚇 Métro'),
      (TransportMode.tram, '🚊 Tram'),
      (TransportMode.bus, '🚌 Bus'),
      (TransportMode.walk, '🚶 Marche'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (mode, label) in filters)
          MedChip(
            label: label,
            selected: _filter == mode,
            onTap: () => setState(() => _filter = mode),
          ),
      ],
    );
  }

  Widget _itineraryCard(Itinerary it) {
    return MedCard(
      border: it.highlighted && _filter == null ? it.tagColor : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DetailScreen(itinerary: it)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: it.tagColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(it.tag,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: it.tagColor)),
              ),
              Text(it.durationLabel,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              ..._rideBadges(it),
              const SizedBox(width: 6),
              Flexible(
                child: Text(it.detail,
                    style: const TextStyle(
                        fontSize: 12, color: MedColors.secondary),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Text('🚶 ${it.walkLabel}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: MedColors.secondary)),
              const SizedBox(width: 14),
              Text('🌱 ${it.co2Label}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: MedColors.green)),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _rideBadges(Itinerary it) {
    final rides = it.legs.whereType<RideLeg>().toList();
    if (rides.isEmpty) return [const Text('🚶', style: TextStyle(fontSize: 15))];
    final widgets = <Widget>[];
    for (var i = 0; i < rides.length; i++) {
      final r = rides[i];
      widgets.add(LineBadge(
          label: r.lineLabel,
          color: r.lineColor,
          darkText: r.darkText,
          mode: r.mode));
      if (i < rides.length - 1) {
        widgets.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('›',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: MedColors.secondary)),
        ));
      }
    }
    return widgets;
  }
}
