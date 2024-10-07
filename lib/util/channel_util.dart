import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';
import 'log_util.dart';
import '../tv/tv_key_navigation.dart';
import '../generated/l10n.dart';

/// 显示底部弹出框选择不同的视频源
Future<int?> changeChannelSources(
  BuildContext context, 
  List<String>? sources, 
  int currentSourceIndex,
) async {
  // 如果 sources 为空或未找到有效的视频源，记录日志并返回 null
  if (sources == null || sources.isEmpty) {
    LogUtil.e('未找到有效的视频源');
    return null;
  }

  // 判断是否是 TV 模式
  bool isTV = context.watch<ThemeProvider>().isTV;

  try {
    // 获取屏幕的方向信息
    var orientation = MediaQuery.of(context).orientation;
    double widthFactor;
    double bottomPadding;

    // 根据方向设置宽度和底部间距
    if (orientation == Orientation.landscape) {
      widthFactor = 0.68; // 横屏时宽度为68%
      bottomPadding = 88.0; // 横屏时距离底部88
    } else {
      widthFactor = 0.88; // 竖屏时宽度为88%
      bottomPadding = 68.0; // 竖屏时距离底部68
    }

    // 显示自定义弹窗，用于选择不同的视频源
    final selectedIndex = await showDialog<int>(
      context: context,
      barrierDismissible: true, // 允许点击外部关闭弹窗
      barrierColor: Colors.transparent, // 取消遮罩层
      builder: (BuildContext context) {
        return Dialog( // 使用Dialog代替AlertDialog
          backgroundColor: Colors.transparent, // 背景设为透明，便于自定义
          child: Container(
            width: MediaQuery.of(context).size.width * widthFactor, // 根据屏幕方向设置宽度
            padding: EdgeInsets.only(left: 10, right: 10, top: 10, bottom: bottomPadding), // 根据方向设置底部间距
            decoration: BoxDecoration(
              color: Colors.black54, // 设置弹窗背景颜色
              borderRadius: BorderRadius.circular(12), // 添加圆角
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * widthFactor, // 限制弹窗最大宽度
              ),
              child: isTV
                  ? TvKeyNavigation(
                      focusNodes: List.generate(sources.length, (index) => FocusNode()),
                      initialIndex: currentSourceIndex,
                      loopFocus: true, // 启用循环焦点
                      child: Wrap(
                        spacing: 8, // 按钮之间的水平间距
                        runSpacing: 8, // 按钮之间的垂直间距
                        children: List.generate(sources.length, (index) {
                          return FocusableItem(
                            focusNode: FocusNode(),
                            isFocused: currentSourceIndex == index,
                            child: buildSourceButton(
                              context, 
                              index, 
                              currentSourceIndex, 
                              S.current.lineIndex(index + 1), 
                              isTV,
                            ),
                          );
                        }),
                      ),
                    )
                  : Wrap(
                      spacing: 10, // 按钮之间的水平间距
                      runSpacing: 10, // 按钮之间的垂直间距
                      children: List.generate(sources.length, (index) {
                        return buildSourceButton(
                          context, 
                          index, 
                          currentSourceIndex, 
                          S.current.lineIndex(index + 1), 
                          isTV,
                        );
                      }),
                    ),
            ),
          ),
        );
      },
    );

    // 返回用户选择的索引
    return selectedIndex;
  } catch (modalError, modalStackTrace) {
    // 捕获弹窗显示过程中发生的错误，并记录日志
    LogUtil.logError('弹出窗口时出错', modalError, modalStackTrace);
    return null;
  }
}

/// 获取按钮样式
ButtonStyle getButtonStyle(bool isSelected) {
  return OutlinedButton.styleFrom(
    padding: EdgeInsets.symmetric(vertical: 2, horizontal: 6), // 设置按钮内边距
    backgroundColor: isSelected
        ? Color(0xFFEB144C) // 选中按钮背景颜色
        : Color(0xFFDFA02A), // 未选中按钮背景颜色
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16), // 按钮的圆角半径
    ),
  );
}

/// 构建视频源按钮
Widget buildSourceButton(
  BuildContext context, 
  int index, 
  int currentSourceIndex, 
  String label, 
  bool isTV
) {
  return OutlinedButton(
    autofocus: currentSourceIndex == index, // 自动聚焦当前选中的按钮
    style: getButtonStyle(currentSourceIndex == index),
    onPressed: currentSourceIndex == index
        ? null // 如果按钮是当前选中的源，禁用点击
        : () {
            Navigator.pop(context, index); // 返回所选按钮的索引
          },
    child: Text(
      label, // 显示按钮文字，使用多语言支持
      textAlign: TextAlign.center, // 文字在按钮内部居中对齐
      style: TextStyle(
        fontSize: 16, // 字体大小
        color: Colors.white, // 文字颜色为白色
        fontWeight: currentSourceIndex == index
            ? FontWeight.bold // 选中按钮文字加粗
            : FontWeight.normal, // 未选中按钮文字为正常字体
      ),
    ),
  );
}
