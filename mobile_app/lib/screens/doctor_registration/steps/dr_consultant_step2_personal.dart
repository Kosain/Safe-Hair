import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:provider/provider.dart';

import '../../../core/app_colors.dart';
import '../../../providers/doctor_registration_provider.dart';
import '../consultant_registration_ui.dart';

class DrConsultantStep2Personal extends StatefulWidget {
  const DrConsultantStep2Personal({super.key});

  @override
  State<DrConsultantStep2Personal> createState() => _DrConsultantStep2PersonalState();
}

class _DrConsultantStep2PersonalState extends State<DrConsultantStep2Personal> {
  late final TextEditingController _name;
  late final TextEditingController _cnic;
  late final TextEditingController _address;

  DateTime _defaultDob(DateTime now) {
    final y = now.year - 28;
    final d = now.day > 28 ? 28 : now.day;
    return DateTime(y, now.month, d);
  }

  Future<void> _pickDob(DoctorRegistrationProvider p) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: p.dob ?? _defaultDob(now),
      firstDate: DateTime(1940),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Select date of birth',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1A1A1A),
              primary: const Color(0xFF1A1A1A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (d != null) {
      p.dob = d;
      p.refresh();
    }
  }

  @override
  void initState() {
    super.initState();
    final p = context.read<DoctorRegistrationProvider>();
    _name = TextEditingController(text: p.fullName);
    _cnic = TextEditingController(text: p.cnic);
    _address = TextEditingController(text: p.address);
  }

  @override
  void dispose() {
    _name.dispose();
    _cnic.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DoctorRegistrationProvider>(
      builder: (context, p, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: consultantCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Personal details',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textDark, letterSpacing: -0.3),
                ),
                const SizedBox(height: 8),
                Text(
                  'We use this to verify your identity and show your name to patients.',
                  style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.textGrey.withValues(alpha: 0.92)),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _name,
                  onChanged: (v) => p.fullName = v,
                  style: const TextStyle(color: Colors.black),
                  decoration: consultantInputDecoration(label: 'Full name', errorText: p.fieldErrors['fullName']),
                ),
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _pickDob(p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.textDark.withValues(alpha: p.fieldErrors['dob'] != null ? 0.9 : 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF1A1A1A)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Date of birth',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark.withValues(alpha: 0.75),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p.dob == null ? 'Tap to select' : DateFormat('EEE, MMM d, y').format(p.dob!),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: p.dob == null ? AppColors.textGrey : AppColors.textDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.edit_calendar_outlined, size: 18, color: AppColors.textDark.withValues(alpha: 0.7)),
                      ],
                    ),
                  ),
                ),
                if (p.fieldErrors['dob'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(p.fieldErrors['dob']!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                const SizedBox(height: 14),
                IntlPhoneField(
                  key: const ValueKey<String>('consultant_phone_pk'),
                  style: const TextStyle(color: Colors.black),
                  dropdownTextStyle: const TextStyle(color: Colors.black),
                  initialCountryCode: 'PK',
                  decoration: consultantInputDecoration(label: 'Phone number', errorText: p.fieldErrors['phone']),
                  invalidNumberMessage: 'Invalid phone number',
                  onChanged: (ph) => p.phone = ph.completeNumber,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _cnic,
                  onChanged: (v) => p.cnic = v,
                  style: const TextStyle(color: Colors.black),
                  keyboardType: TextInputType.text,
                  decoration: consultantInputDecoration(
                    label: 'CNIC number',
                    hint: '#####-#######',
                    errorText: p.fieldErrors['cnic'],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _address,
                  onChanged: (v) => p.address = v,
                  style: const TextStyle(color: Colors.black),
                  maxLines: 4,
                  decoration: consultantInputDecoration(label: 'Address', errorText: p.fieldErrors['address']),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
