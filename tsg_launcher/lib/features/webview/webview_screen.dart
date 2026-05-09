import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';

class WebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  const WebViewScreen({super.key, required this.url, required this.title});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  double _progress = 0;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Full-screen WebView — shares cookie store with LoginScreen for SSO
            if (!_hasError)
              InAppWebView(
                initialUrlRequest:
                    URLRequest(url: WebUri(widget.url)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  cacheEnabled: true,
                  supportZoom: false,
                  useWideViewPort: false,
                  loadWithOverviewMode: false,
                  // Prevent renderer OOM crashes on low-memory devices/emulators
                  rendererPriorityPolicy: RendererPriorityPolicy(
                    rendererRequestedPriority:
                        RendererPriority.RENDERER_PRIORITY_BOUND,
                    waivedWhenNotVisible: false,
                  ),
                ),
                onProgressChanged: (_, progress) =>
                    setState(() => _progress = progress / 100),
                onLoadStop: (_, __) => setState(() => _progress = 1),
                onReceivedError: (_, __, error) => setState(() {
                  _hasError = true;
                  _errorMessage = error.description;
                }),
                onRenderProcessGone: (controller, detail) {
                  // Renderer was killed (OOM or crash) — show error so user can retry
                  if (mounted) {
                    setState(() {
                      _hasError = true;
                      _errorMessage =
                          'Page renderer crashed${detail.didCrash ? '' : ' (low memory)'}. Tap Retry.';
                    });
                  }
                },
              ),

            // Error state
            if (_hasError)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage.isNotEmpty
                          ? _errorMessage
                          : 'Could not load ${widget.title}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() {
                        _hasError = false;
                        _errorMessage = '';
                        _progress = 0;
                      }),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),

            // Progress bar
            if (_progress < 1 && !_hasError)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(value: _progress),
              ),

            // Floating back button — always on top, semi-transparent
            Positioned(
              top: 12,
              left: 12,
              child: SafeArea(
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => context.pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 24),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
