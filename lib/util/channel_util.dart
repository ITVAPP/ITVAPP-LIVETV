import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';
import '../generated/l10n.dart';
import 'log_util.dart';
import '../tv/tv_key_navigation.dart';

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

  LogUtil.i('显示视频源选择弹窗');
  
  // 判断是否是 TV 模式
  bool isTV = context.watch<ThemeProvider>().isTV;

  // 使用 Overlay 显示弹窗
  OverlayEntry? overlayEntry;

  try {
    // 创建 OverlayEntry 并定义弹窗内容
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,  // 避免与底部重叠
        left: 0,  // 左边距为 0
        right: 0,  // 右边距为 0
        child: FractionallySizedBox(
          widthFactor: 0.8, // 设置弹窗宽度为屏幕的80%
          alignment: Alignment.center,
          child: Material(
            color: Colors.transparent,  // 背景设为透明，便于自定义样式
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xff6D6875),  // 渐变颜色1
                    Color(0xffB4838D),  // 渐变颜色2
                    Color(0xffE5989B),  // 渐变颜色3
                  ],
                ),
                borderRadius: BorderRadius.circular(20),  // 设置圆角
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,  // 阴影颜色
                    offset: Offset(0, 4),  // 阴影偏移
                    blurRadius: 8,  // 模糊半径
                  ),
                ],
              ),
              padding: const EdgeInsets.all(10),  // 设置内边距
              child: FocusTraversalGroup(
                policy: WidgetOrderTraversalPolicy(), // 确保焦点顺序处理
                child: isTV
                    ? TvKeyNavigation(  // 使用 TvKeyNavigation 处理 TV 焦点和按键
                        focusableWidgets: List.generate(sources.length, (index) {
                          return buildSourceButton(
                            context, 
                            index, 
                            currentSourceIndex, 
                            S.current.lineIndex(index + 1), 
                            isTV,
                          );
                        }),
                        initialIndex: currentSourceIndex, // 初始选中的视频源索引
                        onSelect: (index) {
                          Navigator.pop(context, index); // 返回所选视频源索引
                        },
                        spacing: 8.0,  // 控件之间的间距
                        loopFocus: true,  // 开启循环焦点切换
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
    );

    // 插入 OverlayEntry 到屏幕上
    Overlay.of(context)?.insert(overlayEntry);

    // 等待用户选择按钮并获取所选视频源索引
    return await Future<int?>.delayed(
      const Duration(seconds: 4),  // 自动关闭弹窗
      () => currentSourceIndex,  // 模拟用户选择
    );

  } catch (modalError, modalStackTrace) {
    // 捕获弹窗显示过程中发生的错误，并记录日志
    LogUtil.logError('弹出窗口时出错', modalError, modalStackTrace);
    return null;
  } finally {
    // 移除 OverlayEntry
    overlayEntry?.remove();
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
