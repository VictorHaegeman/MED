/// Résultat de recherche : soit un arrêt du réseau, soit une adresse géocodée.
class SearchResult {
  const SearchResult.station(this.displayName)
      : isAddress = false,
        lat = null,
        lon = null;

  const SearchResult.address(this.displayName, this.lat, this.lon)
      : isAddress = true;

  final String displayName;
  final bool isAddress;
  final double? lat;
  final double? lon;

  @override
  String toString() => displayName;
}
