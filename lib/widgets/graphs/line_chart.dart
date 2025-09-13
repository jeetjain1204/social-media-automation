// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';

// class MyLineChart extends StatelessWidget {
//   const MyLineChart({
//     super.key,
//     required this.xLabels,
//     required this.yValues,
//     this.title,
//     this.lineColor = const Color.fromRGBO(0, 47, 110, 1),
//     this.dotColor = const Color.fromRGBO(0, 47, 110, 1),
//     this.fillColor = const Color.fromRGBO(47, 178, 255, 1),
//     this.maxY,
//     this.minY,
//   });

//   final List<String> xLabels;
//   final List<double> yValues;
//   final Color lineColor;
//   final Color dotColor;
//   final Color fillColor;
//   final String? title;
//   final double? maxY;
//   final double? minY;

//   @override
//   Widget build(BuildContext context) {
//     final double resolvedMinY = minY ?? 0;
//     final double resolvedMaxY =
//         maxY ?? (yValues.reduce((a, b) => a > b ? a : b) + 2);

//     return Padding(
//       padding: const EdgeInsets.all(16),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           if (title != null)
//             Padding(
//               padding: const EdgeInsets.only(bottom: 12),
//               child: Text(
//                 title!,
//                 style: const TextStyle(
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                   color: Color(0xFF002D72),
//                 ),
//               ),
//             ),
//           AspectRatio(
//             aspectRatio: 1.7,
//             child: LineChart(
//               curve: Curves.easeInOut,
//               duration: Duration(milliseconds: 400),
//               LineChartData(
//                 gridData: FlGridData(show: false),
//                 titlesData: FlTitlesData(
//                   leftTitles: AxisTitles(
//                     sideTitles: SideTitles(showTitles: true, reservedSize: 40),
//                   ),
//                   bottomTitles: AxisTitles(
//                     sideTitles: SideTitles(
//                       showTitles: true,
//                       interval: 1,
//                       getTitlesWidget: (value, meta) {
//                         int index = value.toInt();
//                         return Padding(
//                           padding: const EdgeInsets.only(top: 8),
//                           child: Text(
//                             index >= 0 && index < xLabels.length
//                                 ? xLabels[index]
//                                 : '',
//                             style: const TextStyle(
//                               fontSize: 12,
//                               color: Color(0xFF002D72),
//                             ),
//                           ),
//                         );
//                       },
//                     ),
//                   ),
//                   topTitles: AxisTitles(
//                     sideTitles: SideTitles(showTitles: false),
//                   ),
//                   rightTitles: AxisTitles(
//                     sideTitles: SideTitles(showTitles: false),
//                   ),
//                 ),
//                 borderData: FlBorderData(show: false),
//                 minX: 0,
//                 maxX: (xLabels.length - 1).toDouble(),
//                 minY: resolvedMinY,
//                 maxY: resolvedMaxY,
//                 lineTouchData: LineTouchData(
//                   touchTooltipData: LineTouchTooltipData(
//                     fitInsideHorizontally: true,
//                     fitInsideVertically: true,
//                     getTooltipItems: (touchedSpots) {
//                       return touchedSpots.map((touchedSpot) {
//                         return LineTooltipItem(
//                           '${touchedSpot.y}',
//                           TextStyle(
//                             color: Colors.white,
//                             fontWeight: FontWeight.bold,
//                             fontSize: 14,
//                           ),
//                         );
//                       }).toList();
//                     },
//                   ),
//                 ),
//                 lineBarsData: [
//                   LineChartBarData(
//                     spots: [
//                       for (int i = 0; i < yValues.length; i++)
//                         FlSpot(i.toDouble(), yValues[i]),
//                     ],
//                     isCurved: true,
//                     curveSmoothness: 0.25,
//                     color: lineColor,
//                     barWidth: 4,
//                     dotData: FlDotData(
//                       show: true,
//                       getDotPainter: (spot, percent, bar, index) {
//                         return FlDotCirclePainter(
//                           color: dotColor,
//                           strokeWidth: 2,
//                           strokeColor: Colors.white,
//                           radius: 8,
//                         );
//                       },
//                     ),
//                     belowBarData: BarAreaData(
//                       show: true,
//                       color: fillColor.withOpacity(0.2),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
