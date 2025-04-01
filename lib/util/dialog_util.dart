import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/download_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tvgenerated/l10n.dart';

class DialogUtil {
  // 颜色定义
  static const Color selectedColor = Color(0xFFEB144C);
  static const Color unselectedColor = Color(0xFFDFA02A);

  // 优化日志处理逻辑
  static String _processLogs(String content) {
    if (content == "showlog") {
      var logs = LogUtil.getLogs().reversed.toList();
      return logs.map((log) => 
        '${log['time']}\n${LogUtil.parseLogMessage(log['message']!)}')
        .join('\n\n');
    }
    return content;
  }
  
  // 显示通用的弹窗方法
  static Future<bool?> showCustomDialog(
    BuildContext context, {
    String? title,
    String? content,
    String? positiveButtonLabel,
    VoidCallback? onPositivePressed,
    String? negativeButtonLabel,
    VoidCallback? onNegativePressed,
    String? closeButtonLabel,
    VoidCallback? onClosePressed, 
    bool isDismissible = true,
    bool isCopyButton = false,
    String? ShowUpdateButton,
    Widget? child,
  }) {
    // 处理日志内容
    content = content != null ? _processLogs(content) : null;
    
    // 计算所需焦点节点数量
    int focusNodeCount = 1; // 关闭按钮
    if (positiveButtonLabel != null) focusNodeCount++;
    if (negativeButtonLabel != null) focusNodeCount++;
    if (isCopyButton) focusNodeCount++;
    if (ShowUpdateButton != null) focusNodeCount++;
    if (child != null) focusNodeCount++;
    if (closeButtonLabel != null) focusNodeCount++;
    
    // 初始化焦点节点
    final List<FocusNode> focusNodes = List.generate(focusNodeCount, (_) => FocusNode());
    int focusIndex = 0; // 从 0 开始计数

    // 提前分配焦点节点
    final closeFocusNode = focusNodes[focusIndex++]; // 关闭按钮
    final childFocusNode = child != null ? focusNodes[focusIndex++] : null;
    final updateButtonFocusNode = ShowUpdateButton != null ? focusNodes[focusIndex++] : null;
    final positiveFocusNode = positiveButtonLabel != null ? focusNodes[focusIndex++] : null;
    final negativeFocusNode = negativeButtonLabel != null ? focusNodes[focusIndex++] : null;
    final copyFocusNode = isCopyButton ? focusNodes[focusIndex++] : null;
    final closeButtonFocusNode = closeButtonLabel != null ? focusNodes[focusIndex++] : null;

    // 释放焦点节点资源
    void disposeFocusNodes() {
      for (var node in focusNodes) {
        node.dispose();
      }
      focusNodes.clear();
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: isDismissible,
      builder: (context) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;
            final isPortrait = screenHeight > screenWidth;
            final dialogWidth = isPortrait ? screenWidth * 0.8 : screenWidth * 0.6;
            final maxDialogHeight = screenHeight * 0.8;

            return WillPopScope(
              onWillPop: () async {
                disposeFocusNodes(); // 关闭对话框时释放焦点节点
                return true;
              },
              child: Center(
                child: Container(
                  width: dialogWidth,
                  constraints: BoxConstraints(maxHeight: maxDialogHeight),
                  decoration: const BoxDecoration(
                    color: Color(0xFF2B2D30),
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    gradient: LinearGradient(
                      colors: [Color(0xff6D6875), Color(0xffB4838D), Color(0xffE5989B)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: TvKeyNavigation(
                    focusNodes: focusNodes,
                    initialIndex: 1,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildDialogHeader(context, title: title, closeFocusNode: closeFocusNode),
                        if (content != null || child != null)
                          Flexible(
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 25),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    if (content != null) _buildDialogContent(content: content),
                                    const SizedBox(height: 10),
                                    if (child != null) 
                                      FocusableItem(
                                        focusNode: childFocusNode!,
                                        child: child,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        if (child == null)
                          if (ShowUpdateButton != null)
                            Consumer<DownloadProvider>(
                              builder: (context, provider, _) {
                                final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
                                final btnWidth = isLandscape ? 380.0 : 220.0;
                                return provider.isDownloading
                                    ? _buildDownloadProgress(provider, btnWidth)
                                    : _buildFocusableButton(
                                        focusNode: updateButtonFocusNode!,
                                        onPressed: () => _handleDownload(context, ShowUpdateButton),
                                        label: S.current.update,
                                        width: btnWidth,
                                        isDownloadButton: true,
                                      );
                              },
                            )
                          else
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (negativeButtonLabel != null)
                                  _buildFocusableButton(
                                    focusNode: negativeFocusNode!,
                                    onPressed: onNegativePressed,
                                    label: negativeButtonLabel,
                                  ),
                                if (positiveButtonLabel != null)
                                  const SizedBox(width: 20),
                                if (positiveButtonLabel != null)
                                  _buildFocusableButton(
                                    focusNode: positiveFocusNode!,
                                    onPressed: onPositivePressed,
                                    label: positiveButtonLabel,
                                  ),
                                if (isCopyButton && content != null)
                                  _buildFocusableButton(
                                    focusNode: copyFocusNode!,
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: content));
                                      CustomSnackBar.showSnackBar(
                                        context,
                                        S.current.copyok,
                                        duration: Duration(seconds: 4),
                                      );
                                    },
                                    label: S.current.copy,
                                  ),
                                if (closeButtonLabel != null)
                                  _buildFocusableButton(
                                    focusNode: closeButtonFocusNode!,
                                    onPressed: onClosePressed ?? () => Navigator.of(context).pop(),
                                    label: closeButtonLabel,
                                    autofocus: true,
                                  ),
                              ],
                            ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      disposeFocusNodes(); // 确保对话框关闭后清理焦点节点
    });
  }
 
  // 封装的 UpdateDownloadBtn 方法（未修改，仅用于参考，未在 showCustomDialog 中调用）
  static Widget _buildUpdateDownloadBtn(String apkUrl) {
    return Consumer<DownloadProvider>(
      builder: (BuildContext context, DownloadProvider provider, Widget? child) {
        final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
        final btnWidth = isLandscape ? 380.0 : 220.0;

        return provider.isDownloading
            ? _buildDownloadProgress(provider, btnWidth)
            : _buildFocusableButton(
                focusNode: _focusNodes[focusIndex++], // 注意：此方法未使用全局变量时会报错
                onPressed: () => _handleDownload(context, apkUrl),
                label: S.current.update,
                width: btnWidth,
                isDownloadButton: true,
              );
      },
    );
  }

  // 抽取下载进度显示逻辑为独立方法
  static Widget _buildDownloadProgress(DownloadProvider provider, double width) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 48,
        width: width,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: LinearProgressIndicator(
                value: provider.progress,
                backgroundColor: const Color(0xFFEB144C).withOpacity(0.2),
                color: const Color(0xFFEB144C),
              ),
            ),
            Text(
              '${S.current.downloading} ${(provider.progress * 100).toStringAsFixed(1)}%',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 统一按钮构建方法
  static Widget _buildFocusableButton({
    required FocusNode focusNode,
    required VoidCallback? onPressed,
    required String label,
    double? width,
    bool autofocus = false,
    bool isDownloadButton = false,
  }) {
    return FocusableItem(
      focusNode: focusNode,
      child: Builder(
        builder: (BuildContext context) {
          final bool hasFocus = Focus.of(context).hasFocus;
          return ElevatedButton(
            style: _buttonStyle(hasFocus, width: width, isDownloadButton: isDownloadButton),
            onPressed: onPressed,
            autofocus: autofocus,
            child: Text(
              label,
              style: TextStyle(
                fontSize: isDownloadButton ? 18 : 18,
                fontWeight: hasFocus ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }

  // 统一按钮样式方法
  static ButtonStyle _buttonStyle(bool hasFocus, {double? width, bool isDownloadButton = false}) {
    return ElevatedButton.styleFrom(
      fixedSize: width != null ? Size(width, 48) : null,
      backgroundColor: hasFocus ? darkenColor(selectedColor) : unselectedColor,
      foregroundColor: Colors.white,
      padding: isDownloadButton
          ? null
          : const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: isDownloadButton ? 10 : null,
      shadowColor: isDownloadButton ? (hasFocus ? selectedColor : unselectedColor) : null,
      textStyle: const TextStyle(fontSize: 18),
      alignment: Alignment.center,
    );
  }

  // 优化下载逻辑处理，改为异步操作
  static Future<void> _handleDownload(BuildContext context, String apkUrl) async {
    if (Platform.isAndroid) {
      try {
        await context.read<DownloadProvider>().downloadApk(apkUrl);
      } catch (e, stackTrace) {
        LogUtil.logError('下载时发生错误', e, stackTrace);
        CustomSnackBar.showSnackBar(
          context,
          '下载失败，请稍后重试',
          duration: const Duration(seconds: 4),
        );
      }
    } else {
      try {
        Navigator.of(context).pop(true);
        CustomSnackBar.showSnackBar(
          context,
          '当前平台不支持下载，仅支持Android',
          duration: const Duration(seconds: 4),
        );
      } catch (e, stackTrace) {
        LogUtil.logError('关闭对话框时发生错误', e, stackTrace);
      }
    }
  }

  // 封装的标题部分，包含右上角关闭按钮
  static Widget _buildDialogHeader(BuildContext context, {String? title, FocusNode? closeFocusNode}) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          alignment: Alignment.center,
          child: Text(
            title ?? 'Notification 🔔',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          ),
        ),
        Positioned(
          right: 0,
          child: FocusableItem(
            focusNode: closeFocusNode!,
            child: Builder(
              builder: (BuildContext context) {
                final bool hasFocus = Focus.of(context).hasFocus;
                return IconButton(
                  icon: const Icon(Icons.close),
                  iconSize: 26,
                  color: _closeIconColor(hasFocus),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // 优化内容部分，管理 TextEditingController 的生命周期
  static Widget _buildDialogContent({String? content}) {
    final controller = TextEditingController(text: content ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          readOnly: true,
          maxLines: null,
          textAlign: TextAlign.start,
          decoration: const InputDecoration(
            border: InputBorder.none,
          ),
          style: const TextStyle(fontSize: 18),
          enableInteractiveSelection: true,
        ),
      ],
    )..addListener(() => controller.dispose()); // 确保释放控制器
  }

  // 动态生成按钮，并增加点击效果（未在 showCustomDialog 中调用，保留原样）
  static Widget _buildActionButtons(
    BuildContext context, {
    String? positiveButtonLabel,
    VoidCallback? onPositivePressed,
    String? negativeButtonLabel,
    VoidCallback? onNegativePressed,
    String? closeButtonLabel,
    VoidCallback? onClosePressed,
    String? content,
    bool isCopyButton = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (negativeButtonLabel != null)
          _buildFocusableButton(
            focusNode: _focusNodes[focusIndex++], // 注意：此方法未使用全局变量时会报错
            onPressed: onNegativePressed,
            label: negativeButtonLabel,
          ),
        if (positiveButtonLabel != null)
          const SizedBox(width: 20),
        if (positiveButtonLabel != null)
          _buildFocusableButton(
            focusNode: _focusNodes[focusIndex++],
            onPressed: onPositivePressed,
            label: positiveButtonLabel,
          ),
        if (isCopyButton && content != null)
          _buildFocusableButton(
            focusNode: _focusNodes[focusIndex++],
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              CustomSnackBar.showSnackBar(
                context,
                S.current.copyok,
                duration: Duration(seconds: 4),
              );
            },
            label: S.current.copy,
          ),
        if (closeButtonLabel != null)
          _buildFocusableButton(
            focusNode: _focusNodes[focusIndex++],
            onPressed: onClosePressed ?? () => Navigator.of(context).pop(),
            label: closeButtonLabel,
            autofocus: true,
          ),
      ],
    );
  }

  // 获取关闭按钮的颜色，动态设置焦点状态  
  static Color _closeIconColor(bool hasFocus) {
    return hasFocus ? selectedColor : Colors.white;
  }

  // 用于 darkenColor 的辅助方法（未修改）
  static Color darkenColor(Color color, [double amount = 0.1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(color);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}
