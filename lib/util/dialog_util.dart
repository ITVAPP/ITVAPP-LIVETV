import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/download_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

class DialogUtil {
  // 焦点节点管理
  static final List<FocusNode> _focusNodes = [];
  static int focusIndex = 0;

  // 颜色定义
  static const Color selectedColor = Color(0xFFEB144C);
  static const Color unselectedColor = Color(0xFFDFA02A);

  // 初始化焦点节点的方法，优化为复用已有节点
  static void _initFocusNodes(int count) {
    // 如果已有节点数量足够，则复用，否则补充
    while (_focusNodes.length < count) {
      _focusNodes.add(FocusNode());
    }
    // 清理多余的节点
    while (_focusNodes.length > count) {
      _focusNodes.removeLast().dispose();
    }
    focusIndex = 1; // 重置焦点索引
  }

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
    int focusNodeCount = 1;
    if (positiveButtonLabel != null) focusNodeCount++;
    if (negativeButtonLabel != null) focusNodeCount++;
    if (isCopyButton) focusNodeCount++;
    if (ShowUpdateButton != null) focusNodeCount++;
    if (child != null) focusNodeCount++;
    if (closeButtonLabel != null) focusNodeCount++;

    // 初始化焦点节点
    _initFocusNodes(focusNodeCount);

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

            // 使用 WillPopScope 确保对话框关闭时清理焦点节点
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
                    focusNodes: _focusNodes,
                    initialIndex: 1,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildDialogHeader(context, title: title, closeFocusNode: _focusNodes[0]),
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
                                        focusNode: _focusNodes[focusIndex++],
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
                            _buildUpdateDownloadBtn(ShowUpdateButton)
                          else
                            _buildActionButtons(
                              context,
                              positiveButtonLabel: positiveButtonLabel,
                              onPositivePressed: onPositivePressed,
                              negativeButtonLabel: negativeButtonLabel,
                              onNegativePressed: onNegativePressed,
                              closeButtonLabel: closeButtonLabel,
                              onClosePressed: onClosePressed,
                              content: content,
                              isCopyButton: isCopyButton,
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

  // 封装的 UpdateDownloadBtn 方法
  static Widget _buildUpdateDownloadBtn(String apkUrl) {
    return Consumer<DownloadProvider>(
      builder: (BuildContext context, DownloadProvider provider, Widget? child) {
        final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
        final btnWidth = isLandscape ? 380.0 : 220.0;

        return provider.isDownloading
            ? _buildDownloadProgress(provider, btnWidth)
            : _buildFocusableButton(
          focusNode: _focusNodes[focusIndex++],
          onPressed: () => _handleDownload(context, apkUrl),
          label: S.current.update,
          width: btnWidth,
          isDownloadButton: true, // 标记为下载按钮以应用特定样式
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

  // 统一按钮构建方法，合并 _buildDownloadButton 和 _buildFocusableButton
  static Widget _buildFocusableButton({
    required FocusNode focusNode,
    required VoidCallback? onPressed,
    required String label,
    double? width,
    bool autofocus = false,
    bool isDownloadButton = false, // 是否为下载按钮，应用不同样式
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

  // 统一按钮样式方法，合并 _buttonStyle 和 _DownloadBtnStyle
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

  // 修改后的 _handleDownload 方法，确保下载失败时显示弹窗
  static void _handleDownload(BuildContext context, String apkUrl) {
    if (Platform.isAndroid) {
      context.read<DownloadProvider>().downloadApk(apkUrl).then((_) {
        if (context.mounted) {
          Navigator.of(context).pop(); // 下载成功关闭弹窗
        }
      }).catchError((e, stackTrace) {
        if (context.mounted) {
          Navigator.of(context).pop(); // 关闭当前弹窗
          // 显示下载失败的弹窗
          DialogUtil.showCustomDialog(
            context,
            title: S.current.downloading, // "下载"
            content: '${S.current.filterError}: $e', // "错误: [具体错误信息]"
            closeButtonLabel: S.current.cancelButton, // "取消"
            isDismissible: true,
          );
        }
      });
    } else {
      if (context.mounted) {
        Navigator.of(context).pop(true);
        CustomSnackBar.showSnackBar(
          context,
          '当前平台不支持下载，仅支持Android',
          duration: const Duration(seconds: 4),
        );
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

  // 封装的内容部分，允许选择和复制功能
  static Widget _buildDialogContent({String? content}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: TextEditingController(text: content ?? ''),
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
    );
  }

  // 动态生成按钮，并增加点击效果
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
            focusNode: _focusNodes[focusIndex++],
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

  // 释放焦点节点资源
  static void disposeFocusNodes() {
    for (var node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
  }
}
