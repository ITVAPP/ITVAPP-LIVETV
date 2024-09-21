import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 用于复制到剪贴板

class DialogUtil {
  // 显示通用的弹窗，接受标题、内容、正向/负向按钮文本和点击回调
  static Future<bool?> showCustomDialog(
    BuildContext context, {
    String? title,  // 动态标题
    String? content,  // 动态内容
    String? positiveButtonLabel,  // 正向按钮文本
    VoidCallback? onPositivePressed,  // 正向按钮点击回调
    String? negativeButtonLabel,  // 负向按钮文本（可选）
    VoidCallback? onNegativePressed,  // 负向按钮点击回调
    String? closeButtonLabel,  // 底部关闭按钮文本（可选）
    VoidCallback? onClosePressed,  // 关闭按钮点击回调（可选）
    bool isDismissible = true,  // 是否允许点击对话框外部关闭
    bool isCopyButton = false,  // 新增参数：是否显示复制按钮
  }) {
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
            child: FocusTraversalGroup(
              policy: WidgetOrderTraversalPolicy(), // TV端焦点遍历策略
              child: Column(
                mainAxisSize: MainAxisSize.min,  // 动态调整高度，适应内容
                children: [
                  _buildDialogHeader(context, title: title),  // 调用封装的标题部分
                  Expanded(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: _buildDialogContent(content: content), // 调用封装的内容部分
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
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
                  const SizedBox(height: 15),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 封装的标题部分，包含关闭按钮
  static Widget _buildDialogHeader(BuildContext context, {String? title}) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          alignment: Alignment.center,
          child: Text(
            title ?? 'Notification 🚀',  // 动态标题
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
          ),
        ),
        Positioned(
          right: 0,
          // 去掉 Focus 包裹，直接使用 IconButton
          child: IconButton(
            onPressed: () async {
              // 异步关闭弹窗，避免 UI 阻塞
              Future.microtask(() {
                Navigator.of(context).pop();  // 直接关闭对话框，不传递 false
              });
            },
            icon: const Icon(Icons.close),
          ),
        ),
      ],
    );
  }

  // 封装的内容部分，禁用复制功能
  static Widget _buildDialogContent({String? content}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        TextField(
          controller: TextEditingController(text: content ?? 'No content available'),  // 显示的内容
          readOnly: true,  // 设置为只读
          maxLines: null,  // 允许多行显示
          decoration: const InputDecoration(
            border: InputBorder.none,  // 去掉边框
          ),
          style: const TextStyle(fontSize: 14),  // 设置文本样式
          enableInteractiveSelection: false,  // 禁用交互式选择功能，取消复制功能
        ),
      ],
    );
  }

  // 提取重复的按钮样式
  static ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFFEB144C),  // 按钮背景颜色
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),  // 设置圆角
      ),
      textStyle: const TextStyle(fontSize: 15),  // 按钮文字大小
    );
  }

  // 动态生成按钮
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
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (negativeButtonLabel != null)  // 如果负向按钮文本不为空，则显示
          ElevatedButton(
            style: _buttonStyle(),  // 复用按钮样式
            onPressed: () {
              if (onNegativePressed != null) {
                onNegativePressed();
              }
            },
            child: Text(negativeButtonLabel!, style: const TextStyle(color: Colors.white)),
          ),
        if (positiveButtonLabel != null)  // 如果正向按钮文本不为空，则显示
          ElevatedButton(
            style: _buttonStyle(),  // 复用按钮样式
            onPressed: () {
              if (onPositivePressed != null) {
                onPositivePressed();
              }
            },
            child: Text(positiveButtonLabel!, style: const TextStyle(color: Colors.white)),
          ),
        if (isCopyButton && content != null)  // 如果是复制按钮，且有内容
          ElevatedButton(
            style: _buttonStyle(),  // 复用按钮样式
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));  // 复制内容到剪贴板
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已复制到剪贴板')),
              );
            },
            child: const Text('复制', style: TextStyle(color: Colors.white)),
          ),
        if (!isCopyButton && closeButtonLabel != null)  // 如果显示的是关闭按钮
          ElevatedButton(
            style: _buttonStyle(),  // 复用按钮样式
            onPressed: () {
              if (onClosePressed != null) {
                onClosePressed();  // 点击关闭按钮时执行的回调
              } else {
                Navigator.of(context).pop();  // 如果未传递回调，则默认关闭对话框
              }
            },
            child: Text(closeButtonLabel!, style: const TextStyle(color: Colors.white)),
          ),
      ],
    );
  }
}
