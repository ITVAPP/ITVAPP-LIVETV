import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import '../generated/l10n.dart';

class DialogUtil {
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
    Widget? child,  // 新增参数：自定义Widget（如按钮）
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

    // 定义焦点节点
    final List<FocusNode> _focusNodes = [];
    int focusIndex = 0;  // 焦点节点计数器

    // 定义创建并添加焦点节点的函数，确保顺序正确
    FocusNode createFocusNode() {
      FocusNode node = FocusNode();
      _focusNodes.add(node);
      focusIndex++;
      return node;
    }

    if (closeButtonLabel != null) createFocusNode();
    if (positiveButtonLabel != null) createFocusNode();
    if (negativeButtonLabel != null) createFocusNode();
    if (isCopyButton) createFocusNode();
    if (child != null) createFocusNode();

    // 定义默认选中和未选中的颜色
    Color selectedColor = const Color(0xFFDFA02A);  // 选中时的颜色
    Color unselectedColor = const Color(0xFFEB144C);  // 未选中时的颜色

    return showDialog<bool>(
      context: context,
      barrierDismissible: isDismissible,  // 是否允许点击对话框外部关闭
      builder: (BuildContext context) {
        // 获取屏幕的宽度和高度
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        // 判断屏幕方向，决定对话框宽度比例
        final isPortrait = screenHeight > screenWidth;
        final dialogWidth = isPortrait ? screenWidth * 0.8 : screenWidth * 0.6;  // 根据屏幕方向调整弹窗宽度
        final maxDialogHeight = screenHeight * 0.8;  // 设置对话框的最大高度为屏幕高度的80%

        return Center(
          child: Container(
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
              isHorizontalGroup: true, // 启用横向分组
              child: Column(
                mainAxisSize: MainAxisSize.min,  // 动态调整高度，适应内容
                children: [
                  _buildDialogHeader(context, title: title, closeFocusNode: _focusNodes[0]),
                  Flexible(
                    child: SingleChildScrollView(  // 去除了 FocusableActionDetector 和 contentFocusNode
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 25),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,  // 内容容器水平居中
                          children: [
                            if (content != null) _buildDialogContent(content: content),  // 如果有 content，显示内容
                            const SizedBox(height: 10),
                            if (child != null)
                              Group(
                                groupIndex: 1,  // 如果有外部传入的 child，包裹成可导航焦点，分到 groupIndex=1
                                child: Center(
                                  child: FocusableItem(
                                    focusNode: _focusNodes[1],  // 确保焦点传递给第一个可用的 child
                                    child: child,  // 传入自定义的 child
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (child == null)
                    Group(
                      groupIndex: 1,  // 将所有按钮放在同一组
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,  // 按钮居中
                        children: [
                          if (negativeButtonLabel != null)  // 如果负向按钮文本不为空，则显示
                            _buildButton(
                              focusNodes[focusIndex++],  // 动态获取焦点
                              negativeButtonLabel!,
                              onNegativePressed,
                              selectedColor,
                              unselectedColor,
                            ),
                          if (positiveButtonLabel != null)  // 如果正向按钮文本不为空，则显示
                            const SizedBox(width: 20),  // 添加按钮之间的间距
                          if (positiveButtonLabel != null)
                            _buildButton(
                              focusNodes[focusIndex++],  // 动态获取焦点
                              positiveButtonLabel!,
                              onPositivePressed,
                              selectedColor,
                              unselectedColor,
                            ),
                          if (isCopyButton && content != null)  // 如果是复制按钮，且有内容
                            _buildButton(
                              focusNodes[focusIndex++],  // 动态获取焦点
                              S.current.copy,
                              () {
                                Clipboard.setData(ClipboardData(text: content));  // 复制内容到剪贴板
                                CustomSnackBar.showSnackBar(
                                  context,
                                  S.current.copyok,
                                  duration: Duration(seconds: 4),
                                );
                              },
                              selectedColor,
                              unselectedColor,
                            ),
                          if (!isCopyButton && closeButtonLabel != null)  // 如果显示的是关闭按钮
                            _buildButton(
                              focusNodes[focusIndex++],  // 动态获取焦点
                              closeButtonLabel!,
                              onClosePressed ?? () => Navigator.of(context).pop(),
                              selectedColor,
                              unselectedColor,
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 封装的标题部分，包含关闭按钮
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
          child: Group(  // 分组关闭按钮
            groupIndex: 0,
            child: FocusableItem(  // 仅包裹关闭按钮
              focusNode: closeFocusNode!,  // 使用传入的焦点节点
              child: IconButton(
                onPressed: () {
                  Navigator.of(context).pop();  // 关闭对话框
                },
                icon: const Icon(Icons.close),  // 使用默认关闭图标
                iconSize: 26,  // 关闭按钮大小
                color: _closeIconColor(closeFocusNode),  // 动态设置关闭按钮颜色
              ),
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
        Text(
          content ?? '',  // 显示内容，没有则显示为空
          textAlign: TextAlign.start,  // 文本水平默认左对齐
          style: const TextStyle(fontSize: 18),  // 设置文本样式
        ),
      ],
    );
  }

  // 抽象的按钮生成方法
  static Widget _buildButton(
    FocusNode focusNode,
    String label,
    VoidCallback? onPressed,
    Color selectedColor,
    Color unselectedColor,
  ) {
    return FocusableItem(
      focusNode: focusNode,  // 根据索引分配焦点节点
      child: ElevatedButton(
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.focused)) {
              return darkenColor(selectedColor);  // 聚焦时变暗
            } else if (states.contains(MaterialState.pressed) ||
                states.contains(MaterialState.hovered)) {
              return selectedColor;  // 选中时颜色
            }
            return unselectedColor;  // 未选中时颜色
          }),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }

  // 获取关闭按钮的颜色，动态设置焦点状态
  static Color _closeIconColor(FocusNode? focusNode) {
    return focusNode != null && focusNode.hasFocus
        ? const Color(0xFFEB144C)  // 焦点状态下的颜色
        : Colors.white;  // 默认颜色为白色
  }

  // 用于将颜色变暗的函数
  static Color darkenColor(Color color, [double amount = 0.2]) {
    final hsl = HSLColor.fromColor(color);
    final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return darkened.toColor();
  }
}
