import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/web_session_snapshot.dart';

class NativeMirrorWebView extends StatelessWidget {
  const NativeMirrorWebView({
    super.key,
    required this.initialUrl,
    required this.session,
  });

  final String initialUrl;
  final WebSessionSnapshot session;

  static const String viewType = 'ispace/native_webview';

  @override
  Widget build(BuildContext context) {
    final creationParams = <String, dynamic>{
      'initialUrl': initialUrl,
      'cookies': session.cookies.map((cookie) => cookie.toMap()).toList(),
    };

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    return const Center(child: Text('当前平台暂不支持内嵌官网镜像页面。'));
  }
}
