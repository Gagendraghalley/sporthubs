/// A row of app_modules: whether a module shows in the app. Admins turn
/// them on and off (Admin -> Modules); the app only shows enabled ones.
class AppModuleRow {
  final String key;
  final String name;
  final bool isEnabled;
  final int sortOrder;

  const AppModuleRow({required this.key, required this.name, required this.isEnabled, required this.sortOrder});

  factory AppModuleRow.fromJson(Map<String, dynamic> json) => AppModuleRow(
        key: json['key'] as String,
        name: json['name'] as String,
        isEnabled: json['is_enabled'] as bool,
        sortOrder: json['sort_order'] as int? ?? 100,
      );
}
