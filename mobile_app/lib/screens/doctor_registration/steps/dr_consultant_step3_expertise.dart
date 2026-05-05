import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/app_colors.dart';
import '../../../providers/doctor_registration_provider.dart';
import '../consultant_registration_ui.dart';
import '../doctor_registration_constants.dart';

class DrConsultantStep3Expertise extends StatefulWidget {
  const DrConsultantStep3Expertise({super.key});

  @override
  State<DrConsultantStep3Expertise> createState() => _DrConsultantStep3ExpertiseState();
}

class _DrConsultantStep3ExpertiseState extends State<DrConsultantStep3Expertise> {
  late final TextEditingController _qual;
  late final TextEditingController _otherSpec;
  late final TextEditingController _reg;
  late final TextEditingController _years;

  @override
  void initState() {
    super.initState();
    final p = context.read<DoctorRegistrationProvider>();
    _qual = TextEditingController(text: p.qualification);
    _otherSpec = TextEditingController(text: p.specializationOther);
    _reg = TextEditingController(text: p.registrationNumber);
    _years = TextEditingController(text: p.yearsExperience > 0 ? '${p.yearsExperience}' : '');
  }

  @override
  void dispose() {
    _qual.dispose();
    _otherSpec.dispose();
    _reg.dispose();
    _years.dispose();
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
                  'Consultant expertise',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textDark, letterSpacing: -0.3),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tell patients about your training and focus areas.',
                  style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.textGrey.withValues(alpha: 0.92)),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _qual,
                  onChanged: (v) => p.qualification = v,
                  style: const TextStyle(color: Colors.black),
                  maxLines: 3,
                  decoration: consultantInputDecoration(
                    label: 'Qualification',
                    hint: 'e.g. MBBS, FCPS, MD',
                    errorText: p.fieldErrors['qualification'],
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: p.specialization.isEmpty ? null : p.specialization,
                  style: const TextStyle(color: Colors.black),
                  decoration: consultantInputDecoration(label: 'Specialization', errorText: p.fieldErrors['specialization']),
                  hint: Text('Select specialization', style: TextStyle(color: AppColors.textGrey.withValues(alpha: 0.9))),
                  dropdownColor: Colors.white,
                  isExpanded: true,
                  menuMaxHeight: 320,
                  items: kConsultantSpecializations
                      .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(color: Colors.black))))
                      .toList(),
                  onChanged: (v) {
                    p.specialization = v ?? '';
                    p.refresh();
                  },
                ),
                if (p.specialization == 'Other') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _otherSpec,
                    onChanged: (v) => p.specializationOther = v,
                    style: const TextStyle(color: Colors.black),
                    decoration: consultantInputDecoration(
                      label: 'Specify specialization',
                      errorText: p.fieldErrors['specializationOther'],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _reg,
                  onChanged: (v) => p.registrationNumber = v,
                  style: const TextStyle(color: Colors.black),
                  decoration: consultantInputDecoration(
                    label: 'Registration / license number',
                    errorText: p.fieldErrors['registrationNumber'],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _years,
                  onChanged: (v) => p.yearsExperience = int.tryParse(v.trim()) ?? 0,
                  style: const TextStyle(color: Colors.black),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: consultantInputDecoration(
                    label: 'Years of experience',
                    hint: 'e.g. 5',
                    errorText: p.fieldErrors['yearsExperience'],
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
