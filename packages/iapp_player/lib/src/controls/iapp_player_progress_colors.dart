import 'dart:ui';

/// 进度条颜色配置
class IAppPlayerProgressColors {
  /// 静态缓存避免重复创建Paint对象
  static final Map<Color, Paint> _paintCache = {};
  
  IAppPlayerProgressColors({
    Color playedColor = const Color.fromRGBO(255, 255, 255, 1.0), // 改为白色
    Color bufferedColor = const Color.fromRGBO(255, 255, 255, 0.3), // 半透明白色
    Color handleColor = const Color.fromRGBO(255, 255, 255, 1.0), // 白色手柄
    Color backgroundColor = const Color.fromRGBO(255, 255, 255, 0.2), // 淡白色背景
  }) : playedPaint = _getPaint(playedColor),
       bufferedPaint = _getPaint(bufferedColor),
       handlePaint = _getPaint(handleColor),
       backgroundPaint = _getPaint(backgroundColor);
       
  /// 已播放部分画笔
  final Paint playedPaint;
  /// 缓冲部分画笔
  final Paint bufferedPaint;
  /// 控制柄画笔
  final Paint handlePaint;
  /// 背景画笔
  final Paint backgroundPaint;
  
  /// 获取或创建Paint对象
  static Paint _getPaint(Color color) {
    return _paintCache.putIfAbsent(color, () => Paint()..color = color);
  }
  
  /// YouTube风格配色
  factory IAppPlayerProgressColors.youtube() {
    return IAppPlayerProgressColors(
      playedColor: const Color(0xFFFF0000),
      bufferedColor: const Color.fromRGBO(255, 255, 255, 0.3),
      handleColor: const Color(0xFFFF0000),
      backgroundColor: const Color.fromRGBO(255, 255, 255, 0.2),
    );
  }
  
  /// Netflix风格配色
  factory IAppPlayerProgressColors.netflix() {
    return IAppPlayerProgressColors(
      playedColor: const Color(0xFFE50914),
      bufferedColor: const Color.fromRGBO(229, 9, 20, 0.3),
      handleColor: const Color(0xFFE50914),
      backgroundColor: const Color.fromRGBO(255, 255, 255, 0.2),
    );
  }
  
  /// 蓝色主题配色
  factory IAppPlayerProgressColors.blue() {
    return IAppPlayerProgressColors(
      playedColor: const Color(0xFF2196F3),
      bufferedColor: const Color.fromRGBO(33, 150, 243, 0.3),
      handleColor: const Color(0xFF2196F3),
      backgroundColor: const Color.fromRGBO(255, 255, 255, 0.2),
    );
  }
}
