import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
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

  // 创建一次性的 FocusNode 列表，根据 sources 的长度动态生成
  final List<FocusNode> focusNodes = List.generate(sources.length, (index) => FocusNode());

  try {
    // 计算屏幕的方向、宽度和底部间距
    var orientation = MediaQuery.of(context).orientation;
    final widthFactor = orientation == Orientation.landscape ? 0.68 : 0.88;
    final bottomOffset = orientation == Orientation.landscape ? 88.0 : 68.0; // 横屏88.0，竖屏68.0

    // 使用 showModalBottomSheet 来创建一个从底部弹出的弹窗
    final selectedIndex = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true, // 允许高度根据内容调整
      backgroundColor: Colors.transparent, // 背景透明，便于自定义样式
      builder: (BuildContext context) {
        return TvKeyNavigation( // 包裹整个弹窗，确保焦点管理覆盖所有内容
          focusNodes: focusNodes,
          initialIndex: currentSourceIndex,
          child: Padding(
            // 设置弹窗和屏幕底部的距离
            padding: EdgeInsets.only(bottom: bottomOffset),
            child: Container(
              width: MediaQuery.of(context).size.width * widthFactor, // 根据屏幕方向设置宽度
              padding: EdgeInsets.all(10), // 内边距设置
              decoration: BoxDecoration(
                color: Colors.black54, // 设置弹窗背景颜色
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)), // 仅上边缘圆角
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * widthFactor, // 限制弹窗最大宽度
                  maxHeight: MediaQuery.of(context).size.height * 0.7, // 限制弹窗最大高度为屏幕的70%
                ),
                child: buildSourceContent(context, sources, currentSourceIndex, isTV, focusNodes),
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
  } finally {
    // 释放所有 FocusNode 的资源
    for (var node in focusNodes) {
      node.dispose();
    }
  }
}

/// 构建不同设备的弹窗内容（TV或非TV）
Widget buildSourceContent(
  BuildContext context, 
  List<String> sources, 
  int currentSourceIndex, 
  bool isTV,
  List<FocusNode> focusNodes, // 传递预先创建的 FocusNode 列表
) {
  if (isTV) {
    // 使用 TvKeyNavigation 包裹按钮组，支持 TV 模式的按键导航
    return TvKeyNavigation(
      focusNodes: focusNodes, // 传入已生成的焦点节点
      initialIndex: currentSourceIndex,
      child: buildSourceButtons(context, sources, currentSourceIndex, isTV, focusNodes),
    );
  } else {
    return buildSourceButtons(context, sources, currentSourceIndex, isTV, focusNodes);
  }
}

/// 构建视频源按钮组
Widget buildSourceButtons(
  BuildContext context, 
  List<String> sources, 
  int currentSourceIndex, 
  bool isTV,
  List<FocusNode> focusNodes, // 传递预先创建的焦点节点
) {
  Color selectedColor = Color(0xFFDFA02A); // 选中时的背景色
  Color unselectedColor = Color(0xFFEB144C); // 未选中时的背景色

  return Wrap(
    spacing: 8, // 按钮之间的水平间距
    runSpacing: 8, // 按钮之间的垂直间距
    children: List.generate(sources.length, (index) {
      FocusNode focusNode = focusNodes[index];
      bool isSelected = currentSourceIndex == index; // 判断是否为当前选中项

      return FocusableItem(
        focusNode: focusNode, // 使用外部传入的 FocusNode
        child: Focus(
          focusNode: focusNode,
          onFocusChange: (hasFocus) {
            // 焦点变化时更新 UI
            if (hasFocus) {
              (context as Element).markNeedsBuild();
            }
          },
          child: OutlinedButton(
            autofocus: isSelected, // 自动聚焦当前选中的按钮
            style: getButtonStyle(
              isSelected: isSelected,
              isFocused: focusNode.hasFocus,
              selectedColor: selectedColor,
              unselectedColor: unselectedColor,
            ),
            onPressed: isSelected
                ? null // 如果按钮是当前选中的源，禁用点击
                : () {
                    Navigator.pop(context, index); // 返回所选按钮的索引
                  },
            child: Text(
              S.current.lineIndex(index + 1), // 显示按钮文字，使用多语言支持
              textAlign: TextAlign.center, // 文字在按钮内部居中对齐
              style: TextStyle(
                fontSize: 16, // 字体大小
                color: Colors.white, // 文字颜色为白色
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, // 选中按钮文字加粗
              ),
            ),
          ),
        ),
      );
    }),
  );
}

/// 获取按钮样式
ButtonStyle getButtonStyle({
  required bool isSelected, 
  required bool isFocused, 
  required Color selectedColor, 
  required Color unselectedColor,
}) {
  Color backgroundColor = isSelected
      ? selectedColor // 如果选中则使用选中的颜色
      : unselectedColor; // 未选中时使用未选中的颜色

  if (isFocused) {
    backgroundColor = darkenColor(backgroundColor); // 焦点聚焦时变暗
  }

  return OutlinedButton.styleFrom(
    padding: EdgeInsets.symmetric(vertical: 2, horizontal: 6), // 设置按钮内边距
    backgroundColor: backgroundColor, // 根据状态设置背景颜色
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16), // 按钮的圆角半径
    ),
  );
}

/// 用于将颜色变暗的函数
Color darkenColor(Color color, [double amount = 0.2]) {
  final hsl = HSLColor.fromColor(color);
  final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
  return darkened.toColor();
}
