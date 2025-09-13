import 'dart:async';
import 'dart:io';

import 'package:blob/widgets/auto_skeleton.dart';
import 'package:blob/widgets/my_button.dart';
import 'package:blob/utils/my_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:retry/retry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SelectPages extends StatefulWidget {
  const SelectPages({
    super.key,
    required this.platform,
    this.accessToken,
    this.personUrn,
    this.nonce,
    this.pages,
  });

  final String platform;
  final String? accessToken;
  final String? personUrn;
  final String? nonce;
  final List<Map<String, dynamic>>? pages;

  @override
  State<SelectPages> createState() => _SelectPagesState();
}

class _SelectPagesState extends State<SelectPages> {
  final supabase = Supabase.instance.client;

  // OPT: Avoid 'late' + race-by-build; initialize with empty list and gate on isLoading.

  List<Map<String, dynamic>> pages = const [];
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    // OPT: Defer IO until after first frame so the screen paints faster (LCP win).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.platform == 'linkedin') {
        loadLinkedInPages();
      } else {
        // META branch: data already passed via navigation extras
        setState(() {
          pages = List<Map<String, dynamic>>.from(widget.pages ?? const []);
          isLoading = false;
        });
      }
    });
  }

  Future<void> loadLinkedInPages() async {
    try {
      final res = await retry(
        // OPT: Add network timeout to avoid hangs; keep attempts small with jittered backoff.
        () => supabase.functions.invoke(
          'get-linkedin-pages',
          body: {'access_token': widget.accessToken},
        ).timeout(const Duration(seconds: 15)),
        retryIf: (e) => e is SocketException || e is TimeoutException,
        maxAttempts: 3,
        delayFactor: const Duration(milliseconds: 450), // OPT: modest backoff
      );

      final data = res.data;
      final list = (data is Map<String, dynamic> ? data['pages'] : null)
          as List<dynamic>?;
      if (!mounted) return;

      setState(() {
        pages = List<Map<String, dynamic>>.from(list ?? const []);
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        pages = const [];
      });
      mySnackBar(context, 'Unable to fetch LinkedIn pages');
    }
  }

  Future<void> saveLinkedIn(Map p) async {
    await store(
      fn: 'store-selected-page',
      body: {
        'organization_urn': p['organizationUrn'],
        'page_name': p['name'],
        'access_token': widget.accessToken,
      },
    );
  }

  Future<void> saveLinkedInPersonal() async {
    await store(
      fn: 'store-selected-page',
      body: {
        'organization_urn': widget.personUrn ?? '',
        'access_token': widget.accessToken,
        'account_type': 'personal',
      },
    );
  }

  Future<void> saveMeta(Map p) async {
    if (isSaving) return; // OPT: Debounce double taps.
    setState(() => isSaving = true);

    try {
      final res = await retry(
        () => supabase.functions.invoke(
          'redeem-meta-token',
          body: {
            'nonce': widget.nonce,
            'selectedPage': {
              'page_id': p['page_id'],
              'page_name': p['page_name'],
              'ig_user_id': p['ig_user_id'],
            },
          },
        ).timeout(const Duration(seconds: 20)),
        retryIf: (e) => e is SocketException || e is TimeoutException,
        maxAttempts: 3,
        delayFactor: const Duration(milliseconds: 500),
      );

      if (!mounted) return;

      if (res.status == 200) {
        context.go('/home');
      } else {
        setState(() => isSaving = false);
        mySnackBar(
          context,
          res.data is Map
              ? (res.data['error'] ?? 'Save failed')
              : 'Save failed',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isSaving = false);
      mySnackBar(context, 'Save failed: $e');
    }
  }

  Future<void> store({required String fn, required Map body}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) context.push('/login');
      return;
    }

    if (isSaving) return; // OPT: Debounce
    setState(() => isSaving = true);

    try {
      final res = await retry(
        () => supabase.functions.invoke(fn, body: {
          ...body,
          'user_id': uid
        }).timeout(const Duration(seconds: 20)),
        retryIf: (e) => e is SocketException || e is TimeoutException,
        maxAttempts: 3,
        delayFactor: const Duration(milliseconds: 500),
      );

      if (!mounted) return;

      if (res.status == 200) {
        context.go('/home');
      } else {
        setState(() => isSaving = false);
        // OPT: Defensive message extraction
        final msg = res.data is Map
            ? (res.data['error'] ?? 'Save failed')
            : 'Save failed';
        mySnackBar(context, msg);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isSaving = false);
      mySnackBar(context, 'Save failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    final title = switch (widget.platform) {
      'linkedin' => 'Select LinkedIn Page',
      'facebook' => 'Select Facebook Page',
      'instagram' => 'Select Instagram Business Account',
      _ => 'Select Page',
    };
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(title, style: const TextStyle(color: Color(0xFF1A1A1A))),
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: AutoSkeleton(
        enabled: isLoading,
        preserveSize: true,
        clipPadding: const EdgeInsets.symmetric(vertical: 24),
        child: pages.isEmpty
            ? const Center(
                child: Text(
                  'No eligible pages found',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            : ListView.builder(
                padding: EdgeInsets.symmetric(
                  horizontal: width * 0.04,
                  vertical: 24,
                ),
                itemCount: pages.length,
                itemBuilder: (_, i) {
                  final p = pages[i];
                  final hasIg = p['ig_user_id'] != null;
                  final name = p['page_name'] ?? p['name'] ?? '';
                  final subText = widget.platform == 'linkedin'
                      ? (p['organizationUrn'] ?? '')
                      : (hasIg ? 'Instagram linked' : 'No Instagram',);

                  return _PageRow(
                    name: name,
                    subText: subText,
                    subTextIsPositive: widget.platform != 'linkedin' && hasIg,
                    isSaving: isSaving,
                    onSelect: isSaving
                        ? null
                        : () => switch (widget.platform) {
                              'linkedin' => saveLinkedIn(p),
                              'facebook' => saveMeta(p),
                              'instagram' => saveMeta(p),
                              _ => null,
                            },
                  );
                },
              ),
      ),
      floatingActionButton:
          widget.platform == 'linkedin' && widget.personUrn != null
              ? FloatingActionButton.extended(
                  backgroundColor: const Color(0xFF2fb2ff),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  onPressed: isSaving ? null : saveLinkedInPersonal,
                  label: const Text('Use Personal Profile'),
                  icon: const Icon(Icons.person),
                )
              : null,
    );
  }
}

class _PageRow extends StatelessWidget {
  const _PageRow({
    required this.name,
    required this.subText,
    required this.subTextIsPositive,
    required this.isSaving,
    required this.onSelect,
  });

  final String name;
  final String subText;
  final bool subTextIsPositive;
  final bool isSaving;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            color: Color(0x11000000),
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Page name and info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis, // OPT: Prevent layout thrash
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subText,
                  overflow: TextOverflow.ellipsis, // OPT: Prevent layout thrash
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color:
                        subTextIsPositive ? Colors.green : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          MyButton(
            width: 120,
            height: 40,
            isLoading: isSaving,
            text: 'Select',
            onTap: onSelect,
          ),
        ],
      ),
    );
  }
}
