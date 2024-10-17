import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import '../generated/l10n.dart';

class ChangeChannelSources extends StatefulWidget {
  final List<String>? sources;
  final int currentSourceIndex;

  ChangeChannelSources({
    required this.sources,
    required this.currentSourceIndex,
  });

  @override
  _ChangeChannelSourcesState createState() => _ChangeChannelSourcesState();
}

class _ChangeChannelSourcesState extends State<ChangeChannelSources> {
  late List<FocusNode> focusNodes;

  @override
  void initState() {
    super.initState();
    // 为每个 FocusNode 添加监听器
    focusNodes = List.generate(widget.sources?.length ?? 0, (index) {
      FocusNode focusNode = FocusNode();
      focusNode.addListener(() {
        setState(() {}); // 焦点变化时触发 UI 重绘
      });
      return focusNode;
    });
  }

  @override
  void dispose() {
    // 销毁 FocusNode
    for (var node in focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color selectedColor = const Color(0xFFEB144C); // 选中时背景颜色
    final Color unselectedColor = const Color(0xFFDFA02A); // 未选中时背景颜色

    // 如果 sources 为空或未找到有效的视频源，记录日志并返回空
    if (widget.sources == null || widget.sources!.isEmpty) {
      LogUtil.e('未找到有效的视频源');
      return Container();
    }

    // 显示底部弹出框选择不同的视频源
    return TvKeyNavigation(
      focusNodes: focusNodes,
      initialIndex: widget.currentSourceIndex,
      child: Padding(
        padding: EdgeInsets.only(bottom: 68.0), // 底部间距
        child: Container(
          padding: EdgeInsets.all(10), // 内边距设置
          decoration: BoxDecoration(
            color: Colors.black54, // 背景色
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.88, // 宽度限制
              maxHeight: MediaQuery.of(context).size.height * 0.7, // 高度限制
            ),
            child: buildSourceButtons(
              context,
              widget.sources!,
              widget.currentSourceIndex,
              focusNodes,
              selectedColor,
              unselectedColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// 构建视频源按钮组
Widget buildSourceButtons(
  BuildContext context,
  List<String> sources,
  int currentSourceIndex,
  List<FocusNode> focusNodes,
  Color selectedColor,
  Color unselectedColor,
) {
  return Wrap(
    spacing: 8, // 按钮之间的水平间距
    runSpacing: 8, // 按钮之间的垂直间距
    children: List.generate(sources.length, (index) {
      FocusNode focusNode = focusNodes[index];
      bool isSelected = currentSourceIndex == index; // 判断是否为当前选中项

      return FocusableItem(
        focusNode: focusNode, // 使用外部传入的 FocusNode
        child: OutlinedButton(
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
