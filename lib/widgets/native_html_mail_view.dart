import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NativeHtmlMailView extends StatelessWidget {
  const NativeHtmlMailView({
    super.key,
    required this.htmlContent,
    this.baseUrl,
  });

  static const String viewType = 'ispace/native_webview';

  final String htmlContent;
  final String? baseUrl;

  @override
  Widget build(BuildContext context) {
    final creationParams = <String, dynamic>{
      'htmlContent': htmlContent,
      'isMailContent': true,
      if (baseUrl != null && baseUrl!.trim().isNotEmpty) 'baseUrl': baseUrl,
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

    return const Center(child: Text('当前平台暂不支持原生 HTML 邮件预览。'));
  }
}
