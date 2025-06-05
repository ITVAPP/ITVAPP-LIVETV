import 'package:flutter/material.dart';

/// 公共AppBar分割线样式
class CommonAppBarDivider extends StatelessWidget implements PreferredSizeWidget {
  const CommonAppBarDivider({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.05),
            Colors.white.withOpacity(0.15),
            Colors.white.withOpacity(0.05),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(1);
}

/// 公共AppBar装饰样式
class CommonAppBarDecoration extends BoxDecoration {
  const CommonAppBarDecoration()
      : super(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A1A), Color(0xFF2C2C2C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000), // 使用固定透明度避免运行时计算
              blurRadius: 10,
              spreadRadius: 2,
              offset: Offset(0, 2),
            ),
          ],
        );
}

/// 通用设置页面AppBar
class CommonSettingAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool isTV;
  final TextStyle titleStyle;

  const CommonSettingAppBar({
    Key? key,
    required this.title,
    required this.isTV,
    this.titleStyle = const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 48.0,
      centerTitle: true,
      automaticallyImplyLeading: !isTV,
      title: Text(title, style: titleStyle),
      bottom: const CommonAppBarDivider(),
      flexibleSpace: Container(
        decoration: const CommonAppBarDecoration(),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(49.0); // 48 + 1 for divider
}

/// 颜色缓存管理器
class ColorCache {
  static final Map<Color, Color> _darkenCache = {};
  
  /// 获取变暗的颜色
  static Color getDarkenColor(Color color) {
    return _darkenCache.putIfAbsent(color, () => 
      HSLColor.fromColor(color).withLightness(
        (HSLColor.fromColor(color).lightness * 0.8).clamp(0.0, 1.0)
      ).toColor()
    );
  }
  
  /// 清除缓存
  static void clearCache() {
    _darkenCache.clear();
  }
}
