// import 'package:fl_chart/fl_chart.dart';
// import 'package:flutter/material.dart';

// class MyGraph extends StatefulWidget {
//   const MyGraph({
//     super.key,
//     required this.label,
//     required this.data,
//     required this.color,
//     required this.xLabels,
//     this.width,
//     this.height,
//   });

//   final double? width;
//   final double? height;
//   final String label;
//   final List<int> data;
//   final Color color;
//   final List<String> xLabels;

//   @override
//   State<MyGraph> createState() => _MyGraphState();
// }

// class _MyGraphState extends State<MyGraph> {
//   @override
//   Widget build(BuildContext context) {
//     final maxY = widget.data.isEmpty
//         ? 1.0
//         : widget.data.reduce((a, b) => a > b ? a : b).toDouble();
//     final interval = maxY ~/ 3 == 0 ? 1 : maxY ~/ 3;

//     return SizedBox(
//       width: widget.width,
//       height: widget.height,
//       child: LineChart(
//         LineChartData(
//           gridData: FlGridData(show: false),
//           titlesData: FlTitlesData(
//             leftTitles: AxisTitles(
//               sideTitles: SideTitles(showTitles: false),
//             ),
//             rightTitles: AxisTitles(
//               sideTitles: SideTitles(
//                 showTitles: true,
//                 reservedSize: 40,
//                 interval: interval.toDouble(),
//                 getTitlesWidget: (value, meta) => Text(
//                   value.toInt().toString(),
//                   style: const TextStyle(fontSize: 12),
//                 ),
//               ),
//             ),
//             topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false),),
//             bottomTitles: AxisTitles(
//               sideTitles: SideTitles(
//                 showTitles: true,
//                 interval: 1,
//                 getTitlesWidget: (value, _) {
//                   int index = value.toInt();
//                   if (index < 0 || index >= widget.xLabels.length) {
//                     return const SizedBox.shrink();
//                   }
//                   return Padding(
//                     padding: const EdgeInsets.only(top: 8.0),
//                     child: Text(
//                       widget.xLabels[index],
//                       style: const TextStyle(fontSize: 12),
//                     ),
//                   );
//                 },
//                 reservedSize: 36,
//               ),
//             ),
//           ),
//           borderData: FlBorderData(
//             show: true,
//             border: const Border(
//               bottom: BorderSide(color: Colors.grey),
//               right: BorderSide(color: Colors.grey),
//             ),
//           ),
//           lineBarsData: [
//             LineChartBarData(
//               spots: List.generate(
//                 widget.data.length,
//                 (i) => FlSpot(i.toDouble(), widget.data[i].toDouble(),),
//               ),
//               isCurved: true,
//               color: widget.color,
//               barWidth: 2.5,
//               dotData: FlDotData(show: true),
//               belowBarData: BarAreaData(
//                 show: true,
//                 color: widget.color.withOpacity(0.1),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
