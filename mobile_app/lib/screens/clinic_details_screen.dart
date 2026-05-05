import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';

const _pkCities = <String>[
  'Karachi',
  'Lahore',
  'Islamabad',
  'Rawalpindi',
  'Faisalabad',
  'Multan',
  'Peshawar',
  'Quetta',
  'Hyderabad',
  'Gujranwala',
  'Sialkot',
  'Bahawalpur',
  'Sargodha',
  'Sukkur',
  'Larkana',
  'Abbottabad',
  'Mardan',
  'Other',
];

class ClinicDetailsScreen extends StatefulWidget {
  const ClinicDetailsScreen({super.key});

  @override
  State<ClinicDetailsScreen> createState() => _ClinicDetailsScreenState();
}

class _ClinicDetailsScreenState extends State<ClinicDetailsScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _fee = TextEditingController();

  String _city = 'Karachi';

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _fee.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = context.read<AuthProvider>().userId;
    if (uid == null || !FirebaseService.isInitialized) {
      setState(() => _loading = false);
      return;
    }
    final d = await FirebaseService.getDoctorProfile(uid);
    if (!mounted) return;
    if (d != null) {
      _name.text = (d['clinicName'] ?? d['fullName'] ?? '').toString();
      _address.text = (d['clinicAddress'] ?? d['address'] ?? '').toString();
      _phone.text = (d['clinicPhone'] ?? d['phone'] ?? '').toString();
      final feeRaw = d['consultationFeePkr'];
      if (feeRaw != null) {
        _fee.text = feeRaw is num ? feeRaw.toString() : feeRaw.toString();
      }
      final c = d['clinicCity']?.toString().trim();
      if (c != null && c.isNotEmpty && _pkCities.contains(c)) {
        _city = c;
      }
    }
    setState(() => _loading = false);
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.black, width: 1.2),
      ),
    );
  }

  Future<void> _save() async {
    final uid = context.read<AuthProvider>().userId;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You must be signed in.')));
      return;
    }
    if (!FirebaseService.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Firebase is not available.')));
      return;
    }

    int? feeParsed;
    final feeStr = _fee.text.trim();
    if (feeStr.isNotEmpty) {
      feeParsed = int.tryParse(feeStr.replaceAll(',', ''));
      if (feeParsed == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Consultation fee must be a valid number.')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    final ok = await FirebaseService.saveDoctorProfile({
      'userId': uid,
      'clinicName': _name.text.trim(),
      'clinicAddress': _address.text.trim(),
      'clinicCity': _city,
      'clinicPhone': _phone.text.trim(),
      if (feeParsed != null) 'consultationFeePkr': feeParsed,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clinic details updated')),
      );
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FirebaseService.lastDoctorProfileSaveError ?? 'Could not save. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
        ),
        title: const Text(
          'Clinic Details',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 19),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _name,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
                          decoration: _fieldDecoration('Clinic / Hospital Name'),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _address,
                          minLines: 3,
                          maxLines: 5,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
                          decoration: _fieldDecoration('Clinic Address'),
                        ),
                        const SizedBox(height: 14),
                        InputDecorator(
                          decoration: _fieldDecoration('City'),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              borderRadius: BorderRadius.circular(8),
                              value: _pkCities.contains(_city) ? _city : 'Karachi',
                              items: _pkCities
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _city = v);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
                          decoration: _fieldDecoration('Clinic Phone Number'),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _fee,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
                          decoration: _fieldDecoration('Consultation Fee (PKR)'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                ),
              ],
            ),
    );
  }
}
