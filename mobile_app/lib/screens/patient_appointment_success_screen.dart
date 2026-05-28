import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/safe_hair_colors.dart';
import '../widgets/patient_web_scaffold.dart';

class PatientAppointmentSuccessScreen extends StatelessWidget {
  const PatientAppointmentSuccessScreen({
    super.key,
    required this.doctorName,
    required this.date,
    required this.time,
    this.doctorId,
    this.reminder,
  });

  final String doctorName;
  final String date;
  final String time;
  final String? doctorId;
  final String? reminder;

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    final route = GoRouterState.of(context).matchedLocation;
    return PatientWebScaffold(
      currentRoute: route,
      extraScrollBottomPadding: 80,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                onPressed: () => context.go('/my-appointments'),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
              ),
              const Expanded(
                child: Text(
                  'Request sent',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                decoration: BoxDecoration(
                  color: sh.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sh.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2D3238),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.thumb_up, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 16),
                    Text('Thank you!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: sh.textPrimary)),
                    const SizedBox(height: 8),
                    Text(
                      'Waiting for the doctor to confirm',
                      style: TextStyle(fontSize: 15, color: sh.textPrimary, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'We sent your request to $doctorName for $date at $time${(reminder ?? '').isNotEmpty ? ' (reminder $reminder before)' : ''}. You will get an in-app update when they respond.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: sh.textSecondary, height: 1.35),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => context.go('/my-appointments'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: sh.selectedNavBg,
                          foregroundColor: sh.selectedNavFg,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Back to appointments', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        context.go(
                          '/my-appointments/book',
                          extra: {
                            'doctorName': doctorName,
                            'doctorId': doctorId,
                          },
                        );
                      },
                      child: Text(
                        'Book another time',
                        style: TextStyle(color: sh.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
