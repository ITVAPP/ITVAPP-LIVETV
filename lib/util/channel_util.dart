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
const EdgeInsets _padding = EdgeInsets.all(10);  // 弹窗外边距
const BorderRadius _borderRadius = BorderRadius.all(Radius.circular(16));  // 弹窗和按钮圆角
const EdgeInsets _buttonPadding = EdgeInsets.symmetric(vertical: 2, horizontal: 6);  // 按钮内边距

/// 显示底部弹窗以选择视频源，返回选中索引
Future<int?> changeChannelSources(
  BuildContext context,
  List<String>? sources,
  int currentSourceIndex,
) async {
  // 校验视频源有效性
  if (sources == null || sources.isEmpty) {
    LogUtil.e('无有效视频源');
    return null;  // 返回空表示无视频源
  }

  final List<FocusNode> focusNodes = List.generate(sources.length, (index) => FocusNode());  // 创建焦点节点

  final Color selectedColor = const Color(0xFFEB144C);  // 选中背景色
  final Color unselectedColor = const Color(0xFFDFA02A);  // 未选中背景色

  try {
    var orientation = MediaQuery.of(context).orientation;  // 获取屏幕方向
    final widthFactor = orientation == Orientation.landscape ? 0.78 : 0.88;  // 调整弹窗宽度比例
    final bottomOffset = orientation == Orientation.landscape ? 48.0 : 58.0;  // 调整底部间距

    final double maxWidth = MediaQuery.of(context).size.width * widthFactor;  // 计算弹窗最大宽度
    final double maxHeight = MediaQuery.of(context).size.height * 0.7;  // 计算弹窗最大高度

    final selectedIndex = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,  // 启用内容滚动
      backgroundColor: Colors.transparent,  // 弹窗背景透明
      barrierColor: Colors.transparent,  // 遮罩层透明
      builder: (BuildContext context) {
        return TvKeyNavigation(
          focusNodes: focusNodes,  // 支持键盘导航
          initialIndex: currentSourceIndex,  // 设置初始焦点
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomOffset),  // 设置底部间距
            child: Container(
              width: maxWidth,
              padding: _padding,  // 设置内边距
              decoration: BoxDecoration(
                color: Colors.black54,  // 半透明黑色背景
                borderRadius: _borderRadius,  // 设置圆角
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,  // 限制最大宽度
                  maxHeight: maxHeight,  // 限制最大高度
                ),
                child: buildSourceButtons(context, sources, currentSourceIndex, focusNodes, selectedColor, unselectedColor),  // 构建按钮组
              ),
            ),
          ),
        );
      },
    );

    return selectedIndex;  // 返回选中索引
  } catch (modalError, modalStackTrace) {
    LogUtil.logError('弹窗失败', modalError, modalStackTrace);
    return null;  // 返回空表示弹窗失败
  } finally {
    for (var node in focusNodes) node.dispose();  // 释放焦点节点
  }
}

/// 获取线路显示名称，基于URL或索引
String _getLineDisplayName(String url, int index) {
  if (url.contains('\$')) {  // 检查URL是否含自定义名称
    return url.split('\$')[1].trim();  // 提取名称并去除空格
  }
  return S.current.lineIndex(index + 1);  // 返回默认线路名称
}

/// 构建视频源按钮组，支持动态布局
Widget buildSourceButtons(
  BuildContext context,
  List<String> sources,
  int currentSourceIndex,
  List<FocusNode> focusNodes,
  Color selectedColor,
  Color unselectedColor,
) {
  return Wrap(
    spacing: 8,  // 按钮水平间距
    runSpacing: 8,  // 按钮垂直间距
    children: List.generate(sources.length, (index) {
      return SourceButton(  // 构建单个按钮
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

/// 视频源按钮小部件，管理样式和交互
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
    widget.focusNode.addListener(_handleFocusChange);  // 添加焦点监听
    _isFocused = widget.focusNode.hasFocus;
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);  // 移除焦点监听
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;  // 更新焦点状态
      });
    }
  }

  /// 获取字体大小，支持TV模式
  double _getFontSize(BuildContext context) {
    final isTV = context.read<ThemeProvider>().isTV;
    return isTV ? 22.0 : 16.0;
  }

  @override
  Widget build(BuildContext context) {
    String displayName = widget.isSelected 
        ? S.current.playReconnect 
        : _getLineDisplayName(widget.source, widget.index);  // 设置按钮文本

    return FocusableItem(
      focusNode: widget.focusNode,  // 绑定焦点
      child: OutlinedButton(
        style: getButtonStyle(  // 获取按钮样式
          isSelected: widget.isSelected,
          isFocused: _isFocused,
          selectedColor: widget.selectedColor,
          unselectedColor: widget.unselectedColor,
        ),
        onPressed: () {
          Navigator.pop(context, widget.index);  // 关闭弹窗并返回索引
        },
        child: Text(
          displayName,  // 显示按钮文本
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: _getFontSize(context),  // 使用动态字体大小
            color: Colors.white,
            fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.normal,  // 选中时加粗
          ),
        ),
      ),
    );
  }
}

/// 获取按钮样式，支持动态状态调整
ButtonStyle getButtonStyle({
  required bool isSelected,
  required bool isFocused,
  required Color selectedColor,
  required Color unselectedColor,
}) {
  final String key = '${isSelected}_${isFocused}_${selectedColor.value}_${unselectedColor.value}';  // 生成缓存键

  return _styleCache.putIfAbsent(key, () {  // 从缓存获取或创建样式
    Color backgroundColor = isSelected ? selectedColor : unselectedColor;  // 设置背景色
    if (isFocused) backgroundColor = darkenColor(backgroundColor);  // 焦点时加深颜色

    return OutlinedButton.styleFrom(
      padding: _buttonPadding,  // 设置内边距
      backgroundColor: backgroundColor,  // 设置背景色
      shape: RoundedRectangleBorder(
        borderRadius: _borderRadius,  // 设置圆角
      ),
    );
  });
}
