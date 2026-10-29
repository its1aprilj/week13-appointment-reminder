import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String apiBaseUrl = 'http://127.0.0.1:8000/api';

const Color purple = Color(0xFF6D28D9);
const Color deepPurple = Color(0xFF4C1D95);
const Color lavender = Color(0xFFA78BFA);
const Color pageBackground = Color(0xFFF7F5FC);
const Color mutedText = Color(0xFF77718A);

void main() => runApp(const AppointmentReminderApp());

// ============================================================
// APPOINTMENT MODEL
// ============================================================

class AppointmentRecord {
  const AppointmentRecord({
    required this.id,
    required this.name,
    required this.service,
    required this.destination,
    required this.status,
    required this.attempts,
    required this.maxAttempts,
    required this.simulationMode,
    required this.appointmentAt,
    required this.reminderAt,
    required this.nextAttemptAt,
    required this.lastError,
    required this.logs,
  });

  final int id;
  final String name;
  final String service;
  final String destination;
  final String status;
  final int attempts;
  final int maxAttempts;
  final String simulationMode;
  final DateTime? appointmentAt;
  final DateTime? reminderAt;
  final DateTime? nextAttemptAt;
  final String? lastError;
  final List<Map<String, dynamic>> logs;

  factory AppointmentRecord.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString())?.toLocal();
    }

    final rawLogs = json['logs'] as List? ?? [];

    return AppointmentRecord(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      service: json['service']?.toString() ?? '',
      destination: json['destination']?.toString() ?? '',
      status: json['status']?.toString() ?? 'scheduled',
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      maxAttempts: (json['max_attempts'] as num?)?.toInt() ?? 3,
      simulationMode: json['simulation_mode']?.toString() ?? 'success',
      appointmentAt: parseDate(json['appointment_at']),
      reminderAt: parseDate(json['reminder_at']),
      nextAttemptAt: parseDate(json['next_attempt_at']),
      lastError: json['last_error']?.toString(),
      logs: rawLogs
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(),
    );
  }
}

// ============================================================
// LARAVEL API SERVICE
// ============================================================

class AppointmentApi {
  Future<dynamic> _handle(http.Response response) async {
    dynamic result;
    try {
      result = jsonDecode(response.body);
    } catch (_) {
      result = response.body;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Request failed (${response.statusCode}).';
      if (result is Map) {
        message = result['message']?.toString() ?? message;
        final errors = result['errors'];
        if (errors is Map) {
          final details = errors.values
              .expand((value) => value is List ? value : [value])
              .join('\n');
          if (details.isNotEmpty) message = '$message\n$details';
        }
      }
      throw Exception(message);
    }
    return result;
  }

  Future<List<AppointmentRecord>> getAppointments() async {
    final response = await http
        .get(
      Uri.parse('$apiBaseUrl/appointments'),
      headers: const {'Accept': 'application/json'},
    )
        .timeout(const Duration(seconds: 12));

    final result = await _handle(response);
    if (result is! List) {
      throw Exception('The appointments API did not return a JSON list.');
    }

    return result
        .whereType<Map>()
        .map((entry) => AppointmentRecord.fromJson(
      Map<String, dynamic>.from(entry),
    ))
        .toList();
  }

  Future<dynamic> post(
      String path, {
        Map<String, dynamic>? body,
      }) async {
    final response = await http
        .post(
      Uri.parse('$apiBaseUrl$path'),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body ?? <String, dynamic>{}),
    )
        .timeout(const Duration(seconds: 12));

    return _handle(response);
  }
}

// ============================================================
// APP THEME
// ============================================================

class AppointmentReminderApp extends StatelessWidget {
  const AppointmentReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: purple,
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Appointment Reminder System',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: pageBackground,
        fontFamily: 'Arial',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: deepPurple,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFECE7F5)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFAF9FD),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: purple,
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
      ),
      home: const AppointmentDashboard(),
    );
  }
}

// ============================================================
// DASHBOARD
// ============================================================

class AppointmentDashboard extends StatefulWidget {
  const AppointmentDashboard({super.key});

  @override
  State<AppointmentDashboard> createState() => _AppointmentDashboardState();
}

class _AppointmentDashboardState extends State<AppointmentDashboard> {
  final AppointmentApi api = AppointmentApi();

  List<AppointmentRecord> appointments = [];
  bool loading = true;
  bool busy = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadAppointments();
  }

  Future<void> loadAppointments({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        loading = true;
        errorMessage = null;
      });
    }

    try {
      final data = await api.getAppointments();
      if (!mounted) return;
      setState(() {
        appointments = data;
        loading = false;
        errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage =
        'Could not load appointments.\n$error\n\n'
            'Make sure Laravel is running at 127.0.0.1:8000.';
      });
    }
  }

  int count(String status) =>
      appointments.where((item) => item.status == status).length;

  Future<void> runAction(
      String successMessage,
      Future<void> Function() action,
      ) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      await loadAppointments(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> createAppointment() async {
    final input = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const AppointmentFormDialog(),
    );
    if (input == null) return;

    final appointmentAt = input['appointmentAt'] as DateTime;
    final reminderAt = appointmentAt.subtract(const Duration(hours: 1));

    await runAction('Appointment created successfully.', () async {
      await api.post(
        '/appointments',
        body: {
          'name': input['name'],
          'service': input['service'],
          'destination': input['destination'],
          'appointment_at': appointmentAt.toUtc().toIso8601String(),
          'reminder_at': reminderAt.toUtc().toIso8601String(),
          'simulation_mode': input['simulationMode'],
        },
      );
    });
  }

  Future<void> cancelAppointment(AppointmentRecord item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel appointment?'),
        content: Text('Cancel "${item.name}"? This action will be sent to Laravel.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep appointment'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm cancel'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await runAction('Appointment cancelled.', () async {
      await api.post('/appointments/${item.id}/cancel');
    });
  }

  Future<void> rescheduleAppointment(AppointmentRecord item) async {
    await runAction('Reminder rescheduled.', () async {
      await api.post('/appointments/${item.id}/schedule');
    });
  }

  Future<void> resolveReview(AppointmentRecord item) async {
    final controller = TextEditingController(
      text: 'Reviewed the simulated delivery failure and confirmed the destination.',
    );

    final resolution = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolve manual review'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Review action taken',
              hintText: 'Describe the action taken',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Back'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (controller.text.trim().length < 5) return;
              Navigator.pop(dialogContext, controller.text.trim());
            },
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Confirm review'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (resolution == null) return;

    await runAction('Review submitted to Laravel.', () async {
      await api.post(
        '/appointments/${item.id}/resolve-review',
        body: {
          'resolution': resolution,
          'simulation_mode': 'success',
        },
      );
    });
  }

  String formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  String statusLabel(String status) => status
      .replaceAll('_', ' ')
      .split(' ')
      .map((part) => part.isEmpty
      ? part
      : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  Color statusColor(String status) {
    switch (status) {
      case 'delivered':
        return const Color(0xFF16845B);
      case 'manual_review':
        return const Color(0xFFDC4545);
      case 'retrying':
        return const Color(0xFFCB7A12);
      case 'expired':
        return const Color(0xFF64748B);
      case 'cancelled':
        return const Color(0xFF7B8496);
      default:
        return purple;
    }
  }

  IconData statusIcon(String status) {
    switch (status) {
      case 'delivered':
        return Icons.check_circle_rounded;
      case 'manual_review':
        return Icons.support_agent_rounded;
      case 'retrying':
        return Icons.refresh_rounded;
      case 'expired':
        return Icons.event_busy_rounded;
      case 'cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.schedule_rounded;
    }
  }

  List<Map<String, dynamic>> get recentLogs {
    final entries = <Map<String, dynamic>>[];
    for (final item in appointments) {
      for (final log in item.logs) {
        entries.add({
          ...log,
          'appointment_id': item.id,
          'appointment_name': item.name,
        });
      }
    }
    DateTime logDate(Map<String, dynamic> log) =>
        DateTime.tryParse(log['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
    entries.sort((a, b) => logDate(b).compareTo(logDate(a)));
    return entries.take(12).toList();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1000;
    final columns = width >= 1200 ? 4 : width >= 700 ? 3 : 2;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide) _buildSidebar(),
            Expanded(
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => loadAppointments(),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.all(wide ? 30 : 18),
                        children: [
                          _buildWelcomeBanner(),
                          const SizedBox(height: 20),
                          _buildDemoNotice(),
                          if (errorMessage != null) ...[
                            const SizedBox(height: 16),
                            _buildErrorPanel(),
                          ],
                          const SizedBox(height: 25),
                          _heading('Dashboard overview',
                              'A quick look at your appointment activity.',
                              Icons.grid_view_rounded),
                          const SizedBox(height: 14),
                          if (loading && appointments.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(35),
                              child: Center(
                                child: CircularProgressIndicator(color: purple),
                              ),
                            )
                          else
                            GridView.count(
                              crossAxisCount: columns,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: width < 400 ? 1.05 : 1.45,
                              children: [
                                MetricCard(title: 'Total appointments',
                                    value: appointments.length,
                                    icon: Icons.calendar_month_rounded,
                                    accent: purple),
                                MetricCard(title: 'Scheduled',
                                    value: count('scheduled'),
                                    icon: Icons.schedule_rounded,
                                    accent: const Color(0xFF7C3AED)),
                                MetricCard(title: 'Delivered',
                                    value: count('delivered'),
                                    icon: Icons.mark_email_read_rounded,
                                    accent: const Color(0xFF16845B)),
                                MetricCard(title: 'Retrying',
                                    value: count('retrying'),
                                    icon: Icons.sync_rounded,
                                    accent: const Color(0xFFCB7A12)),
                                MetricCard(title: 'Manual review',
                                    value: count('manual_review'),
                                    icon: Icons.support_agent_rounded,
                                    accent: const Color(0xFFDC4545)),
                                MetricCard(title: 'Expired',
                                    value: count('expired'),
                                    icon: Icons.event_busy_rounded,
                                    accent: const Color(0xFF64748B)),
                                MetricCard(title: 'Cancelled',
                                    value: count('cancelled'),
                                    icon: Icons.event_busy_outlined,
                                    accent: const Color(0xFF8B849B)),
                              ],
                            ),
                          const SizedBox(height: 28),
                          _heading('Appointment records',
                              '${appointments.length} records from your Laravel API',
                              Icons.event_note_rounded,
                              trailing: FilledButton.icon(
                                onPressed: busy ? null : createAppointment,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('New appointment'),
                              )),
                          const SizedBox(height: 14),
                          if (!loading && appointments.isEmpty)
                            _emptyState()
                          else
                            ...appointments.map(_buildAppointmentCard),
                          const SizedBox(height: 28),
                          _heading('Recent automation activity',
                              'Latest events recorded by the system.',
                              Icons.bolt_rounded),
                          const SizedBox(height: 14),
                          _buildActivityPanel(),
                          const SizedBox(height: 20),
                          _buildFooter(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 235,
      color: const Color(0xFF32105F),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.notifications_active_rounded,
                color: Colors.white, size: 32),
            SizedBox(width: 10),
            Expanded(child: Text('Remindly',
                style: TextStyle(color: Colors.white,
                    fontSize: 22, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 6),
          const Text('APPOINTMENT SYSTEM',
              style: TextStyle(color: Color(0xFFD5C5F5), fontSize: 10)),
          const SizedBox(height: 38),
          const Text('WORKSPACE',
              style: TextStyle(color: Color(0xFFB9A3DE),
                  fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListTile(
            selected: true,
            selectedTileColor: purple,
            leading: const Icon(Icons.grid_view_rounded, color: Colors.white),
            title: const Text('Dashboard',
                style: TextStyle(color: Colors.white)),
            onTap: () => loadAppointments(),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_rounded,
                    color: Color(0xFFD7C4FF), size: 25),
                SizedBox(height: 10),
                Text('Automation active',
                    style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 5),
                Text('Processing is managed by the Laravel backend.',
                    style: TextStyle(color: Color(0xFFD5C5F5),
                        fontSize: 12, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('WEEK 13  •  SA7',
              style: TextStyle(color: Color(0xFFB9A3DE), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFECE7F5))),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Appointment Reminder System',
                    style: TextStyle(color: deepPurple,
                        fontWeight: FontWeight.bold, fontSize: 16)),
                SizedBox(height: 3),
                Text('Week 13 · Automation Foundation',
                    style: TextStyle(color: mutedText, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh appointments',
            onPressed: busy ? null : () => loadAppointments(),
            icon: const Icon(Icons.refresh_rounded, color: purple),
          ),
          const SizedBox(width: 5),
          const Chip(
            avatar: Icon(Icons.cloud_done_rounded, color: purple, size: 17),
            label: Text('Laravel API'),
            backgroundColor: Color(0xFFF0E9FF),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6D28D9), Color(0xFF4C1D95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: purple.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 500;
        return Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SMART REMINDER MANAGEMENT',
                    style: TextStyle(color: Color(0xFFE8DFFF),
                        fontSize: 10, letterSpacing: 1,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 17),
                Text('Stay on top of\nevery appointment.',
                    style: TextStyle(color: Colors.white,
                        fontSize: compact ? 26 : 34,
                        height: 1.15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                const Text(
                  'Manage schedules, track reminder delivery, and review automation activity.',
                  style: TextStyle(color: Color(0xFFE9DFFF),
                      height: 1.5, fontSize: 13),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: busy ? null : createAppointment,
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.white, foregroundColor: deepPurple),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create appointment'),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 16),
            const Icon(Icons.calendar_month_rounded,
                color: Color(0xFFE9DFFF), size: 75),
          ],
        ]);
      }),
    );
  }

  Widget _buildDemoNotice() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF0E9FF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFDFD0FF)),
      ),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, color: purple, size: 22),
        SizedBox(width: 11),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Demonstration mode',
                style: TextStyle(color: deepPurple,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('Reminder delivery is simulated for testing. No real email or SMS is sent.',
                style: TextStyle(color: Color(0xFF655581),
                    fontSize: 12, height: 1.5)),
          ],
        )),
      ]),
    );
  }

  Widget _buildErrorPanel() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEEE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Colors.red),
        const SizedBox(width: 10),
        Expanded(child: SelectableText(errorMessage!,
            style: const TextStyle(color: Color(0xFF9F2424)))),
        IconButton(
          onPressed: () => loadAppointments(),
          icon: const Icon(Icons.refresh_rounded, color: Colors.red),
        ),
      ]),
    );
  }

  Widget _heading(String title, String subtitle, IconData icon,
      {Widget? trailing}) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE5FF),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: purple, size: 22),
          ),
          const SizedBox(width: 11),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: deepPurple,
                fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: mutedText, fontSize: 12)),
          ]),
        ]),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildAppointmentCard(AppointmentRecord item) {
    final color = statusColor(item.status);
    final canCancel = !['delivered', 'expired', 'cancelled']
        .contains(item.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 13),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 9,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0E9FF),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.event_available_rounded,
                        color: purple, size: 22),
                  ),
                  const SizedBox(width: 11),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('#${item.id} · ${item.name}',
                        style: const TextStyle(color: deepPurple,
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(item.service,
                        style: const TextStyle(color: mutedText, fontSize: 12)),
                  ]),
                ]),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(statusIcon(item.status), color: color, size: 15),
                    const SizedBox(width: 6),
                    Text(statusLabel(item.status),
                        style: TextStyle(color: color, fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFFF0ECF7), height: 1),
            const SizedBox(height: 15),
            Wrap(spacing: 22, runSpacing: 14, children: [
              _detail(Icons.person_outline_rounded, 'Client', item.name),
              _detail(Icons.alternate_email_rounded, 'Destination', item.destination),
              _detail(Icons.calendar_today_rounded, 'Appointment', formatDate(item.appointmentAt)),
              _detail(Icons.notifications_none_rounded, 'Reminder', formatDate(item.reminderAt)),
              _detail(Icons.sync_rounded, 'Delivery attempts', '${item.attempts} / ${item.maxAttempts}'),
              _detail(Icons.science_outlined, 'Test scenario', item.simulationMode),
            ]),
            if (item.lastError != null && item.lastError!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFC53D3D), size: 19),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.lastError!,
                      style: const TextStyle(color: Color(0xFFAA3030), fontSize: 12))),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            // Every action has its own visible button and callback.
            // These buttons are intentionally larger for easier clicking.
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : () => loadAppointments(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(105, 48),
                    foregroundColor: purple,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh'),
                ),
                if (item.status == 'retrying')
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => rescheduleAppointment(item),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(160, 48),
                      foregroundColor: purple,
                    ),
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: const Text('Restart reminder'),
                  ),
                if (item.status == 'manual_review')
                  FilledButton.icon(
                    onPressed: busy ? null : () => resolveReview(item),
                    style: FilledButton.styleFrom(
                      backgroundColor: deepPurple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(160, 48),
                    ),
                    icon: const Icon(Icons.fact_check_rounded, size: 20),
                    label: const Text('Resolve review'),
                  ),
                if (canCancel)
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => cancelAppointment(item),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB83D4A),
                      minimumSize: const Size(160, 48),
                    ),
                    icon: const Icon(Icons.cancel_outlined, size: 20),
                    label: const Text('Cancel appointment'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(IconData icon, String label, String value) {
    return SizedBox(
      width: 220,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: lavender, size: 19),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: mutedText, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Color(0xFF39304C),
                fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        )),
      ]),
    );
  }

  Widget _emptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(children: [
          const Icon(Icons.event_note_rounded, color: purple, size: 42),
          const SizedBox(height: 12),
          const Text('No appointments yet',
              style: TextStyle(color: deepPurple,
                  fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 7),
          const Text('Create an appointment to start using the reminder system.',
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedText)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : createAppointment,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create first appointment'),
          ),
        ]),
      ),
    );
  }

  Widget _buildActivityPanel() {
    final logs = recentLogs;
    if (logs.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(22),
          child: Row(children: [
            Icon(Icons.history_rounded, color: lavender, size: 27),
            SizedBox(width: 12),
            Expanded(child: Text('No activity logs recorded yet.',
                style: TextStyle(color: mutedText))),
          ]),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        child: Column(
          children: logs.map((log) {
            final event = log['event']?.toString() ?? 'event';
            final message = log['message']?.toString() ?? '';
            final created = log['created_at']?.toString() ?? '';
            final warning = log['level']?.toString() == 'warning';

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 3),
              leading: Icon(
                warning ? Icons.warning_amber_rounded : Icons.bolt_rounded,
                color: warning ? const Color(0xFFCB7A12) : purple,
                size: 27,
              ),
              title: Text('$event · Appointment #${log['appointment_id']}',
                  style: const TextStyle(color: deepPurple,
                      fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: Text('$message\n$created',
                  style: const TextStyle(color: mutedText,
                      fontSize: 12, height: 1.5)),
              isThreeLine: true,
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFFF0E9FF),
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.code_rounded, color: purple, size: 22),
        SizedBox(width: 11),
        Expanded(child: Text(
          'System design: Laravel manages appointment records, retry scheduling, expiration, and persistent logs. Flutter provides the dashboard and sends requests to the API.',
          style: TextStyle(color: Color(0xFF655581),
              fontSize: 12, height: 1.6),
        )),
      ]),
    );
  }
}

// ============================================================
// SUMMARY METRIC CARD
// ============================================================

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String title;
  final int value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 21),
              ),
              Text('$value', style: TextStyle(color: accent,
                  fontSize: 26, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 12),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF655B76),
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// CREATE APPOINTMENT FORM
// ============================================================

class AppointmentFormDialog extends StatefulWidget {
  const AppointmentFormDialog({super.key});

  @override
  State<AppointmentFormDialog> createState() => _AppointmentFormDialogState();
}

class _AppointmentFormDialogState extends State<AppointmentFormDialog> {
  final nameController = TextEditingController();
  final serviceController = TextEditingController();
  final destinationController = TextEditingController();

  late DateTime appointmentAt;
  String simulationMode = 'success';
  String? formError;

  @override
  void initState() {
    super.initState();
    appointmentAt = DateTime.now().add(const Duration(days: 1));
    appointmentAt = DateTime(
      appointmentAt.year,
      appointmentAt.month,
      appointmentAt.day,
      appointmentAt.hour,
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    serviceController.dispose();
    destinationController.dispose();
    super.dispose();
  }

  String formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  Future<void> chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: appointmentAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(seedColor: purple),
        ),
        child: child!,
      ),
    );
    if (selected == null) return;
    setState(() {
      appointmentAt = DateTime(
        selected.year, selected.month, selected.day,
        appointmentAt.hour, appointmentAt.minute,
      );
    });
  }

  Future<void> chooseTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(appointmentAt),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(seedColor: purple),
        ),
        child: child!,
      ),
    );
    if (selected == null) return;
    setState(() {
      appointmentAt = DateTime(
        appointmentAt.year, appointmentAt.month, appointmentAt.day,
        selected.hour, selected.minute,
      );
    });
  }

  void submit() {
    if (nameController.text.trim().isEmpty ||
        serviceController.text.trim().isEmpty ||
        destinationController.text.trim().isEmpty) {
      setState(() => formError =
      'Complete the name, service, and destination fields.');
      return;
    }
    if (!appointmentAt.isAfter(DateTime.now())) {
      setState(() => formError = 'Choose an appointment time in the future.');
      return;
    }

    Navigator.pop(context, {
      'name': nameController.text.trim(),
      'service': serviceController.text.trim(),
      'destination': destinationController.text.trim(),
      'appointmentAt': appointmentAt,
      'simulationMode': simulationMode,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Row(children: [
        Icon(Icons.event_available_rounded, color: purple, size: 27),
        SizedBox(width: 10),
        Expanded(child: Text('Create appointment',
            style: TextStyle(color: deepPurple,
                fontWeight: FontWeight.bold))),
      ]),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameController,
                decoration: const InputDecoration(
                    labelText: 'Student / client name',
                    prefixIcon: Icon(Icons.person_outline_rounded))),
            const SizedBox(height: 12),
            TextField(controller: serviceController,
                decoration: const InputDecoration(
                    labelText: 'Appointment service',
                    prefixIcon: Icon(Icons.medical_services_outlined))),
            const SizedBox(height: 12),
            TextField(controller: destinationController,
                decoration: const InputDecoration(
                    labelText: 'Email / phone destination (test data)',
                    prefixIcon: Icon(Icons.alternate_email_rounded))),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('DATE AND TIME',
                  style: TextStyle(color: purple, fontSize: 11,
                      fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
            const SizedBox(height: 9),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: chooseDate,
                icon: const Icon(Icons.calendar_month_rounded),
                label: const Text('Select date'),
              ),
              OutlinedButton.icon(
                onPressed: chooseTime,
                icon: const Icon(Icons.access_time_rounded),
                label: const Text('Select time'),
              ),
            ]),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0E9FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(formatDate(appointmentAt),
                  style: const TextStyle(color: deepPurple,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            const Text('The reminder is scheduled one hour before the appointment.',
                style: TextStyle(fontSize: 12, color: mutedText)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: simulationMode,
              decoration: const InputDecoration(
                labelText: 'Delivery test scenario',
                prefixIcon: Icon(Icons.science_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'success',
                    child: Text('Success (simulated)')),
                DropdownMenuItem(value: 'transient',
                    child: Text('Temporary failure, then recovery')),
                DropdownMenuItem(value: 'permanent',
                    child: Text('Permanent failure / manual review')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => simulationMode = value);
              },
            ),
            if (formError != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEEEE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(formError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: submit,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Create appointment'),
        ),
      ],
    );
  }
}
