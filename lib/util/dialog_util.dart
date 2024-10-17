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
                  _buildDialogHeader(context, title: title, closeFocusNode: _focusNodes[0]),  // 传递关闭按钮的焦点节点
                  Flexible( 
                    child: FocusableActionDetector(
                      shortcuts: {
                        LogicalKeySet(LogicalKeyboardKey.arrowUp): ScrollIntent(direction: AxisDirection.up),
                        LogicalKeySet(LogicalKeyboardKey.arrowDown): ScrollIntent(direction: AxisDirection.down),
                      },
                      actions: {
                        ScrollIntent: CallbackAction<ScrollIntent>(
                          onInvoke: (intent) {
                            if (intent.direction == AxisDirection.up) {
                              FocusScope.of(context).requestFocus(_focusNodes[0]);  // 上键切换到关闭按钮
                            } else if (intent.direction == AxisDirection.down) {
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
                                Center(  // 将 child 居中
                                  child: child,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (child == null)
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
                      focusIndex: focusIndex,  // 传递焦点索引用于按钮动态焦点处理
                    ),  // 动态按钮处理
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
          child: Theme(
            data: Theme.of(context).copyWith(
              iconTheme: IconThemeData(
                color: _closeIconColor(closeFocusNode),  // 设置关闭按钮颜色
              ),
            ),
            child: IconButton(
              onPressed: () {
                Navigator.of(context).pop();  // 关闭对话框
              },
              icon: const Icon(Icons.close),  // 使用默认关闭图标
              iconSize: 26,  // 关闭按钮大小
            ),
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
    required int focusIndex,  // 传递焦点索引，required 修饰
    String? positiveButtonLabel,
    VoidCallback? onPositivePressed,
    String? negativeButtonLabel,
    VoidCallback? onNegativePressed,
    String? closeButtonLabel,  // 关闭按钮文本
    VoidCallback? onClosePressed,  // 关闭按钮点击事件
    String? content,  // 传递的内容，用于复制
    bool isCopyButton = false,  // 控制是否显示复制按钮
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,  // 按钮居中
      children: [
        Group(
          groupIndex: 1,  // 将所有按钮放在同一组
          children: [
            if (negativeButtonLabel != null)  // 如果负向按钮文本不为空，则显示
              FocusableItem(
                focusNode: _focusNodes[focusIndex++],  // 递增焦点索引
                child: ElevatedButton(
                  style: _buttonStyle(_focusNodes[focusIndex - 1]),
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
                focusNode: _focusNodes[focusIndex++],  // 递增焦点索引
                child: ElevatedButton(
                  style: _buttonStyle(_focusNodes[focusIndex - 1]),
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
                focusNode: _focusNodes[focusIndex++],  // 递增焦点索引
                child: ElevatedButton(
                  style: _buttonStyle(_focusNodes[focusIndex - 1]),
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
                focusNode: _focusNodes[focusIndex++],  // 递增焦点索引
                child: ElevatedButton(
                  style: _buttonStyle(_focusNodes[focusIndex - 1]),
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
        ),
      ],
    );
  }

  // 动态设置按钮样式
  static ButtonStyle _buttonStyle(FocusNode? focusNode) {
    return ElevatedButton.styleFrom(
      backgroundColor: _getButtonColor(focusNode),
      foregroundColor: Colors.white,  // 设置按钮文本的颜色为白色
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0), // 设置上下和左右内边距
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),  // 设置按钮圆角
      ),
      textStyle: TextStyle(
        fontSize: 18,  // 设置按钮文字大小
        fontWeight: (focusNode != null && focusNode.hasFocus)
            ? FontWeight.bold  // 选中时文字加粗
            : FontWeight.normal,  // 未选中时文字正常
      ),
      alignment: Alignment.center,  // 文字在按钮内部居中对齐
    );
  }

  // 获取按钮的背景颜色，根据焦点状态进行切换
  static Color _getButtonColor(FocusNode? focusNode) {
    return focusNode != null && focusNode.hasFocus
        ? const Color(0xFFEB144C)  // 焦点状态下的颜色
        : const Color(0xFFDFA02A);  // 默认未选中时的颜色
  }

  // 获取关闭按钮的颜色，动态设置焦点状态
  static Color _closeIconColor(FocusNode? focusNode) {
    return focusNode != null && focusNode.hasFocus
        ? const Color(0xFFEB144C)  // 焦点状态下的颜色
        : Colors.white;  // 默认颜色为白色
  }
}
