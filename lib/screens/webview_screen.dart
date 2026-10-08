import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../widgets/bet_panel.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _web;
  int _progress = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onPageStarted: (_) => setState(() => _failed = false),
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) setState(() => _failed = true);
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<bool> _goBackInWeb() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (!await _goBackInWeb()) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.page,
        appBar: AppBar(
          backgroundColor: AppColors.header,
          foregroundColor: Colors.white,
          title: Text(widget.title,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _web.reload(),
            ),
          ],
          bottom: _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(
                    value: _progress / 100,
                    minHeight: 3,
                    backgroundColor: Colors.transparent,
                    color: AppColors.green,
                  ),
                )
              : null,
        ),
        body: _failed
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        color: Colors.white54, size: 56),
                    const SizedBox(height: 12),
                    const Text('Unable to load the page',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.green),
                      onPressed: () => _web.reload(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : WebViewWidget(controller: _web),
      ),
    );
  }
}
