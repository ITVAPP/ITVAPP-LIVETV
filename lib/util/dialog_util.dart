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
    // 优化部分：生成所需焦点节点，并在对话框关闭时进行释放
    final List<FocusNode> _focusNodes = _generateFocusNodes(
      content: content,
      positiveButtonLabel: positiveButtonLabel,
      negativeButtonLabel: negativeButtonLabel,
      isCopyButton: isCopyButton,
      child: child,
    );

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
              focusNodes: _focusNodes,
              isHorizontalGroup: true, // 启用横向分组
              initialIndex: 1,
              child: Column(
                mainAxisSize: MainAxisSize.min,  // 动态调整高度，适应内容
                children: [
                  // Group 0: 关闭按钮组
                  Group(
                    groupIndex: 0,
                    children: [
                      FocusableItem(
                        focusNode: _focusNodes[0],
                        child: _buildDialogHeader(context, title: title),
                      ),
                    ],
                  ),
                  if (content != null) Flexible(
                    child: FocusableActionDetector(
                      focusNode: _focusNodes[1],
                      shortcuts: {
                        LogicalKeySet(LogicalKeyboardKey.arrowUp): ScrollIntent(direction: AxisDirection.up),
                        LogicalKeySet(LogicalKeyboardKey.arrowDown): ScrollIntent(direction: AxisDirection.down),
                      },
                      actions: {
                        ScrollIntent: CallbackAction<ScrollIntent>(
                          onInvoke: (intent) {
                            if (intent.direction == AxisDirection.up && _focusNodes[1].hasFocus) {
                              FocusScope.of(context).requestFocus(_focusNodes[0]);  // 上键切换到关闭按钮
                            } else if (intent.direction == AxisDirection.down && _focusNodes[1].hasFocus) {
                              FocusScope.of(context).requestFocus(_focusNodes[2]);  // 下键切换到底部按钮
                            }
                            return null;
                          },
                        ),
                      },
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
                                  focusNode: _focusNodes.last,
                                  child: Center(  // 将 child 居中
                                    child: child,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Group 1: 底部按钮组
                  Group(
                    groupIndex: 1,
                    children: [
                      if (positiveButtonLabel != null || negativeButtonLabel != null)
                        _buildActionButtons(
                          context,
                          positiveButtonLabel: positiveButtonLabel,
                          onPositivePressed: onPositivePressed,
                          positiveFocusNode: _focusNodes[2],
                          negativeButtonLabel: negativeButtonLabel,
                          onNegativePressed: onNegativePressed,
                          negativeFocusNode: _focusNodes[3],
                          closeButtonLabel: closeButtonLabel,
                          onClosePressed: onClosePressed,
                          closeActionFocusNode: _focusNodes[0],
                          content: content,  // 传递内容用于复制
                          isCopyButton: isCopyButton,  // 控制是否显示复制按钮
                          copyFocusNode: _focusNodes[4],
                        ),  // 动态按钮处理
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      // 优化部分：确保在对话框关闭时释放所有FocusNode，避免内存泄漏
      for (final node in _focusNodes) {
        node.dispose();
      }
    });
  }

  // Helper方法：生成FocusNode列表
  static List<FocusNode> _generateFocusNodes({
    String? content,
    String? positiveButtonLabel,
    String? negativeButtonLabel,
    bool isCopyButton = false,
    Widget? child,
  }) {
    List<FocusNode> nodes = [];
    nodes.add(FocusNode());  // Close button
    if (content != null) nodes.add(FocusNode());
    if (positiveButtonLabel != null) nodes.add(FocusNode());
    if (negativeButtonLabel != null) nodes.add(FocusNode());
    if (isCopyButton) nodes.add(FocusNode());
    if (child != null) nodes.add(FocusNode());
    return nodes;
  }

  // 封装的标题部分，包含关闭按钮
  static Widget _buildDialogHeader(BuildContext context, {String? title}) {
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
          child: IconButton(
            onPressed: () {
              Navigator.of(context).pop();  // 关闭对话框
            },
            icon: const Icon(Icons.close),  // 使用默认关闭图标
            iconSize: 26,  // 关闭按钮大小
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
    FocusNode? positiveFocusNode,
    String? negativeButtonLabel,
    VoidCallback? onNegativePressed,
    FocusNode? negativeFocusNode,
    String? closeButtonLabel,  // 关闭按钮文本
    VoidCallback? onClosePressed,  // 关闭按钮点击事件
    FocusNode? closeActionFocusNode,
    String? content,  // 传递的内容，用于复制
    bool isCopyButton = false,  // 控制是否显示复制按钮
    FocusNode? copyFocusNode,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,  // 按钮居中
      children: [
        if (negativeButtonLabel != null)  // 如果负向按钮文本不为空，则显示
          FocusableItem(
            focusNode: negativeFocusNode!,
            child: ElevatedButton(
              style: _buttonStyle(negativeFocusNode, unselectedColor: Color(0xFFEB144C), selectedColor: Color(0xFFDFA02A)),
              onPressed: () {
                if (onNegativePressed != null) {
                  onNegativePressed();
                }
              },
              child: Text(negativeButtonLabel!),
            ),
          ),
        if (positiveButtonLabel != null)  // 如果正向按钮文本不为空，则显示
          const SizedBox(width: 20),  // 添加按钮之间的间距
        if (positiveButtonLabel != null)
          FocusableItem(
            focusNode: positiveFocusNode!,
            child: ElevatedButton(
              style: _buttonStyle(positiveFocusNode, unselectedColor: Color(0xFFEB144C), selectedColor: Color(0xFFDFA02A)),
              onPressed: () {
                if (onPositivePressed != null) {
                  onPositivePressed();
                }
              },
              child: Text(positiveButtonLabel!),
            ),
          ),
        if (isCopyButton && content != null)  // 如果是复制按钮，且有内容
          FocusableItem(
            focusNode: copyFocusNode!,
            child: ElevatedButton(
              style: _buttonStyle(copyFocusNode, unselectedColor: Color(0xFFEB144C), selectedColor: Color(0xFFDFA02A)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));  // 复制内容到剪贴板
                CustomSnackBar.showSnackBar(
                  context,
                  S.current.copyok,
                  duration: Duration(seconds: 4),
                );
              },
              child: Text(S.current.copy),
            ),
          ),
        if (!isCopyButton && closeButtonLabel != null)  // 如果显示的是关闭按钮
          FocusableItem(
            focusNode: closeActionFocusNode!,
            child: ElevatedButton(
              style: _buttonStyle(closeActionFocusNode, unselectedColor: Color(0xFFEB144C), selectedColor: Color(0xFFDFA02A)),
              autofocus: true,
              onPressed: () {
                if (onClosePressed != null) {
                  onClosePressed();  // 点击关闭按钮时执行的回调
                } else {
                  Navigator.of(context).pop();  // 如果未传递回调，则默认关闭对话框
                }
              },
              child: Text(closeButtonLabel!),
            ),
          ),
      ],
    );
  }

  // 动态设置按钮样式，使用 unselectedColor 和 selectedColor 实现不同状态的背景颜色
  static ButtonStyle _buttonStyle(FocusNode? focusNode, {required Color unselectedColor, required Color selectedColor}) {
    return ElevatedButton.styleFrom(
      backgroundColor: focusNode != null && focusNode.hasFocus
          ? darkenColor(selectedColor)  // 聚焦时使用选中颜色并变暗
          : unselectedColor,  // 未选中时使用未选中颜色
      foregroundColor: Colors.white,  // 设置按钮文本的颜色为白色
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0), // 设置上下和左右内边距
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),  // 设置按钮圆角
      ),
      textStyle: TextStyle(
        fontSize: 18,  // 设置按钮文字大小
        fontWeight: focusNode != null && focusNode.hasFocus ? FontWeight.bold : FontWeight.normal,  // 选中时加粗
      ),
      alignment: Alignment.center,  // 文字在按钮内部居中对齐
    );
  }

  // 用于将颜色变暗的函数
  static Color darkenColor(Color color, [double amount = 0.1]) {
    final hsl = HSLColor.fromColor(color);
    final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return darkened.toColor();
  }

  // 获取关闭按钮的颜色，动态设置焦点状态
  static Color _closeIconColor(FocusNode? focusNode) {
    return focusNode != null && focusNode.hasFocus
        ? const Color(0xFFEB144C)  // 焦点状态下的颜色
        : Colors.white;  // 默认颜色为白色
  }
}
