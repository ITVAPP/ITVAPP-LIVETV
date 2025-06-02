#import "BetterPlayer.h"
#import <better_player/better_player-Swift.h>

static void* timeRangeContext = &timeRangeContext;
static void* statusContext = &statusContext;
static void* playbackLikelyToKeepUpContext = &playbackLikelyToKeepUpContext;
static void* playbackBufferEmptyContext = &playbackBufferEmptyContext;
static void* playbackBufferFullContext = &playbackBufferFullContext;
static void* presentationSizeContext = &presentationSizeContext;

#if TARGET_OS_IOS
void (^__strong _Nonnull _restoreUserInterfaceForPIPStopCompletionHandler)(BOOL);
API_AVAILABLE(ios(9.0))
AVPictureInPictureController *_pipController;
#endif

/// 视频播放器插件实现，管理播放、画中画和事件监听
@implementation BetterPlayer {
    AVPlayerItem* _currentObservedItem; /// 跟踪当前被观察的播放项
}

/// 初始化播放器，设置默认状态和行为
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _isInitialized = false;
    _isPlaying = false;
    _disposed = false;
    _player = [[AVPlayer alloc] init];
    _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    /// 禁用自动等待以减少卡顿（iOS 10+）
    if (@available(iOS 10.0, *)) {
        _player.automaticallyWaitsToMinimizeStalling = false;
    }
    self._observersAdded = false;
    _currentObservedItem = nil; /// 初始化跟踪变量
    return self;
}

/// 返回播放器视图
- (nonnull UIView *)view {
    BetterPlayerView *playerView = [[BetterPlayerView alloc] initWithFrame:CGRectZero];
    playerView.player = _player;
    return playerView;
}

/// 为播放项添加 KVO 和通知观察者
- (void)addObservers:(AVPlayerItem*)item {
    if (!self._observersAdded){
        [_player addObserver:self forKeyPath:@"rate" options:0 context:nil];
        [item addObserver:self forKeyPath:@"loadedTimeRanges" options:0 context:timeRangeContext];
        [item addObserver:self forKeyPath:@"status" options:0 context:statusContext];
        [item addObserver:self forKeyPath:@"presentationSize" options:0 context:presentationSizeContext];
        [item addObserver:self
               forKeyPath:@"playbackLikelyToKeepUp"
                  options:0
                  context:playbackLikelyToKeepUpContext];
        [item addObserver:self
               forKeyPath:@"playbackBufferEmpty"
                  options:0
                  context:playbackBufferEmptyContext];
        [item addObserver:self
               forKeyPath:@"playbackBufferFull"
                  options:0
                  context:playbackBufferFullContext];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(itemDidPlayToEndTime:)
                                                     name:AVPlayerItemDidPlayToEndTimeNotification
                                                   object:item];
        self._observersAdded = true;
        _currentObservedItem = item; /// 记录当前观察的播放项
    }
}

/// 清除播放器状态和资源
- (void)clear {
    _isInitialized = false;
    _isPlaying = false;
    _disposed = false;
    _failedCount = 0;
    _key = nil;
    if (_player.currentItem == nil) {
        return;
    }

    /// 移除重复的 null 检查，提升效率
    [self removeObservers];
    AVAsset* asset = [_player.currentItem asset];
    [asset cancelLoading];
}

/// 移除播放器和播放项的观察者
- (void)removeObservers {
    if (self._observersAdded){
        [_player removeObserver:self forKeyPath:@"rate" context:nil];
        
        /// 使用当前观察项移除 KVO 观察者
        if (_currentObservedItem != nil) {
            [_currentObservedItem removeObserver:self forKeyPath:@"status" context:statusContext];
            [_currentObservedItem removeObserver:self forKeyPath:@"presentationSize" context:presentationSizeContext];
            [_currentObservedItem removeObserver:self
                                       forKeyPath:@"loadedTimeRanges"
                                          context:timeRangeContext];
            [_currentObservedItem removeObserver:self
                                       forKeyPath:@"playbackLikelyToKeepUp"
                                          context:playbackLikelyToKeepUpContext];
            [_currentObservedItem removeObserver:self
                                       forKeyPath:@"playbackBufferEmpty"
                                          context:playbackBufferEmptyContext];
            [_currentObservedItem removeObserver:self
                                       forKeyPath:@"playbackBufferFull"
                                          context:playbackBufferFullContext];
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        self._observersAdded = false;
        _currentObservedItem = nil; /// 清理观察项引用
    }
}

/// 处理视频播放结束事件
- (void)itemDidPlayToEndTime:(NSNotification*)notification {
    if (_isLooping) {
        AVPlayerItem* p = [notification object];
        [p seekToTime:kCMTimeZero completionHandler:nil];
    } else {
        if (_eventSink) {
            _eventSink(@{@"event" : @"completed", @"key" : _key});
            [self removeObservers];
        }
    }
}

/// 将弧度转换为角度
static inline CGFloat radiansToDegrees(CGFloat radians) {
    CGFloat degrees = GLKMathRadiansToDegrees((float)radians);
    if (degrees < 0) {
        return degrees + 360;
    }
    return degrees;
}

/// 创建视频合成对象，应用变换
- (AVMutableVideoComposition*)getVideoCompositionWithTransform:(CGAffineTransform)transform
                                                     withAsset:(AVAsset*)asset
                                                withVideoTrack:(AVAssetTrack*)videoTrack {
    AVMutableVideoCompositionInstruction* instruction =
    [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange = CMTimeRangeMake(kCMTimeZero, [asset duration]);
    AVMutableVideoCompositionLayerInstruction* layerInstruction =
    [AVMutableVideoCompositionLayerInstruction
     videoCompositionLayerInstructionWithAssetTrack:videoTrack];
    [layerInstruction setTransform:_preferredTransform atTime:kCMTimeZero];

    AVMutableVideoComposition* videoComposition = [AVMutableVideoComposition videoComposition];
    instruction.layerInstructions = @[ layerInstruction ];
    videoComposition.instructions = @[ instruction ];

    /// 调整视频尺寸以适配旋转
    CGFloat width = videoTrack.naturalSize.width;
    CGFloat height = videoTrack.naturalSize.height;
    NSInteger rotationDegrees =
    (NSInteger)round(radiansToDegrees(atan2(_preferredTransform.b, _preferredTransform.a)));
    if (rotationDegrees == 90 || rotationDegrees == 270) {
        width = videoTrack.naturalSize.height;
        height = videoTrack.naturalSize.width;
    }
    videoComposition.renderSize = CGSizeMake(width, height);

    float nominalFrameRate = videoTrack.nominalFrameRate;
    int fps = 30;
    if (nominalFrameRate > 0) {
        fps = (int) ceil(nominalFrameRate);
    }
    videoComposition.frameDuration = CMTimeMake(1, fps);
    
    return videoComposition;
}

/// 修正视频轨道变换
- (CGAffineTransform)fixTransform:(AVAssetTrack*)videoTrack {
    CGAffineTransform transform = videoTrack.preferredTransform;
    NSInteger rotationDegrees = (NSInteger)round(radiansToDegrees(atan2(transform.b, transform.a)));
    if (rotationDegrees == 90) {
        transform.tx = videoTrack.naturalSize.height;
        transform.ty = 0;
    } else if (rotationDegrees == 180) {
        transform.tx = videoTrack.naturalSize.width;
        transform.ty = videoTrack.naturalSize.height;
    } else if (rotationDegrees == 270) {
        transform.tx = 0;
        transform.ty = videoTrack.naturalSize.width;
    }
    return transform;
}

/// 设置本地资源数据源
- (void)setDataSourceAsset:(NSString*)asset withKey:(NSString*)key withCertificateUrl:(NSString*)certificateUrl withLicenseUrl:(NSString*)licenseUrl cacheKey:(NSString*)cacheKey cacheManager:(CacheManager*)cacheManager overriddenDuration:(int)overriddenDuration {
    NSString* path = [[NSBundle mainBundle] pathForResource:asset ofType:nil];
    return [self setDataSourceURL:[NSURL fileURLWithPath:path] withKey:key withCertificateUrl:certificateUrl withLicenseUrl:(NSString*)licenseUrl withHeaders:@{} withCache:false cacheKey:cacheKey cacheManager:cacheManager overriddenDuration:overriddenDuration videoExtension:nil];
}

/// 设置网络资源数据源
- (void)setDataSourceURL:(NSURL*)url withKey:(NSString*)key withCertificateUrl:(NSString*)certificateUrl withLicenseUrl:(NSString*)licenseUrl withHeaders:(NSDictionary*)headers withCache:(BOOL)useCache cacheKey:(NSString*)cacheKey cacheManager:(CacheManager*)cacheManager overriddenDuration:(int)overriddenDuration videoExtension:(NSString*)videoExtension {
    _overriddenDuration = 0;
    if (headers == [NSNull null] || headers == NULL){
        headers = @{};
    }
    
    AVPlayerItem* item;
    if (useCache){
        if (cacheKey == [NSNull null]){
            cacheKey = nil;
        }
        if (videoExtension == [NSNull null]){
            videoExtension = nil;
        }
        
        item = [cacheManager getCachingPlayerItemForNormalPlayback:url cacheKey:cacheKey videoExtension:videoExtension headers:headers];
    } else {
        AVURLAsset* asset = [AVURLAsset URLAssetWithURL:url
                                                options:@{@"AVURLAssetHTTPHeaderFieldsKey" : headers}];
        if (certificateUrl && certificateUrl != [NSNull null] && [certificateUrl length] > 0) {
            NSURL * certificateNSURL = [[NSURL alloc] initWithString:certificateUrl];
            NSURL * licenseNSURL = [[NSURL alloc] initWithString:licenseUrl];
            _loaderDelegate = [[BetterPlayerEzDrmAssetsLoaderDelegate alloc] init:certificateNSURL withLicenseURL:licenseNSURL];
            dispatch_queue_attr_t qos = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_DEFAULT, -1);
            dispatch_queue_t streamQueue = dispatch_queue_create("streamQueue", qos);
            [asset.resourceLoader setDelegate:_loaderDelegate queue:streamQueue];
        }
        item = [AVPlayerItem playerItemWithAsset:asset];
    }

    if (@available(iOS 10.0, *) && overriddenDuration > 0) {
        _overriddenDuration = overriddenDuration;
    }
    return [self setDataSourcePlayerItem:item withKey:key];
}

/// 设置播放项并初始化观察者
- (void)setDataSourcePlayerItem:(AVPlayerItem*)item withKey:(NSString*)key {
    _key = key;
    _stalledCount = 0;
    _isStalledCheckStarted = false;
    _playerRate = 1;
    [_player replaceCurrentItemWithPlayerItem:item];

    AVAsset* asset = [item asset];
    void (^assetCompletionHandler)(void) = ^{
        if ([asset statusOfValueForKey:@"tracks" error:nil] == AVKeyValueStatusLoaded) {
            NSArray* tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
            if ([tracks count] > 0) {
                AVAssetTrack* videoTrack = tracks[0];
                void (^trackCompletionHandler)(void) = ^{
                    if (self->_disposed) return;
                    if ([videoTrack statusOfValueForKey:@"preferredTransform"
                                                  error:nil] == AVKeyValueStatusLoaded) {
                        /// 应用修正后的视频变换
                        self->_preferredTransform = [self fixTransform:videoTrack];
                        AVMutableVideoComposition* videoComposition =
                        [self getVideoCompositionWithTransform:self->_preferredTransform
                                                     withAsset:asset
                                                withVideoTrack:videoTrack];
                        item.videoComposition = videoComposition;
                    }
                };
                [videoTrack loadValuesAsynchronouslyForKeys:@[ @"preferredTransform" ]
                                          completionHandler:trackCompletionHandler];
            }
        }
    };

    [asset loadValuesAsynchronouslyForKeys:@[ @"tracks" ] completionHandler:assetCompletionHandler];
    [self addObservers:item];
}

/// 处理播放卡顿
- (void)handleStalled {
    if (_isStalledCheckStarted){
        return;
    }
    _isStalledCheckStarted = true;
    [self startStalledCheck];
}

/// 开始卡顿检查并尝试恢复播放
- (void)startStalledCheck {
    if (_player.currentItem.playbackLikelyToKeepUp ||
        [self availableDuration] - CMTimeGetSeconds(_player.currentItem.currentTime) > 10.0) {
        [self play];
    } else {
        _stalledCount++;
        if (_stalledCount > 60){
            if (_eventSink != nil) {
                _eventSink([FlutterError
                        errorWithCode:@"VideoError"
                        message:@"视频播放卡顿失败"
                        details:nil]);
            }
            return;
        }
        /// 使用 GCD 定时检查，替换 performSelector
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self startStalledCheck];
        });
    }
}

/// 获取已加载的视频时长
- (NSTimeInterval)availableDuration {
    NSArray *loadedTimeRanges = [[_player currentItem] loadedTimeRanges];
    if (loadedTimeRanges.count > 0){
        CMTimeRange timeRange = [[loadedTimeRanges objectAtIndex:0] CMTimeRangeValue];
        Float64 startSeconds = CMTimeGetSeconds(timeRange.start);
        Float64 durationSeconds = CMTimeGetSeconds(timeRange.duration);
        NSTimeInterval result = startSeconds + durationSeconds;
        return result;
    } else {
        return 0;
    }
}

/// 监听播放器状态变化
- (void)observeValueForKeyPath:(NSString*)path
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context {
    if ([path isEqualToString:@"rate"]) {
        if (@available(iOS 10.0, *)) {
            if (_pipController.pictureInPictureActive == true){
                if (_lastAvPlayerTimeControlStatus != [NSNull null] && _lastAvPlayerTimeControlStatus == _player.timeControlStatus){
                    return;
                }

                if (_player.timeControlStatus == AVPlayerTimeControlStatusPaused){
                    _lastAvPlayerTimeControlStatus = _player.timeControlStatus;
                    if (_eventSink != nil) {
                        _eventSink(@{@"event" : @"pause"});
                    }
                    return;
                }
                if (_player.timeControlStatus == AVPlayerTimeControlStatusPlaying){
                    _lastAvPlayerTimeControlStatus = _player.timeControlStatus;
                    if (_eventSink != nil) {
                        _eventSink(@{@"event" : @"play"});
                    }
                }
            }
        }

        if (_player.rate == 0 &&
            CMTIME_COMPARE_INLINE(_player.currentItem.currentTime, >, kCMTimeZero) &&
            CMTIME_COMPARE_INLINE(_player.currentItem.currentTime, <, _player.currentItem.duration) &&
            _isPlaying) {
            [self handleStalled];
        }
    }

    if (context == timeRangeContext) {
        if (_eventSink != nil) {
            NSMutableArray<NSArray<NSNumber*>*>* values = [[NSMutableArray alloc] init];
            for (NSValue* rangeValue in [object loadedTimeRanges]) {
                CMTimeRange range = [rangeValue CMTimeRangeValue];
                int64_t start = [BetterPlayerTimeUtils FLTCMTimeToMillis:(range.start)];
                int64_t end = start + [BetterPlayerTimeUtils FLTCMTimeToMillis:(range.duration)];
                if (!CMTIME_IS_INVALID(_player.currentItem.forwardPlaybackEndTime)) {
                    int64_t endTime = [BetterPlayerTimeUtils FLTCMTimeToMillis:(_player.currentItem.forwardPlaybackEndTime)];
                    if (end > endTime){
                        end = endTime;
                    }
                }

                [values addObject:@[ @(start), @(end) ]];
            }
            _eventSink(@{@"event" : @"bufferingUpdate", @"values" : values, @"key" : _key});
        }
    }
    else if (context == presentationSizeContext){
        [self onReadyToPlay];
    }

    else if (context == statusContext) {
        AVPlayerItem* item = (AVPlayerItem*)object;
        switch (item.status) {
            case AVPlayerItemStatusFailed:
                if (_eventSink != nil) {
                    _eventSink([FlutterError
                                errorWithCode:@"VideoError"
                                message:[NSString stringWithFormat:@"视频加载失败: %@", [item.error localizedDescription]]
                                details:nil]);
                }
                break;
            case AVPlayerItemStatusUnknown:
                break;
            case AVPlayerItemStatusReadyToPlay:
                [self onReadyToPlay];
                break;
        }
    } else if (context == playbackLikelyToKeepUpContext) {
        if ([[_player currentItem] isPlaybackLikelyToKeepUp]) {
            [self updatePlayingState];
            if (_eventSink != nil) {
                _eventSink(@{@"event" : @"bufferingEnd", @"key" : _key});
            }
        }
    } else if (context == playbackBufferEmptyContext) {
        if (_eventSink != nil) {
            _eventSink(@{@"event" : @"bufferingStart", @"key" : _key});
        }
    } else if (context == playbackBufferFullContext) {
        if (_eventSink != nil) {
            _eventSink(@{@"event" : @"bufferingEnd", @"key" : _key});
        }
    }
}

/// 更新播放状态
- (void)updatePlayingState {
    if (!_isInitialized || !_key) {
        return;
    }
    if (!self._observersAdded){
        [self addObservers:[_player currentItem]];
    }

    if (_isPlaying) {
        if (@available(iOS 10.0, *)) {
            [_player playImmediatelyAtRate:1.0];
            _player.rate = _playerRate;
        } else {
            [_player play];
            _player.rate = _playerRate;
        }
    } else {
        [_player pause];
    }
}

/// 处理播放器准备完成
- (void)onReadyToPlay {
    if (_eventSink && !_isInitialized && _key) {
        if (!_player.currentItem) {
            return;
        }
        if (_player.status != AVPlayerStatusReadyToPlay) {
            return;
        }

        CGSize size = [_player currentItem].presentationSize;
        CGFloat width = size.width;
        CGFloat height = size.height;

        AVAsset *asset = _player.currentItem.asset;
        bool onlyAudio = [[asset tracksWithMediaType:AVMediaTypeVideo] count] == 0;

        if (!onlyAudio && height == CGSizeZero.height && width == CGSizeZero.width) {
            return;
        }
        const BOOL isLive = CMTIME_IS_INDEFINITE([_player currentItem].duration);
        if (isLive == false && [self duration] == 0) {
            return;
        }

        AVPlayerItemTrack *track = [self.player currentItem].tracks.firstObject;
        CGSize naturalSize = track.assetTrack.naturalSize;
        CGAffineTransform prefTrans = track.assetTrack.preferredTransform;
        CGSize realSize = CGSizeApplyAffineTransform(naturalSize, prefTrans);

        int64_t duration = [BetterPlayerTimeUtils FLTCMTimeToMillis:(_player.currentItem.asset.duration)];
        if (_overriddenDuration > 0 && duration > _overriddenDuration){
            _player.currentItem.forwardPlaybackEndTime = CMTimeMake(_overriddenDuration/1000, 1);
        }

        _isInitialized = true;
        [self updatePlayingState];
        _eventSink(@{
            @"event" : @"initialized",
            @"duration" : @([self duration]),
            @"width" : @(fabs(realSize.width) ? : width),
            @"height" : @(fabs(realSize.height) ? : height),
            @"key" : _key
        });
    }
}

/// 播放视频
- (void)play {
    _stalledCount = 0;
    _isStalledCheckStarted = false;
    _isPlaying = true;
    [self updatePlayingState];
}

/// 暂停视频
- (void)pause {
    _isPlaying = false;
    [self updatePlayingState];
}

/// 获取当前播放位置（毫秒）
- (int64_t)position {
    return [BetterPlayerTimeUtils FLTCMTimeToMillis:([_player currentTime])];
}

/// 获取绝对播放位置（毫秒）
- (int64_t)absolutePosition {
    return [BetterPlayerTimeUtils FLTNSTimeIntervalToMillis:([[[_player currentItem] currentDate] timeIntervalSince1970])];
}

/// 获取视频总时长（毫秒）
- (int64_t)duration {
    CMTime time;
    if (@available(iOS 13, *)) {
        time = [[_player currentItem] duration];
    } else {
        time = [[[_player currentItem] asset] duration];
    }
    if (!CMTIME_IS_INVALID(_player.currentItem.forwardPlaybackEndTime)) {
        time = [[_player currentItem] forwardPlaybackEndTime];
    }

    return [BetterPlayerTimeUtils FLTCMTimeToMillis:(time)];
}

/// 定位到指定时间（毫秒）
- (void)seekTo:(int)location {
    bool wasPlaying = _isPlaying;
    if (wasPlaying){
        [_player pause];
    }

    [_player seekToTime:CMTimeMake(location, 1000)
        toleranceBefore:kCMTimeZero
         toleranceAfter:kCMTimeZero
      completionHandler:^(BOOL finished){
        if (wasPlaying){
            _player.rate = _playerRate;
        }
    }];
}

/// 设置循环播放状态
- (void)setIsLooping:(bool)isLooping {
    _isLooping = isLooping;
}

/// 设置音量
- (void)setVolume:(double)volume {
    _player.volume = (float)((volume < 0.0) ? 0.0 : ((volume > 1.0) ? 1.0 : volume));
}

/// 设置播放速度
- (void)setSpeed:(double)speed result:(FlutterResult)result {
    if (speed == 1.0 || speed == 0.0) {
        _playerRate = 1;
        result(nil);
    } else if (speed < 0 || speed > 2.0) {
        result([FlutterError errorWithCode:@"unsupported_speed"
                                   message:@"播放速度必须在 0.0 到 2.0 之间"
                                   details:nil]);
    } else if ((speed > 1.0 && _player.currentItem.canPlayFastForward) ||
               (speed < 1.0 && _player.currentItem.canPlaySlowForward)) {
        _playerRate = speed;
        result(nil);
    } else {
        if (speed > 1.0) {
            result([FlutterError errorWithCode:@"unsupported_fast_forward"
                                       message:@"此视频不支持快进"
                                       details:nil]);
        } else {
            result([FlutterError errorWithCode:@"unsupported_slow_forward"
                                       message:@"此视频不支持慢放"
                                       details:nil]);
        }
    }

    if (_isPlaying){
        _player.rate = _playerRate;
    }
}

/// 设置视频轨道参数
- (void)setTrackParameters:(int)width :(int)height :(int)bitrate {
    _player.currentItem.preferredPeakBitRate = bitrate;
    if (@available(iOS 11.0, *)) {
        if (width == 0 && height == 0){
            _player.currentItem.preferredMaximumResolution = CGSizeZero;
        } else {
            _player.currentItem.preferredMaximumResolution = CGSizeMake(width, height);
        }
    }
}

/// 设置画中画状态
- (void)setPictureInPicture:(BOOL)pictureInPicture {
    self._pictureInPicture = pictureInPicture;
    if (@available(iOS 9.0, *)) {
        if (_pipController && self._pictureInPicture && ![_pipController isPictureInPictureActive]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [_pipController startPictureInPicture];
            });
        } else if (_pipController && !self._pictureInPicture && [_pipController isPictureInPictureActive]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [_pipController stopPictureInPicture];
            });
        }
    }
}

#if TARGET_OS_IOS
/// 设置画中画停止后的界面恢复回调
- (void)setRestoreUserInterfaceForPIPStopCompletionHandler:(BOOL)restore {
    if (_restoreUserInterfaceForPIPStopCompletionHandler != NULL) {
        _restoreUserInterfaceForPIPStopCompletionHandler(restore);
        _restoreUserInterfaceForPIPStopCompletionHandler = NULL;
    }
}

/// 初始化画中画控制器
- (void)setupPipController {
    if (@available(iOS 9.0, *)) {
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
        if (!_pipController && self._playerLayer && [AVPictureInPictureController isPictureInPictureSupported]) {
            _pipController = [[AVPictureInPictureController alloc] initWithPlayerLayer:self._playerLayer];
            _pipController.delegate = self;
        }
    }
}

/// 启用画中画模式
- (void)enablePictureInPicture:(CGRect)frame {
    [self disablePictureInPicture];
    [self usePlayerLayer:frame];
}

/// 设置播放器层并启用画中画
- (void)usePlayerLayer:(CGRect)frame {
    if (_player) {
        self._playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
        UIViewController* vc = [[[UIApplication sharedApplication] keyWindow] rootViewController];
        self._playerLayer.frame = frame;
        self._playerLayer.needsDisplayOnBoundsChange = YES;
        [vc.view.layer addSublayer:self._playerLayer];
        vc.view.layer.needsDisplayOnBoundsChange = YES;
        if (@available(iOS 9.0, *)) {
            _pipController = NULL;
        }
        [self setupPipController];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self setPictureInPicture:true];
        });
    }
}

/// 禁用画中画模式
- (void)disablePictureInPicture {
    [self setPictureInPicture:false];
    if (_playerLayer){
        [_playerLayer removeFromSuperlayer];
        _playerLayer = nil;
        if (_eventSink != nil) {
            _eventSink(@{@"event" : @"pipStop"});
        }
    }
}

/// 画中画停止回调
- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController API_AVAILABLE(ios(9.0)){
    [self disablePictureInPicture];
}

/// 画中画启动回调
- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController API_AVAILABLE(ios(9.0)){
    if (_eventSink != nil) {
        _eventSink(@{@"event" : @"pipStart"});
    }
}

/// 画中画即将停止回调
- (void)pictureInPictureControllerWillStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController API_AVAILABLE(ios(9.0)){
}

/// 画中画即将启动回调
- (void)pictureInPictureControllerWillStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
}

/// 画中画启动失败回调
- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController failedToStartPictureInPictureWithError:(NSError *)error {
}

/// 恢复画中画用户界面
- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL))completionHandler {
    [self setRestoreUserInterfaceForPIPStopCompletionHandler:true];
}

/// 设置音频轨道
- (void)setAudioTrack:(NSString*)name index:(int)index {
    AVMediaSelectionGroup *audioSelectionGroup = [[[_player currentItem] asset] mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicAudible];
    NSArray* options = audioSelectionGroup.options;

    for (int audioTrackIndex = 0; audioTrackIndex < [options count]; audioTrackIndex++) {
        AVMediaSelectionOption* option = [options objectAtIndex:audioTrackIndex];
        NSArray *metaDatas = [AVMetadataItem metadataItemsFromArray:option.commonMetadata withKey:@"title" keySpace:@"comn"];
        if (metaDatas.count > 0) {
            NSString *title = ((AVMetadataItem*)[metaDatas objectAtIndex:0]).stringValue;
            if ([name compare:title] == NSOrderedSame && audioTrackIndex == index ){
                [[_player currentItem] selectMediaOption:option inMediaSelectionGroup: audioSelectionGroup];
            }
        }
    }
}

/// 设置音频混音模式
- (void)setMixWithOthers:(bool)mixWithOthers {
    if (mixWithOthers) {
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                     withOptions:AVAudioSessionCategoryOptionMixWithOthers
                                           error:nil];
    } else {
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    }
}
#endif

/// 取消事件监听
- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    return nil;
}

/// 开始事件监听
- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(nonnull FlutterEventSink)events {
    _eventSink = events;
    [self onReadyToPlay];
    return nil;
}

/// 释放资源（不含事件通道）
- (void)disposeSansEventChannel {
    @try{
        [self clear];
    }
    @catch(NSException *exception) {
        NSLog(@"释放资源失败: %@", exception.debugDescription);
    }
}

/// 释放所有资源
- (void)dispose {
    [self pause];
    [self disposeSansEventChannel];
    [_eventChannel setStreamHandler:nil];
    [self disablePictureInPicture];
    [self setPictureInPicture:false];
    _disposed = true;
}

@end
