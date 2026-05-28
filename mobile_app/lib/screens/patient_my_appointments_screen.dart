import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/safe_hair_colors.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/patient_web_scaffold.dart';

class _BookableDoctor {
  const _BookableDoctor({
    required this.id,
    required this.name,
    required this.clinic,
    required this.city,
    required this.rating,
    required this.reviewCount,
    required this.fee,
  });

  final String id;
  final String name;
  final String clinic;
  final String city;
  final double rating;
  final int reviewCount;
  final int fee;
}

class PatientMyAppointmentsScreen extends StatefulWidget {
  const PatientMyAppointmentsScreen({super.key});

  @override
  State<PatientMyAppointmentsScreen> createState() => _PatientMyAppointmentsScreenState();
}

class _PatientMyAppointmentsScreenState extends State<PatientMyAppointmentsScreen> {
  List<_BookableDoctor> _bookable = const [];
  bool _loadingDoctors = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBookableDoctors());
  }

  Future<void> _loadBookableDoctors() async {
    if (!FirebaseService.isInitialized) {
      if (mounted) {
        setState(() {
          _bookable = const [];
          _loadingDoctors = false;
        });
      }
      return;
    }
    setState(() => _loadingDoctors = true);
    try {
      final uid = context.read<AuthProvider>().userId;
      final rows = await FirebaseService.getDoctorsForPatientBookingOnce(patientUserId: uid);
      if (!mounted) return;
      final doctorIds = <String>[];
      for (final r in rows) {
        final id = (r['id'] ?? r['userId'] ?? r['user_id'] ?? '').toString().trim();
        if (id.isNotEmpty) doctorIds.add(id);
      }
      final ratingSummaries = await FirebaseService.getDoctorRatingSummaries(doctorIds);
      if (!mounted) return;
      final mapped = <_BookableDoctor>[];
      for (final r in rows) {
        final id = (r['id'] ?? r['userId'] ?? r['user_id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final name = (r['fullName'] ?? r['name'] ?? 'Doctor').toString().trim();
        final clinic = (r['clinicName'] ?? r['clinic_name'] ?? '').toString().trim();
        final city = (r['city'] ?? '').toString().trim();
        final feeRaw = r['consultationFee'] ?? r['consultation_fee'];
        final fee = feeRaw == null
            ? 0
            : (feeRaw is num ? feeRaw.toInt() : int.tryParse(feeRaw.toString()) ?? 0);
        final summary = ratingSummaries[id] ?? const DoctorRatingSummary(average: 0, count: 0);
        mapped.add(
          _BookableDoctor(
            id: id,
            name: name.isEmpty ? 'Doctor' : name,
            clinic: clinic.isEmpty ? 'Clinic' : clinic,
            city: city.isEmpty ? '' : city,
            rating: summary.hasReviews ? summary.average : 0,
            reviewCount: summary.count,
            fee: fee,
          ),
        );
      }
      setState(() {
        _bookable = mapped;
        _loadingDoctors = false;
      });
    } on FirebaseException catch (e) {
      debugPrint('_loadBookableDoctors: ${e.code} ${e.message}');
      if (mounted) {
        setState(() {
          _bookable = const [];
          _loadingDoctors = false;
        });
      }
    } catch (e, st) {
      debugPrint('_loadBookableDoctors: $e\n$st');
      FirebaseService.lastDoctorsListError = 'Could not load doctors: $e';
      if (mounted) {
        setState(() {
          _bookable = const [];
          _loadingDoctors = false;
        });
      }
    }
  }

  void _openBook(_BookableDoctor d) {
    context.push(
      '/my-appointments/book',
      extra: {
        'doctorId': d.id,
        'doctorName': d.name,
        'clinicName': d.clinic,
        'city': d.city,
        'consultationFeePkr': d.fee,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthProvider>().userId;
    final canStream = FirebaseService.isInitialized && uid != null && uid.isNotEmpty;

    final sh = context.sh;
    return PatientWebScaffold(
      currentRoute: GoRouterState.of(context).matchedLocation,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (uid != null && uid.isNotEmpty && FirebaseService.isInitialized) _UpcomingAppointmentsCard(userId: uid),
                if (canStream) const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: sh.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sh.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Book a doctor', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: sh.textPrimary)),
                          ),
                          if (canStream)
                            TextButton.icon(
                              onPressed: _loadingDoctors ? null : _loadBookableDoctors,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Refresh'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        canStream
                            ? 'Choose a doctor, then pick date and time on the next screen. Slots already taken are disabled.'
                            : 'Sign in to save bookings to your account and see them above.',
                        style: TextStyle(fontSize: 13, color: sh.textSecondary, height: 1.35),
                      ),
                      const SizedBox(height: 16),
                      if (_loadingDoctors)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))),
                        )
                      else if (_bookable.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            canStream
                                ? (FirebaseService.lastDoctorsListError ??
                                    'No doctors available to book yet. Ask your doctor to sign in, finish all 6 registration steps, and save on the last step — then tap Refresh.')
                                : 'Enable Firebase and sign in to load doctors you can book.',
                            style: TextStyle(fontSize: 13, color: sh.textSecondary, height: 1.4),
                          ),
                        )
                      else
                        ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _bookable.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final d = _bookable[index];
                          return Material(
                            color: sh.sidebarSelectedBg,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _openBook(d),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                constraints: const BoxConstraints(minHeight: 92),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: sh.border),
                                  boxShadow: const [
                                    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: const Color(0xFFECECEC),
                                      child: Text(
                                        d.name.replaceFirst(RegExp(r'^Dr\.\s*', caseSensitive: false), '').isNotEmpty
                                            ? d.name.replaceFirst(RegExp(r'^Dr\.\s*', caseSensitive: false), '')[0]
                                            : 'D',
                                        style: TextStyle(fontWeight: FontWeight.w700, color: sh.textPrimary),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            d.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: sh.textPrimary),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${d.clinic} • ${d.city}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 13, color: sh.textSecondary),
                                          ),
                                          const SizedBox(height: 3),
                                          if (d.reviewCount > 0)
                                            Row(
                                              children: [
                                                ...List.generate(
                                                  5,
                                                  (i) => Icon(
                                                    Icons.star,
                                                    size: 16,
                                                    color: i < d.rating.round().clamp(0, 5)
                                                        ? Colors.amber
                                                        : sh.border,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '${d.rating.toStringAsFixed(1)} (${d.reviewCount})',
                                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sh.textPrimary),
                                                ),
                                              ],
                                            )
                                          else
                                            Text(
                                              'No reviews yet',
                                              style: TextStyle(fontSize: 12, color: sh.textSecondary),
                                            ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Consultation Fee: PKR ${d.fee}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sh.textPrimary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () => _openBook(d),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFFFF176),
                                        foregroundColor: Colors.black87,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      ),
                                      child: const Text('Book', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpcomingAppointmentsCard extends StatelessWidget {
  const _UpcomingAppointmentsCard({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: sh.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: sh.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your upcoming appointments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: sh.textPrimary)),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseService.getAppointments(userId),
            builder: (context, snap) {
              if (snap.hasError) {
                final err = snap.error.toString();
                final extra = err.contains('permission-denied')
                    ? ' Publish Firestore rules: firebase deploy --only firestore:rules'
                    : '';
                return Text(
                  'Could not load appointments.$extra',
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                );
              }
              final docs = snap.data!.docs.toList();
              docs.sort((a, b) {
                final ad = (a.data()['createdAt'] ?? a.data()['created_at'] ?? '').toString();
                final bd = (b.data()['createdAt'] ?? b.data()['created_at'] ?? '').toString();
                return bd.compareTo(ad);
              });
              if (docs.isEmpty) {
                return Text(
                  'No saved appointments yet. Book a doctor below.',
                  style: TextStyle(fontSize: 13, color: sh.textSecondary),
                );
              }
              return Column(
                children: docs.take(8).map((doc) {
                  final m = doc.data();
                  final doctor = (m['doctorName'] ?? m['doctor_name'] ?? 'Doctor').toString();
                  final date = (m['date'] ?? m['day'] ?? '').toString();
                  final time = (m['timeSlot'] ?? m['time_slot'] ?? '').toString();
                  final statusRaw = (m['status'] ?? 'confirmed').toString().toLowerCase();
                  final statusLabel = statusRaw.isEmpty
                      ? 'Confirmed'
                      : '${statusRaw[0].toUpperCase()}${statusRaw.length > 1 ? statusRaw.substring(1) : ''}';
                  final Color statusColor;
                  if (statusRaw == 'cancelled' || statusRaw == 'declined') {
                    statusColor = Colors.red.shade700;
                  } else if (statusRaw == 'pending') {
                    statusColor = Colors.deepOrange.shade800;
                  } else {
                    statusColor = Colors.green.shade800;
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: sh.sidebarSelectedBg,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        dense: true,
                        title: Text(doctor, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: sh.textPrimary)),
                        subtitle: Text(
                          '$date • $time',
                          style: TextStyle(fontSize: 12, color: sh.textSecondary),
                        ),
                        trailing: Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
