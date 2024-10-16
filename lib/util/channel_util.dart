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

  // 创建一次性的 FocusNode 列表
  final List<FocusNode> focusNodes = List.generate(sources.length, (index) => FocusNode());

  try {
    // 计算屏幕的方向、宽度和底部间距
    var orientation = MediaQuery.of(context).orientation;
    final widthFactor = orientation == Orientation.landscape ? 0.68 : 0.88;
    final bottomOffset = orientation == Orientation.landscape ? 88.0 : 68.0;

    // 使用 showModalBottomSheet 来创建一个从底部弹出的弹窗
    final selectedIndex = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.only(bottom: bottomOffset),
          child: Container(
            width: MediaQuery.of(context).size.width * widthFactor,
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * widthFactor,
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: buildSourceContent(context, sources, currentSourceIndex, isTV, focusNodes),
            ),
          ),
        );
      },
    );

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

/// 构建不同设备的弹窗内容（TV或非TV）
Widget buildSourceContent(
  BuildContext context, 
  List<String> sources, 
  int currentSourceIndex, 
  bool isTV,
  List<FocusNode> focusNodes
) {
  if (isTV) {
    return TvKeyNavigation(
      focusNodes: focusNodes,
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
  List<FocusNode> focusNodes
) {
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: List.generate(sources.length, (index) {
      FocusNode focusNode = focusNodes[index];
      bool isSelected = currentSourceIndex == index;

      return FocusableItem(
        focusNode: focusNode,
        child: OutlinedButton(
          autofocus: isSelected,
          style: getButtonStyle(isSelected),
          onPressed: isSelected
              ? null
              : () {
                  Navigator.pop(context, index);
                },
          child: Text(
            S.current.lineIndex(index + 1),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      );
    }),
  );
}

/// 获取按钮样式
ButtonStyle getButtonStyle(bool isSelected) {
  return OutlinedButton.styleFrom(
    padding: EdgeInsets.symmetric(vertical: 2, horizontal: 6),
    backgroundColor: isSelected ? Color(0xFFDFA02A) : Color(0xFFEB144C),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
  );
}
