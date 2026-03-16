import 'package:equatable/equatable.dart';

class NotificationItem extends Equatable {
  final String id;
  final String title;
  final String? subtitle;
  final String? body;
  final DateTime timestamp;
  final String actionUrl;
  final bool isUnread;
  final bool isFlagged;
  final Map<String, dynamic> metadata;

  const NotificationItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.body,
    required this.timestamp,
    required this.actionUrl,
    this.isUnread = false,
    this.isFlagged = false,
    this.metadata = const {},
  });

  @override
  List<Object?> get props => [
    id, 
    title, 
    subtitle, 
    body, 
    timestamp, 
    actionUrl, 
    isUnread, 
    isFlagged, 
    metadata,
  ];
}
