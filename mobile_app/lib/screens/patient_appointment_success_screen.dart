import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAF6),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE8E8E8)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 86,
                  height: 86,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2D3238),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.thumb_up, color: Colors.white, size: 38),
                ),
                const SizedBox(height: 18),
                const Text('Thank You!', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                const Text('Your Appointment Successful', style: TextStyle(fontSize: 28, color: Color(0xFF3C5BAA))),
                const SizedBox(height: 8),
                Text(
                  'You booked an appointment with $doctorName on $date at $time',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 26, color: Color(0xFF3C5BAA), height: 1.3),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.go('/my-appointments'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Done', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
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
                  child: const Text(
                    'Edit your appointment',
                    style: TextStyle(color: Color(0xFF6879A8), fontSize: 24),
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
