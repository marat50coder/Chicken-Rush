// PortalDeck — hosts a WebView showing the backend-decided URL.
//
// Behaviour:
//   • uses the sealed BrowserMarker UA;
//   • injects the three sealed JS enhancer scripts after first page load;
//   • intercepts navigation to tel:/mailto:/intent: → url_launcher;
//   • supports hardware back → webview.goBack();
//   • delegates <input type="file"> to the native MainActivity bridge
//     (method channel FabricPlan.nativeChannel).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../shell/shell_palette.dart';
import '../current/browser_marker.dart';
import '../current/portal_scripts.dart';
import '../plan/fabric_plan.dart';

class PortalDeck extends StatefulWidget {
  const PortalDeck({
    super.key,
    required this.url,
    this.injectKeyboardScroll = true,
    this.injectAutoplay = true,
  });

  final String url;
  final bool injectKeyboardScroll;
  final bool injectAutoplay;

  @override
  State<PortalDeck> createState() => _PortalDeckState();
}

class _PortalDeckState extends State<PortalDeck> {
  late final WebViewController _controller;
  final _native = const MethodChannel(FabricPlan.nativeChannel);
  int _redirectCount = 0;
  String? _lastUrl;

  @override
  void initState() {
    super.initState();
    _native.setMethodCallHandler(_onNative);
    _bootController();
  }

  Future<void> _bootController() async {
    final ua = await BrowserMarker.get();
    final params = AndroidWebViewControllerCreationParams();
    final c = WebViewController.fromPlatformCreationParams(params);
    if (c.platform is AndroidWebViewController) {
      await (c.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    await c.setJavaScriptMode(JavaScriptMode.unrestricted);
    await c.setBackgroundColor(ShellPalette.backdrop);
    await c.setUserAgent(ua);
    await c.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: _gate,
      onPageFinished: _inject,
    ));
    await c.loadRequest(Uri.parse(widget.url));
    setState(() => _controller = c);
  }

  FutureOr<NavigationDecision> _gate(NavigationRequest r) async {
    final u = r.url;
    if (u.startsWith('tel:') || u.startsWith('mailto:') ||
        u.startsWith('intent:') || u.startsWith('whatsapp:') ||
        u.startsWith('tg:') || u.startsWith('viber:')) {
      try { await launchUrl(Uri.parse(u),
            mode: LaunchMode.externalApplication); } catch (_) {}
      return NavigationDecision.prevent;
    }
    if (_lastUrl == u) {
      _redirectCount++;
      if (_redirectCount >= FabricPlan.redirectLoopRetries) {
        return NavigationDecision.prevent;
      }
    } else {
      _redirectCount = 0;
      _lastUrl = u;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _inject(String url) async {
    try { await _controller.runJavaScript(PortalScripts.safeArea); } catch (_) {}
    if (widget.injectKeyboardScroll) {
      try { await _controller.runJavaScript(PortalScripts.keyboardFocus); }
      catch (_) {}
    }
    if (widget.injectAutoplay) {
      try { await _controller.runJavaScript(PortalScripts.inlineAutoplay); }
      catch (_) {}
    }
  }

  Future<dynamic> _onNative(MethodCall call) async {
    // Reserved for future bridge calls (file-upload complete, back nav).
    return null;
  }

  Future<bool> _onPop() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final hasController = _controllerReady;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldClose = await _onPop();
        if (!shouldClose) return;
        if (!mounted) return;
        Navigator.of(this.context).maybePop();
      },
      child: Scaffold(
        backgroundColor: ShellPalette.backdrop,
        body: SafeArea(
          child: hasController
              ? WebViewWidget(controller: _controller)
              : const Center(
                  child: CircularProgressIndicator(
                    color: ShellPalette.flame,
                  ),
                ),
        ),
      ),
    );
  }

  bool get _controllerReady {
    try {
      // ignore: unnecessary_statements
      _controller;
      return true;
    } catch (_) {
      return false;
    }
  }
}
