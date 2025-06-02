import 'package:better_player/src/core/better_player_controller.dart';
import 'package:flutter/material.dart';

// 提供 BetterPlayerController 的继承组件
class BetterPlayerControllerProvider extends InheritedWidget {
  const BetterPlayerControllerProvider({
    Key? key,
    required this.controller,
    required Widget child,
  }) : super(key: key, child: child);

  // 控制器实例
  final BetterPlayerController controller;

  // 判断是否需要更新通知
  @override
  bool updateShouldNotify(BetterPlayerControllerProvider old) =>
      controller != old.controller;
}
