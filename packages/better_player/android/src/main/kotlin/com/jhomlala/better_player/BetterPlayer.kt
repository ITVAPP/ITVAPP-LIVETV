package com.jhomlala.better_player

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.jhomlala.better_player.DataSourceUtils.getUserAgent
import com.jhomlala.better_player.DataSourceUtils.getRtmpDataSourceFactory
import com.jhomlala.better_player.DataSourceUtils.getDataSourceFactory
import io.flutter.plugin.common.EventChannel
import io.flutter.view.TextureRegistry.SurfaceTextureEntry
import io.flutter.plugin.common.MethodChannel
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.PlayerNotificationManager
import androidx.media3.session.MediaSession
import androidx.work.WorkManager
import androidx.work.WorkInfo
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.cronet.CronetDataSource
import androidx.media3.datasource.cronet.CronetUtil
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.ui.PlayerNotificationManager.MediaDescriptionAdapter
import androidx.media3.ui.PlayerNotificationManager.BitmapCallback
import androidx.work.OneTimeWorkRequest
import androidx.media3.common.PlaybackParameters
import android.view.Surface
import androidx.lifecycle.Observer
import androidx.media3.exoplayer.smoothstreaming.SsMediaSource
import androidx.media3.exoplayer.smoothstreaming.DefaultSsChunkSource
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.dash.DefaultDashChunkSource
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.hls.DefaultHlsExtractorFactory
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.rtsp.RtspMediaSource
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import androidx.media3.extractor.ts.TsExtractor
import io.flutter.plugin.common.EventChannel.EventSink
import androidx.work.Data
import androidx.media3.exoplayer.*
import androidx.media3.common.AudioAttributes
import androidx.media3.common.util.Util
import androidx.media3.common.*
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo
import androidx.media3.exoplayer.DefaultRenderersFactory
import org.chromium.net.CronetEngine
import java.io.File
import java.lang.Exception
import java.lang.IllegalStateException
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.math.max
import kotlin.math.min

// 视频播放器核心类，管理ExoPlayer及播放相关功能
internal class BetterPlayer(
    context: Context,
    private val eventChannel: EventChannel,
    private val textureEntry: SurfaceTextureEntry,
    inputCustomDefaultLoadControl: CustomDefaultLoadControl?,  // 自定义加载控制参数
    result: MethodChannel.Result
) {
    private var exoPlayer: ExoPlayer? = null // ExoPlayer实例
    private val eventSink = QueuingEventSink() // 事件发送队列
    private val trackSelector: DefaultTrackSelector = DefaultTrackSelector(context) // 轨道选择器
    private val loadControl: LoadControl // 加载控制
    private var isInitialized = false // 播放器初始化状态
    private var surface: Surface? = null // 视频渲染表面
    private var key: String? = null // 播放器标识
    private var playerNotificationManager: PlayerNotificationManager? = null // 通知管理器
    private var exoPlayerEventListener: Player.Listener? = null // 播放器事件监听器
    private var bitmap: Bitmap? = null // 通知图片
    private var mediaSession: MediaSession? = null // 媒体会话
    private val workManager: WorkManager // WorkManager实例
    private val workerObserverMap: ConcurrentHashMap<UUID, Observer<WorkInfo?>> // WorkManager观察者映射
    private val customDefaultLoadControl: CustomDefaultLoadControl =
        inputCustomDefaultLoadControl ?: CustomDefaultLoadControl() // 默认加载控制
    private var lastSendBufferedPosition = 0L // 最后发送的缓冲位置

    // 重试机制相关变量
    private var retryCount = 0 // 重试计数
    private val maxRetryCount = 2 // 最大重试次数
    private val retryDelayMs = 1000L // 重试延迟时间（毫秒）
    private var currentMediaSource: MediaSource? = null // 当前媒体源
    private var wasPlayingBeforeError = false // 错误前播放状态
    private val retryHandler: Handler = Handler(Looper.getMainLooper()) // 重试Handler
    private var isCurrentlyRetrying = false // 是否正在重试
    
    private val applicationContext: Context = context.applicationContext // 缓存的应用上下文
    
    private val isDisposed = AtomicBoolean(false) // 播放器释放状态
    
    private var isUsingCronet = false // 是否使用Cronet引擎
    
    private var hasCronetFailed = false // Cronet引擎是否失败

    private var currentMediaItem: MediaItem? = null // 当前媒体项
    private var currentDataSourceFactory: DataSource.Factory? = null // 当前数据源工厂
    
    private var preferredDecoderType: Int = HARDWARE_FIRST // 解码器优先级
    private var currentVideoFormat: String? = null // 当前视频格式
    
    private var currentHeaders: Map<String, String>? = null // 当前请求头
    private var currentUserAgent: String? = null // 当前用户代理
    
    private var isPlayerCreated = false // 播放器是否已创建

    // 初始化播放器，配置加载控制与事件通道
    init {
        // 优化缓冲区大小，降低内存占用
        val loadBuilder = DefaultLoadControl.Builder()
        
        // 设置缓冲区参数，优先使用自定义配置
        val minBufferMs = customDefaultLoadControl.minBufferMs?.takeIf { it > 0 } ?: 30000
        val maxBufferMs = customDefaultLoadControl.maxBufferMs?.takeIf { it > 0 } ?: 30000
        val bufferForPlaybackMs = customDefaultLoadControl.bufferForPlaybackMs?.takeIf { it > 0 } ?: 3000
        val bufferForPlaybackAfterRebufferMs = customDefaultLoadControl.bufferForPlaybackAfterRebufferMs?.takeIf { it > 0 } ?: 5000
        
        loadBuilder.setBufferDurationsMs(
            minBufferMs,
            maxBufferMs,
            bufferForPlaybackMs,
            bufferForPlaybackAfterRebufferMs
        )
        
        // 优化内存分配，优先考虑时间而非大小
        loadBuilder.setPrioritizeTimeOverSizeThresholds(true)
        
        loadControl = loadBuilder.build()
        
        workManager = WorkManager.getInstance(context)
        workerObserverMap = ConcurrentHashMap()
        
        // 设置事件通道与视频表面
        setupEventChannel(eventChannel, textureEntry, result)
    }
    
    // 配置事件通道与视频表面
    private fun setupEventChannel(
        eventChannel: EventChannel,
        textureEntry: SurfaceTextureEntry,
        result: MethodChannel.Result
    ) {
        // 设置事件流处理器
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(o: Any?, sink: EventSink) {
                    eventSink.setDelegate(sink)
                }

                override fun onCancel(o: Any?) {
                    eventSink.setDelegate(null)
                }
            })
        // 初始化视频表面
        surface = Surface(textureEntry.surfaceTexture())
        
        // 返回纹理ID
        val reply: MutableMap<String, Any> = HashMap()
        reply["textureId"] = textureEntry.id()
        result.success(reply)
    }

    // 创建ExoPlayer实例
    private fun createPlayer(context: Context) {
        // 配置渲染器工厂
        val renderersFactory = DefaultRenderersFactory(context).apply {	
            // 启用解码器回退
            setEnableDecoderFallback(true)

           // 启用自定解码设置
           setMediaCodecSelector(CustomMediaCodecSelector())
                
            // 根据解码器类型设置渲染模式
            if (preferredDecoderType == SOFTWARE_FIRST) {
                // 优先使用软解码
                setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
            } else {
                // 优先使用硬解码
                setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
            }
            
            // 禁用视频拼接
            setAllowedVideoJoiningTimeMs(0L)
            
            // 禁用音频处理器以提升性能
            setEnableAudioTrackPlaybackParams(false)
        }
        
        // 创建ExoPlayer实例
        exoPlayer = ExoPlayer.Builder(context, renderersFactory)
            .setTrackSelector(trackSelector)
            .setLoadControl(loadControl)
            .build()
    }

    // 创建播放器事件监听器
    private fun createPlayerListener(): Player.Listener {
        return object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (isDisposed.get()) return
                
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        // 发送缓冲开始事件
                        sendBufferingUpdate(true)
                        sendEvent(EVENT_BUFFERING_START)
                    }
                    Player.STATE_READY -> {
                        // 重置重试计数
                        if (retryCount > 0) {
                            retryCount = 0
                            isCurrentlyRetrying = false
                        }
                        
                        // 初始化完成，发送相关事件
                        if (!isInitialized) {
                            isInitialized = true
                            sendInitialized()
                        }
                        sendEvent(EVENT_BUFFERING_END)
                    }
                    Player.STATE_ENDED -> {
                        // 发送播放结束事件
                        sendEvent(EVENT_COMPLETED) { event ->
                            event["key"] = key
                        }
                    }
                    Player.STATE_IDLE -> {
                        // 播放器空闲，无操作
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                if (isDisposed.get()) return
                // 处理播放器错误
                handlePlayerError(error)
            }
        }
    }

    // 判断是否为Android TV设备
    private fun isAndroidTV(): Boolean {
        val uiModeManager = applicationContext.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        return uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
    }

    // 创建Cronet数据源工厂，支持自动降级
    private fun getCronetDataSourceFactory(
        userAgent: String?,
        headers: Map<String, String>?
    ): DataSource.Factory? {
        // 如果禁用 Cronet，返回 null
        if (!ENABLE_CRONET) {
            return null
        }
        
        val engine = getCronetEngine(applicationContext) ?: return null
        
        return try {
            // 配置Cronet数据源
            val cronetFactory = CronetDataSource.Factory(engine, getExecutorService())
                .setUserAgent(userAgent)
                .setConnectionTimeoutMs(3000)
                .setReadTimeoutMs(15000)
                .setHandleSetCookieRequests(true)
            
            // 设置自定义请求头
            headers?.filterValues { it != null }?.let { notNullHeaders ->
                if (notNullHeaders.isNotEmpty()) {
                    cronetFactory.setDefaultRequestProperties(notNullHeaders)
                }
            }
            
            isUsingCronet = true
            cronetFactory
        } catch (e: Exception) {
            null
        }
    }

    // 获取优化的数据源工厂，优先尝试Cronet
    private fun getOptimizedDataSourceFactoryWithCronet(
        userAgent: String?,
        headers: Map<String, String>?
    ): DataSource.Factory {
        // 如果禁用 Cronet，直接使用 HTTP
        if (!ENABLE_CRONET) {
            return getOptimizedDataSourceFactory(userAgent, headers)
        }
        
        // 如果Cronet已失败，直接使用HTTP
        if (hasCronetFailed) {
            return getOptimizedDataSourceFactory(userAgent, headers)
        }
        
        // 尝试使用Cronet
        getCronetDataSourceFactory(userAgent, headers)?.let {
            return it
        }
        
        // 降级到HTTP数据源
        return getOptimizedDataSourceFactory(userAgent, headers)
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
        clearKey: String?,
        preferredDecoderType: Int
    ) {
        if (isDisposed.get()) {
            result.error("DISPOSED", "播放器已释放", null)
            return
        }
        
        // 重置重试相关状态，确保新播放不受上次影响
        resetRetryState()
        
        // 验证解码器类型
        this.preferredDecoderType = when (preferredDecoderType) {
            AUTO, HARDWARE_FIRST, SOFTWARE_FIRST -> if (preferredDecoderType == AUTO) HARDWARE_FIRST else preferredDecoderType
            else -> HARDWARE_FIRST
        }
        
        this.key = key
        isInitialized = false
        
        // 保存请求头和用户代理
        this.currentHeaders = headers
        val userAgent = getUserAgent(headers)
        this.currentUserAgent = userAgent
        
        val uri = Uri.parse(dataSource)
        var dataSourceFactory: DataSource.Factory?
        
        // 获取协议信息
        val protocolInfo = DataSourceUtils.getProtocolInfo(uri)
        
        // 缓存URI字符串
        val uriString = uri.toString()
        
        // 检测视频格式
        val detectedFormat = detectVideoFormat(uriString)
        val finalFormatHint = formatHint ?: when (detectedFormat) {
            VideoFormat.HLS -> FORMAT_HLS
            VideoFormat.DASH -> FORMAT_DASH
            VideoFormat.SS -> FORMAT_SS
            else -> null
        }
        
        // 保存视频格式 - 修复：在创建播放器之前设置
        currentVideoFormat = finalFormatHint
        
        // 创建播放器（首次调用时）
        if (!isPlayerCreated) {
            createPlayer(applicationContext)
            setupVideoPlayer()
            isPlayerCreated = true
        }
        
        // 判断是否为HLS流
        val isHlsStream = detectedFormat == VideoFormat.HLS ||
                         finalFormatHint == FORMAT_HLS ||
                         protocolInfo.isHttp && (uri.path?.contains("m3u8") == true)
        
        // 判断是否为HLS直播流
        val isHlsLive = isHlsStream && uriString.contains("live", ignoreCase = true)
        
        // 判断是否为RTSP流
        val isRtspStream = uri.scheme?.equals("rtsp", ignoreCase = true) == true
        
        // 选择数据源工厂
        dataSourceFactory = when {
            protocolInfo.isRtmp -> getRtmpDataSourceFactory()
            isRtspStream -> null
            protocolInfo.isHttp -> {
                // 为HLS流优化数据源
                var httpDataSourceFactory = if (isHlsStream) {
                    getOptimizedDataSourceFactoryWithCronet(userAgent, headers)
                } else {
                    // 如果启用 Cronet，尝试使用；否则直接使用 HTTP
                    if (ENABLE_CRONET) {
                        getCronetDataSourceFactory(userAgent, headers) 
                            ?: getDataSourceFactory(userAgent, headers)
                    } else {
                        getDataSourceFactory(userAgent, headers)
                    }
                }
                
                // 启用缓存
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
            else -> DefaultDataSource.Factory(context)
        }
        
        // 构建媒体项
        val mediaItem = buildMediaItemWithDrm(
            uri, finalFormatHint, cacheKey, licenseUrl, drmHeaders, clearKey, overriddenDuration
        )
        
        // 保存媒体项和数据源工厂
        this.currentMediaItem = mediaItem
        this.currentDataSourceFactory = dataSourceFactory
        
        // 构建媒体源
        val mediaSource = buildMediaSource(mediaItem, dataSourceFactory, context, protocolInfo.isRtmp, isHlsStream, isRtspStream)
        
        // 保存媒体源
        currentMediaSource = mediaSource
        
        // 设置并准备媒体源
        exoPlayer?.setMediaSource(mediaSource)
        exoPlayer?.prepare()
        result.success(null)
    }
    
    // 配置播放器视频参数
    private fun setupVideoPlayer() {
       // 清理可能的残留状态
       exoPlayer?.clearVideoSurface()
        // 设置视频缩放模式
        exoPlayer?.videoScalingMode = C.VIDEO_SCALING_MODE_SCALE_TO_FIT
        // 设置视频表面
        exoPlayer?.setVideoSurface(surface)
        // 设置音频属性
        setAudioAttributes(exoPlayer, true)
        
        // 添加事件监听器
        exoPlayerEventListener = createPlayerListener()
        exoPlayer?.addListener(exoPlayerEventListener!!)
    }

    // 视频格式枚举
    private enum class VideoFormat {
        HLS, DASH, SS, OTHER
    }
    
    // 检测视频格式
    private fun detectVideoFormat(url: String): VideoFormat {
        if (url.isEmpty()) return VideoFormat.OTHER
        
        val lowerCaseUrl = url.lowercase(Locale.getDefault())
        
        // 单次遍历检测格式
        return when {
            lowerCaseUrl.contains(".m3u8") -> VideoFormat.HLS
            lowerCaseUrl.contains(".mpd") -> VideoFormat.DASH
            lowerCaseUrl.contains(".ism") -> VideoFormat.SS
            else -> VideoFormat.OTHER
        }
    }

    // 构建媒体项，支持DRM配置
    private fun buildMediaItemWithDrm(
        uri: Uri,
        formatHint: String?,
        cacheKey: String?,
        licenseUrl: String?,
        drmHeaders: Map<String, String>?,
        clearKey: String?,
        overriddenDuration: Long
    ): MediaItem {
        val mediaItemBuilder = MediaItem.Builder()
            .setUri(uri)
        
        // 设置缓存键
        if (cacheKey != null && cacheKey.isNotEmpty()) {
            mediaItemBuilder.setCustomCacheKey(cacheKey)
        }
        
        // 为HLS直播流配置播放延迟
        if (uri.toString().contains(".m3u8", ignoreCase = true)) {
            val liveConfiguration = MediaItem.LiveConfiguration.Builder()
                .setTargetOffsetMs(8000)
                .setMinOffsetMs(4000)
                .setMaxOffsetMs(20000)
                .setMinPlaybackSpeed(0.97f)
                .setMaxPlaybackSpeed(1.03f)
                .build()
        
            mediaItemBuilder.setLiveConfiguration(liveConfiguration)
        }
        
        // 配置DRM
        val drmConfiguration = buildDrmConfiguration(licenseUrl, drmHeaders, clearKey)
        if (drmConfiguration != null) {
            mediaItemBuilder.setDrmConfiguration(drmConfiguration)
        }
        
        // 设置裁剪时长
        if (overriddenDuration > 0) {
            mediaItemBuilder.setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setEndPositionMs(overriddenDuration * 1000)
                    .build()
            )
        }
        
        return mediaItemBuilder.build()
    }

    // 构建DRM配置
    private fun buildDrmConfiguration(
        licenseUrl: String?,
        drmHeaders: Map<String, String>?,
        clearKey: String?
    ): MediaItem.DrmConfiguration? {
        if (Util.SDK_INT < 18) return null
        
        return when {
            // 配置Widevine DRM
            licenseUrl != null && licenseUrl.isNotEmpty() -> {
                val drmBuilder = MediaItem.DrmConfiguration.Builder(C.WIDEVINE_UUID)
                    .setLicenseUri(licenseUrl)
                    .setMultiSession(false)
                    .setPlayClearContentWithoutKey(true)
                
                // 设置DRM请求头
                drmHeaders?.filterValues { it != null }?.let { notNullHeaders ->
                    if (notNullHeaders.isNotEmpty()) {
                        drmBuilder.setLicenseRequestHeaders(notNullHeaders)
                    }
                }
                
                drmBuilder.build()
            }
            
            // 配置ClearKey DRM
            clearKey != null && clearKey.isNotEmpty() -> {
                MediaItem.DrmConfiguration.Builder(C.CLEARKEY_UUID)
                    .setKeySetId(clearKey.toByteArray())
                    .setMultiSession(false)
                    .setPlayClearContentWithoutKey(true)
                    .build()
            }
            
            else -> null
        }
    }

    // 获取优化的HTTP数据源工厂
    private fun getOptimizedDataSourceFactory(
        userAgent: String?,
        headers: Map<String, String>?
    ): DataSource.Factory {
        // 配置HTTP数据源
        val dataSourceFactory: DataSource.Factory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(3000)
            .setReadTimeoutMs(15000)
            .setKeepPostFor302Redirects(true)
            .setTransferListener(null)

        // 设置自定义请求头
        headers?.filterValues { it != null }?.let { notNullHeaders ->
            if (notNullHeaders.isNotEmpty()) {
                (dataSourceFactory as DefaultHttpDataSource.Factory).setDefaultRequestProperties(
                    notNullHeaders
                )
            }
        }
        return dataSourceFactory
    }

    // 配置播放器通知
    fun setupPlayerNotification(
        context: Context, title: String, author: String?,
        imageUrl: String?, notificationChannelName: String?,
        activityName: String
    ) {
        if (isDisposed.get()) return
        
        // 检查播放器是否已创建
        if (!isPlayerCreated) return
        
        // TV设备不显示通知
        if (isAndroidTV()) return
        
        var currentWorkerId: UUID? = null
        
        // 创建通知描述适配器
        val mediaDescriptionAdapter: MediaDescriptionAdapter = object : MediaDescriptionAdapter {
            override fun getCurrentContentTitle(player: Player): String = title

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

            override fun getCurrentContentText(player: Player): String? = author

            override fun getCurrentLargeIcon(
                player: Player,
                callback: BitmapCallback
            ): Bitmap? {
                if (imageUrl == null) return null
                if (bitmap != null) return bitmap
                
                // 创建图片加载任务
                val imageWorkRequest = OneTimeWorkRequest.Builder(ImageWorker::class.java)
                    .addTag(imageUrl)
                    .setInputData(
                        Data.Builder()
                            .putString(BetterPlayerPlugin.URL_PARAMETER, imageUrl)
                            .build()
                    )
                    .build()
                workManager.enqueue(imageWorkRequest)
                
                currentWorkerId = imageWorkRequest.id
                
                // 监听图片加载状态
                val workInfoObserver = Observer { workInfo: WorkInfo? ->
                    try {
                        if (workInfo != null) {
                            val state = workInfo.state
                            if (state == WorkInfo.State.SUCCEEDED) {
                                val outputData = workInfo.outputData
                                val filePath =
                                    outputData.getString(BetterPlayerPlugin.FILE_PATH_PARAMETER)
                                bitmap = BitmapFactory.decodeFile(filePath)
                                bitmap?.let { callback.onBitmap(it) }
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
                        // 清理观察者
                        currentWorkerId?.let { id ->
                            val observer = workerObserverMap.remove(id)
                            if (observer != null) {
                                try {
                                    workManager.getWorkInfoByIdLiveData(id).removeObserver(observer)
                                } catch (e: Exception) {
                                    // 静默处理
                                }
                            }
                        }
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
                // 创建通知通道
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

        // 初始化通知管理器
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
        // 定位到起始位置
        exoPlayer?.seekTo(0)
    }

    // 释放通知相关资源
    fun disposeRemoteNotifications() {
        // 释放通知管理器
        if (playerNotificationManager != null) {
            playerNotificationManager?.setPlayer(null)
            playerNotificationManager = null
        }
        
        // 清理WorkManager观察者
        clearAllWorkManagerObservers()
        
        // 释放图片资源
        bitmap?.let {
            if (!it.isRecycled) {
                it.recycle()
            }
        }
        bitmap = null
    }

    // 清理WorkManager观察者
    private fun clearAllWorkManagerObservers() {
        val iterator = workerObserverMap.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            try {
                workManager.getWorkInfoByIdLiveData(entry.key).removeObserver(entry.value)
            } catch (e: Exception) {
                // 静默处理
            }
            iterator.remove()
        }
    }

    // 创建优化的 ExtractorsFactory
    private fun createOptimizedExtractorsFactory(): ExtractorsFactory {
        return DefaultExtractorsFactory().apply {
            // 增加 TS 流时间戳搜索字节数，提高定位精度
            // 默认值是 188 * 50 (9400)，增加到 3 倍以提高精度
            setTsExtractorTimestampSearchBytes(TsExtractor.DEFAULT_TIMESTAMP_SEARCH_BYTES * 3)
            
            // 启用常量比特率寻址，适用于 MP3、ADTS 等固定比特率格式
            // 可以大幅提升这些格式的寻址速度
            setConstantBitrateSeekingEnabled(true)
            
            // 始终尝试使用常量比特率寻址（如果格式支持）
            setConstantBitrateSeekingAlwaysEnabled(true)
        }
    }

    // 创建优化的 HLS ExtractorFactory
    private fun createOptimizedHlsExtractorFactory(): DefaultHlsExtractorFactory {
        return DefaultHlsExtractorFactory(
            DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES,
            true // exposeCea608WhenMissingDeclarations
        ).apply {
            // HLS 特定的优化已在构造函数中配置
            // FLAG_ALLOW_NON_IDR_KEYFRAMES 允许非 IDR 关键帧，提高兼容性
            // exposeCea608WhenMissingDeclarations 允许在缺少声明时暴露 CEA-608 字幕
        }
    }

    // 构建媒体源
    private fun buildMediaSource(
        mediaItem: MediaItem,
        mediaDataSourceFactory: DataSource.Factory?,
        context: Context,
        isRtmpStream: Boolean = false,
        isHlsStream: Boolean = false,
        isRtspStream: Boolean = false
    ): MediaSource {
        // 推断内容类型
        val type = inferContentType(mediaItem.localConfiguration?.uri, isRtmpStream, isHlsStream, isRtspStream)
        
        // 创建优化的 ExtractorsFactory
        val optimizedExtractorsFactory = createOptimizedExtractorsFactory()
        
        // 创建媒体源
        return when (type) {
            C.CONTENT_TYPE_SS -> {
                SsMediaSource.Factory(
                    DefaultSsChunkSource.Factory(mediaDataSourceFactory!!),
                    DefaultDataSource.Factory(context, mediaDataSourceFactory)
                ).createMediaSource(mediaItem)
            }
            C.CONTENT_TYPE_DASH -> {
                DashMediaSource.Factory(
                    DefaultDashChunkSource.Factory(mediaDataSourceFactory!!),
                    DefaultDataSource.Factory(context, mediaDataSourceFactory)
                ).createMediaSource(mediaItem)
            }
            C.CONTENT_TYPE_HLS -> {
                val factory = HlsMediaSource.Factory(mediaDataSourceFactory!!)
                // 配置错误处理策略
                val errorHandlingPolicy = object : DefaultLoadErrorHandlingPolicy() {
                    override fun getMinimumLoadableRetryCount(dataType: Int): Int {
                        return when (dataType) {
                            C.DATA_TYPE_MANIFEST -> 5
                            C.DATA_TYPE_MEDIA -> 3
                            else -> 2
                        }
                    }
                    override fun getRetryDelayMsFor(loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo): Long {
                        return 500L
                    }
                }
                factory.setLoadErrorHandlingPolicy(errorHandlingPolicy)
    
                // 禁用无分片准备
                factory.setAllowChunklessPreparation(false)
                
                // 使用优化的 HLS ExtractorFactory
                factory.setExtractorFactory(createOptimizedHlsExtractorFactory())
                
                factory.createMediaSource(mediaItem)
            }
            C.CONTENT_TYPE_RTSP -> {
                // 创建RTSP媒体源
                RtspMediaSource.Factory()
                    .setForceUseRtpTcp(false)
                    .setTimeoutMs(8000)
                    .createMediaSource(mediaItem)
            }
            C.CONTENT_TYPE_OTHER -> {
                // 创建渐进式媒体源，使用优化的 ExtractorsFactory
                ProgressiveMediaSource.Factory(
                    mediaDataSourceFactory!!,
                    optimizedExtractorsFactory
                ).createMediaSource(mediaItem)
            }
            else -> {
                throw IllegalStateException("不支持的媒体类型: $type")
            }
        }
    }

    // 推断内容类型
    private fun inferContentType(uri: Uri?, isRtmpStream: Boolean, isHlsStream: Boolean, isRtspStream: Boolean): Int {
        if (uri == null) return C.CONTENT_TYPE_OTHER
        
        return when {
            isRtmpStream -> C.CONTENT_TYPE_OTHER
            isRtspStream -> C.CONTENT_TYPE_RTSP
            isHlsStream -> C.CONTENT_TYPE_HLS
            else -> {
                when (detectVideoFormat(uri.toString())) {
                    VideoFormat.HLS -> C.CONTENT_TYPE_HLS
                    VideoFormat.DASH -> C.CONTENT_TYPE_DASH
                    VideoFormat.SS -> C.CONTENT_TYPE_SS
                    VideoFormat.OTHER -> {
                        val lastPathSegment = uri.lastPathSegment ?: ""
                        Util.inferContentType(lastPathSegment)
                    }
                }
            }
        }
    }

    // 处理播放器错误
    private fun handlePlayerError(error: PlaybackException) {
        if (isDisposed.get()) return
        
        // 记录播放状态
        wasPlayingBeforeError = exoPlayer?.isPlaying == true
        
        when (error.errorCode) {
            // 解码器错误，依赖ExoPlayer自动回退
            PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
            PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED,
            PlaybackException.ERROR_CODE_DECODING_FAILED -> {
                // 启用了解码器回退，ExoPlayer会自动处理
            }
            
            // 格式相关错误
            PlaybackException.ERROR_CODE_IO_UNSPECIFIED,
            PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED,
            PlaybackException.ERROR_CODE_PARSING_MANIFEST_MALFORMED,
            PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED,
            PlaybackException.ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED -> {
                // 进行网络重试
                if (isNetworkError(error) && retryCount < maxRetryCount && !isCurrentlyRetrying) {
                    performNetworkRetry()
                } else {
                    eventSink.error("VideoError", "格式错误: ${error.errorCodeName}", "")
                }
            }
            
            // 直播窗口落后，重新定位
            PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW -> {
                exoPlayer?.seekToDefaultPosition()
                exoPlayer?.prepare()
            }
            
            // 其他错误，尝试网络重试或Cronet降级
            else -> {
                if (isNetworkError(error) && retryCount < maxRetryCount && !isCurrentlyRetrying) {
                    performNetworkRetry()
                } else {
                    // 只有在启用 Cronet 的情况下才尝试降级
                    if (ENABLE_CRONET && isUsingCronet && isNetworkError(error) && !hasCronetFailed) {
                        hasCronetFailed = true
                        performCronetFallback()
                    } else {
                        eventSink.error("VideoError", "播放错误: ${error.errorCodeName}", "")
                    }
                }
            }
        }
    }

    // 执行Cronet降级
    private fun performCronetFallback() {
        if (currentMediaItem == null || currentVideoFormat == null) {
            eventSink.error("VideoError", "无法执行Cronet降级：缺少必要信息", "")
            return
        }
        
        // 使用标准HTTP数据源
        val httpDataSourceFactory = getOptimizedDataSourceFactory(currentUserAgent, currentHeaders)
        
        // 检测流类型
        val uri = currentMediaItem?.localConfiguration?.uri
        val isHlsStream = currentVideoFormat == FORMAT_HLS
        val isRtspStream = uri?.scheme?.equals("rtsp", ignoreCase = true) == true
        val protocolInfo = DataSourceUtils.getProtocolInfo(uri!!)
        
        // 重建媒体源
        val newMediaSource = buildMediaSource(
            currentMediaItem!!,
            httpDataSourceFactory,
            applicationContext,
            protocolInfo.isRtmp,
            isHlsStream,
            isRtspStream
        )
        
        currentMediaSource = newMediaSource
        currentDataSourceFactory = httpDataSourceFactory
        
        // 重新加载媒体源
        exoPlayer?.stop()
        exoPlayer?.setMediaSource(newMediaSource)
        exoPlayer?.prepare()
        
        // 恢复播放状态
        if (wasPlayingBeforeError) {
            exoPlayer?.play()
        }
        
        isUsingCronet = false
    }

    // 执行网络重试
    private fun performNetworkRetry() {
        retryCount++
        isCurrentlyRetrying = true
        
        // 计算重试延迟
        val delayMs = retryDelayMs * retryCount
        
        // 清理重试任务
        retryHandler.removeCallbacksAndMessages(null)
        
        // 延迟执行重试
        retryHandler.postDelayed({
            if (!isDisposed.get()) {
                performRetry()
            }
        }, delayMs)
    }

    // 判断是否为网络错误
    private fun isNetworkError(error: PlaybackException): Boolean {
        when (error.errorCode) {
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
            PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE,
            PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED,
            PlaybackException.ERROR_CODE_PARSING_MANIFEST_MALFORMED -> return true
        }
        
        if (error.errorCode == PlaybackException.ERROR_CODE_IO_UNSPECIFIED) {
            val errorMessage = error.message?.lowercase() ?: return false
            val networkErrorKeywords = arrayOf(
                "network", "timeout", "connection", 
                "failed to connect", "unable to connect", "sockettimeout"
            )
            return networkErrorKeywords.any { keyword -> errorMessage.contains(keyword) }
        }
        
        return false
    }

    // 执行重试操作
    private fun performRetry() {
        if (isDisposed.get()) return
        
        try {
            currentMediaSource?.let { mediaSource ->
                // 停止并重新加载媒体源
                exoPlayer?.stop()
                exoPlayer?.setMediaSource(mediaSource)
                exoPlayer?.prepare()
                
                // 恢复播放状态
                if (wasPlayingBeforeError) {
                    exoPlayer?.play()
                }
            } ?: run {
                resetRetryState()
                eventSink.error("VideoError", "重试失败: 媒体源不可用", "")
            }
            
        } catch (exception: Exception) {
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

    // 发送缓冲更新事件
    fun sendBufferingUpdate(isFromBufferingStart: Boolean) {
        if (isDisposed.get()) return
        
        if (!isPlayerCreated) return
        
        val bufferedPosition = exoPlayer?.bufferedPosition ?: 0L
        if (isFromBufferingStart || bufferedPosition != lastSendBufferedPosition) {
            sendEvent(EVENT_BUFFERING_UPDATE) { event ->
                val range: List<Number?> = listOf(0, bufferedPosition)
                event["values"] = listOf(range)
            }
            lastSendBufferedPosition = bufferedPosition
        }
    }

    // 设置音频属性
    private fun setAudioAttributes(exoPlayer: ExoPlayer?, mixWithOthers: Boolean) {
        if (exoPlayer == null) return
        
        // 直播场景使用默认音频属性即可
        exoPlayer.setAudioAttributes(AudioAttributes.DEFAULT, !mixWithOthers)
    }

    // 播放视频
    fun play() {
        if (!isDisposed.get() && isPlayerCreated) {
            exoPlayer?.play()
        }
    }

    // 暂停视频
    fun pause() {
        if (!isDisposed.get() && isPlayerCreated) {
            exoPlayer?.pause()
        }
    }

    // 设置循环播放
    fun setLooping(value: Boolean) {
        if (!isDisposed.get() && isPlayerCreated) {
            exoPlayer?.repeatMode = if (value) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
        }
    }

    // 设置音量
    fun setVolume(value: Double) {
        if (!isDisposed.get() && isPlayerCreated) {
            val bracketedValue = max(0.0, min(1.0, value)).toFloat()
            exoPlayer?.volume = bracketedValue
        }
    }

    // 设置播放速度
    fun setSpeed(value: Double) {
        if (!isDisposed.get() && isPlayerCreated) {
            val bracketedValue = value.toFloat()
            val playbackParameters = PlaybackParameters(bracketedValue)
            exoPlayer?.setPlaybackParameters(playbackParameters)
        }
    }

    // 设置视频轨道参数
    fun setTrackParameters(width: Int, height: Int, bitrate: Int) {
        if (isDisposed.get() || !isPlayerCreated) return
        
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

    // 定位到指定位置
    fun seekTo(location: Int) {
        if (!isDisposed.get() && isPlayerCreated) {
            exoPlayer?.seekTo(location.toLong())
        }
    }

    // 获取当前播放位置
    val position: Long
        get() = if (!isDisposed.get() && isPlayerCreated) exoPlayer?.currentPosition ?: 0L else 0L

    // 获取绝对播放位置
    val absolutePosition: Long
        get() {
            if (isDisposed.get() || !isPlayerCreated) return 0L
            
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
        if (isInitialized && !isDisposed.get() && isPlayerCreated) {
            sendEvent(EVENT_INITIALIZED) { event ->
                event["key"] = key
                event["duration"] = getDuration()
                
                exoPlayer?.videoFormat?.let { videoFormat ->
                    var width = videoFormat.width
                    var height = videoFormat.height
                    val rotationDegrees = videoFormat.rotationDegrees
                    if (rotationDegrees == 90 || rotationDegrees == 270) {
                        width = videoFormat.height
                        height = videoFormat.width
                    }
                    event["width"] = width
                    event["height"] = height
                }
            }
        }
    }

    // 获取视频总时长
    private fun getDuration(): Long = if (!isDisposed.get() && isPlayerCreated) exoPlayer?.duration ?: 0L else 0L

    // 创建媒体会话
    @SuppressLint("InlinedApi")
    fun setupMediaSession(context: Context?): MediaSession? {
        if (isDisposed.get() || !isPlayerCreated) return null
        
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

    // 通知画中画状态变化
    fun onPictureInPictureStatusChanged(inPip: Boolean) {
        if (!isDisposed.get()) {
            sendEvent(if (inPip) EVENT_PIP_START else EVENT_PIP_STOP)
        }
    }

    // 释放媒体会话
    fun disposeMediaSession() {
        if (mediaSession != null) {
            mediaSession?.release()
        }
        mediaSession = null
    }

    // 设置音频轨道
    fun setAudioTrack(name: String, index: Int) {
        if (isDisposed.get() || !isPlayerCreated) return
        
        try {
            exoPlayer?.let { player ->
                val currentParameters = trackSelector.parameters
                val parametersBuilder = currentParameters.buildUpon()
                parametersBuilder.setPreferredAudioLanguage(name)
                trackSelector.setParameters(parametersBuilder)
            }
        } catch (exception: Exception) {
        }
    }

    // 设置音频混合模式
    fun setMixWithOthers(mixWithOthers: Boolean) {
        if (!isDisposed.get() && isPlayerCreated) {
            setAudioAttributes(exoPlayer, mixWithOthers)
        }
    }

    // 释放播放器资源
    fun dispose() {
        if (isDisposed.getAndSet(true)) return
        
        // 停止播放
        try {
            if (isPlayerCreated) {
                exoPlayer?.stop()
            }
        } catch (e: Exception) {
        }
        
        // 清理重试机制
        resetRetryState()
        
        // 移除监听器
        if (isPlayerCreated) {
            exoPlayerEventListener?.let { 
                try {
                    exoPlayer?.removeListener(it)
                } catch (e: Exception) {
                }
            }
        }
        exoPlayerEventListener = null
        
        // 清理视频表面
        if (isPlayerCreated) {
            try {
                exoPlayer?.clearVideoSurface()
            } catch (e: Exception) {
            }
        }
        
        // 清理通知和媒体会话
        disposeRemoteNotifications()
        disposeMediaSession()
        
        // 释放表面
        surface?.release()
        surface = null
        
        // 释放播放器
        if (isPlayerCreated) {
            try {
                exoPlayer?.release()
            } catch (e: Exception) {
            }
        }
        exoPlayer = null
        isPlayerCreated = false
        
        // 清理事件通道
        eventChannel.setStreamHandler(null)
        
        // 释放纹理
        try {
            textureEntry.release()
        } catch (e: Exception) {
        }
        
        // 清理引用
        currentMediaSource = null
        currentMediaItem = null
        currentDataSourceFactory = null
        currentHeaders = null
        currentUserAgent = null
        
        // 释放Cronet引擎
        if (isUsingCronet) {
            releaseCronetEngine()
            isUsingCronet = false
        }
        
        // 清理事件池
        EventMapPool.clear()
        
        // 重置Cronet失败标记
        hasCronetFailed = false
    }

    // 发送事件
    private inline fun sendEvent(eventName: String, configure: (MutableMap<String, Any?>) -> Unit = {}) {
        if (isDisposed.get()) return
        
        val event = EventMapPool.acquire()
        try {
            event["event"] = eventName
            configure(event)
            eventSink.success(event)
        } finally {
            EventMapPool.release(event)
        }
    }

// 自定义解码器选择器
private inner class CustomMediaCodecSelector : MediaCodecSelector {
    
    override fun getDecoderInfos(
        mimeType: String,
        requiresSecureDecoder: Boolean,
        requiresTunnelingDecoder: Boolean
    ): List<MediaCodecInfo> {
        // 根据配置选择基础选择器
        val baseSelector = when (preferredDecoderType) {
            SOFTWARE_FIRST -> MediaCodecSelector.PREFER_SOFTWARE
            else -> MediaCodecSelector.DEFAULT  // HARDWARE_FIRST 和 AUTO 都使用 DEFAULT
        }
        
        // 获取基础选择器的解码器列表
        val decoders = baseSelector.getDecoderInfos(
            // mimeType, requiresSecureDecoder, requiresTunnelingDecoder
            mimeType, false, requiresTunnelingDecoder
        )
        
        // 过滤掉已知的问题解码器
        val filteredDecoders = decoders.filterNot { 
            isProblematicDecoder(it.name) 
        }
        
        // 检查过滤后是否为空
        if (filteredDecoders.isEmpty()) {
            return emptyList()
        }
        
        // 根据解码器类型返回正确排序的列表
        return when (preferredDecoderType) {
            SOFTWARE_FIRST -> {
                // 软解码优先：PREFER_SOFTWARE 已经处理了排序，直接返回过滤后的结果
                filteredDecoders
            }
            else -> {
                // 硬解码优先：需要重新排序，因为 DEFAULT 可能没有按硬件优先排序
                sortDecodersHardwareFirst(filteredDecoders)
            }
        }
    }
    
    // 硬解码优先排序
    private fun sortDecodersHardwareFirst(decoders: List<MediaCodecInfo>): List<MediaCodecInfo> {
        return decoders.sortedBy { codecInfo ->
            val name = codecInfo.name.lowercase()
            when {
                // 软解码器标识符
                name.startsWith("omx.google.") || 
                name.startsWith("c2.android.") ||
                name.startsWith("c2.google.") ||
                name.contains("ffmpeg") -> 1  // 排在后面
                else -> 0  // 硬解码器排在前面
            }
        }
    }
    
    // 检查是否为问题解码器
    private fun isProblematicDecoder(decoderName: String?): Boolean {
        if (decoderName.isNullOrEmpty()) return false
        return ProblematicDecodersConfig.decoders.any { 
            decoderName.contains(it, ignoreCase = true) 
        }
    }
}
    
    companion object {
        private const val FORMAT_SS = "ss" // SmoothStreaming格式
        private const val FORMAT_DASH = "dash" // DASH格式
        private const val FORMAT_HLS = "hls" // HLS格式
        private const val DEFAULT_NOTIFICATION_CHANNEL = "BETTER_PLAYER_NOTIFICATION" // 默认通知通道
        private const val NOTIFICATION_ID = 20772077 // 通知ID
        
        const val AUTO = 0 // 自动解码
        const val HARDWARE_FIRST = 1 // 硬解码优先
        const val SOFTWARE_FIRST = 2 // 软解码优先
        
        private const val EVENT_INITIALIZED = "initialized" // 初始化事件
        private const val EVENT_BUFFERING_UPDATE = "bufferingUpdate" // 缓冲更新事件
        private const val EVENT_BUFFERING_START = "bufferingStart" // 缓冲开始事件
        private const val EVENT_BUFFERING_END = "bufferingEnd" // 缓冲结束事件
        private const val EVENT_COMPLETED = "completed" // 播放完成事件
        private const val EVENT_RETRY = "retry" // 重试事件
        private const val EVENT_PIP_START = "pipStart" // 画中画开始事件
        private const val EVENT_PIP_STOP = "pipStop" // 画中画结束事件
        
        // 是否启用 Cronet 引擎（用于调试）
        private const val ENABLE_CRONET = true // 设置为 false 可禁用 Cronet
        
        @Volatile
        private var globalCronetEngine: CronetEngine? = null // Cronet引擎
        private val cronetRefCount = AtomicInteger(0) // Cronet引用计数
        private val cronetLock = Any() // Cronet锁
        
        // 获取Cronet引擎
        @JvmStatic
        private fun getCronetEngine(context: Context): CronetEngine? {
            synchronized(cronetLock) {
                // 如果禁用 Cronet，直接返回 null
                if (!ENABLE_CRONET) {
                    return null
                }
                
                if (globalCronetEngine == null) {
                    try {
                        globalCronetEngine = CronetUtil.buildCronetEngine(
                            context.applicationContext,
                            null,
                            false
                        )
                        if (globalCronetEngine == null) {
                            return null
                        }
                    } catch (e: Exception) {
                        return null
                    }
                }
                cronetRefCount.incrementAndGet()
                return globalCronetEngine
            }
        }
        
        // 释放Cronet引擎
        @JvmStatic
        private fun releaseCronetEngine() {
            synchronized(cronetLock) {
                if (cronetRefCount.decrementAndGet() == 0) {
                    globalCronetEngine?.shutdown()
                    globalCronetEngine = null
                }
            }
        }
        
        @Volatile
        private var executorService: java.util.concurrent.ExecutorService? = null
        
        // 获取Executor服务
        @JvmStatic
        @Synchronized
        private fun getExecutorService(): java.util.concurrent.ExecutorService {
            if (executorService == null) {
                executorService = java.util.concurrent.Executors.newFixedThreadPool(4)
            }
            return executorService!!
        }
        
        // 关闭Executor服务
        @JvmStatic
        fun shutdownExecutorService() {
            executorService?.shutdown()
            executorService = null
        }

        // 清除缓存
        fun clearCache(context: Context?, result: MethodChannel.Result) {
            try {
                context?.let { context ->
                    val file = File(context.cacheDir, "betterPlayerCache")
                    deleteDirectory(file)
                }
                result.success(null)
            } catch (exception: Exception) {
                result.error("CLEAR_CACHE_ERROR", exception.message, null)
            }
        }

        // 递归删除目录
        private fun deleteDirectory(file: File) {
            if (file.isDirectory) {
                val entries = file.listFiles()
                if (entries != null) {
                    for (entry in entries) {
                        deleteDirectory(entry)
                    }
                }
            }
            file.delete()
        }

        // 预缓存视频
        fun preCache(
            context: Context?, dataSource: String?, preCacheSize: Long,
            maxCacheSize: Long, maxCacheFileSize: Long, headers: Map<String, String?>,
            cacheKey: String?, result: MethodChannel.Result
        ) {
            if (context == null || dataSource == null) {
                result.error("INVALID_PARAMS", "Context or dataSource is null", null)
                return
            }
            
            // 配置缓存任务
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
            
            // 创建缓存任务
            val cacheWorkRequest = OneTimeWorkRequest.Builder(CacheWorker::class.java)
                .addTag(dataSource)
                .setInputData(dataBuilder.build()).build()
            WorkManager.getInstance(context).enqueue(cacheWorkRequest)
            
            result.success(null)
        }

        // 停止预缓存
        fun stopPreCache(context: Context?, url: String?, result: MethodChannel.Result) {
            if (url != null && context != null) {
                WorkManager.getInstance(context).cancelAllWorkByTag(url)
            }
            result.success(null)
        }
    }
}

// 事件对象池
private object EventMapPool {
    private const val MAX_POOL_SIZE = 10
    private val pool = ConcurrentLinkedQueue<MutableMap<String, Any?>>()
    
    // 获取事件对象
    fun acquire(): MutableMap<String, Any?> {
        return pool.poll() ?: HashMap()
    }
    
    // 释放事件对象
    fun release(map: MutableMap<String, Any?>) {
        if (pool.size < MAX_POOL_SIZE) {
            map.clear()
            pool.offer(map)
        }
    }
    
    // 清理对象池
    fun clear() {
        pool.clear()
    }
}
