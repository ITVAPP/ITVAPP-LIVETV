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

  // 创建一次性的 FocusNode 列表，无需为每个 FocusNode 添加监听器
  final List<FocusNode> focusNodes = List.generate(sources.length, (index) => FocusNode());

  // 定义选中与未选中的颜色变量
  final Color selectedColor = const Color(0xFFEB144C); // 选中时背景颜色
  final Color unselectedColor = const Color(0xFFDFA02A); // 未选中时背景颜色

  try {
    // 计算屏幕的方向、宽度和底部间距
    var orientation = MediaQuery.of(context).orientation;
    final widthFactor = orientation == Orientation.landscape ? 0.78 : 0.88;
    final bottomOffset = orientation == Orientation.landscape ? 58.0 : 68.0; // 横屏88.0，竖屏68.0

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
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)), // 仅上边缘圆角
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * widthFactor, // 限制弹窗最大宽度
                  maxHeight: MediaQuery.of(context).size.height * 0.7, // 限制弹窗最大高度为屏幕的70%
                ),
                child: buildSourceButtons(context, sources, currentSourceIndex, focusNodes, selectedColor, unselectedColor), // 传递颜色
              ),
            ),
          ),
        );
      },
    );

    // 返回用户选择的索引
    return selectedIndex;
  } catch (modalError, modalStackTrace) {
    LogUtil.logError('弹出窗口时出错', modalError, modalStackTrace);
    return null;
  } finally {
    for (var node in focusNodes) {
      node.dispose();
    }
  }
}

/// 构建视频源按钮组
Widget buildSourceButtons(
  BuildContext context, 
  List<String> sources, 
  int currentSourceIndex,
  List<FocusNode> focusNodes, // 传递预先创建的焦点节点
  Color selectedColor, // 接收选中时的颜色
  Color unselectedColor, // 接收未选中时的颜色
) {
  return StatefulBuilder(
    builder: (context, setState) {
      return Wrap(
        spacing: 8, // 按钮之间的水平间距
        runSpacing: 8, // 按钮之间的垂直间距
        children: List.generate(sources.length, (index) {
          FocusNode focusNode = focusNodes[index];
          bool isSelected = currentSourceIndex == index; // 判断是否为当前选中项

          // 为每个 FocusNode 添加监听器，在焦点状态改变时调用 setState 重新渲染
          focusNode.addListener(() {
            setState(() {});
          });

          return FocusableItem(
            focusNode: focusNode, // 使用外部传入的 FocusNode
            child: OutlinedButton(
              style: getButtonStyle(
                isSelected: isSelected,
                isFocused: focusNode.hasFocus, // 实时判断是否获得焦点
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
          );
        }),
      );
    },
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
