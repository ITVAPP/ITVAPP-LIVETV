import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/download_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

/// 弹窗工具类，提供通用对话框显示功能
class DialogUtil {
  static final List<FocusNode> _focusNodePool = []; /// 焦点节点对象池
  static final List<FocusNode> _activeFocusNodes = []; /// 当前活跃焦点节点
  static int focusIndex = 0; /// 当前焦点索引

  static const Color selectedColor = Color(0xFFEB144C); /// 选中状态颜色
  static const Color unselectedColor = Color(0xFFDFA02A); /// 未选中状态颜色

  static final Map<String, ButtonStyle> _buttonStyleCache = {}; /// 按钮样式缓存

  /// 初始化焦点节点，从对象池获取或新建
  static void _initFocusNodes(int count) {
    _activeFocusNodes.clear();
    
    for (int i = 0; i < count; i++) {
      FocusNode node;
      if (_focusNodePool.isNotEmpty) {
        node = _focusNodePool.removeLast();
      } else {
        node = FocusNode();
      }
      _activeFocusNodes.add(node);
    }
    
    focusIndex = 1;
  }

  /// 格式化日志内容为可显示字符串
  static String _processLogs(String content) {
    if (content == "showlog") {
      var logs = LogUtil.getLogs();
      if (logs.isEmpty) return '';
      
      final buffer = StringBuffer();
      final reversedLogs = logs.reversed.toList();
      
      for (int i = 0; i < reversedLogs.length; i++) {
        if (i > 0) buffer.write('\n\n');
        buffer
          ..write(reversedLogs[i]['time'])
          ..write('\n')
          ..write(LogUtil.parseLogMessage(reversedLogs[i]['message']!));
      }
      
      return buffer.toString();
    }
    return content;
  }

  /// 显示通用弹窗，支持多种配置选项
  static Future<bool?> showCustomDialog(
      BuildContext context, {
        String? title, // 弹窗标题
        String? content, // 弹窗内容
        String? positiveButtonLabel, // 确认按钮标签
        VoidCallback? onPositivePressed, // 确认按钮回调
        String? negativeButtonLabel, // 取消按钮标签
        VoidCallback? onNegativePressed, // 取消按钮回调
        String? closeButtonLabel, // 关闭按钮标签
        VoidCallback? onClosePressed, // 关闭按钮回调
        bool isDismissible = true, // 是否可点击外部关闭
        bool isCopyButton = false, // 是否显示复制按钮
        String? ShowUpdateButton, // 更新按钮的 APK URL
        Widget? child, // 自定义内容组件
      }) {
    content = content != null ? _processLogs(content) : null;

    int focusNodeCount = 1;
    if (positiveButtonLabel != null) focusNodeCount++;
    if (negativeButtonLabel != null) focusNodeCount++;
    if (isCopyButton) focusNodeCount++;
    if (ShowUpdateButton != null) focusNodeCount++;
    if (child != null) focusNodeCount++;
    if (closeButtonLabel != null) focusNodeCount++;

    _initFocusNodes(focusNodeCount);

    return showDialog<bool>(
      context: context,
      barrierDismissible: isDismissible,
      barrierColor: Colors.transparent,
      useRootNavigator: true,
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
                _returnFocusNodesToPool();
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
                    focusNodes: _activeFocusNodes,
                    initialIndex: 1,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildDialogHeader(context, title: title, closeFocusNode: _activeFocusNodes[0]),
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
                                        focusNode: _activeFocusNodes[focusIndex++],
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
      _returnFocusNodesToPool();
    });
  }

  /// 构建更新下载按钮，显示下载状态
  static Widget _buildUpdateDownloadBtn(String apkUrl) {
    return Consumer<DownloadProvider>(
      builder: (BuildContext context, DownloadProvider provider, Widget? child) {
        final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
        final btnWidth = isLandscape ? 380.0 : 220.0;

        return provider.isDownloading
            ? _buildDownloadProgress(provider, btnWidth)
            : _buildFocusableButton(
          focusNode: _activeFocusNodes[focusIndex++],
          onPressed: () => _handleDownload(context, apkUrl),
          label: S.current.update,
          width: btnWidth,
          isDownloadButton: true,
        );
      },
    );
  }

  /// 显示下载进度条
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

  /// 构建可聚焦按钮，统一样式
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
            style: _getButtonStyle(hasFocus, width: width, isDownloadButton: isDownloadButton),
            onPressed: onPressed,
            autofocus: autofocus,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: hasFocus ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }

  /// 获取缓存的按钮样式
  static ButtonStyle _getButtonStyle(bool hasFocus, {double? width, bool isDownloadButton = false}) {
    final cacheKey = '${hasFocus}_${width}_$isDownloadButton';
    
    if (_buttonStyleCache.containsKey(cacheKey)) {
      return _buttonStyleCache[cacheKey]!;
    }
    
    final style = ElevatedButton.styleFrom(
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
    
    _buttonStyleCache[cacheKey] = style;
    return style;
  }

  /// 处理下载逻辑并显示结果提示
  static void _handleDownload(BuildContext context, String apkUrl) {
    LogUtil.d('开始下载: URL=$apkUrl');
    if (Platform.isAndroid) {
      context.read<DownloadProvider>().downloadApk(apkUrl).then((_) {
        LogUtil.d('下载成功: URL=$apkUrl');
        if (context.mounted) {
          Navigator.of(context).pop();
          CustomSnackBar.showSnackBar(
            context,
            S.current.downloadSuccess,
            duration: const Duration(seconds: 5),
          );
        }
      }).catchError((e, stackTrace) {
        LogUtil.logError('下载失败: URL=$apkUrl', e, stackTrace);
        if (context.mounted) {
          Navigator.of(context).pop();
          CustomSnackBar.showSnackBar(
            context,
            S.current.downloadFailed,
            duration: const Duration(seconds: 5),
          );
        }
      });
    } else {
      LogUtil.d('平台不支持下载: URL=$apkUrl');
      if (context.mounted) {
        Navigator.of(context).pop(true);
        CustomSnackBar.showSnackBar(
          context,
          S.current.platformNotSupported,
          duration: const Duration(seconds: 5),
        );
      }
    }
  }

  /// 构建弹窗标题，包含关闭按钮
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
          right: 8,
          top: 8,
          child: FocusableItem(
            focusNode: closeFocusNode!,
            child: Builder(
              builder: (BuildContext context) {
                final bool hasFocus = Focus.of(context).hasFocus;
                return Container(
                  // 添加圆形边框装饰
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: hasFocus
                        ? Border.all(
                            color: selectedColor, // 使用已有的红色常量
                            width: 3,
                          )
                        : null,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    iconSize: 28, // 图标大小
                    color: _closeIconColor(hasFocus),
                    onPressed: () {
                      Navigator.of(context).pop(); // 关闭弹窗
                    },
                    // 减小内边距，让按钮更紧凑
                    padding: const EdgeInsets.all(2),
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 构建弹窗内容，支持选择和复制
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

  /// 构建操作按钮组
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
            focusNode: _activeFocusNodes[focusIndex++],
            onPressed: onNegativePressed,
            label: negativeButtonLabel,
          ),
        if (positiveButtonLabel != null)
          const SizedBox(width: 20),
        if (positiveButtonLabel != null)
          _buildFocusableButton(
            focusNode: _activeFocusNodes[focusIndex++],
            onPressed: onPositivePressed,
            label: positiveButtonLabel,
          ),
        if (isCopyButton && content != null)
          _buildFocusableButton(
            focusNode: _activeFocusNodes[focusIndex++],
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content)); // 复制内容
              CustomSnackBar.showSnackBar(
                context,
                S.current.copyok,
                duration: const Duration(seconds: 4),
              );
            },
            label: S.current.copy,
          ),
        if (closeButtonLabel != null)
          _buildFocusableButton(
            focusNode: _activeFocusNodes[focusIndex++],
            onPressed: onClosePressed ?? () => Navigator.of(context).pop(),
            label: closeButtonLabel,
            autofocus: true,
          ),
      ],
    );
  }

  /// 获取关闭按钮颜色
  static Color _closeIconColor(bool hasFocus) {
    return hasFocus ? selectedColor : Colors.white;
  }

  /// 回收焦点节点到对象池
  static void _returnFocusNodesToPool() {
    _focusNodePool.addAll(_activeFocusNodes);
    _activeFocusNodes.clear();
    
    const maxPoolSize = 20;
    while (_focusNodePool.length > maxPoolSize) {
      _focusNodePool.removeAt(0).dispose();
    }
  }

  /// 释放所有焦点节点
  static void disposeFocusNodes() {
    _returnFocusNodesToPool();
  }
}
