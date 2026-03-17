import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:notibar/plugins/github/github_plugin.dart';
import 'package:notibar/plugins/jira/jira_plugin.dart';
import 'package:notibar/plugins/frappe/frappe_plugin.dart';
import 'package:notibar/plugins/mattermost/mattermost_plugin.dart';
import 'package:notibar/plugins/teams/teams_plugin.dart';
import 'package:notibar/plugins/outlook/outlook_plugin.dart';
import 'package:notibar/plugins/slack/slack_plugin.dart';

void main() {
  group('Plugin Parsing Tests', () {
    test('SlackPlugin parses conversations correctly', () {
      final fixture = File(
        'test/fixtures/slack_conversations.json',
      ).readAsStringSync();
      final json = jsonDecode(fixture);
      final plugin = SlackPlugin();

      final summary = plugin.parseSummary(json);

      expect(summary.items.length, 2);
      expect(summary.unreadCount, 6);
      expect(summary.mentionCount, 3);
      expect(summary.items.first.metadata['channelId'], 'C123');
    });

    test('GithubPlugin parses search results correctly', () {
      final fixture = File(
        'test/fixtures/github_search_issues.json',
      ).readAsStringSync();
      final json = jsonDecode(fixture) as Map<String, dynamic>;
      json['_type'] = 'Issue';
      json['_reason'] = 'assign';
      final plugin = GithubPlugin();

      final summary = plugin.parseSummary(json);

      expect(summary.items.length, 2);
      expect(summary.assignedIssuesCount, 2);
      expect(summary.items.first.metadata['type'], 'Issue');
      expect(summary.items.first.metadata['reason'], 'assign');
      expect(
        summary.items.first.actionUrl,
        'https://github.com/owner/repo/issues/10',
      );
    });

    test('JiraPlugin parses issues correctly', () {
      final fixture = File('test/fixtures/jira_issues.json').readAsStringSync();
      final json = jsonDecode(fixture);
      final plugin = JiraPlugin();

      final summary = plugin.parseSummary(json, baseUrl: 'https://jira.com');

      expect(summary.items.length, 2);
      expect(summary.assignedIssuesCount, 2);
      expect(summary.items.first.metadata['key'], 'PROJ-123');
    });

    test('FrappePlugin parses todos correctly', () {
      final fixture = File(
        'test/fixtures/frappe_todos.json',
      ).readAsStringSync();
      final json = jsonDecode(fixture);
      final plugin = FrappePlugin();

      final summary = plugin.parseSummary(json, baseUrl: 'https://frappe.com');

      expect(summary.items.length, 2);
      expect(summary.items.first.metadata['priority'], 'High');
    });

    test('MattermostPlugin parses team unreads correctly', () {
      final fixture = File(
        'test/fixtures/mattermost_unreads.json',
      ).readAsStringSync();
      final json = {'teams': jsonDecode(fixture)};
      final plugin = MattermostPlugin();

      final summary = plugin.parseSummary(
        json,
        baseUrl: 'https://mattermost.example.com',
      );

      expect(summary.items.length, 1);
      expect(summary.mentionCount, 2);
      expect(summary.items.first.metadata['teamId'], 'team123');
    });

    test('TeamsPlugin parses chats correctly', () {
      final fixture = File('test/fixtures/teams_chats.json').readAsStringSync();
      final json = jsonDecode(fixture);
      final plugin = TeamsPlugin();

      final summary = plugin.parseSummary(json);

      expect(summary.items.length, 1);
      expect(summary.items.first.metadata['source'], 'chat');
    });

    test('OutlookPlugin parses messages correctly', () {
      final fixture = File(
        'test/fixtures/outlook_messages.json',
      ).readAsStringSync();
      final json = jsonDecode(fixture);
      final plugin = OutlookPlugin();

      final summary = plugin.parseSummary(json);

      expect(summary.items.length, 1);
      expect(summary.items.first.metadata['from'], 'Alice');
    });
  });
}
