// import 'package:blob/widgets/hoverable_card.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../../brand_profile_draft.dart';

// class PlatformStep extends StatelessWidget {
//   final VoidCallback onNext;
//   const PlatformStep({super.key, required this.onNext});
//   @override
//   Widget build(BuildContext context) {
//     final d = context.watch<BrandProfileDraft>();
//     const p = [
//       'LinkedIn Pages',
//       'linkedin',
//       'Instagram',
//       'Facebook',
//       'X',
//       'YouTube',
//       'TikTok',
//       'Skip for now'
//     ];
//     return LayoutBuilder(
//       builder: (_, c) => Center(
//         child: SingleChildScrollView(
//           padding: EdgeInsets.all(
//             c.maxWidth * .0125,
//           ),
//           child: Column(
//             children: [
//               const Text(
//                 'First platform to connect',
//                 style: TextStyle(
//                   fontSize: 24,
//                 ),
//               ),
//               const SizedBox(
//                 height: 32,
//               ),
//               Wrap(
//                 spacing: 16,
//                 runSpacing: 16,
//                 alignment: WrapAlignment.center,
//                 children: [
//                   ...p.map(
//                     (e) => Padding(
//                       padding: const EdgeInsets.only(
//                         bottom: 12,
//                       ),
//                       child: HoverableCard(
//                         fatherProperty: 'platform',
//                         property: e,
//                         onTap: () {
//                           d.firstPlatform = e;
//                           d.notify();
//                           onNext();
//                         },
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
