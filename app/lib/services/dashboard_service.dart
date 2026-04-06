import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class DashboardService extends ChangeNotifier {
  bool _loading = false;
  bool _connected = false;
  String? _error;

  List<EmailItem> _emails = [];
  List<EmailItem> _sentEmails = [];
  List<EmailItem> _spamEmails = [];
  List<EmailItem> _trashEmails = [];
  List<EventItem> _events = [];
  List<FileItem> _files = [];
  List<ActivityItem> _activities = [];

  bool get loading => _loading;
  bool get connected => _connected;
  String? get error => _error;
  List<EmailItem> get emails => _emails;
  List<EmailItem> get sentEmails => _sentEmails;
  List<EmailItem> get spamEmails => _spamEmails;
  List<EmailItem> get trashEmails => _trashEmails;
  List<EventItem> get events => _events;
  List<FileItem> get files => _files;
  List<ActivityItem> get activities => _activities;

  int get unreadCount => _emails.where((e) => e.unread).length;
  int get sentCount => _sentEmails.length;
  List<EmailItem> get businessEmails =>
      _emails.where((e) => e.isBusiness).toList();
  List<EmailItem> get businessSentEmails =>
      _sentEmails.where((e) => e.isBusiness).toList();
  int get todayEventCount {
    final now = DateTime.now();
    return _events.where((e) {
      try {
        final start = DateTime.parse(e.start);
        return start.year == now.year &&
            start.month == now.month &&
            start.day == now.day;
      } catch (_) {
        return false;
      }
    }).length;
  }

  bool _autoPilot = true;
  bool get autoPilot => _autoPilot;

  Future<bool> toggleAutoPilot(String? accessToken, bool enabled) async {
    if (accessToken == null) return false;
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/settings/autopilot'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'enabled': enabled}),
      );
      if (res.statusCode == 200) {
        _autoPilot = enabled;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('AutoPilot toggle error: $e');
    }
    return false;
  }

  Future<void> loadDashboard(String? accessToken) async {
    if (accessToken == null) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/api/dashboard'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _connected = data['connected'] == true;
        _emails = (data['emails'] as List? ?? [])
            .map((e) => EmailItem.fromJson(e))
            .toList();
        _events = (data['events'] as List? ?? [])
            .map((e) => EventItem.fromJson(e))
            .toList();
        _files = (data['files'] as List? ?? [])
            .map((e) => FileItem.fromJson(e))
            .toList();
        _activities = (data['activities'] as List? ?? [])
            .map((e) => ActivityItem.fromJson(e))
            .toList();
      } else {
        _error = 'Failed to load dashboard (${res.statusCode})';
      }
    } catch (e) {
      _error = 'Network error: $e';
      debugPrint('Dashboard load error: $e');
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> loadEmails(
    String? accessToken, {
    String query = '',
    String label = 'INBOX',
  }) async {
    if (accessToken == null) return;
    _loading = true;
    notifyListeners();

    try {
      final qParam = query.isNotEmpty ? '&q=$query' : '';
      final uri = Uri.parse('$apiBaseUrl/api/emails?label=$label$qParam');
      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _connected = data['connected'] == true;
        final items = (data['emails'] as List? ?? [])
            .map((e) => EmailItem.fromJson(e))
            .toList();
        if (label == 'SENT') {
          _sentEmails = items;
        } else if (label == 'SPAM') {
          _spamEmails = items;
        } else if (label == 'TRASH') {
          _trashEmails = items;
        } else {
          _emails = items;
        }
      }
    } catch (e) {
      debugPrint('Emails load error: $e');
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> loadEvents(String? accessToken) async {
    if (accessToken == null) return;
    _loading = true;
    notifyListeners();

    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/api/events'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _connected = data['connected'] == true;
        _events = (data['events'] as List? ?? [])
            .map((e) => EventItem.fromJson(e))
            .toList();
      }
    } catch (e) {
      debugPrint('Events load error: $e');
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> loadFiles(String? accessToken, {String query = ''}) async {
    if (accessToken == null) return;
    _loading = true;
    notifyListeners();

    try {
      final uri = Uri.parse(
        '$apiBaseUrl/api/files${query.isNotEmpty ? '?q=$query' : ''}',
      );
      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _connected = data['connected'] == true;
        _files = (data['files'] as List? ?? [])
            .map((e) => FileItem.fromJson(e))
            .toList();
      }
    } catch (e) {
      debugPrint('Files load error: $e');
    }

    _loading = false;
    notifyListeners();
  }
}

class EmailItem {
  final String id;
  final String subject;
  final String from;
  final String to;
  final String snippet;
  final String date;
  final bool unread;
  final bool isBusiness;

  EmailItem({
    required this.id,
    required this.subject,
    required this.from,
    this.to = '',
    required this.snippet,
    required this.date,
    required this.unread,
    this.isBusiness = false,
  });

  factory EmailItem.fromJson(Map<String, dynamic> json) => EmailItem(
    id: json['id'] ?? '',
    subject: json['subject'] ?? '(No Subject)',
    from: json['from'] ?? '',
    to: json['to'] ?? '',
    snippet: json['snippet'] ?? '',
    date: json['date'] ?? '',
    unread: json['unread'] == true,
    isBusiness: json['isBusiness'] == true,
  );

  String get recipientName {
    final match = RegExp(r'^([^<]+)').firstMatch(to);
    return match?.group(1)?.trim() ?? to;
  }

  String get senderName {
    final match = RegExp(r'^([^<]+)').firstMatch(from);
    return match?.group(1)?.trim() ?? from;
  }

  String get shortDate {
    try {
      final parsed = _parseEmailDate(date);
      if (parsed == null) return date;
      final now = DateTime.now();
      final diff = now.difference(parsed);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays == 1) return 'Yesterday';
      return '${parsed.month}/${parsed.day}';
    } catch (_) {
      return date.length > 16 ? date.substring(0, 16) : date;
    }
  }

  static DateTime? _parseEmailDate(String raw) {
    try {
      return DateTime.parse(raw);
    } catch (_) {}
    // Try common email date format: "Fri, 4 Apr 2026 10:30:00 +0000"
    try {
      final cleaned = raw.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
      return DateTime.tryParse(cleaned);
    } catch (_) {}
    return null;
  }
}

class EventItem {
  final String id;
  final String summary;
  final String start;
  final String end;
  final String location;
  final List<String> attendees;

  EventItem({
    required this.id,
    required this.summary,
    required this.start,
    required this.end,
    required this.location,
    required this.attendees,
  });

  factory EventItem.fromJson(Map<String, dynamic> json) => EventItem(
    id: json['id'] ?? '',
    summary: json['summary'] ?? '(No title)',
    start: json['start'] ?? '',
    end: json['end'] ?? '',
    location: json['location'] ?? '',
    attendees:
        (json['attendees'] as List?)?.map((e) => e.toString()).toList() ?? [],
  );

  String get timeRange {
    try {
      final s = DateTime.parse(start);
      final e = DateTime.parse(end);
      String fmt(DateTime d) {
        final hour = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
        final ampm = d.hour >= 12 ? 'PM' : 'AM';
        return '$hour:${d.minute.toString().padLeft(2, '0')} $ampm';
      }

      return '${fmt(s)} - ${fmt(e)}';
    } catch (_) {
      return '$start - $end';
    }
  }

  String get startTime {
    try {
      final s = DateTime.parse(start);
      final hour = s.hour > 12 ? s.hour - 12 : (s.hour == 0 ? 12 : s.hour);
      final ampm = s.hour >= 12 ? 'PM' : 'AM';
      return '$hour:${s.minute.toString().padLeft(2, '0')} $ampm';
    } catch (_) {
      return start;
    }
  }
}

class FileItem {
  final String id;
  final String name;
  final String mimeType;
  final String modifiedTime;
  final String webViewLink;

  FileItem({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.modifiedTime,
    required this.webViewLink,
  });

  factory FileItem.fromJson(Map<String, dynamic> json) => FileItem(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    mimeType: json['mimeType'] ?? '',
    modifiedTime: json['modifiedTime'] ?? '',
    webViewLink: json['webViewLink'] ?? '',
  );

  String get typeLabel {
    if (mimeType.contains('document') || mimeType.contains('word')) {
      return 'Document';
    }
    if (mimeType.contains('spreadsheet') || mimeType.contains('excel')) {
      return 'Spreadsheet';
    }
    if (mimeType.contains('presentation') || mimeType.contains('powerpoint')) {
      return 'Presentation';
    }
    if (mimeType.contains('pdf')) return 'PDF';
    if (mimeType.contains('image')) return 'Image';
    if (mimeType.contains('folder')) return 'Folder';
    return 'File';
  }

  String get shortDate {
    try {
      final parsed = DateTime.parse(modifiedTime);
      final now = DateTime.now();
      final diff = now.difference(parsed);
      if (diff.inHours < 24) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      return '${parsed.month}/${parsed.day}/${parsed.year}';
    } catch (_) {
      return modifiedTime;
    }
  }
}

class ActivityItem {
  final String id;
  final String action;
  final String detail;
  final String status;

  ActivityItem({
    required this.id,
    required this.action,
    required this.detail,
    required this.status,
  });

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
    id: json['id'] ?? '',
    action: json['action'] ?? '',
    detail: json['detail'] ?? '',
    status: json['status'] ?? 'done',
  );
}
