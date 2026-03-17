// Template test file — copy to test/plugins/ and uncomment to use.
//
// import 'dart:convert';
// import 'dart:io';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:notibar/plugins/your_service/your_service_plugin.dart';
//
// void main() {
//   group('YourServicePlugin Parsing Tests', () {
//     test('parses items correctly', () {
//       final fixture = File(
//         'test/fixtures/your_service_response.json',
//       ).readAsStringSync();
//       final json = jsonDecode(fixture) as Map<String, dynamic>;
//       final plugin = YourServicePlugin();
//
//       final summary = plugin.parseSummary(json, baseUrl: 'https://example.com');
//
//       expect(summary.items.length, 2);
//       expect(summary.unreadCount, 1);
//       expect(summary.items.first.actionUrl, contains('example.com'));
//     });
//   });
// }
