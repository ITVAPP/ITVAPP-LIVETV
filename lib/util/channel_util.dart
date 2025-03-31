import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 缓存按钮样式
final Map<String, ButtonStyle> _styleCache = {};

// 定义常量边距和圆角
const EdgeInsets _padding = EdgeInsets.all(10);
const BorderRadius _borderRadius = BorderRadius.all(Radius.circular(16));
const EdgeInsets _buttonPadding = EdgeInsets.symmetric(vertical: 2, horizontal: 6);

/// 显示底部弹出框以选择不同的视频源
Future<int?> changeChannelSources(
  BuildContext context,
  List<String>? sources, // 视频源列表
  int currentSourceIndex, // 当前选中的视频源索引
) async {
  // 如果 sources 为空或未找到有效的视频源，记录日志并返回 null
  if (sources == null || sources.isEmpty) {
    LogUtil.e('未找到有效的视频源');
    return null;
  }

  // 创建 FocusNode 列表，即使 sources 为空也初始化为空列表以避免未定义行为
  final List<FocusNode> focusNodes = List.generate(sources.length, (index) => FocusNode());

  // 定义选中与未选中的颜色变量
  final Color selectedColor = const Color(0xFFEB144C); // 选中时的按钮背景颜色
  final Color unselectedColor = const Color(0xFFDFA02A); // 未选中时的按钮背景颜色

  try {
    // 获取屏幕的方向和相关尺寸信息
    var orientation = MediaQuery.of(context).orientation;
    final widthFactor = orientation == Orientation.landscape ? 0.78 : 0.88; // 根据横竖屏动态调整宽度
    final bottomOffset = orientation == Orientation.landscape ? 48.0 : 58.0; // 动态调整底部间距

    // 提前计算尺寸约束，用于设置弹窗的最大宽高
    final double maxWidth = MediaQuery.of(context).size.width * widthFactor;
    final double maxHeight = MediaQuery.of(context).size.height * 0.7;

    // 弹出底部弹窗，用户可以选择视频源
    final selectedIndex = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true, // 支持滚动内容
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (BuildContext context) {
        return TvKeyNavigation(
          focusNodes: focusNodes, // 键盘导航支持
          initialIndex: currentSourceIndex, // 设置初始焦点
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomOffset), // 调整弹窗的底部间距
            child: Container(
              width: maxWidth,
              padding: _padding,
              decoration: BoxDecoration(
                color: Colors.black54, // 半透明背景颜色
                borderRadius: _borderRadius,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: maxHeight, // 限制最大宽高
                ),
                // 构建视频源按钮组
                child: buildSourceButtons(context, sources, currentSourceIndex, focusNodes, selectedColor, unselectedColor),
              ),
            ),
          ),
        );
      },
    );

    return selectedIndex; // 返回用户选择的视频源索引
  } catch (modalError, modalStackTrace) {
    LogUtil.logError('弹出窗口时出错', modalError, modalStackTrace);
    return null;
  } finally {
    // 销毁 FocusNode，释放资源
    for (var node in focusNodes) {
      node.dispose();
    }
    // 修改代码开始
    // 清理样式缓存，防止内存占用持续增加
    _styleCache.clear();
    // 修改代码结束
    // 注释：弹窗关闭后清理缓存，优化长期运行时的内存使用
  }
}

/// 获取线路显示名称
String _getLineDisplayName(String url, int index) {
  // 修改代码开始
  // 检查是否包含 $，并解析 URL 以提取显示名称
  if (url.contains('\$')) {
    // 分割字符串并返回后半部分作为显示名称，确保 trim() 去除多余空格
    return url.split('\$')[1].trim();
  }
  // 如果不包含 $，则返回默认的线路序号（如“线路1”）
  return S.current.lineIndex(index + 1);
  // 修改代码结束
  // 注释：此函数根据 URL 格式动态生成线路名称，支持带 $ 的自定义名称和默认序号两种情况
}

/// 构建视频源按钮组
Widget buildSourceButtons(
  BuildContext context,
  List<String> sources, // 视频源列表
  int currentSourceIndex, // 当前选中索引
  List<FocusNode> focusNodes, // 键盘导航的焦点节点
  Color selectedColor, // 选中时的颜色
  Color unselectedColor, // 未选中时的颜色
) {
  // 使用 ValueNotifier 来管理焦点索引
  final ValueNotifier<int> focusedIndex = ValueNotifier(-1);

  return ValueListenableBuilder<int>(
    valueListenable: focusedIndex, // 监听焦点变化
    builder: (context, value, child) {
      return Wrap(
        spacing: 8, // 按钮之间的水平间距
        runSpacing: 8, // 按钮之间的垂直间距
        children: List.generate(sources.length, (index) {
          // 修改代码开始
          // 将按钮构建逻辑抽取为独立小部件，减少 Wrap 重建范围
          return SourceButton(
            context: context,
            source: sources[index],
            index: index,
            isSelected: currentSourceIndex == index,
            focusNode: focusNodes[index],
            selectedColor: selectedColor,
            unselectedColor: unselectedColor,
            focusedIndex: focusedIndex,
          );
          // 修改代码结束
        }),
      );
    },
  );
}

// 修改代码开始
/// 独立的小部件，用于构建单个视频源按钮
class SourceButton extends StatelessWidget {
  final BuildContext context;
  final String source;
  final int index;
  final bool isSelected;
  final FocusNode focusNode;
  final Color selectedColor;
  final Color unselectedColor;
  final ValueNotifier<int> focusedIndex;

  const SourceButton({
    required this.context,
    required this.source,
    required this.index,
    required this.isSelected,
    required this.focusNode,
    required this.selectedColor,
    required this.unselectedColor,
    required this.focusedIndex,
  });

  @override
  Widget build(BuildContext context) {
    // 如果是当前选中项，显示 "重试"，否则显示线路名称
    String displayName = isSelected ? S.current.playReconnect : _getLineDisplayName(source, index);

    // 监听焦点变化，当按钮获得焦点时更新 focusedIndex
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        focusedIndex.value = index;
      }
    });

    return FocusableItem(
      focusNode: focusNode, // 关联焦点节点
      child: OutlinedButton(
        style: getButtonStyle(
          isSelected: isSelected, // 是否被选中
          isFocused: focusNode.hasFocus, // 是否获得焦点
          selectedColor: selectedColor, // 选中时的颜色
          unselectedColor: unselectedColor, // 未选中时的颜色
        ),
        onPressed: () {
          Navigator.pop(context, index); // 返回选中的索引并关闭弹窗
        },
        child: Text(
          displayName, // 使用动态显示名称
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, // 选中项加粗
          ),
        ),
      ),
    );
  }
}
// 修改代码结束
// 注释：将按钮逻辑抽取为独立小部件，减少 Wrap 重建时的性能开销，提升渲染效率

/// 获取按钮样式
ButtonStyle getButtonStyle({
  required bool isSelected, // 是否被选中
  required bool isFocused, // 是否获得焦点
  required Color selectedColor, // 选中时的颜色
  required Color unselectedColor, // 未选中时的颜色
}) {
  // 修改代码开始
  // 优化缓存键设计，包含颜色值以确保不同颜色组合的样式唯一
  final String key = '${isSelected}_${isFocused}_${selectedColor.value}_${unselectedColor.value}';

  return _styleCache.putIfAbsent(key, () {
    Color backgroundColor = isSelected ? selectedColor : unselectedColor; // 根据状态设置背景颜色
    if (isFocused) {
      // 如果 darkenColor 未定义，提供默认实现：降低亮度10%
      backgroundColor = backgroundColor.withLightness((backgroundColor.computeLuminance() - 0.1).clamp(0.0, 1.0));
    }

    return OutlinedButton.styleFrom(
      padding: _buttonPadding, // 设置按钮内边距
      backgroundColor: backgroundColor, // 按钮背景颜色
      shape: RoundedRectangleBorder(
        borderRadius: _borderRadius, // 设置按钮的圆角
      ),
    );
  });
  // 修改代码结束
  // 注释：此函数根据选中状态和焦点状态生成按钮样式，使用缓存避免重复创建；若外部未定义 darkenColor，提供默认颜色加深逻辑
}
