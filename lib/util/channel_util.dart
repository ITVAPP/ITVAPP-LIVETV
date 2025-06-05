import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';

// 缓存按钮样式，避免重复创建以提升性能
final Map<String, ButtonStyle> _styleCache = {};

// 定义常量边距和圆角，提高代码可读性与复用性
const EdgeInsets _padding = EdgeInsets.all(10);  // 弹窗外边距
const BorderRadius _borderRadius = BorderRadius.all(Radius.circular(16));  // 弹窗和按钮的圆角
const EdgeInsets _buttonPadding = EdgeInsets.symmetric(vertical: 2, horizontal: 6);  // 按钮内边距

/// 显示底部弹出框以选择不同的视频源，返回用户选择的索引
Future<int?> changeChannelSources(
  BuildContext context,
  List<String>? sources, // 视频源列表
  int currentSourceIndex, // 当前选中的视频源索引
) async {
  if (sources == null || sources.isEmpty) {  // 检查视频源是否有效
    LogUtil.e('未找到有效的视频源');  // 记录错误日志
    return null;  // 返回null表示无有效视频源
  }

  final List<FocusNode> focusNodes = List.generate(sources.length, (index) => FocusNode());  // 为每个视频源创建焦点节点

  final Color selectedColor = const Color(0xFFEB144C);  // 选中时的背景颜色
  final Color unselectedColor = const Color(0xFFDFA02A);  // 未选中时的背景颜色

  try {
    var orientation = MediaQuery.of(context).orientation;  // 获取屏幕方向
    final widthFactor = orientation == Orientation.landscape ? 0.78 : 0.88;  // 根据屏幕方向调整宽度比例
    final bottomOffset = orientation == Orientation.landscape ? 48.0 : 58.0;  // 根据屏幕方向调整底部间距

    final double maxWidth = MediaQuery.of(context).size.width * widthFactor;  // 计算弹窗最大宽度
    final double maxHeight = MediaQuery.of(context).size.height * 0.7;  // 计算弹窗最大高度

    final selectedIndex = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,  // 启用滚动以适应内容
      backgroundColor: Colors.transparent,  // 弹窗背景透明
      barrierColor: Colors.transparent,  // 遮罩层透明
      builder: (BuildContext context) {
        return TvKeyNavigation(
          focusNodes: focusNodes,  // 支持键盘导航
          initialIndex: currentSourceIndex,  // 设置初始焦点索引
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomOffset),  // 设置弹窗底部间距
            child: Container(
              width: maxWidth,
              padding: _padding,  // 设置弹窗内边距
              decoration: BoxDecoration(
                color: Colors.black54,  // 弹窗背景为半透明黑色
                borderRadius: _borderRadius,  // 设置圆角
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,  // 限制弹窗最大宽度
                  maxHeight: maxHeight,  // 限制弹窗最大高度
                ),
                child: buildSourceButtons(context, sources, currentSourceIndex, focusNodes, selectedColor, unselectedColor),  // 构建按钮组
              ),
            ),
          ),
        );
      },
    );

    return selectedIndex;  // 返回用户选择的视频源索引
  } catch (modalError, modalStackTrace) {
    LogUtil.logError('弹出窗口时出错', modalError, modalStackTrace);  // 记录弹窗错误日志
    return null;  // 返回null表示弹窗失败
  } finally {
    for (var node in focusNodes) node.dispose();  // 释放所有焦点节点资源
    // 移除了 _styleCache.clear()，保持缓存有效
  }
}

/// 获取线路显示名称，根据URL格式动态生成
String _getLineDisplayName(String url, int index) {
  if (url.contains('\$')) {  // 检查URL是否包含自定义名称标记
    return url.split('\$')[1].trim();  // 提取$后的名称并去除多余空格
  }
  return S.current.lineIndex(index + 1);  // 返回默认线路名称，如"线路1"
}

/// 构建视频源按钮组，支持动态显示和焦点管理
Widget buildSourceButtons(
  BuildContext context,
  List<String> sources, // 视频源列表
  int currentSourceIndex, // 当前选中索引
  List<FocusNode> focusNodes, // 焦点节点列表
  Color selectedColor, // 选中时的颜色
  Color unselectedColor, // 未选中时的颜色
) {
  return Wrap(
    spacing: 8,  // 按钮水平间距
    runSpacing: 8,  // 按钮垂直间距
    children: List.generate(sources.length, (index) {
      return SourceButton(  // 使用独立小部件构建按钮
        source: sources[index],
        index: index,
        isSelected: currentSourceIndex == index,
        focusNode: focusNodes[index],
        selectedColor: selectedColor,
        unselectedColor: unselectedColor,
      );
    }),
  );
}

/// 视频源按钮小部件，封装单个按钮的样式和交互逻辑
class SourceButton extends StatefulWidget {
  final String source;  // 视频源URL
  final int index;  // 按钮索引
  final bool isSelected;  // 是否选中
  final FocusNode focusNode;  // 焦点节点
  final Color selectedColor;  // 选中颜色
  final Color unselectedColor;  // 未选中颜色

  const SourceButton({
    Key? key,
    required this.source,
    required this.index,
    required this.isSelected,
    required this.focusNode,
    required this.selectedColor,
    required this.unselectedColor,
  }) : super(key: key);

  @override
  _SourceButtonState createState() => _SourceButtonState();
}

class _SourceButtonState extends State<SourceButton> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    // 在 initState 中添加监听器，避免重复添加
    widget.focusNode.addListener(_handleFocusChange);
    _isFocused = widget.focusNode.hasFocus;
  }

  @override
  void dispose() {
    // 在 dispose 中移除监听器，防止内存泄漏
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String displayName = widget.isSelected 
        ? S.current.playReconnect 
        : _getLineDisplayName(widget.source, widget.index);  // 动态设置按钮文本

    return FocusableItem(
      focusNode: widget.focusNode,  // 绑定焦点节点
      child: OutlinedButton(
        style: getButtonStyle(  // 获取按钮样式
          isSelected: widget.isSelected,
          isFocused: _isFocused,
          selectedColor: widget.selectedColor,
          unselectedColor: widget.unselectedColor,
        ),
        onPressed: () {
          Navigator.pop(context, widget.index);  // 点击后关闭弹窗并返回索引
        },
        child: Text(
          displayName,  // 显示按钮文本
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: Colors.white,
            fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.normal,  // 选中时加粗
          ),
        ),
      ),
    );
  }
}

/// 获取按钮样式，支持选中和焦点状态的动态调整
ButtonStyle getButtonStyle({
  required bool isSelected, // 是否选中
  required bool isFocused, // 是否获得焦点
  required Color selectedColor, // 选中时的颜色
  required Color unselectedColor, // 未选中时的颜色
}) {
  final String key = '${isSelected}_${isFocused}_${selectedColor.value}_${unselectedColor.value}';  // 生成唯一缓存键

  return _styleCache.putIfAbsent(key, () {  // 从缓存获取或创建样式
    Color backgroundColor = isSelected ? selectedColor : unselectedColor;  // 设置背景颜色
    if (isFocused) backgroundColor = darkenColor(backgroundColor);  // 焦点状态下加深颜色

    return OutlinedButton.styleFrom(
      padding: _buttonPadding,  // 设置内边距
      backgroundColor: backgroundColor,  // 设置背景颜色
      shape: RoundedRectangleBorder(
        borderRadius: _borderRadius,  // 设置圆角
      ),
    );
  });
}
