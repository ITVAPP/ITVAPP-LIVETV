package com.jhomlala.better_player

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.jhomlala.better_player.DataSourceUtils.getUserAgent
import com.jhomlala.better_player.DataSourceUtils.isHTTP
import com.jhomlala.better_player.DataSourceUtils.isRTMP
import com.jhomlala.better_player.DataSourceUtils.getRtmpDataSourceFactory
import com.jhomlala.better_player.DataSourceUtils.getDataSourceFactory
import io.flutter.plugin.common.EventChannel
import io.flutter.view.TextureRegistry.SurfaceTextureEntry
import io.flutter.plugin.common.MethodChannel
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.PlayerNotificationManager
import androidx.media3.session.MediaSession
import androidx.media3.exoplayer.drm.DrmSessionManager
import androidx.work.WorkManager
import androidx.work.WorkInfo
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.UnsupportedDrmException
import androidx.media3.exoplayer.drm.DummyExoMediaDrm
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ClippingMediaSource
import androidx.media3.ui.PlayerNotificationManager.MediaDescriptionAdapter
import androidx.media3.ui.PlayerNotificationManager.BitmapCallback
import androidx.work.OneTimeWorkRequest
import androidx.media3.common.PlaybackParameters
import android.util.Log
import android.view.Surface
import androidx.lifecycle.Observer
import androidx.media3.exoplayer.smoothstreaming.SsMediaSource
import androidx.media3.exoplayer.smoothstreaming.DefaultSsChunkSource
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.dash.DefaultDashChunkSource
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.extractor.DefaultExtractorsFactory
import io.flutter.plugin.common.EventChannel.EventSink
import androidx.work.Data
import androidx.media3.exoplayer.*
import androidx.media3.common.AudioAttributes
import androidx.media3.exoplayer.drm.DrmSessionManagerProvider
import androidx.media3.datasource.DataSource
import androidx.media3.common.util.Util
import androidx.media3.common.*
import androidx.media3.exoplayer.trackselection.AdaptiveTrackSelection
import java.io.File
import java.lang.Exception
import java.lang.IllegalStateException
import java.util.*
import kotlin.math.max
import kotlin.math.min

// 视频播放器核心类，管理ExoPlayer及相关功能
internal class BetterPlayer(
    context: Context,
    private val eventChannel: EventChannel,
    private val textureEntry: SurfaceTextureEntry,
    customDefaultLoadControl: CustomDefaultLoadControl?,
    result: MethodChannel.Result
) {
    private val exoPlayer: ExoPlayer?
    private val eventSink = QueuingEventSink()
    private val trackSelector: DefaultTrackSelector = DefaultTrackSelector(context)
    private val loadControl: LoadControl
    private var isInitialized = false
    private var surface: Surface? = null
    private var key: String? = null
    private var playerNotificationManager: PlayerNotificationManager? = null
    private var exoPlayerEventListener: Player.Listener? = null
    private var bitmap: Bitmap? = null
    private var mediaSession: MediaSession? = null
    private var drmSessionManager: DrmSessionManager? = null
    private val workManager: WorkManager
    private val workerObserverMap: HashMap<UUID, Observer<WorkInfo?>>
    private val customDefaultLoadControl: CustomDefaultLoadControl =
        customDefaultLoadControl ?: CustomDefaultLoadControl()
    private var lastSendBufferedPosition = 0L

    // 重试机制相关变量
    private var retryCount = 0
    private val maxRetryCount = 2
    private val retryDelayMs = 2000L
    private var currentMediaSource: MediaSource? = null
    private var wasPlayingBeforeError = false
    // 复用Handler实例，避免重复创建
    private val retryHandler: Handler = Handler(Looper.getMainLooper())
    private var isCurrentlyRetrying = false
    
    // 复用的事件HashMap，用于高频事件
    private val reusableEventMap: MutableMap<String, Any> = HashMap()

    // 初始化播放器，配置加载控制和事件监听
    init {
        // 为解决花屏问题优化的缓冲配置
        val loadBuilder = DefaultLoadControl.Builder()
        loadBuilder.setBufferDurationsMs(
            this.customDefaultLoadControl.minBufferMs,
            this.customDefaultLoadControl.maxBufferMs,
            this.customDefaultLoadControl.bufferForPlaybackMs,
            this.customDefaultLoadControl.bufferForPlaybackAfterRebufferMs
        )
        loadControl = loadBuilder.build()
        // 创建带有优化设置的RenderersFactory
        val renderersFactory = DefaultRenderersFactory(context).apply {
            // 启用解码器回退，当主解码器失败时自动尝试其他解码器
            setEnableDecoderFallback(true)
            
            // 设置更长的视频连接时间容差，减少视频卡顿
            setAllowedVideoJoiningTimeMs(5000L)
        }
        
        exoPlayer = ExoPlayer.Builder(context, renderersFactory)
            .setTrackSelector(trackSelector)
            .setLoadControl(loadControl)
            .build()
        workManager = WorkManager.getInstance(context)
        workerObserverMap = HashMap()
        setupVideoPlayer(eventChannel, textureEntry, result)
    }

    // 设置视频数据源，支持多种协议和DRM
    fun setDataSource(
        context: Context,
        key: String?,
        dataSource: String?,
        formatHint: String?,
        result: MethodChannel.Result,
        headers: Map<String, String>?,
        useCache: Boolean,
        maxCacheSize: Long,
        maxCacheFileSize: Long,
        overriddenDuration: Long,
        licenseUrl: String?,
        drmHeaders: Map<String, String>?,
        cacheKey: String?,
        clearKey: String?
    ) {
        this.key = key
        isInitialized = false
        val uri = Uri.parse(dataSource)
        var dataSourceFactory: DataSource.Factory?
        val userAgent = getUserAgent(headers)
        
        // 配置DRM会话管理器
        drmSessionManager = configureDrmSessionManager(licenseUrl, drmHeaders, clearKey)
        
        // 使用优化的协议检测
        val protocolInfo = DataSourceUtils.getProtocolInfo(uri)
        
        // 检测是否为HLS流，以便应用专门优化
        val isHlsStream = uri.toString().contains(".m3u8", ignoreCase = true) || 
                         formatHint == FORMAT_HLS ||
                         protocolInfo.isHttp && (uri.path?.contains("m3u8") == true)
        
        // 根据URI类型选择合适的数据源工厂
        dataSourceFactory = when {
            protocolInfo.isRtmp -> {
                // 检测到RTMP流，使用专用数据源工厂
                getRtmpDataSourceFactory()
            }
            protocolInfo.isHttp -> {
                // 为HLS流使用优化的数据源工厂
                var httpDataSourceFactory = if (isHlsStream) {
                    getOptimizedDataSourceFactory(userAgent, headers)
                } else {
                    getDataSourceFactory(userAgent, headers)
                }
                
                if (useCache && maxCacheSize > 0 && maxCacheFileSize > 0) {
                    httpDataSourceFactory = CacheDataSourceFactory(
                        context,
                        maxCacheSize,
                        maxCacheFileSize,
                        httpDataSourceFactory
                    )
                }
                httpDataSourceFactory
            }
            else -> {
                DefaultDataSource.Factory(context)
            }
        }
        
        val mediaSource = buildMediaSource(uri, dataSourceFactory, formatHint, cacheKey, context, protocolInfo.isRtmp)
        
        // 保存媒体源用于重试
        currentMediaSource = mediaSource
        
        if (overriddenDuration != 0L) {
            val clippingMediaSource = ClippingMediaSource(mediaSource, 0, overriddenDuration * 1000)
            exoPlayer?.setMediaSource(clippingMediaSource)
            currentMediaSource = clippingMediaSource
        } else {
            exoPlayer?.setMediaSource(mediaSource)
        }
        exoPlayer?.prepare()
        result.success(null)
    }

    // HLS优化的数据源工厂
    private fun getOptimizedDataSourceFactory(
        userAgent: String?,
        headers: Map<String, String>?
    ): DataSource.Factory {
        val dataSourceFactory: DataSource.Factory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
            // HLS直播流优化的超时参数
            .setConnectTimeoutMs(10000)   // 连接超时10秒
            .setReadTimeoutMs(15000)      // 读取超时15秒
            .setTransferListener(null)     // 减少传输监听器开销

        // 设置自定义请求头
        if (headers != null) {
            val notNullHeaders = mutableMapOf<String, String>()
            headers.forEach { entry ->
                entry.value?.let { value ->
                    notNullHeaders[entry.key] = value
                }
            }
            if (notNullHeaders.isNotEmpty()) {
                (dataSourceFactory as DefaultHttpDataSource.Factory).setDefaultRequestProperties(
                    notNullHeaders
                )
            }
        }
        return dataSourceFactory
    }

    // 配置DRM会话管理器，支持Widevine和ClearKey
    private fun configureDrmSessionManager(
        licenseUrl: String?,
        drmHeaders: Map<String, String>?,
        clearKey: String?
    ): DrmSessionManager? {
        return when {
            licenseUrl != null && licenseUrl.isNotEmpty() -> {
                val httpMediaDrmCallback =
                    HttpMediaDrmCallback(licenseUrl, DefaultHttpDataSource.Factory())
                if (drmHeaders != null) {
                    for ((drmKey, drmValue) in drmHeaders) {
                        httpMediaDrmCallback.setKeyRequestProperty(drmKey, drmValue)
                    }
                }
                if (Util.SDK_INT < 18) {
                    // API级别18以下不支持DRM
                    Log.e(TAG, "DRM配置失败: API级别18以下不支持受保护内容")
                    null
                } else {
                    val drmSchemeUuid = Util.getDrmUuid("widevine")
                    if (drmSchemeUuid != null) {
                        DefaultDrmSessionManager.Builder()
                            .setUuidAndExoMediaDrmProvider(
                                drmSchemeUuid
                            ) { uuid: UUID? ->
                                try {
                                    val mediaDrm = FrameworkMediaDrm.newInstance(uuid!!)
                                    mediaDrm.setPropertyString("securityLevel", "L3")
                                    return@setUuidAndExoMediaDrmProvider mediaDrm
                                } catch (e: UnsupportedDrmException) {
                                    return@setUuidAndExoMediaDrmProvider DummyExoMediaDrm()
                                }
                            }
                            .setMultiSession(false)
                            .build(httpMediaDrmCallback)
                    } else null
                }
            }
            clearKey != null && clearKey.isNotEmpty() -> {
                if (Util.SDK_INT < 18) {
                    // API级别18以下不支持DRM
                    Log.e(TAG, "DRM配置失败: API级别18以下不支持受保护内容")
                    null
                } else {
                    DefaultDrmSessionManager.Builder()
                        .setUuidAndExoMediaDrmProvider(
                            C.CLEARKEY_UUID,
                            FrameworkMediaDrm.DEFAULT_PROVIDER
                        ).build(LocalMediaDrmCallback(clearKey.toByteArray()))
                }
            }
            else -> null
        }
    }

    // 设置播放器通知，配置标题、作者和图片等
    fun setupPlayerNotification(
        context: Context, title: String, author: String?,
        imageUrl: String?, notificationChannelName: String?,
        activityName: String
    ) {
        val mediaDescriptionAdapter: MediaDescriptionAdapter = object : MediaDescriptionAdapter {
            override fun getCurrentContentTitle(player: Player): String {
                return title
            }

            @SuppressLint("UnspecifiedImmutableFlag")
            override fun createCurrentContentIntent(player: Player): PendingIntent? {
                val packageName = context.applicationContext.packageName
                val notificationIntent = Intent()
                notificationIntent.setClassName(
                    packageName,
                    "$packageName.$activityName"
                )
                notificationIntent.flags = (Intent.FLAG_ACTIVITY_CLEAR_TOP
                        or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                return PendingIntent.getActivity(
                    context, 0,
                    notificationIntent,
                    PendingIntent.FLAG_IMMUTABLE
                )
            }

            override fun getCurrentContentText(player: Player): String? {
                return author
            }

            override fun getCurrentLargeIcon(
                player: Player,
                callback: BitmapCallback
            ): Bitmap? {
                if (imageUrl == null) {
                    return null
                }
                if (bitmap != null) {
                    return bitmap
                }
                val imageWorkRequest = OneTimeWorkRequest.Builder(ImageWorker::class.java)
                    .addTag(imageUrl)
                    .setInputData(
                        Data.Builder()
                            .putString(BetterPlayerPlugin.URL_PARAMETER, imageUrl)
                            .build()
                    )
                    .build()
                workManager.enqueue(imageWorkRequest)
                val workInfoObserver = Observer { workInfo: WorkInfo? ->
                    try {
                        if (workInfo != null) {
                            val state = workInfo.state
                            if (state == WorkInfo.State.SUCCEEDED) {
                                val outputData = workInfo.outputData
                                val filePath =
                                    outputData.getString(BetterPlayerPlugin.FILE_PATH_PARAMETER)
                                // 这里的Bitmap已经经过处理且非常小，不会出现问题
                                bitmap = BitmapFactory.decodeFile(filePath)
                                bitmap?.let { bitmap ->
                                    callback.onBitmap(bitmap)
                                }
                            }
                            if (state == WorkInfo.State.SUCCEEDED || state == WorkInfo.State.CANCELLED || state == WorkInfo.State.FAILED) {
                                val uuid = imageWorkRequest.id
                                val observer = workerObserverMap.remove(uuid)
                                if (observer != null) {
                                    workManager.getWorkInfoByIdLiveData(uuid)
                                        .removeObserver(observer)
                                }
                            }
                        }
                    } catch (exception: Exception) {
                        Log.e(TAG, "图片选择错误: $exception")
                    }
                }
                val workerUuid = imageWorkRequest.id
                workManager.getWorkInfoByIdLiveData(workerUuid)
                    .observeForever(workInfoObserver)
                workerObserverMap[workerUuid] = workInfoObserver
                return null
            }
        }
        var playerNotificationChannelName = notificationChannelName
        if (notificationChannelName == null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val importance = NotificationManager.IMPORTANCE_LOW
                val channel = NotificationChannel(
                    DEFAULT_NOTIFICATION_CHANNEL,
                    DEFAULT_NOTIFICATION_CHANNEL, importance
                )
                channel.description = DEFAULT_NOTIFICATION_CHANNEL
                val notificationManager = context.getSystemService(
                    NotificationManager::class.java
                )
                notificationManager.createNotificationChannel(channel)
                playerNotificationChannelName = DEFAULT_NOTIFICATION_CHANNEL
            }
        }

        playerNotificationManager = PlayerNotificationManager.Builder(
            context, NOTIFICATION_ID,
            playerNotificationChannelName!!
        ).setMediaDescriptionAdapter(mediaDescriptionAdapter).build()

        playerNotificationManager?.apply {
            exoPlayer?.let {
                setPlayer(exoPlayer)
                setUseNextAction(false)
                setUsePreviousAction(false)
                setUseStopAction(false)
            }
            setupMediaSession(context)
        }
        exoPlayerEventListener?.let { exoPlayerEventListener ->
            exoPlayer?.addListener(exoPlayerEventListener)
        }
        exoPlayer?.seekTo(0)
    }

    // 移除远程通知监听和资源
    fun disposeRemoteNotifications() {
        // 移除播放器监听器
        exoPlayerEventListener?.let { exoPlayerEventListener ->
            exoPlayer?.removeListener(exoPlayerEventListener)
        }
        exoPlayerEventListener = null
        
        // 释放通知管理器
        if (playerNotificationManager != null) {
            playerNotificationManager?.setPlayer(null)
            playerNotificationManager = null
        }
        
        // 清理WorkManager观察者
        clearAllWorkManagerObservers()
        
        // 清理图片资源
        bitmap = null
    }

    // 清理所有WorkManager观察者
    private fun clearAllWorkManagerObservers() {
        workerObserverMap.forEach { (uuid, observer) ->
            workManager.getWorkInfoByIdLiveData(uuid).removeObserver(observer)
        }
        workerObserverMap.clear()
    }

    // 构建媒体源，支持多种格式和DRM
    private fun buildMediaSource(
        uri: Uri,
        mediaDataSourceFactory: DataSource.Factory,
        formatHint: String?,
        cacheKey: String?,
        context: Context,
        isRtmpStream: Boolean = false
    ): MediaSource {
        val type: Int
        if (formatHint == null) {
            var lastPathSegment = uri.lastPathSegment
            if (lastPathSegment == null) {
                lastPathSegment = ""
            }
            type = if (isRtmpStream) {
                // RTMP流按直播流处理
                C.CONTENT_TYPE_OTHER
            } else {
                // 检查URL中是否包含.m3u8，优先识别为HLS
                if (uri.toString().contains(".m3u8", ignoreCase = true)) {
                    C.CONTENT_TYPE_HLS
                } else {
                    Util.inferContentType(lastPathSegment)
                }
            }
        } else {
            type = when (formatHint) {
                FORMAT_SS -> C.CONTENT_TYPE_SS
                FORMAT_DASH -> C.CONTENT_TYPE_DASH
                FORMAT_HLS -> C.CONTENT_TYPE_HLS
                FORMAT_OTHER -> C.CONTENT_TYPE_OTHER
                "rtmp" -> C.CONTENT_TYPE_OTHER
                else -> -1
            }
        }
        val mediaItemBuilder = MediaItem.Builder()
        mediaItemBuilder.setUri(uri)
        if (cacheKey != null && cacheKey.isNotEmpty() && !isRtmpStream) {
            mediaItemBuilder.setCustomCacheKey(cacheKey)
        }
        val mediaItem = mediaItemBuilder.build()
        return when (type) {
            C.CONTENT_TYPE_SS -> {
                val factory = SsMediaSource.Factory(
                    DefaultSsChunkSource.Factory(mediaDataSourceFactory),
                    DefaultDataSource.Factory(context, mediaDataSourceFactory)
                )
                drmSessionManager?.let { drm ->
                    factory.setDrmSessionManagerProvider(DrmSessionManagerProvider { drm })
                }
                factory.createMediaSource(mediaItem)
            }
            C.CONTENT_TYPE_DASH -> {
                val factory = DashMediaSource.Factory(
                    DefaultDashChunkSource.Factory(mediaDataSourceFactory),
                    DefaultDataSource.Factory(context, mediaDataSourceFactory)
                )
                drmSessionManager?.let { drm ->
                    factory.setDrmSessionManagerProvider(DrmSessionManagerProvider { drm })
                }
                factory.createMediaSource(mediaItem)
            }
            C.CONTENT_TYPE_HLS -> {
                val factory = HlsMediaSource.Factory(mediaDataSourceFactory)
                drmSessionManager?.let { drm ->
                    factory.setDrmSessionManagerProvider(DrmSessionManagerProvider { drm })
                }
                
                // HLS优化配置
                factory.setAllowChunklessPreparation(true)  // 允许无分片准备，加快启动
                
                factory.createMediaSource(mediaItem)
            }
            C.CONTENT_TYPE_OTHER -> {
                // RTMP和其他流使用ProgressiveMediaSource
                val factory = ProgressiveMediaSource.Factory(
                    mediaDataSourceFactory,
                    DefaultExtractorsFactory()
                )
                drmSessionManager?.let { drm ->
                    factory.setDrmSessionManagerProvider(DrmSessionManagerProvider { drm })
                }
                factory.createMediaSource(mediaItem)
            }
            else -> {
                throw IllegalStateException("不支持的媒体类型: $type")
            }
        }
    }

    // 设置视频播放器，配置事件通道和表面
    private fun setupVideoPlayer(
        eventChannel: EventChannel, textureEntry: SurfaceTextureEntry, result: MethodChannel.Result
    ) {
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(o: Any?, sink: EventSink) {
                    eventSink.setDelegate(sink)
                }

                override fun onCancel(o: Any?) {
                    eventSink.setDelegate(null)
                }
            })
        surface = Surface(textureEntry.surfaceTexture())
        
        // 设置视频缩放模式，避免渲染问题
        exoPlayer?.videoScalingMode = C.VIDEO_SCALING_MODE_SCALE_TO_FIT
        exoPlayer?.setVideoChangeFrameRateStrategy(C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF)
        
        exoPlayer?.setVideoSurface(surface)
        setAudioAttributes(exoPlayer, true)
        exoPlayer?.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        sendBufferingUpdate(true)
                        sendEvent("bufferingStart")
                    }
                    Player.STATE_READY -> {
                        // 播放成功，重置重试计数
                        if (retryCount > 0) {
                            retryCount = 0
                            isCurrentlyRetrying = false
                        }
                        
                        if (!isInitialized) {
                            isInitialized = true
                            sendInitialized()
                        }
                        sendEvent("bufferingEnd")
                    }
                    Player.STATE_ENDED -> {
                        sendEventWithData("completed", "key" to key)
                    }
                    Player.STATE_IDLE -> {
                        // 无操作
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                Log.e(TAG, "播放错误: 错误码=${error.errorCode}, 消息=${error.message}")
                
                // 增强的错误处理和重试逻辑
                handlePlayerError(error)
            }
        })
        val reply: MutableMap<String, Any> = HashMap()
        reply["textureId"] = textureEntry.id()
        result.success(reply)
    }

    // 智能错误处理方法
    private fun handlePlayerError(error: PlaybackException) {
        // 记录当前播放状态
        wasPlayingBeforeError = exoPlayer?.isPlaying == true
        
        // 判断是否为可重试的网络错误
        val isRetriableError = isNetworkError(error)
        
        when {
            // 网络错误且未超过重试次数且未在重试中
            isRetriableError && retryCount < maxRetryCount && !isCurrentlyRetrying -> {
                retryCount++
                isCurrentlyRetrying = true
                
                // 发送重试事件给Flutter层
                sendEventWithData("retry", 
                    "retryCount" to retryCount,
                    "maxRetryCount" to maxRetryCount
                )
                
                // 计算递增延迟时间
                val delayMs = retryDelayMs * retryCount
                
                // 清理之前的重试任务
                retryHandler.removeCallbacksAndMessages(null)
                
                // 延迟重试
                retryHandler.postDelayed({
                    performRetry()
                }, delayMs)
            }
            
            // 超过重试次数或非网络错误
            else -> {
                Log.e(TAG, "播放失败: ${if (retryCount >= maxRetryCount) "超过最大重试次数" else "非网络错误"}")
                
                // 重置重试状态
                resetRetryState()
                
                // 发送错误事件
                eventSink.error("VideoError", "视频播放器错误 $error", "")
            }
        }
    }

    // 优化的网络错误判断
    private fun isNetworkError(error: PlaybackException): Boolean {
        // 先判断明确的网络错误码
        when (error.errorCode) {
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
            PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE,
            PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED,
            PlaybackException.ERROR_CODE_PARSING_MANIFEST_MALFORMED -> return true
        }
        
        // 对于未明确分类的IO错误，检查异常消息
        if (error.errorCode == PlaybackException.ERROR_CODE_IO_UNSPECIFIED) {
            val errorMessage = error.message?.lowercase() ?: return false
            
            // 使用预定义的网络错误关键词列表，避免重复的contains调用
            val networkErrorKeywords = arrayOf(
                "network", "timeout", "connection", 
                "failed to connect", "unable to connect", "sockettimeout"
            )
            
            return networkErrorKeywords.any { keyword -> errorMessage.contains(keyword) }
        }
        
        return false
    }

    // 执行重试
    private fun performRetry() {
        try {
            currentMediaSource?.let { mediaSource ->
                // 停止当前播放
                exoPlayer?.stop()
                
                // 重新设置媒体源
                exoPlayer?.setMediaSource(mediaSource)
                exoPlayer?.prepare()
                
                // 如果之前在播放，继续播放
                if (wasPlayingBeforeError) {
                    exoPlayer?.play()
                }
            } ?: run {
                Log.e(TAG, "重试失败: 媒体源为空")
                resetRetryState()
                eventSink.error("VideoError", "重试失败: 媒体源不可用", "")
            }
            
        } catch (exception: Exception) {
            Log.e(TAG, "重试过程中出现异常: ${exception.message}")
            resetRetryState()
            eventSink.error("VideoError", "重试失败: $exception", "")
        }
    }

    // 重置重试状态
    private fun resetRetryState() {
        retryCount = 0
        isCurrentlyRetrying = false
        wasPlayingBeforeError = false
        retryHandler.removeCallbacksAndMessages(null)
    }

    // 优化的发送缓冲更新事件，复用HashMap
    fun sendBufferingUpdate(isFromBufferingStart: Boolean) {
        val bufferedPosition = exoPlayer?.bufferedPosition ?: 0L
        if (isFromBufferingStart || bufferedPosition != lastSendBufferedPosition) {
            // 清理并复用HashMap
            reusableEventMap.clear()
            reusableEventMap["event"] = "bufferingUpdate"
            val range: List<Number?> = listOf(0, bufferedPosition)
            reusableEventMap["values"] = listOf(range)
            eventSink.success(HashMap(reusableEventMap)) // 创建副本以确保线程安全
            lastSendBufferedPosition = bufferedPosition
        }
    }

    // 设置音频属性，控制是否与其他音频混合
    @Suppress("DEPRECATION")
    private fun setAudioAttributes(exoPlayer: ExoPlayer?, mixWithOthers: Boolean) {
        if (exoPlayer == null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            exoPlayer.setAudioAttributes(
                AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
                !mixWithOthers
            )
        } else {
            exoPlayer.setAudioAttributes(
                AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(),
                !mixWithOthers
            )
        }
    }

    // 播放视频
    fun play() {
        exoPlayer?.play()
    }

    // 暂停视频
    fun pause() {
        exoPlayer?.pause()
    }

    // 设置循环播放模式
    fun setLooping(value: Boolean) {
        exoPlayer?.repeatMode = if (value) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
    }

    // 设置音量，范围0.0到1.0
    fun setVolume(value: Double) {
        val bracketedValue = max(0.0, min(1.0, value))
            .toFloat()
        exoPlayer?.volume = bracketedValue
    }

    // 设置播放速度
    fun setSpeed(value: Double) {
        val bracketedValue = value.toFloat()
        val playbackParameters = PlaybackParameters(bracketedValue)
        exoPlayer?.setPlaybackParameters(playbackParameters)
    }

    // 设置视频轨道参数（宽、高、比特率）
    fun setTrackParameters(width: Int, height: Int, bitrate: Int) {
        val parametersBuilder = trackSelector.buildUponParameters()
        if (width != 0 && height != 0) {
            parametersBuilder.setMaxVideoSize(width, height)
        }
        if (bitrate != 0) {
            parametersBuilder.setMaxVideoBitrate(bitrate)
        }
        if (width == 0 && height == 0 && bitrate == 0) {
            parametersBuilder.clearVideoSizeConstraints()
            parametersBuilder.setMaxVideoBitrate(Int.MAX_VALUE)
        }
        trackSelector.setParameters(parametersBuilder)
    }

    // 定位到指定播放位置（毫秒）
    fun seekTo(location: Int) {
        exoPlayer?.seekTo(location.toLong())
    }

    // 获取当前播放位置（毫秒）
    val position: Long
        get() = exoPlayer?.currentPosition ?: 0L

    // 获取绝对播放位置（考虑时间轴偏移）
    val absolutePosition: Long
        get() {
            val timeline = exoPlayer?.currentTimeline
            timeline?.let {
                if (!timeline.isEmpty) {
                    val windowStartTimeMs =
                        timeline.getWindow(0, Timeline.Window()).windowStartTimeMs
                    val pos = exoPlayer?.currentPosition ?: 0L
                    return windowStartTimeMs + pos
                }
            }
            return exoPlayer?.currentPosition ?: 0L
        }

    // 发送初始化完成事件
    private fun sendInitialized() {
        if (isInitialized) {
            val event: MutableMap<String, Any?> = HashMap()
            event["event"] = "initialized"
            event["key"] = key
            event["duration"] = getDuration()
            if (exoPlayer?.videoFormat != null) {
                val videoFormat = exoPlayer.videoFormat
                var width = videoFormat?.width
                var height = videoFormat?.height
                val rotationDegrees = videoFormat?.rotationDegrees
                if (rotationDegrees == 90 || rotationDegrees == 270) {
                    width = exoPlayer.videoFormat?.height
                    height = exoPlayer.videoFormat?.width
                }
                event["width"] = width
                event["height"] = height
            }
            eventSink.success(event)
        }
    }

    // 获取视频总时长（毫秒）
    private fun getDuration(): Long = exoPlayer?.duration ?: 0L

    // 创建媒体会话，用于通知和画中画模式
    @SuppressLint("InlinedApi")
    fun setupMediaSession(context: Context?): MediaSession? {
        mediaSession?.release()
        context?.let {
            exoPlayer?.let { player ->
                val mediaSession = MediaSession.Builder(context, player).build()
                this.mediaSession = mediaSession
                return mediaSession
            }
        }
        return null
    }

    // 通知画中画模式状态变更
    fun onPictureInPictureStatusChanged(inPip: Boolean) {
        sendEvent(if (inPip) "pipStart" else "pipStop")
    }

    // 释放媒体会话资源
    fun disposeMediaSession() {
        if (mediaSession != null) {
            mediaSession?.release()
        }
        mediaSession = null
    }

    // 设置音频轨道，指定语言和索引
    fun setAudioTrack(name: String, index: Int) {
        try {
            exoPlayer?.let { player ->
                // 设置音频轨道
                val currentParameters = trackSelector.parameters
                val parametersBuilder = currentParameters.buildUpon()
                parametersBuilder.setPreferredAudioLanguage(name)
                trackSelector.setParameters(parametersBuilder)
            }
        } catch (exception: Exception) {
            // 音频轨道设置失败，记录异常
            Log.e(TAG, "音频轨道设置失败: ${exception.message}")
        }
    }

    // 发送定位事件
    private fun sendSeekToEvent(positionMs: Long) {
        exoPlayer?.seekTo(positionMs)
        sendEventWithData("seek", "position" to positionMs)
    }

    // 智能检测HLS流：检查URL和查询参数中的.m3u8标识
    private fun isLikelyHLSStream(uri: Uri): Boolean {
        val uriString = uri.toString().lowercase()
        
        // 检查URL路径中是否包含.m3u8
        if (uriString.contains(".m3u8")) {
            return true
        }
        
        // 检查常见的HLS相关查询参数
        val hlsParams = listOf("list", "playlist", "manifest")
        for (param in hlsParams) {
            val paramValue = uri.getQueryParameter(param)
            if (paramValue?.lowercase()?.contains(".m3u8") == true) {
                return true
            }
        }
        
        return false
    }

    // 设置音频混合模式
    fun setMixWithOthers(mixWithOthers: Boolean) {
        setAudioAttributes(exoPlayer, mixWithOthers)
    }

    // 释放播放器资源
    fun dispose() {
        // 清理重试相关资源
        resetRetryState()
        
        // 释放媒体会话
        disposeMediaSession()
        
        // 释放通知相关资源（包含WorkManager观察者清理）
        disposeRemoteNotifications()
        
        // 停止播放器
        if (isInitialized) {
            exoPlayer?.stop()
        }
        
        // 释放DRM会话管理器
        drmSessionManager?.release()
        drmSessionManager = null
        
        // 清理事件通道
        eventChannel.setStreamHandler(null)
        
        // 释放视频表面
        surface?.release()
        surface = null
        
        // 释放纹理
        textureEntry.release()
        
        // 释放播放器
        exoPlayer?.release()
        
        // 清理其他引用
        currentMediaSource = null
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || javaClass != other.javaClass) return false
        val that = other as BetterPlayer
        if (if (exoPlayer != null) exoPlayer != that.exoPlayer else that.exoPlayer != null) return false
        return if (surface != null) surface == that.surface else that.surface == null
    }

    override fun hashCode(): Int {
        var result = exoPlayer?.hashCode() ?: 0
        result = 31 * result + if (surface != null) surface.hashCode() else 0
        return result
    }

    // 通用事件发送方法，减少代码重复
    private fun sendEvent(eventName: String) {
        val event: MutableMap<String, Any> = HashMap()
        event["event"] = eventName
        eventSink.success(event)
    }

    // 带数据的事件发送方法
    private fun sendEventWithData(eventName: String, vararg data: Pair<String, Any?>) {
        val event: MutableMap<String, Any?> = HashMap()
        event["event"] = eventName
        data.forEach { (key, value) ->
            event[key] = value
        }
        eventSink.success(event)
    }

    companion object {
        // 日志标签
        private const val TAG = "BetterPlayer"
        // SmoothStreaming格式
        private const val FORMAT_SS = "ss"
        // DASH格式
        private const val FORMAT_DASH = "dash"
        // HLS格式
        private const val FORMAT_HLS = "hls"
        // 其他格式
        private const val FORMAT_OTHER = "other"
        // 默认通知通道
        private const val DEFAULT_NOTIFICATION_CHANNEL = "BETTER_PLAYER_NOTIFICATION"
        // 通知ID
        private const val NOTIFICATION_ID = 20772077

        // 清除缓存目录
        fun clearCache(context: Context?, result: MethodChannel.Result) {
            try {
                context?.let { context ->
                    val file = File(context.cacheDir, "betterPlayerCache")
                    deleteDirectory(file)
                }
                result.success(null)
            } catch (exception: Exception) {
                // 清除缓存失败，记录异常
                Log.e(TAG, "清除缓存失败: ${exception.message}")
                result.error("", "", "")
            }
        }

        // 递归删除缓存目录
        private fun deleteDirectory(file: File) {
            if (file.isDirectory) {
                val entries = file.listFiles()
                if (entries != null) {
                    for (entry in entries) {
                        deleteDirectory(entry)
                    }
                }
            }
            if (!file.delete()) {
                // 删除缓存目录失败，记录错误
                Log.e(TAG, "删除缓存目录失败")
            }
        }

        // 开始视频预缓存，使用WorkManager执行
        fun preCache(
            context: Context?, dataSource: String?, preCacheSize: Long,
            maxCacheSize: Long, maxCacheFileSize: Long, headers: Map<String, String?>,
            cacheKey: String?, result: MethodChannel.Result
        ) {
            val dataBuilder = Data.Builder()
                .putString(BetterPlayerPlugin.URL_PARAMETER, dataSource)
                .putLong(BetterPlayerPlugin.PRE_CACHE_SIZE_PARAMETER, preCacheSize)
                .putLong(BetterPlayerPlugin.MAX_CACHE_SIZE_PARAMETER, maxCacheSize)
                .putLong(BetterPlayerPlugin.MAX_CACHE_FILE_SIZE_PARAMETER, maxCacheFileSize)
            if (cacheKey != null) {
                dataBuilder.putString(BetterPlayerPlugin.CACHE_KEY_PARAMETER, cacheKey)
            }
            for (headerKey in headers.keys) {
                dataBuilder.putString(
                    BetterPlayerPlugin.HEADER_PARAMETER + headerKey,
                    headers[headerKey]
                )
            }
            if (dataSource != null && context != null) {
                val cacheWorkRequest = OneTimeWorkRequest.Builder(CacheWorker::class.java)
                    .addTag(dataSource)
                    .setInputData(dataBuilder.build()).build()
                WorkManager.getInstance(context).enqueue(cacheWorkRequest)
            }
            result.success(null)
        }

        // 停止指定URL的视频预缓存
        fun stopPreCache(context: Context?, url: String?, result: MethodChannel.Result) {
            if (url != null && context != null) {
                WorkManager.getInstance(context).cancelAllWorkByTag(url)
            }
            result.success(null)
        }
    }
}
