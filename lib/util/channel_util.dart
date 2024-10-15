import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import '../generated/l10n.dart';

/// 用于将颜色变暗的函数
Color darkenColor(Color color, [double amount = 0.1]) {
  final hsl = HSLColor.fromColor(color);
  final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
  return darkened.toColor();
}

class ChangeChannelSourcesWidget extends StatefulWidget {
  final List<String>? sources;
  final int currentSourceIndex;

  ChangeChannelSourcesWidget({required this.sources, required this.currentSourceIndex});

  @override
  _ChangeChannelSourcesWidgetState createState() => _ChangeChannelSourcesWidgetState();
}

class _ChangeChannelSourcesWidgetState extends State<ChangeChannelSourcesWidget> {
  late List<FocusNode> _focusNodes; // 存储所有焦点节点
  late List<Widget> _sourceButtons; // 缓存生成的按钮

  @override
  void initState() {
    super.initState();
    // 初始化 focusNodes，保证它们的生命周期不受重建影响
    _focusNodes = List.generate(widget.sources?.length ?? 0, (index) => FocusNode());
    _buildSourceButtons(); // 初始构建按钮
  }

  @override
  void didUpdateWidget(covariant ChangeChannelSourcesWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 widget.sources 发生变化时，重新生成 focusNodes 和按钮
    if (widget.sources?.length != oldWidget.sources?.length) {
      _focusNodes = List.generate(widget.sources?.length ?? 0, (index) => FocusNode());
      _buildSourceButtons();
    }
  }

  @override
  void dispose() {
    // 确保在 widget 销毁时清理所有 FocusNode
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  // 构建按钮列表
  void _buildSourceButtons() {
    _sourceButtons = List.generate(widget.sources?.length ?? 0, (index) {
      return _buildButton(
        context: context,
        index: index,
        sources: widget.sources!,
        currentSourceIndex: widget.currentSourceIndex,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isTV = context.watch<ThemeProvider>().isTV;
    return buildSourceContent(context, widget.sources, widget.currentSourceIndex, isTV);
  }

  /// 构建不同设备的弹窗内容（TV或非TV）
  Widget buildSourceContent(
    BuildContext context, 
    List<String>? sources, 
    int currentSourceIndex, 
    bool isTV
  ) {
    if (isTV) {
      // 使用 TvKeyNavigation 包裹按钮组，支持 TV 模式的按键导航
      return TvKeyNavigation(
        focusNodes: _focusNodes, // 直接使用持久化的焦点节点
        initialIndex: currentSourceIndex, // 使用 initialIndex 来设置初始聚焦
        child: Wrap(
          spacing: 8, // 按钮之间的水平间距
          runSpacing: 8, // 按钮之间的垂直间距
          children: _sourceButtons,
        ),
      );
    } else {
      return Wrap(
        spacing: 8, // 按钮之间的水平间距
        runSpacing: 8, // 按钮之间的垂直间距
        children: _sourceButtons,
      );
    }
  }

  /// 构建单个按钮，并处理焦点和选中状态
  Widget _buildButton({
    required BuildContext context,
    required int index,
    required List<String> sources,
    required int currentSourceIndex,
  }) {
    final bool isSelected = currentSourceIndex == index;
    final Color unselectedColor = Color(0xFFEB144C); // 未选中的颜色
    final Color selectedColor = Color(0xFFDFA02A); // 选中的颜色

    return FocusableItem(
      focusNode: _focusNodes[index], // 使用已创建的 FocusNode
      child: Focus(
        focusNode: _focusNodes[index],
        onFocusChange: (hasFocus) {
          setState(() {
            // 触发重绘以根据焦点更新按钮背景
          });
        },
        child: OutlinedButton(
          key: ValueKey(index), // 给每个按钮分配唯一的Key
          autofocus: currentSourceIndex == index, // 自动聚焦当前选中的按钮
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.symmetric(vertical: 2, horizontal: 6), // 设置按钮内边距
            backgroundColor: _getBackgroundColor(isSelected, _focusNodes[index].hasFocus, selectedColor, unselectedColor), // 设置背景颜色
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16), // 按钮的圆角半径
            ),
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
  }

  /// 根据当前状态获取背景色
  Color _getBackgroundColor(bool isSelected, bool hasFocus, Color selectedColor, Color unselectedColor) {
    Color baseColor = isSelected ? selectedColor : unselectedColor;
    return hasFocus ? darkenColor(baseColor) : baseColor;
  }
}

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
        return Padding(
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
              child: ChangeChannelSourcesWidget(
                sources: sources, 
                currentSourceIndex: currentSourceIndex,
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
