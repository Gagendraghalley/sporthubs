/// A row of notifications: written by the database's functions (a new
/// membership request, a membership activated, one about to end...).
class AppNotification {
  final String id;
  final String? moduleKey;
  final String title;
  final String? body;

  /// The app page it's about ('/my-gym'), opened when it's tapped.
  final String? link;
  final DateTime? readAt;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.createdAt,
    this.moduleKey,
    this.body,
    this.link,
    this.readAt,
  });

  bool get isRead => readAt != null;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        moduleKey: json['module_key'] as String?,
        title: json['title'] as String,
        body: json['body'] as String?,
        link: json['link'] as String?,
        readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
