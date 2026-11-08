/// Bhutan's places, from the master tables: dzongkhag -> gewog (or thromde)
/// -> village. Used for addresses, e.g. a gym member's registration.
library;

/// The three levels of the location master.
enum LocationLevel {
  dzongkhag('Dzongkhag', 'Dzongkhags'),
  gewog('Gewog', 'Gewogs and thromdes'),
  village('Village', 'Villages');

  const LocationLevel(this.label, this.plural);
  final String label;
  final String plural;
}

/// gewogs.kind: a rural gewog, or a thromde or town that stands in for one.
abstract final class GewogKind {
  static const gewog = 'gewog';
  static const thromde = 'thromde';

  static String label(String kind) => kind == thromde ? 'Thromde' : 'Gewog';
}

/// A row of one of the master tables. [parentId] is the dzongkhag of a
/// gewog and the gewog of a village; [parentName] its name, when loaded.
class LocationItem {
  final int id;
  final LocationLevel level;
  final String name;
  final bool isActive;
  final int? parentId;
  final String? parentName;

  /// For villages: the dzongkhag the gewog is in, when loaded.
  final int? grandparentId;
  final String? grandparentName;

  /// For gewogs: [GewogKind].
  final String? kind;

  /// For villages: the national code (DDGGVVV), where known.
  final String? code;

  const LocationItem({
    required this.id,
    required this.level,
    required this.name,
    this.isActive = true,
    this.parentId,
    this.parentName,
    this.grandparentId,
    this.grandparentName,
    this.kind,
    this.code,
  });

  /// Where it is: 'Chokhor, Bumthang' for a village, 'Bumthang' for a gewog.
  String? get place => [parentName, grandparentName].whereType<String>().join(', ').ifEmpty;

  factory LocationItem.dzongkhag(Map<String, dynamic> json) => LocationItem(
        id: json['id'] as int,
        level: LocationLevel.dzongkhag,
        name: json['name'] as String,
        isActive: json['is_active'] as bool? ?? true,
      );

  /// A gewogs row, with `dzongkhag:dzongkhags(name)` if selected.
  factory LocationItem.gewog(Map<String, dynamic> json) => LocationItem(
        id: json['id'] as int,
        level: LocationLevel.gewog,
        name: json['name'] as String,
        isActive: json['is_active'] as bool? ?? true,
        parentId: json['dzongkhag_id'] as int?,
        parentName: (json['dzongkhag'] as Map<String, dynamic>?)?['name'] as String?,
        kind: json['kind'] as String? ?? GewogKind.gewog,
      );

  /// A villages row, with
  /// `gewog:gewogs(name, dzongkhag_id, dzongkhag:dzongkhags(name))` if
  /// selected.
  factory LocationItem.village(Map<String, dynamic> json) {
    final gewog = json['gewog'] as Map<String, dynamic>?;
    return LocationItem(
      id: json['id'] as int,
      level: LocationLevel.village,
      name: json['name'] as String,
      isActive: json['is_active'] as bool? ?? true,
      parentId: json['gewog_id'] as int?,
      parentName: gewog?['name'] as String?,
      grandparentId: gewog?['dzongkhag_id'] as int?,
      grandparentName: (gewog?['dzongkhag'] as Map<String, dynamic>?)?['name'] as String?,
      code: json['code'] as String?,
    );
  }
}

/// A place picked in a form: as far down as they went.
class LocationSelection {
  final int? dzongkhagId;
  final int? gewogId;
  final int? villageId;

  const LocationSelection({this.dzongkhagId, this.gewogId, this.villageId});

  static const empty = LocationSelection();

  /// Choosing a dzongkhag clears the gewog and village under the old one.
  LocationSelection withDzongkhag(int? id) => id == dzongkhagId ? this : LocationSelection(dzongkhagId: id);

  /// Choosing a gewog clears the village under the old one.
  LocationSelection withGewog(int? id) =>
      id == gewogId ? this : LocationSelection(dzongkhagId: dzongkhagId, gewogId: id);

  LocationSelection withVillage(int? id) =>
      LocationSelection(dzongkhagId: dzongkhagId, gewogId: gewogId, villageId: id);

  bool get isComplete => dzongkhagId != null && gewogId != null && villageId != null;

  @override
  bool operator ==(Object other) =>
      other is LocationSelection &&
      other.dzongkhagId == dzongkhagId &&
      other.gewogId == gewogId &&
      other.villageId == villageId;

  @override
  int get hashCode => Object.hash(dzongkhagId, gewogId, villageId);
}

extension on String {
  String? get ifEmpty => isEmpty ? null : this;
}
