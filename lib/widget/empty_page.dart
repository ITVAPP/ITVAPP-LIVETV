import 'package:flutter/material.dart';
import 'package:provider/provider.dart';  // 导入 Provider 包
import '../provider/theme_provider.dart'; // 导入 ThemeProvider
import '../generated/l10n.dart';

class EmptyPage extends StatelessWidget {
  final GestureTapCallback onRefresh;
  const EmptyPage({super.key, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    // 通过 Provider 获取 isTV 的状态
    bool isTV = context.watch<ThemeProvider>().isTV;

    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '⚠️',
            style: TextStyle(fontSize: 50),
          ),
          const Text(
            '出现错误',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, color: Colors.white),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            onPressed: onRefresh,
            child: Text(
              '      ${isTV ? S.current.okRefresh : S.current.refresh}      ',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
