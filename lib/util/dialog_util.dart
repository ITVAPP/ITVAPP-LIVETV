import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/download_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import '../generated/l10n.dart';

class DialogUtil {
  // 定义焦点节点
  static List<FocusNode> _focusNodes = [];
  static int focusIndex = 0; 

  // 颜色定义
  static const Color selectedColor = Color(0xFFEB144C);
  static const Color unselectedColor = Color(0xFFDFA02A);

  // 用于将颜色变暗的函数
  static Color darkenColor(Color color, [double amount = 0.2]) {
    final hsl = HSLColor.fromColor(color);
    final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return darkened.toColor();
  }

  // 显示通用的弹窗，接受标题、内容、正向/负向按钮文本和点击回调
  static Future<bool?> showCustomDialog(
    BuildContext context, {
    String? title,  // 动态标题
    String? content,  // 动态内容
    String? positiveButtonLabel,  // 正向按钮文本
    VoidCallback? onPositivePressed,  // 正向按钮点击回调
    String? negativeButtonLabel,  // 负向按钮文本（可选）
    VoidCallback? onNegativePressed,  // 负向按钮点击回调（可选）
    String? closeButtonLabel,  // 底部关闭按钮文本（可选）
    VoidCallback? onClosePressed,  // 关闭按钮点击回调（可选）
    bool isDismissible = true,  // 是否允许点击对话框外部关闭
    bool isCopyButton = false,  // 新增参数：是否显示复制按钮
    String? ShowUpdateButton,  // 判断是否显示 UpdateDownloadBtn
    Widget? child,  // 自定义 widget 作为 child
  }) {
    // 检查 content 是否为 "showlog"，如果是则显示日志
    if (content == "showlog") {
      List<Map<String, String>> logs = LogUtil.getLogs();
      logs = logs.reversed.toList();  // 日志条目反转，确保最新日志在最前面
      content = logs.map((log) {
        String time = log['time']!;
        String parsedMessage = LogUtil.parseLogMessage(log['message']!);
        return '$time\n$parsedMessage';  // 每条日志的时间和内容分两行显示
      }).join('\n\n');  // 在每条日志之间增加换行
    }

    // 清空焦点节点列表
    _focusNodes.clear();
    focusIndex = 0; 

    // 统计需要的 FocusNode 数量
    int focusNodeCount = 1;  // 右上角关闭按钮始终需要1个FocusNode
    if (positiveButtonLabel != null) focusNodeCount++;
    if (negativeButtonLabel != null) focusNodeCount++;
    if (isCopyButton) focusNodeCount++;
    if (ShowUpdateButton != null) focusNodeCount++;  // 如果有 Update 按钮，增加焦点
    if (child != null) focusNodeCount++;  // 如果有自定义 child，增加焦点
    if (closeButtonLabel != null) focusNodeCount++;  // 底部关闭按钮需要一个 FocusNode

    // 使用 List.generate 创建需要的 FocusNode 数量
    _focusNodes = List.generate(focusNodeCount, (index) => FocusNode());

    return showDialog<bool>(
      context: context,
      barrierDismissible: isDismissible,  // 是否允许点击对话框外部关闭
      builder: (BuildContext dialogContext) {
        // 获取屏幕的宽度和高度
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final screenHeight = MediaQuery.of(dialogContext).size.height;
        // 判断屏幕方向，决定对话框宽度比例
        final isPortrait = screenHeight > screenWidth;
        final dialogWidth = isPortrait ? screenWidth * 0.8 : screenWidth * 0.6;  // 根据屏幕方向调整弹窗宽度
        final maxDialogHeight = screenHeight * 0.8;  // 设置对话框的最大高度为屏幕高度的80%

        return Center(
          child: StatefulBuilder(
            builder: (BuildContext statefulContext, StateSetter setState) {
              return Container(
                width: dialogWidth,  // 设置对话框宽度
                constraints: BoxConstraints(
                  maxHeight: maxDialogHeight,  // 限制对话框最大高度
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B2D30),
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                    colors: [Color(0xff6D6875), Color(0xffB4838D), Color(0xffE5989B)], 
                    begin: Alignment.topCenter, 
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: TvKeyNavigation(
                  focusNodes: _focusNodes,  // 动态生成的焦点节点
                  initialIndex: 1,  // 初始焦点
                  child: Column(
                    mainAxisSize: MainAxisSize.min,  // 动态调整高度，适应内容
                    children: [
                      _buildDialogHeader(dialogContext, title: title, closeFocusNode: _focusNodes[0]),  // 传递右上角关闭按钮的焦点节点
                      Flexible( 
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 25),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,  // 内容容器水平居中
                              children: [
                                if (content != null) _buildDialogContent(content: content),  // 如果有 content，显示内容
                                const SizedBox(height: 10),
                                if (child != null) 
                                  FocusableItem(
                                    focusNode: _focusNodes[focusIndex++], // 动态递增焦点节点索引
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
                          _buildUpdateDownloadBtn(ShowUpdateButton),  // 显示 UpdateDownloadBtn
                      if (child == null && ShowUpdateButton == null)
                        _buildActionButtons(
                          context,
                          positiveButtonLabel: positiveButtonLabel,
                          onPositivePressed: onPositivePressed,
                          negativeButtonLabel: negativeButtonLabel,
                          onNegativePressed: onNegativePressed,
                          closeButtonLabel: closeButtonLabel,
                          onClosePressed: onClosePressed,
                          content: content,  // 传递内容用于复制
                          isCopyButton: isCopyButton,  // 控制是否显示复制按钮
                        ),  // 动态按钮处理
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // 封装的 UpdateDownloadBtn 方法
static Widget _buildUpdateDownloadBtn(String apkUrl) {
  return Consumer<DownloadProvider>(
    builder: (BuildContext context, DownloadProvider provider, Widget? child) {
      // 判断当前屏幕方向是否为横屏
      bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
      // 根据屏幕方向设置按钮宽度
      double btnWidth = isLandscape ? 380 : 220;

      return provider.isDownloading
          ? _buildDownloadProgress(provider, btnWidth)  // 提取下载进度为独立方法
          : _buildDownloadButton(  // 使用优化后的可聚焦按钮构建逻辑
              context: context,
              focusNode: _focusNodes[focusIndex++],  // 使用焦点节点
              label: S.of(context).update,  // 更新按钮文本
              onPressed: () => _handleDownload(context, apkUrl),  // 下载逻辑
              width: btnWidth,  // 按钮宽度
            );
    },
  );
}

// 抽取下载进度显示逻辑为独立方法
static Widget _buildDownloadProgress(DownloadProvider provider, double width) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(16),  // 圆角按钮样式
    child: SizedBox(
      height: 48,
      width: width,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 下载进度条
          Positioned.fill(
            child: LinearProgressIndicator(
              value: provider.progress,  // 进度条的进度
              backgroundColor: const Color(0xFFEB144C).withOpacity(0.2),  // 进度条背景颜色
              color: const Color(0xFFEB144C),  // 进度条前景颜色
            ),
          ),
          // 下载进度的文字显示
          Text(
            '${S.of(context).downloading} ${(provider.progress * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
              color: Colors.white,  // 白色文字
              fontWeight: FontWeight.bold,  // 文字加粗
              fontSize: 16,  // 文字大小
            ),
          ),
        ],
      ),
    ),
  );
}

// 优化后的可聚焦按钮构建方法
static Widget _buildDownloadButton({
  required BuildContext context,
  required FocusNode focusNode,
  required String label,
  required VoidCallback onPressed,
  required double width,
}) {
  return FocusableItem(
    focusNode: focusNode,  // 使用焦点节点
    child: Builder(
      builder: (BuildContext context) {
        bool hasFocus = Focus.of(context).hasFocus;  // 获取焦点状态
        return ElevatedButton(
          style: _DownloadBtnStyle(hasFocus, width),  // 按钮样式
          onPressed: onPressed,  // 按钮点击事件
          child: Text(label),  // 按钮文本
        );
      },
    ),
  );
}

// 提取按钮样式设置为独立方法
static ButtonStyle _DownloadBtnStyle(bool hasFocus, double width) {
  return ElevatedButton.styleFrom(
    fixedSize: Size(width, 48),  // 按钮尺寸
    backgroundColor: hasFocus ? selectedColor : unselectedColor,  // 根据焦点状态设置背景颜色
    elevation: 10,  // 按钮阴影
    foregroundColor: Colors.white,  // 按钮文字颜色
    shadowColor: hasFocus ? selectedColor : unselectedColor,  // 按钮阴影颜色
  );
}

// 提取下载逻辑处理为独立方法
static void _handleDownload(BuildContext context, String apkUrl) {
  if (Platform.isAndroid) {
    try {
      context.read<DownloadProvider>().downloadApk(apkUrl);  // 执行 APK 下载
    } catch (e, stackTrace) {
      LogUtil.logError('下载时发生错误', e, stackTrace);  // 记录下载时的错误
    }
  } else {
    try {
      Navigator.of(context).pop(true);  // 关闭对话框
    } catch (e, stackTrace) {
      LogUtil.logError('关闭对话框时发生错误', e, stackTrace);  // 记录关闭对话框时的错误
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
            title ?? 'Notification 🔔',  // 动态标题
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          ),
        ),
        Positioned(
          right: 0,
          child: FocusableItem(
            focusNode: closeFocusNode!,  // 使用传入的焦点节点
            child: Builder(
              builder: (BuildContext context) {
                final bool hasFocus = Focus.of(context).hasFocus;
                return IconButton(
                  icon: const Icon(Icons.close),  // 使用默认关闭图标
                  iconSize: 26,  // 关闭按钮大小
                  color: _closeIconColor(hasFocus),  // 设置关闭按钮颜色
                  onPressed: () {
                    Navigator.of(context).pop();  // 关闭对话框
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
      crossAxisAlignment: CrossAxisAlignment.start,  // 调整内容文本为默认左对齐
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: TextEditingController(text: content ?? ''),  // 显示内容，没有则显示为空
          readOnly: true,  // 设置为只读
          maxLines: null,  // 允许多行显示
          textAlign: TextAlign.start,  // 文本水平默认左对齐
          decoration: const InputDecoration(
            border: InputBorder.none,  // 去掉边框
          ),
          style: const TextStyle(fontSize: 18),  // 设置文本样式
          enableInteractiveSelection: true,  // 启用交互式选择功能，允许复制
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
    String? closeButtonLabel,  // 底部关闭按钮文本
    VoidCallback? onClosePressed,  // 底部关闭按钮点击事件
    String? content,  // 传递的内容，用于复制
    bool isCopyButton = false,  // 控制是否显示复制按钮
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,  // 按钮居中
      children: [
        if (negativeButtonLabel != null)  // 如果负向按钮文本不为空，则显示
          _buildFocusableButton(
            focusNode: _focusNodes[focusIndex++],
            onPressed: onNegativePressed,
            label: negativeButtonLabel,
          ),
        if (positiveButtonLabel != null)  // 如果正向按钮文本不为空，则显示
          const SizedBox(width: 20),  // 添加按钮之间的间距
        if (positiveButtonLabel != null)
          _buildFocusableButton(
            focusNode: _focusNodes[focusIndex++],
            onPressed: onPositivePressed,
            label: positiveButtonLabel,
          ),
        if (isCopyButton && content != null)  // 如果是复制按钮，且有内容
          _buildFocusableButton(
            focusNode: _focusNodes[focusIndex++],
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));  // 复制内容到剪贴板
              CustomSnackBar.showSnackBar(
                context,
                S.current.copyok,
                duration: Duration(seconds: 4),
              );
            },
            label: S.current.copy,
          ),
        if (closeButtonLabel != null)  // 底部关闭按钮
          _buildFocusableButton(
            focusNode: _focusNodes[focusIndex++],
            onPressed: onClosePressed ?? () => Navigator.of(context).pop(),
            label: closeButtonLabel,
            autofocus: true,
          ),
      ],
    );
  }

  // 构建可聚焦按钮的方法
  static Widget _buildFocusableButton({
    required FocusNode focusNode,
    required VoidCallback? onPressed,
    required String label,
    bool autofocus = false,
  }) {
    return FocusableItem(
      focusNode: focusNode,
      child: Builder(
        builder: (BuildContext context) {
          final bool hasFocus = Focus.of(context).hasFocus;
          return ElevatedButton(
            style: _buttonStyle(hasFocus),
            onPressed: onPressed,
            autofocus: autofocus,
            child: Text(label),
          );
        },
      ),
    );
  }

  // 动态设置按钮样式
  static ButtonStyle _buttonStyle(bool hasFocus) {
    return ElevatedButton.styleFrom(
      backgroundColor: hasFocus ? darkenColor(selectedColor) : unselectedColor,
      foregroundColor: Colors.white,  // 设置按钮文本的颜色为白色
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0), // 设置上下和左右内边距
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),  // 设置按钮圆角
      ),
      textStyle: TextStyle(
        fontSize: 18,  // 设置按钮文字大小
        fontWeight: hasFocus ? FontWeight.bold : FontWeight.normal,  // 选中时文字加粗
      ),
      alignment: Alignment.center,  // 文字在按钮内部居中对齐
    );
  }

  // 获取关闭按钮的颜色，动态设置焦点状态
  static Color _closeIconColor(bool hasFocus) {
    return hasFocus ? selectedColor : Colors.white;
  }
}
