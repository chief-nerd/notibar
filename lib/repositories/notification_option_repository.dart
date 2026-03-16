import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_option.dart';

class NotificationOptionRepository {
  static const _key = 'notibar_notification_options';
  final SharedPreferences _prefs;

  NotificationOptionRepository(this._prefs);

  Future<List<NotificationOption>> getOptions() async {
    final jsonString = _prefs.getString(_key);
    if (jsonString == null) return [];

    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      final options = jsonList
          .map((e) => NotificationOption.fromJson(e as Map<String, dynamic>))
          .toList();
      options.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return options;
    } catch (e) {
      return [];
    }
  }

  Future<void> saveOptions(List<NotificationOption> options) async {
    final jsonString = json.encode(options.map((e) => e.toJson()).toList());
    await _prefs.setString(_key, jsonString);
  }

  Future<void> addOption(NotificationOption option) async {
    final options = await getOptions();
    options.add(option);
    await saveOptions(options);
  }

  Future<void> removeOption(String id) async {
    final options = await getOptions();
    options.removeWhere((o) => o.id == id);
    await saveOptions(options);
  }
}
