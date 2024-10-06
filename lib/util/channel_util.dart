import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../provider/theme_provider.dart';
import '../generated/l10n.dart';
import '../tv/tv_key_navigation.dart';
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
    // 显示弹窗，用于选择不同的视频源
    final selectedIndex = await showDialog<int>(
      context: context,
      barrierDismissible: true, // 允许点击外部关闭弹窗
      barrierColor: Colors.transparent, // 设置遮罩层为透明，允许点击背景
      builder: (BuildContext context) {
        // 判断屏幕方向：竖屏或横屏
        final bool isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

        return Stack(
          children: [
            // 使用 Align 控制弹窗位置
            Align(
              alignment: Alignment.bottomCenter, // 弹窗在底部中央对齐
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28.0), // 距离屏幕底部 28 像素
                child: Material(
                  color: Colors.transparent, // 设置弹窗背景透明
                  child: Container(
                    width: isPortrait
                        ? MediaQuery.of(context).size.width * 0.88 // 竖屏时宽度为 88%
                        : MediaQuery.of(context).size.width * 0.68, // 横屏时宽度为 68%
                    padding: const EdgeInsets.all(10), // 内边距
                    decoration: BoxDecoration(
                      color: Colors.black45, // 弹窗背景颜色
                      borderRadius: BorderRadius.circular(16), // 圆角半径
                    ),
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isPortrait
                              ? MediaQuery.of(context).size.width * 0.88 // 竖屏时最大宽度为 88%
                              : MediaQuery.of(context).size.width * 0.68, // 横屏时最大宽度为 68%
                        ),
                        child: isTV
                            ? TvKeyNavigation(
                                focusableWidgets: List.generate(sources.length, (index) {
                                  return buildSourceButton(
                                    context, 
                                    index, 
                                    currentSourceIndex, 
                                    S.current.lineIndex(index + 1), 
                                    isTV,
                                  );
                                }),
                                initialIndex: currentSourceIndex, // 初始聚焦的控件索引
                                onSelect: (index) {
                                  Navigator.pop(context, index); // 返回所选的索引
                                },
                                spacing: 8.0, // 控件间的间距
                                loopFocus: true, // 是否允许焦点循环
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
                  ),
                ),
              ),
            ),
          ],
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
