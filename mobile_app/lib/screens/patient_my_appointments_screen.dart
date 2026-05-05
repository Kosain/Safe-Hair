import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/patient_web_scaffold.dart';

class PatientMyAppointmentsScreen extends StatefulWidget {
  const PatientMyAppointmentsScreen({super.key});

  @override
  State<PatientMyAppointmentsScreen> createState() => _PatientMyAppointmentsScreenState();
}

class _PatientMyAppointmentsScreenState extends State<PatientMyAppointmentsScreen> {
  int? _selectedIndex;

  static const _doctors = <(String id, String name, String clinic, String city, double rating, int fee)>[
    ('d1', 'Dr. Ayesha Khan', 'Safe Hair Clinic', 'Lahore', 4.8, 3000),
    ('d2', 'Dr. Bilal Ahmad', 'Hair Wellness Center', 'Islamabad', 4.6, 2500),
    ('d3', 'Dr. Sana Tariq', 'Derma Care Studio', 'Karachi', 4.9, 3500),
    ('d4', 'Dr. Hamza Noor', 'Scalp Expert Hub', 'Faisalabad', 4.5, 2200),
  ];

  @override
  Widget build(BuildContext context) {
    return PatientWebScaffold(
      currentRoute: GoRouterState.of(context).matchedLocation,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _selectedIndex == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 78),
              child: ElevatedButton(
                onPressed: () {
                  final d = _doctors[_selectedIndex!];
                  context.push(
                    '/my-appointments/book',
                    extra: {
                      'doctorId': d.$1,
                      'doctorName': d.$2,
                      'clinicName': d.$3,
                      'city': d.$4,
                    },
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFF176),
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                ),
                child: const Text('Book Appointment'),
              ),
            ),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('My Appointments', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _doctors.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final d = _doctors[index];
                    final selected = _selectedIndex == index;
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _selectedIndex = index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        constraints: const BoxConstraints(minHeight: 92, maxHeight: 112),
                        decoration: BoxDecoration(
                          color: selected ? const Color(0xFFF7F7F7) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected ? const Color(0xFF2E2E2E) : const Color(0xFFEAEAEA),
                            width: selected ? 1.5 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0x0A000000),
                              blurRadius: selected ? 14 : 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: const Color(0xFFECECEC),
                              child: Text(
                                d.$2[0],
                                style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.$2,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${d.$3} • ${d.$4}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      ...List.generate(
                                        5,
                                        (i) => Icon(
                                          Icons.star,
                                          size: 16,
                                          color: i < d.$5.round() ? Colors.amber : const Color(0xFFD0D0D0),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('${d.$5}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Consultation Fee: PKR ${d.$6}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
