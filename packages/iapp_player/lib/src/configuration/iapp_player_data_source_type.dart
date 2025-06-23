///Source types of video. Network type is used for videos that are hosted on
///the web service. File type is used for videos that will be read from
/// mobile device.
enum IAppPlayerDataSourceType { network, file, memory }

/// 解码器类型配置
enum IAppPlayerDecoderType {
  /// 自动选择（默认）
  auto,

  /// 硬件解码优先
  hardwareFirst,

  /// 软件解码优先
  softwareFirst,
}
