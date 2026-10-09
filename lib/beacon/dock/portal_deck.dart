// PortalDeck — hosts a WebView showing the backend-decided URL.
//
// Behaviour:
//   • immersiveSticky system chrome — the Android status / navigation
//     bars are hidden. Any pixels that still have to be reserved
//     (display cutout / punch-hole) are padded in BLACK.
//   • `resizeToAvoidBottomInset: false` keeps the WebView at full
//     height when the IME opens; the page lifts the focused field via
//     the sealed JS enhancer rather than letting Android re-lay-out
//     the heavy native surface per frame.
//   • Scaffold + WebView background both black, so safe-area pads are
//     invisible rather than showing a different tint.
//   • Uses the sealed BrowserMarker UA.
//   • Injects three sealed JS enhancer scripts after first page load.
//   • Intercepts tel:/mailto:/intent: → url_launcher.
//   • Hardware back → webview.goBack() when possible.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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

class _PortalDeckState extends State<PortalDeck>
    with WidgetsBindingObserver {
  WebViewController? _controller;
  final _native = const MethodChannel(FabricPlan.nativeChannel);
  int _redirectCount = 0;
  String? _lastUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _native.setMethodCallHandler(_onNative);
    _enterImmersive();
    _bootController();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _enterImmersive();
  }

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ));
  }

  Future<void> _bootController() async {
    final ua = await BrowserMarker.get();
    final params = AndroidWebViewControllerCreationParams();
    final c = WebViewController.fromPlatformCreationParams(params);
    if (c.platform is AndroidWebViewController) {
      final android = c.platform as AndroidWebViewController;
      await android.setMediaPlaybackRequiresUserGesture(false);
      try {
        await android.setOnPlatformPermissionRequest(
          (PlatformWebViewPermissionRequest r) => r.grant(),
        );
      } catch (_) {}
    }
    await c.setJavaScriptMode(JavaScriptMode.unrestricted);
    await c.setBackgroundColor(Colors.black);
    await c.enableZoom(false);
    await c.setUserAgent(ua);
    await c.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: _gate,
      onPageFinished: _inject,
    ));
    await c.loadRequest(Uri.parse(widget.url));
    if (!mounted) return;
    setState(() => _controller = c);
  }

  FutureOr<NavigationDecision> _gate(NavigationRequest r) async {
    final u = r.url;
    const stayInside = <String>{'http', 'https', 'about', 'data', 'blob'};
    final scheme = Uri.tryParse(u)?.scheme ?? '';
    if (!stayInside.contains(scheme)) {
      try {
        await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
      } catch (_) {}
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
    final c = _controller;
    if (c == null) return;
    try { await c.runJavaScript(PortalScripts.safeArea); } catch (_) {}
    if (widget.injectKeyboardScroll) {
      try { await c.runJavaScript(PortalScripts.keyboardFocus); }
      catch (_) {}
    }
    if (widget.injectAutoplay) {
      try { await c.runJavaScript(PortalScripts.inlineAutoplay); }
      catch (_) {}
    }
  }

  Future<dynamic> _onNative(MethodCall call) async => null;

  Future<bool> _onPop() async {
    final c = _controller;
    if (c == null) return true;
    if (await c.canGoBack()) {
      await c.goBack();
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldClose = await _onPop();
        if (!shouldClose || !mounted) return;
        Navigator.of(this.context).maybePop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // Full-height WebView when IME opens; page handles field lift
        // via the sealed JS enhancers.
        resizeToAvoidBottomInset: false,
        body: Container(
          color: Colors.black,
          child: c == null
              ? const Center(
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFFFFB063)),
                    ),
                  ),
                )
              // Pad ONLY for physical cutouts (notch / punch-hole).
              // Never add the keyboard inset here.
              : Padding(
                  padding: MediaQuery.viewPaddingOf(context),
                  child: WebViewWidget(controller: c),
                ),
        ),
      ),
    );
  }
}
