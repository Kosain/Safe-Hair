import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/app_colors.dart';
import '../../../providers/doctor_registration_provider.dart';
import '../consultant_registration_ui.dart';
import '../doctor_registration_constants.dart';

class DrConsultantStep4Clinic extends StatefulWidget {
  const DrConsultantStep4Clinic({super.key});

  @override
  State<DrConsultantStep4Clinic> createState() => _DrConsultantStep4ClinicState();
}

class _DrConsultantStep4ClinicState extends State<DrConsultantStep4Clinic> {
  late final TextEditingController _clinicName;
  late final TextEditingController _addr;
  late final TextEditingController _fee;

  @override
  void initState() {
    super.initState();
    final p = context.read<DoctorRegistrationProvider>();
    _clinicName = TextEditingController(text: p.clinicName);
    _addr = TextEditingController(text: p.clinicAddress);
    _fee = TextEditingController(text: p.consultationFee > 0 ? '${p.consultationFee}' : '');
  }

  @override
  void dispose() {
    _clinicName.dispose();
    _addr.dispose();
    _fee.dispose();
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
                  'Clinic Details',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textDark, letterSpacing: -0.3),
                ),
                const SizedBox(height: 8),
                Text(
                  'Where you see patients and your consultation fee (PKR).',
                  style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.textGrey.withValues(alpha: 0.92)),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _clinicName,
                  onChanged: (v) => p.clinicName = v,
                  style: const TextStyle(color: Colors.black),
                  decoration: consultantInputDecoration(
                    label: 'Clinic / Hospital name',
                    hint: 'e.g. Safe Hair Clinic',
                    errorText: p.fieldErrors['clinicName'],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _addr,
                  onChanged: (v) => p.clinicAddress = v,
                  style: const TextStyle(color: Colors.black),
                  maxLines: 3,
                  decoration: consultantInputDecoration(
                    label: 'Clinic address',
                    errorText: p.fieldErrors['clinicAddress'],
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: p.city.isEmpty ? null : p.city,
                  style: const TextStyle(color: Colors.black),
                  decoration: consultantInputDecoration(label: 'City', errorText: p.fieldErrors['city']),
                  hint: Text('Select city', style: TextStyle(color: AppColors.textGrey.withValues(alpha: 0.9))),
                  dropdownColor: Colors.white,
                  isExpanded: true,
                  items: kPakistaniCities
                      .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(color: Colors.black))))
                      .toList(),
                  onChanged: (v) {
                    p.city = v ?? '';
                    p.refresh();
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _fee,
                  onChanged: (v) => p.consultationFee = int.tryParse(v.trim()) ?? 0,
                  style: const TextStyle(color: Colors.black),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: consultantInputDecoration(
                    label: 'Consultation fee (PKR)',
                    errorText: p.fieldErrors['consultationFee'],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
