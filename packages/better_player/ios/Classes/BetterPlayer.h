#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <GLKit/GLKit.h>
#import "BetterPlayerTimeUtils.h"
#import "BetterPlayerView.h"
#import "BetterPlayerEzDrmAssetsLoaderDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@class CacheManager;

/// Flutter 视频播放器插件，管理视频播放、画中画和事件通道
@interface BetterPlayer : NSObject <FlutterPlatformView, FlutterStreamHandler, AVPictureInPictureControllerDelegate>
/// 视频播放器实例
@property(readonly, nonatomic) AVPlayer* player;
/// DRM 资源加载委托
@property(readonly, nonatomic) BetterPlayerEzDrmAssetsLoaderDelegate* loaderDelegate;
/// Flutter 事件通道
@property(nonatomic) FlutterEventChannel* eventChannel;
/// 事件接收器
@property(nonatomic) FlutterEventSink eventSink;
/// 视频变换矩阵
@property(nonatomic) CGAffineTransform preferredTransform;
/// 是否已释放资源
@property(nonatomic, readonly) bool disposed;
/// 是否正在播放
@property(nonatomic, readonly) bool isPlaying;
/// 是否循环播放
@property(nonatomic) bool isLooping;
/// 是否初始化完成
@property(nonatomic, readonly) bool isInitialized;
/// 视频资源标识
@property(nonatomic, readonly) NSString* key;
/// 失败重试次数
@property(nonatomic, readonly) int failedCount;
/// 视频播放层
@property(nonatomic) AVPlayerLayer* _playerLayer;
/// 是否启用画中画
@property(nonatomic) bool _pictureInPicture;
/// 是否添加了观察者
@property(nonatomic) bool _observersAdded;
/// 卡顿次数
@property(nonatomic) int stalledCount;
/// 是否开始卡顿检查
@property(nonatomic) bool isStalledCheckStarted;
/// 播放速率
@property(nonatomic) float playerRate;
/// 覆盖的视频时长
@property(nonatomic) int overriddenDuration;
/// 上次播放器时间控制状态
@property(nonatomic) AVPlayerTimeControlStatus lastAvPlayerTimeControlStatus;

/// 初始化播放器视图
- (instancetype)initWithFrame:(CGRect)frame;
/// 设置是否与其他音频混音
- (void)setMixWithOthers:(bool)mixWithOthers;
/// 播放视频
- (void)play;
/// 暂停视频
- (void)pause;
/// 设置循环播放状态
- (void)setIsLooping:(bool)isLooping;
/// 更新播放状态
- (void)updatePlayingState;
/// 获取视频总时长（毫秒）
- (int64_t)duration;
/// 获取当前播放位置（毫秒）
- (int64_t)position;
/// 定位到指定时间（毫秒）
- (void)seekTo:(int)location;
/// 设置本地资源数据源
- (void)setDataSourceAsset:(NSString*)asset withKey:(NSString*)key withCertificateUrl:(NSString*)certificateUrl withLicenseUrl:(NSString*)licenseUrl cacheKey:(NSString*)cacheKey cacheManager:(CacheManager*)cacheManager overriddenDuration:(int)overriddenDuration;
/// 设置网络资源数据源
- (void)setDataSourceURL:(NSURL*)url withKey:(NSString*)key withCertificateUrl:(NSString*)certificateUrl withLicenseUrl:(NSString*)licenseUrl withHeaders:(NSDictionary*)headers withCache:(BOOL)useCache cacheKey:(NSString*)cacheKey cacheManager:(CacheManager*)cacheManager overriddenDuration:(int)overriddenDuration videoExtension:(NSString*)videoExtension;
/// 设置音量
- (void)setVolume:(double)volume;
/// 设置播放速度
- (void)setSpeed:(double)speed result:(FlutterResult)result;
/// 设置音频轨道
- (void)setAudioTrack:(NSString*)name index:(int)index;
/// 设置视频轨道参数
- (void)setTrackParameters:(int)width :(int)height :(int)bitrate;
/// 启用画中画模式
- (void)enablePictureInPicture:(CGRect)frame;
/// 设置画中画状态
- (void)setPictureInPicture:(BOOL)pictureInPicture;
/// 禁用画中画模式
- (void)disablePictureInPicture;
/// 获取绝对播放位置（毫秒）
- (int64_t)absolutePosition;
/// 将 CMTime 转换为毫秒
- (int64_t)FLTCMTimeToMillis:(CMTime)time;
/// 清除播放器资源
- (void)clear;
/// 释放播放器资源（不含事件通道）
- (void)disposeSansEventChannel;
/// 释放播放器所有资源
- (void)dispose;
@end

NS_ASSUME_NONNULL_END
