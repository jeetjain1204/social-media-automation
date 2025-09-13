import 'package:flutter/material.dart';
import 'package:blob/utils/my_snack_bar.dart';
import 'package:blob/utils/colors.dart'; // uses: darkColor, lightColor

DateTime roundUpToNextQuarter(DateTime t) {
  final add = (15 - (t.minute % 15)) % 15;
  final next = t.add(Duration(minutes: add));
  return DateTime(next.year, next.month, next.day, next.hour, next.minute);
}

bool isSameYmd(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

DateTime asDateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

ThemeData pickerTheme(BuildContext context) {
  final base = Theme.of(context);
  final scheme = const ColorScheme.light().copyWith(
    primary: darkColor,
    secondary: lightColor,
    surface: lightColor,
    onPrimary: lightColor, // text/icons on dark headers
    onSecondary: darkColor, // text/icons on light accents
    onSurface: darkColor, // general text on surfaces
  );

  return base.copyWith(
    useMaterial3: true,
    colorScheme: scheme,
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: MaterialStatePropertyAll(darkColor),
        overlayColor: MaterialStatePropertyAll(darkColor.withOpacity(0.08)),
        textStyle: const MaterialStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: lightColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      headerBackgroundColor: darkColor,
      headerForegroundColor: lightColor,
      dayOverlayColor: MaterialStatePropertyAll(lightColor.withOpacity(0.15)),
      todayForegroundColor: const MaterialStatePropertyAll(darkColor),
      todayBackgroundColor: MaterialStatePropertyAll(
        darkColor.withOpacity(0.12),
      ),
    ),
    timePickerTheme: TimePickerThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: lightColor,
      dialBackgroundColor: lightColor.withOpacity(0.10),
      dialHandColor: darkColor,
      entryModeIconColor: darkColor,
      hourMinuteTextStyle: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: darkColor,
      ),
      helpTextStyle: TextStyle(color: darkColor),
    ),
  );
}

Future<DateTime?> showFutureDateTimePicker(BuildContext context) async {
  final now = DateTime.now();
  final roundedNow = roundUpToNextQuarter(now);

  final firstDate = asDateOnly(now);
  final lastDate = asDateOnly(now.add(const Duration(days: 365)));

  final initialDate = firstDate.isAfter(now)
      ? firstDate
      : (now.isAfter(lastDate) ? lastDate : now);

  // Date
  final date = await showDatePicker(
    context: context,
    initialDate: asDateOnly(initialDate),
    firstDate: firstDate,
    lastDate: lastDate,
    builder: (ctx, child) => Theme(data: pickerTheme(ctx), child: child!),
  );

  if (date == null) {
    if (context.mounted) mySnackBar(context, 'Please select a date');
    return null;
  }

  final isToday = isSameYmd(date, now);
  if (!context.mounted) return null;

  // Time
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(
      isToday ? roundedNow : DateTime(date.year, date.month, date.day, 9, 0),
    ),
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
      child: Theme(data: pickerTheme(ctx), child: child!),
    ),
  );

  if (time == null) {
    if (context.mounted) mySnackBar(context, 'Please select a time');
    return null;
  }

  final roundedMinuteInput = (time.minute ~/ 15) * 15;
  final selected = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    roundedMinuteInput,
  );

  if (selected.isBefore(roundedNow)) {
    if (context.mounted) mySnackBar(context, 'Please select a future time');
    return null;
  }

  return selected;
}
