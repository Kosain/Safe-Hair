import 'package:flutter/material.dart';

import '../core/safe_hair_colors.dart';
import '../services/firebase_service.dart';

/// Shows star rating + comment for a completed appointment.
Future<bool?> showDoctorReviewDialog(
  BuildContext context, {
  required PendingDoctorReview pending,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _DoctorReviewDialog(pending: pending),
  );
}

class _DoctorReviewDialog extends StatefulWidget {
  const _DoctorReviewDialog({required this.pending});

  final PendingDoctorReview pending;

  @override
  State<_DoctorReviewDialog> createState() => _DoctorReviewDialogState();
}

class _DoctorReviewDialogState extends State<_DoctorReviewDialog> {
  int _stars = 0;
  final _commentController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a star rating.')),
      );
      return;
    }
    setState(() => _submitting = true);
    final ok = await FirebaseService.submitDoctorReview(
      appointmentId: widget.pending.appointmentId,
      doctorId: widget.pending.doctorId,
      patientUserId: widget.pending.patientUserId,
      stars: _stars,
      comment: _commentController.text.trim(),
      doctorName: widget.pending.doctorName,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thank you for your review!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not submit review. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sh = context.sh;
    return AlertDialog(
      backgroundColor: sh.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Rate your visit',
        style: TextStyle(color: sh.textPrimary, fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How was your appointment with ${widget.pending.doctorName}?',
              style: TextStyle(color: sh.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final filled = i < _stars;
                return IconButton(
                  onPressed: _submitting ? null : () => setState(() => _stars = i + 1),
                  icon: Icon(
                    filled ? Icons.star_rounded : Icons.star_border_rounded,
                    color: Colors.amber,
                    size: 36,
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commentController,
              maxLines: 4,
              enabled: !_submitting,
              style: TextStyle(color: sh.textPrimary),
              decoration: InputDecoration(
                labelText: 'Comments (optional)',
                labelStyle: TextStyle(color: sh.textSecondary),
                filled: true,
                fillColor: sh.scaffold,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: sh.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: sh.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: sh.textPrimary, width: 1.2),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: Text('Not now', style: TextStyle(color: sh.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: sh.selectedNavBg,
            foregroundColor: sh.selectedNavFg,
          ),
          child: _submitting
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: sh.selectedNavFg),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }
}
