import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/download_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 弹窗工具类，提供通用对话框显示功能
class DialogUtil {
  // 焦点节点管理 - 使用对象池优化
  static final List<FocusNode> _focusNodePool = []; // 焦点节点对象池
  static final List<FocusNode> _activeFocusNodes = []; // 当前活跃的焦点节点
  static int focusIndex = 0; // 当前焦点索引

  // 颜色定义
  static const Color selectedColor = Color(0xFFEB144C); // 选中状态颜色
  static const Color unselectedColor = Color(0xFFDFA02A); // 未选中状态颜色

  // ButtonStyle 缓存 - 预创建常用样式
  static final Map<String, ButtonStyle> _buttonStyleCache = {};

  // 初始化焦点节点，从对象池获取或创建新节点
  static void _initFocusNodes(int count) {
    _activeFocusNodes.clear();
    
    for (int i = 0; i < count; i++) {
      FocusNode node;
      if (_focusNodePool.isNotEmpty) {
        // 从对象池获取节点
        node = _focusNodePool.removeLast();
      } else {
        // 创建新节点
        node = FocusNode();
      }
      _activeFocusNodes.add(node);
    }
    
    focusIndex = 1; // 重置焦点索引为初始值
  }

  // 处理日志内容，转换为可显示格式 - 优化性能
  static String _processLogs(String content) {
    if (content == "showlog") {
      var logs = LogUtil.getLogs();
      if (logs.isEmpty) return '';
      
      // 使用 StringBuffer 优化字符串拼接性能
      final buffer = StringBuffer();
      final reversedLogs = logs.reversed;
      bool isFirst = true;
      
      for (final log in reversedLogs) {
        if (!isFirst) {
          buffer.write('\n\n');
        }
        buffer.write(log['time']);
        buffer.write('\n');
        buffer.write(LogUtil.parseLogMessage(log['message']!));
        isFirst = false;
      }
      
      return buffer.toString();
    }
    return content;
  }

  // 显示通用弹窗，支持多种配置选项
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
    content = content != null ? _processLogs(content) : null; // 处理日志内容

    // 计算所需焦点节点数量
    int focusNodeCount = 1;
    if (positiveButtonLabel != null) focusNodeCount++;
    if (negativeButtonLabel != null) focusNodeCount++;
    if (isCopyButton) focusNodeCount++;
    if (ShowUpdateButton != null) focusNodeCount++;
    if (child != null) focusNodeCount++;
    if (closeButtonLabel != null) focusNodeCount++;

    _initFocusNodes(focusNodeCount); // 初始化焦点节点

    return showDialog<bool>(
      context: context,
      barrierDismissible: isDismissible,
      barrierColor: Colors.transparent, // 背景初始透明
      useRootNavigator: true, // 使用根导航器避免嵌套问题
      builder: (context) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;
            final isPortrait = screenHeight > screenWidth; // 判断屏幕方向
            final dialogWidth = isPortrait ? screenWidth * 0.8 : screenWidth * 0.6; // 弹窗宽度
            final maxDialogHeight = screenHeight * 0.8; // 最大弹窗高度

            return WillPopScope(
              onWillPop: () async {
                _returnFocusNodesToPool(); // 返回焦点节点到对象池
                return true;
              },
              child: Center(
                child: Container(
                  width: dialogWidth,
                  constraints: BoxConstraints(maxHeight: maxDialogHeight),
                  decoration: const BoxDecoration(
                    color: Color(0xFF2B2D30), // 弹窗背景色
                    borderRadius: BorderRadius.all(Radius.circular(16)), // 圆角
                    gradient: LinearGradient( // 渐变效果
                      colors: [Color(0xff6D6875), Color(0xffB4838D), Color(0xffE5989B)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: TvKeyNavigation(
                    focusNodes: _activeFocusNodes, // 使用活跃焦点节点
                    initialIndex: 1, // 初始焦点索引
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
                            _buildUpdateDownloadBtn(ShowUpdateButton) // 更新下载按钮
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
      _returnFocusNodesToPool(); // 弹窗关闭后返回节点到对象池
    });
  }

  // 构建更新下载按钮，支持下载状态显示
  static Widget _buildUpdateDownloadBtn(String apkUrl) {
    return Consumer<DownloadProvider>(
      builder: (BuildContext context, DownloadProvider provider, Widget? child) {
        final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
        final btnWidth = isLandscape ? 380.0 : 220.0; // 根据屏幕方向调整宽度

        return provider.isDownloading
            ? _buildDownloadProgress(provider, btnWidth) // 显示下载进度
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

  // 显示下载进度条
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
                value: provider.progress, // 下载进度
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

  // 构建可聚焦按钮，统一样式和逻辑
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
                fontSize: isDownloadButton ? 18 : 18,
                fontWeight: hasFocus ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }

  // 获取缓存的按钮样式，优化性能
  static ButtonStyle _getButtonStyle(bool hasFocus, {double? width, bool isDownloadButton = false}) {
    // 构建缓存键
    final cacheKey = '${hasFocus}_${width}_$isDownloadButton';
    
    // 检查缓存
    if (_buttonStyleCache.containsKey(cacheKey)) {
      return _buttonStyleCache[cacheKey]!;
    }
    
    // 创建新样式并缓存
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
      elevation: isDownloadButton ? 10 : null, // 下载按钮增加阴影
      shadowColor: isDownloadButton ? (hasFocus ? selectedColor : unselectedColor) : null,
      textStyle: const TextStyle(fontSize: 18),
      alignment: Alignment.center,
    );
    
    _buttonStyleCache[cacheKey] = style;
    return style;
  }

  // 处理下载逻辑并显示提示
  static void _handleDownload(BuildContext context, String apkUrl) {
    if (Platform.isAndroid) {
      context.read<DownloadProvider>().downloadApk(apkUrl).then((_) {
        if (context.mounted) {
          Navigator.of(context).pop(); // 下载成功关闭弹窗
          CustomSnackBar.showSnackBar(
            context,
            S.current.downloadSuccess,
            duration: const Duration(seconds: 5),
          );
        }
      }).catchError((e, stackTrace) {
        if (context.mounted) {
          Navigator.of(context).pop(); // 下载失败关闭弹窗
          CustomSnackBar.showSnackBar(
            context,
            S.current.downloadFailed,
            duration: const Duration(seconds: 5),
          );
        }
      });
    } else {
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

  // 构建弹窗标题部分，包含关闭按钮
  static Widget _buildDialogHeader(BuildContext context, {String? title, FocusNode? closeFocusNode}) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          alignment: Alignment.center,
          child: Text(
            title ?? 'Notification 🔔', // 默认标题
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
                    Navigator.of(context).pop(); // 关闭弹窗
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // 构建弹窗内容，支持选择和复制
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
          enableInteractiveSelection: true, // 支持选择和复制
        ),
      ],
    );
  }

  // 动态生成操作按钮
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
                duration: Duration(seconds: 4),
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

  // 获取关闭按钮颜色，根据焦点状态变化
  static Color _closeIconColor(bool hasFocus) {
    return hasFocus ? selectedColor : Colors.white;
  }

  // 将焦点节点返回到对象池
  static void _returnFocusNodesToPool() {
    // 将活跃节点返回到对象池
    _focusNodePool.addAll(_activeFocusNodes);
    _activeFocusNodes.clear();
    
    // 限制对象池大小，避免内存泄漏
    const maxPoolSize = 20;
    while (_focusNodePool.length > maxPoolSize) {
      _focusNodePool.removeAt(0).dispose();
    }
  }

  // 释放所有焦点节点资源 - 保留原有接口兼容性
  static void disposeFocusNodes() {
    _returnFocusNodesToPool();
  }


}
