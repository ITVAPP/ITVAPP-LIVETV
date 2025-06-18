import 'package:better_player/src/configuration/better_player_event_type.dart';

/// 播放器状态获取
class BetterPlayerEvent {
  final BetterPlayerEventType betterPlayerEventType;
  final Map<String, dynamic>? parameters;

  BetterPlayerEvent(this.betterPlayerEventType, {this.parameters});
}
