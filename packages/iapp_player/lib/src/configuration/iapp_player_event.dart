import 'package:iapp_player/src/configuration/iapp_player_event_type.dart';

///Event that happens in player. It can be used to determine current player state
///on higher layer.
class IAppPlayerEvent {
  final IAppPlayerEventType iappPlayerEventType;
  final Map<String, dynamic>? parameters;

  IAppPlayerEvent(this.iappPlayerEventType, {this.parameters});
}
