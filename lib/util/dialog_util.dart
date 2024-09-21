import 'package:flutter/material.dart';

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
    bool isDismissible = true,  // 是否允许点击对话框外部关闭
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
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _buildDialogContent(content: content), // 调用封装的内容部分
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildActionButtons(
                    context,
                    positiveButtonLabel: positiveButtonLabel,
                    onPositivePressed: onPositivePressed,
                    negativeButtonLabel: negativeButtonLabel,
                    onNegativePressed: onNegativePressed,
                  ),  // 动态按钮处理
                  const SizedBox(height: 30),
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
          padding: const EdgeInsets.all(20),
          alignment: Alignment.center,
          child: Text(
            title ?? 'Notification 🚀',  // 动态标题
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
          ),
        ),
        Positioned(
          right: 0,
          child: Focus(
            child: IconButton(
              onPressed: () {
                Navigator.of(context).pop(false);  // 点击关闭按钮，关闭对话框
              },
              icon: const Icon(Icons.close),
            ),
          ),
        ),
      ],
    );
  }

  // 封装的内容部分，允许内容复制
  static Widget _buildDialogContent({String? content}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        SelectableText(
          content ?? 'No content available',  // 动态内容，使用 SelectableText 启用复制
          style: const TextStyle(fontSize: 14),
          enableInteractiveSelection: true,  // 启用文本选择
        ),
      ],
    );
  }

  // 动态生成按钮
  static Widget _buildActionButtons(
    BuildContext context, {
    String? positiveButtonLabel,
    VoidCallback? onPositivePressed,
    String? negativeButtonLabel,
    VoidCallback? onNegativePressed,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (negativeButtonLabel != null)  // 如果负向按钮文本不为空，则显示
          ElevatedButton(
            onPressed: () {
              if (onNegativePressed != null) {
                onNegativePressed();
              }
              Navigator.of(context).pop(false);  // 点击后关闭对话框
            },
            child: Text(negativeButtonLabel),
          ),
        ElevatedButton(
          onPressed: () {
            if (onPositivePressed != null) {
              onPositivePressed();
            }
            Navigator.of(context).pop(true);  // 点击后关闭对话框
          },
          child: Text(positiveButtonLabel ?? 'OK'),  // 正向按钮，文本默认为 'OK'
        ),
      ],
    );
  }
}
