import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/patient_web_scaffold.dart';

DateTime? _reportCreatedAt(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

class PatientMyReportScreen extends StatelessWidget {
  const PatientMyReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthProvider>().userId;
    final route = GoRouterState.of(context).matchedLocation;

    Widget listBody;
    if (uid != null && FirebaseService.isInitialized) {
      listBody = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseService.patientPdfReportsStream(uid),
        builder: (context, snap) {
          if (snap.hasError) {
            final err = snap.error.toString();
            final hint = err.contains('permission-denied')
                ? '\n\nFirestore rules are not published for safe-hair-274. '
                    'From mobile_app folder run: firebase deploy --only firestore:rules'
                : '';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error loading reports: $err$hint',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                ),
              ),
            );
          }
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return _EmptyReportsPrompt(onStart: () => context.go('/my-scans'));
          }

          final sorted = [...docs]..sort((a, b) {
              final ta = _reportCreatedAt(a.data()['createdAt']);
              final tb = _reportCreatedAt(b.data()['createdAt']);
              if (ta == null && tb == null) return 0;
              if (ta == null) return 1;
              if (tb == null) return -1;
              return tb.compareTo(ta);
            });

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final doc = sorted[i];
              final d = doc.data();
              final created = _reportCreatedAt(d['createdAt']);
              final avg = (d['averageScore'] as num?)?.toStringAsFixed(1) ?? '—';
              final line = created != null
                  ? '${DateFormat('d MMM y, HH:mm').format(created)} – Avg. score: $avg'
                  : 'Report ${doc.id.substring(0, 8)}… – Avg. score: $avg';
              return Material(
                color: const Color(0xFFF8F8F8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.push('/my-report/view/${doc.id}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            line,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/my-report/view/${doc.id}'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('View', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } else {
      listBody = _EmptyReportsPrompt(onStart: () => context.go('/my-scans'));
    }

    return PatientWebScaffold(
      currentRoute: route,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'My Reports',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                listBody,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyReportsPrompt extends StatelessWidget {
  const _EmptyReportsPrompt({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.description_outlined, size: 72, color: Color(0xFF7A7A7A)),
        const SizedBox(height: 14),
        const Text('No report yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black)),
        const SizedBox(height: 8),
        const Text(
          'Complete a scalp analysis or consultation to generate reports.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Color(0xFF5D5D5D)),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: onStart,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text('Start Scalp Analysis', style: TextStyle(fontSize: 14)),
        ),
      ],
    );
  }
}
