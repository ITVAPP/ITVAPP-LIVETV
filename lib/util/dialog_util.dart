import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:itvapp_live_tv/util/log_util.dart'; 
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import '../generated/l10n.dart';
import 'tv_key_navigation.dart'; // 引入 TvKeyNavigation 组件

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
      // 日志条目反转，确保最新日志在最前面
      logs = logs.reversed.toList();
      
      // 时间和内容分别占两行
      content = logs.map((log) {
        String time = log['time']!;
        String parsedMessage = LogUtil.parseLogMessage(log['message']!);
        return '$time\n$parsedMessage';  // 每条日志的时间和内容分两行显示
      }).join('\n\n');  // 在每条日志之间增加换行
    } 

    // 构建焦点可切换的控件列表
    List<Widget> focusableWidgets = [];
    
    // 如果有内容，显示内容区域
    if (content != null) {
      focusableWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: _buildDialogContent(content: content),
        )
      );
    }

    // 如果没有自定义的子控件，则显示按钮区域
    if (child == null) {
      focusableWidgets.add(
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
      );
    } else {
      focusableWidgets.add(Center(child: child));  // 显示自定义子控件并居中
    }

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
            child: TvKeyNavigation(  // 使用 TvKeyNavigation 管理焦点
              focusableWidgets: focusableWidgets, // 将焦点可切换的控件传递给 TvKeyNavigation
              onSelect: (index) {
                if (index == focusableWidgets.length - 1) {
                  // 如果最后一个控件是关闭按钮，触发关闭逻辑
                  if (onClosePressed != null) {
                    onClosePressed();
                  } else {
                    Navigator.of(context).pop();
                  }
                }
              },
              spacing: 10.0,  // 控件之间的间距
              loopFocus: true,  // 允许焦点循环切换
              isFrame: false,  // 不需要框架切换
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
          child: Theme(
            data: Theme.of(context).copyWith(
              iconTheme: IconThemeData(
                color: _closeIconColor(closeFocusNode),  // 设置关闭按钮颜色
              ),
            ),
            child: IconButton(
              focusNode: closeFocusNode,  // 关闭按钮的焦点节点
              onPressed: () {
                Navigator.of(context).pop();  // 关闭对话框
              },
              icon: const Icon(Icons.close),  // 使用默认关闭图标
              iconSize: 26,  // 关闭按钮大小
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
    String? closeButtonLabel,  // 关闭按钮文本
    VoidCallback? onClosePressed,  // 关闭按钮点击事件
    String? content,  // 传递的内容，用于复制
    bool isCopyButton = false,  // 控制是否显示复制按钮
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,  // 按钮居中
      children: [
        if (negativeButtonLabel != null)  // 如果负向按钮文本不为空，则显示
          ElevatedButton(
            onPressed: () {
              if (onNegativePressed != null) {
                onNegativePressed();
              }
            },
            child: Text(negativeButtonLabel!),
          ),
        if (positiveButtonLabel != null)  // 如果正向按钮文本不为空，则显示
          const SizedBox(width: 20),  // 添加按钮之间的间距
        if (positiveButtonLabel != null)
          ElevatedButton(
            onPressed: () {
              if (onPositivePressed != null) {
                onPositivePressed();
              }
            },
            child: Text(positiveButtonLabel!),
          ),
        if (isCopyButton && content != null)  // 如果是复制按钮，且有内容
          ElevatedButton(
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
        if (!isCopyButton && closeButtonLabel != null)  // 如果显示的是关闭按钮
          ElevatedButton(
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
      ],
    );
  }
}
