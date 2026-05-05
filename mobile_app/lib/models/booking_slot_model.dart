class BookingSlotModel {
  final String consultantId;
  final DateTime date;
  final String timeSlot;

  const BookingSlotModel({
    required this.consultantId,
    required this.date,
    required this.timeSlot,
  });

  Map<String, dynamic> toJson() => {
        'consultantId': consultantId,
        'date': date.toIso8601String(),
        'timeSlot': timeSlot,
      };
}
