import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../provider/theme_provider.dart';
import '../generated/l10n.dart';
import 'log_util.dart';

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
    // 显示底部弹窗，用于选择不同的视频源
    final selectedIndex = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true, // 使用根导航器，确保弹窗显示在顶层
      barrierColor: Colors.transparent, // 弹窗背景的屏障颜色设为透明
      backgroundColor: Colors.black38, // 弹窗背景颜色
      builder: (BuildContext context) {
        return SingleChildScrollView(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20),
            color: Colors.transparent, // 容器背景设为透明
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7, // 设置弹窗内容最大宽度
              ),
              child: isTV
                  ? FocusScope(
                      autofocus: true, // 自动聚焦第一个按钮
                      child: Wrap(
                        spacing: 8, // 按钮之间的水平间距
                        runSpacing: 8, // 按钮之间的垂直间距
                        children: List.generate(sources.length, (index) {
                          return Focus(
                            onKey: (node, event) {
                              // 限制焦点在弹窗内部，只处理上下左右键事件
                              if (event is RawKeyDownEvent) {
                                if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                                    event.logicalKey == LogicalKeyboardKey.arrowUp ||
                                    event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                                    event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
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
