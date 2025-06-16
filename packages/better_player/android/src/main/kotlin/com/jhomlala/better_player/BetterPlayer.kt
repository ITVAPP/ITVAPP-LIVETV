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
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
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
import org.chromium.net.CronetEngine
import android.util.Log
import java.io.File
import java.lang.Exception
import java.lang.IllegalStateException
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max
import kotlin.math.min

// 视频播放器核心类，管理ExoPlayer及相关功能
internal class BetterPlayer(
    context: Context,
    private val eventChannel: EventChannel,
    private val textureEntry: SurfaceTextureEntry,
    inputCustomDefaultLoadControl: CustomDefaultLoadControl?,  // 修改：重命名参数避免冲突
    result: MethodChannel.Result
) {
    private var exoPlayer: ExoPlayer? = null
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
    private val workManager: WorkManager
    private val workerObserverMap: ConcurrentHashMap<UUID, Observer<WorkInfo?>>
    private val customDefaultLoadControl: CustomDefaultLoadControl =
        inputCustomDefaultLoadControl ?: CustomDefaultLoadControl()  // 修改：使用重命名后的参数
    private var lastSendBufferedPosition = 0L

    // 重试机制相关变量
    private var retryCount = 0
    private val maxRetryCount = 2
    private val retryDelayMs = 1000L
    private var currentMediaSource: MediaSource? = null
    private var wasPlayingBeforeError = false
    // 复用Handler实例，避免重复创建
    private val retryHandler: Handler = Handler(Looper.getMainLooper())
    private var isCurrentlyRetrying = false
    
    // 缓存的Context引用
    private val applicationContext: Context = context.applicationContext
    
    // 标记对象是否已释放
    private val isDisposed = AtomicBoolean(false)
    
    // 标记是否使用了Cronet引擎
    private var isUsingCronet = false

// 初始化播放器，配置加载控制和事件监听
init {
    // 优化1：减少缓冲区大小以降低内存占用
    val loadBuilder = DefaultLoadControl.Builder()
    
    // 判断是否有自定义缓冲配置，如果没有则使用优化后的默认值
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
    
    // 优化内存分配策略
    loadBuilder.setPrioritizeTimeOverSizeThresholds(true)
    
    loadControl = loadBuilder.build()
    
    // 优化3：创建禁用不必要视频处理效果的RenderersFactory
    val renderersFactory = DefaultRenderersFactory(context).apply {
        // 启用解码器回退，当主解码器失败时自动尝试其他解码器
        setEnableDecoderFallback(true)
        
        // 修改：使用 EXTENSION_RENDERER_MODE_PREFER 实现软件优先，硬件备选
        setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
        
        // 禁用视频拼接（所有设备）
        setAllowedVideoJoiningTimeMs(0L)
        
        // 禁用音频处理器以提高性能（所有设备）
        setEnableAudioTrackPlaybackParams(false)
    }
    
    exoPlayer = ExoPlayer.Builder(context, renderersFactory)
        .setTrackSelector(trackSelector)
        .setLoadControl(loadControl)
        .build()
    workManager = WorkManager.getInstance(context)
    workerObserverMap = ConcurrentHashMap()
    setupVideoPlayer(eventChannel, textureEntry, result)
}

    // 创建Player监听器实例 - 简化版本
    private fun createPlayerListener(): Player.Listener {
        return object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (isDisposed.get()) return
                
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        sendBufferingUpdate(true)
                        val event: MutableMap<String, Any> = HashMap()
                        event["event"] = "bufferingStart"
                        eventSink.success(event)
                    }
                    Player.STATE_READY -> {
                        // 播放成功，重置重试计数
                        if (retryCount > 0) {
                            retryCount = 0
                            isCurrentlyRetrying = false
                        }
                        
                        // 修改：简化初始化逻辑，与参考代码保持一致
                        if (!isInitialized) {
                            isInitialized = true
                            sendInitialized()
                        }
                        val event: MutableMap<String, Any> = HashMap()
                        event["event"] = "bufferingEnd"
                        eventSink.success(event)
                    }
                    Player.STATE_ENDED -> {
                        val event: MutableMap<String, Any?> = HashMap()
                        event["event"] = "completed"
                        event["key"] = key
                        eventSink.success(event)
                    }
                    Player.STATE_IDLE -> {
                        // 无操作
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                if (isDisposed.get()) return
                // 增强的错误处理和重试逻辑
                handlePlayerError(error)
            }
        }
    }

    // 检测是否为Android TV设备
    private fun isAndroidTV(): Boolean {
        val uiModeManager = applicationContext.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        return uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
    }

    // 创建Cronet数据源工厂（带自动降级）
    private fun getCronetDataSourceFactory(
        userAgent: String?,
        headers: Map<String, String>?
    ): DataSource.Factory? {
        val engine = getCronetEngine(applicationContext) ?: return null
        
        return try {
            val cronetFactory = CronetDataSource.Factory(engine, getExecutorService())
                .setUserAgent(userAgent)
                .setConnectionTimeoutMs(3000)
                .setReadTimeoutMs(12000)
                .setHandleSetCookieRequests(true)
            
            // 设置自定义请求头
            headers?.filterValues { it != null }?.let { notNullHeaders ->
                if (notNullHeaders.isNotEmpty()) {
                    cronetFactory.setDefaultRequestProperties(notNullHeaders)
                }
            }
            
            // 标记正在使用Cronet
            isUsingCronet = true
            cronetFactory
        } catch (e: Exception) {
            Log.e(TAG, "创建Cronet数据源失败: ${e.message}")
            null
        }
    }

    // 获取优化的数据源工厂（优先Cronet，自动降级）
    private fun getOptimizedDataSourceFactoryWithCronet(
        userAgent: String?,
        headers: Map<String, String>?
    ): DataSource.Factory {
        // 尝试使用Cronet
        getCronetDataSourceFactory(userAgent, headers)?.let {
            Log.d(TAG, "使用Cronet数据源")
            return it
        }
        
        // 降级到优化的HTTP数据源
        Log.d(TAG, "降级到默认HTTP数据源")
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
        clearKey: String?
    ) {
        if (isDisposed.get()) {
            result.error("DISPOSED", "Player has been disposed", null)
            return
        }
        
        this.key = key
        isInitialized = false
        
        val uri = Uri.parse(dataSource)
        var dataSourceFactory: DataSource.Factory?
        val userAgent = getUserAgent(headers)
        
        // 使用优化的协议检测
        val protocolInfo = DataSourceUtils.getProtocolInfo(uri)
        
        // 缓存URI字符串，避免重复调用toString()
        val uriString = uri.toString()
        
        // 修改：使用新的视频格式检测方法
        val detectedFormat = detectVideoFormat(uriString)
        val finalFormatHint = formatHint ?: when (detectedFormat) {
            VideoFormat.HLS -> FORMAT_HLS
            VideoFormat.DASH -> FORMAT_DASH
            VideoFormat.SS -> FORMAT_SS
            else -> null
        }
        
        // 检测是否为HLS流，以便应用专门优化
        val isHlsStream = detectedFormat == VideoFormat.HLS ||
                         finalFormatHint == FORMAT_HLS ||
                         protocolInfo.isHttp && (uri.path?.contains("m3u8") == true)
        
        // 检测是否为HLS直播流
        val isHlsLive = isHlsStream && uriString.contains("live", ignoreCase = true)
        
        // 根据URI类型选择合适的数据源工厂
        dataSourceFactory = when {
            protocolInfo.isRtmp -> {
                // 检测到RTMP流，使用专用数据源工厂
                getRtmpDataSourceFactory()
            }
            protocolInfo.isHttp -> {
                // 为HLS流使用优化的数据源工厂（优先Cronet）
                var httpDataSourceFactory = if (isHlsStream) {
                    getOptimizedDataSourceFactoryWithCronet(userAgent, headers)
                } else {
                    // 普通HTTP也尝试使用Cronet
                    getCronetDataSourceFactory(userAgent, headers) 
                        ?: getDataSourceFactory(userAgent, headers)
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
        
        // 使用现代方式构建 MediaItem（包含 DRM 配置）
        val mediaItem = buildMediaItemWithDrm(
            uri, finalFormatHint, cacheKey, licenseUrl, drmHeaders, clearKey, overriddenDuration
        )
        
        // 构建 MediaSource，传递已知的流类型信息
        val mediaSource = buildMediaSource(mediaItem, dataSourceFactory, context, protocolInfo.isRtmp, isHlsStream)
        
        // 保存媒体源用于重试
        currentMediaSource = mediaSource
        
        exoPlayer?.setMediaSource(mediaSource)
        exoPlayer?.prepare()
        result.success(null)
    }

    // 修改：添加视频格式检测枚举
    private enum class VideoFormat {
        HLS, DASH, SS, OTHER
    }
    
    // 修改：添加视频格式检测方法
    private fun detectVideoFormat(url: String): VideoFormat {
        if (url.isEmpty()) return VideoFormat.OTHER
        
        val lowerCaseUrl = url.lowercase(Locale.getDefault())
        return when {
            lowerCaseUrl.contains(".m3u8") -> VideoFormat.HLS
            lowerCaseUrl.contains(".mpd") -> VideoFormat.DASH
            lowerCaseUrl.contains(".ism") -> VideoFormat.SS
            else -> VideoFormat.OTHER
        }
    }

    // 现代方式：使用 MediaItem.DrmConfiguration 配置 DRM
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
        
        // 为HLS直播流设置播放延迟
       if (uri.toString().contains(".m3u8", ignoreCase = true)) {
           val liveConfiguration = MediaItem.LiveConfiguration.Builder()
               .setTargetOffsetMs(8000)    // 保持8秒延迟
               .setMinOffsetMs(4000)        // 最小延迟
               .setMaxOffsetMs(20000)       // 最大延迟
               .setMinPlaybackSpeed(0.97f)  // 允许轻微减速追赶
               .setMaxPlaybackSpeed(1.03f)  // 允许轻微加速赶上
               .build()
        
           mediaItemBuilder.setLiveConfiguration(liveConfiguration)
       }
        
        // 配置 DRM（现代方式）
        val drmConfiguration = buildDrmConfiguration(licenseUrl, drmHeaders, clearKey)
        if (drmConfiguration != null) {
            mediaItemBuilder.setDrmConfiguration(drmConfiguration)
        }
        
        // 使用现代的 ClippingConfiguration 替代 ClippingMediaSource
        if (overriddenDuration > 0) {
            mediaItemBuilder.setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setEndPositionMs(overriddenDuration * 1000)
                    .build()
            )
        }
        
        return mediaItemBuilder.build()
    }

    // 现代 DRM 配置构建方法
    private fun buildDrmConfiguration(
        licenseUrl: String?,
        drmHeaders: Map<String, String>?,
        clearKey: String?
    ): MediaItem.DrmConfiguration? {
        // API级别18以下不支持DRM
        if (Util.SDK_INT < 18) {
            return null
        }
        
        return when {
            // Widevine DRM
            licenseUrl != null && licenseUrl.isNotEmpty() -> {
                val drmBuilder = MediaItem.DrmConfiguration.Builder(C.WIDEVINE_UUID)
                    .setLicenseUri(licenseUrl)
                    .setMultiSession(false)
                    .setPlayClearContentWithoutKey(true)
                
                // 设置 DRM 请求头
                drmHeaders?.filterValues { it != null }?.let { notNullHeaders ->
                    if (notNullHeaders.isNotEmpty()) {
                        drmBuilder.setLicenseRequestHeaders(notNullHeaders)
                    }
                }
                
                drmBuilder.build()
            }
            
            // ClearKey DRM
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

    // HLS优化的数据源工厂
    private fun getOptimizedDataSourceFactory(
        userAgent: String?,
        headers: Map<String, String>?
    ): DataSource.Factory {
        val dataSourceFactory: DataSource.Factory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
            // HLS直播流优化的超时参数（适度增加，避免过短导致失败）
            .setConnectTimeoutMs(3000)    // 3秒连接超时
            .setReadTimeoutMs(12000)      // 12秒读取超时
            .setTransferListener(null)     // 减少传输监听器开销

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

    // 设置播放器通知，配置标题、作者和图片等
    fun setupPlayerNotification(
        context: Context, title: String, author: String?,
        imageUrl: String?, notificationChannelName: String?,
        activityName: String
    ) {
        if (isDisposed.get()) return
        
        // TV设备不需要通知
        if (isAndroidTV()) {
            Log.d(TAG, "TV设备跳过通知设置")
            return
        }
        
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
                        // 图片处理异常，静默处理
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
        // 注意：移除了重复的监听器添加，因为已在setupVideoPlayer中添加
        exoPlayer?.seekTo(0)
    }

    // 移除远程通知监听和资源
    fun disposeRemoteNotifications() {
        // 释放通知管理器
        if (playerNotificationManager != null) {
            playerNotificationManager?.setPlayer(null)
            playerNotificationManager = null
        }
        
        // 清理WorkManager观察者
        clearAllWorkManagerObservers()
        
        // 正确释放图片资源
        bitmap?.let {
            if (!it.isRecycled) {
                it.recycle()
            }
        }
        bitmap = null
    }

    // 清理所有WorkManager观察者
    private fun clearAllWorkManagerObservers() {
        workerObserverMap.forEach { (uuid, observer) ->
            workManager.getWorkInfoByIdLiveData(uuid).removeObserver(observer)
        }
        workerObserverMap.clear()
    }

    // 现代化的 MediaSource 构建方法
    private fun buildMediaSource(
        mediaItem: MediaItem,
        mediaDataSourceFactory: DataSource.Factory,
        context: Context,
        isRtmpStream: Boolean = false,
        isHlsStream: Boolean = false
    ): MediaSource {
        // 推断内容类型，传递已知的流类型信息
        val type = inferContentType(mediaItem.localConfiguration?.uri, isRtmpStream, isHlsStream)
        
        // 创建对应的 MediaSource.Factory
        return when (type) {
            C.CONTENT_TYPE_SS -> {
                SsMediaSource.Factory(
                    DefaultSsChunkSource.Factory(mediaDataSourceFactory),
                    DefaultDataSource.Factory(context, mediaDataSourceFactory)
                ).createMediaSource(mediaItem)
            }
            C.CONTENT_TYPE_DASH -> {
                DashMediaSource.Factory(
                    DefaultDashChunkSource.Factory(mediaDataSourceFactory),
                    DefaultDataSource.Factory(context, mediaDataSourceFactory)
                ).createMediaSource(mediaItem)
            }
            C.CONTENT_TYPE_HLS -> {
                val factory = HlsMediaSource.Factory(mediaDataSourceFactory)

                 // 错误处理策略
                 val errorHandlingPolicy = object : DefaultLoadErrorHandlingPolicy() {
                     // 重试次数
                     override fun getMinimumLoadableRetryCount(dataType: Int): Int {
                        return when (dataType) {
                             C.DATA_TYPE_MANIFEST -> 5  // 播放列表重试5次
                             C.DATA_TYPE_MEDIA -> 3     // 分片重试3次
                             else -> 2
                         }
                     }
                     override fun getRetryDelayMsFor(loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo): Long {
                         return 500L  // 所有错误都等待500ms
                     }
                 }
                factory.setLoadErrorHandlingPolicy(errorHandlingPolicy)
    
                // 禁用无分片准备（所有设备）
                factory.setAllowChunklessPreparation(false)
                
                // 优化TS分片解析，使用更激进的标志位
                factory.setExtractorFactory(
                    DefaultHlsExtractorFactory(
                        DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES
                            or DefaultTsPayloadReaderFactory.FLAG_DETECT_ACCESS_UNITS
                            or DefaultTsPayloadReaderFactory.FLAG_ENABLE_HDMV_DTS_AUDIO_STREAMS,
                        false // 不暴露CEA608字幕，减少处理开销
                    )
                )
                
                factory.createMediaSource(mediaItem)
            }
            C.CONTENT_TYPE_OTHER -> {
                // RTMP和其他流使用ProgressiveMediaSource
                ProgressiveMediaSource.Factory(
                    mediaDataSourceFactory,
                    DefaultExtractorsFactory()
                ).createMediaSource(mediaItem)
            }
            else -> {
                throw IllegalStateException("不支持的媒体类型: $type")
            }
        }
    }

    // 辅助方法：推断内容类型
    private fun inferContentType(uri: Uri?, isRtmpStream: Boolean, isHlsStream: Boolean): Int {
        if (uri == null) return C.CONTENT_TYPE_OTHER
        
        return when {
            isRtmpStream -> C.CONTENT_TYPE_OTHER
            isHlsStream -> C.CONTENT_TYPE_HLS  // 使用传递的HLS检测结果，避免重复检测
            else -> {
                val lastPathSegment = uri.lastPathSegment ?: ""
                Util.inferContentType(lastPathSegment)
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
        
        // 优化4：视频缩放模式已经是SCALE_TO_FIT，这是性能最好的模式
        // 保持不变，因为这个模式计算最少
        exoPlayer?.videoScalingMode = C.VIDEO_SCALING_MODE_SCALE_TO_FIT
        
        // 优化5：禁用帧率监控（所有设备）
        // 删除 setVideoFrameMetadataListener，减少不必要的回调开销
        
        exoPlayer?.setVideoSurface(surface)
        setAudioAttributes(exoPlayer, true)
        
        // 设置监听器实例
        exoPlayerEventListener = createPlayerListener()
        exoPlayer?.addListener(exoPlayerEventListener!!)
        
        val reply: MutableMap<String, Any> = HashMap()
        reply["textureId"] = textureEntry.id()
        result.success(reply)
    }

    // 智能错误处理方法
    private fun handlePlayerError(error: PlaybackException) {
        if (isDisposed.get()) return
        
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
                val retryEvent: MutableMap<String, Any> = HashMap()
                retryEvent["event"] = "retry"
                retryEvent["retryCount"] = retryCount
                retryEvent["maxRetryCount"] = maxRetryCount
                eventSink.success(retryEvent)
                
                // 计算递增延迟时间
                val delayMs = retryDelayMs * retryCount
                
                // 清理之前的重试任务
                retryHandler.removeCallbacksAndMessages(null)
                
                // 延迟重试
                retryHandler.postDelayed({
                    if (!isDisposed.get()) {
                        performRetry()
                    }
                }, delayMs)
            }
            
            // 超过重试次数或非网络错误
            else -> {
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
        if (isDisposed.get()) return
        
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
        
        val bufferedPosition = exoPlayer?.bufferedPosition ?: 0L
        if (isFromBufferingStart || bufferedPosition != lastSendBufferedPosition) {
            val event: MutableMap<String, Any> = HashMap()
            event["event"] = "bufferingUpdate"
            val range: List<Number?> = listOf(0, bufferedPosition)
            // iOS supports a list of buffered ranges, so here is a list with a single range.
            event["values"] = listOf(range)
            eventSink.success(event)
            lastSendBufferedPosition = bufferedPosition
        }
    }

    // 设置音频属性，控制是否与其他音频混合
    private fun setAudioAttributes(exoPlayer: ExoPlayer?, mixWithOthers: Boolean) {
        if (exoPlayer == null) return
        
        // 使用Media3推荐的音频属性配置
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
            .build()
        
        exoPlayer.setAudioAttributes(audioAttributes, !mixWithOthers)
    }

    // 播放视频
    fun play() {
        if (!isDisposed.get()) {
            exoPlayer?.play()
        }
    }

    // 暂停视频
    fun pause() {
        if (!isDisposed.get()) {
            exoPlayer?.pause()
        }
    }

    // 设置循环播放模式
    fun setLooping(value: Boolean) {
        if (!isDisposed.get()) {
            exoPlayer?.repeatMode = if (value) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
        }
    }

    // 设置音量，范围0.0到1.0
    fun setVolume(value: Double) {
        if (!isDisposed.get()) {
            val bracketedValue = max(0.0, min(1.0, value)).toFloat()
            exoPlayer?.volume = bracketedValue
        }
    }

    // 设置播放速度
    fun setSpeed(value: Double) {
        if (!isDisposed.get()) {
            val bracketedValue = value.toFloat()
            val playbackParameters = PlaybackParameters(bracketedValue)
            exoPlayer?.setPlaybackParameters(playbackParameters)
        }
    }

    // 设置视频轨道参数（宽、高、比特率）
    fun setTrackParameters(width: Int, height: Int, bitrate: Int) {
        if (isDisposed.get()) return
        
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
        if (!isDisposed.get()) {
            exoPlayer?.seekTo(location.toLong())
        }
    }

    // 获取当前播放位置（毫秒）
    val position: Long
        get() = if (!isDisposed.get()) exoPlayer?.currentPosition ?: 0L else 0L

    // 获取绝对播放位置（考虑时间轴偏移）
    val absolutePosition: Long
        get() {
            if (isDisposed.get()) return 0L
            
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
        if (isInitialized && !isDisposed.get()) {
            val event: MutableMap<String, Any?> = HashMap()
            event["event"] = "initialized"
            event["key"] = key
            event["duration"] = getDuration()
            
            exoPlayer?.videoFormat?.let { videoFormat ->
                var width = videoFormat.width
                var height = videoFormat.height
                val rotationDegrees = videoFormat.rotationDegrees
                // Switch the width/height if video was taken in portrait mode
                if (rotationDegrees == 90 || rotationDegrees == 270) {
                    width = videoFormat.height
                    height = videoFormat.width
                }
                event["width"] = width
                event["height"] = height
            }
            eventSink.success(event)
        }
    }

    // 获取视频总时长（毫秒）
    private fun getDuration(): Long = if (!isDisposed.get()) exoPlayer?.duration ?: 0L else 0L

    // 创建媒体会话，用于通知和画中画模式
    @SuppressLint("InlinedApi")
    fun setupMediaSession(context: Context?): MediaSession? {
        if (isDisposed.get()) return null
        
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
        if (!isDisposed.get()) {
            val event: MutableMap<String, Any> = HashMap()
            event["event"] = if (inPip) "pipStart" else "pipStop"
            eventSink.success(event)
        }
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
        if (isDisposed.get()) return
        
        try {
            exoPlayer?.let { player ->
                // 设置音频轨道
                val currentParameters = trackSelector.parameters
                val parametersBuilder = currentParameters.buildUpon()
                parametersBuilder.setPreferredAudioLanguage(name)
                trackSelector.setParameters(parametersBuilder)
            }
        } catch (exception: Exception) {
            // 音频轨道设置失败，静默处理
        }
    }

    // 设置音频混合模式
    fun setMixWithOthers(mixWithOthers: Boolean) {
        if (!isDisposed.get()) {
            setAudioAttributes(exoPlayer, mixWithOthers)
        }
    }

    // 释放播放器资源 - 优化资源释放顺序和安全性
    fun dispose() {
        if (isDisposed.getAndSet(true)) {
            return // 已经释放，避免重复执行
        }
        
        // 1. 先停止所有活动操作
        try {
            exoPlayer?.stop()
        } catch (e: Exception) {
            Log.e(TAG, "停止播放器时出错: ${e.message}")
        }
        
        // 2. 清理重试机制
        resetRetryState()
        
        // 3. 移除监听器（在释放播放器前）
        exoPlayerEventListener?.let { 
            try {
                exoPlayer?.removeListener(it)
            } catch (e: Exception) {
                Log.e(TAG, "移除监听器时出错: ${e.message}")
            }
        }
        exoPlayerEventListener = null
        
        // 4. 清理视频表面（在释放播放器前）
        try {
            exoPlayer?.clearVideoSurface()
        } catch (e: Exception) {
            Log.e(TAG, "清理视频表面时出错: ${e.message}")
        }
        
        // 5. 清理通知和媒体会话
        disposeRemoteNotifications()
        disposeMediaSession()
        
        // 6. 释放表面（在清理视频表面后）
        surface?.release()
        surface = null
        
        // 7. 释放播放器资源
        try {
            exoPlayer?.release()
        } catch (e: Exception) {
            Log.e(TAG, "释放播放器时出错: ${e.message}")
        }
        exoPlayer = null
        
        // 8. 清理事件通道
        eventChannel.setStreamHandler(null)
        
        // 9. 释放纹理
        try {
            textureEntry.release()
        } catch (e: Exception) {
            Log.e(TAG, "释放纹理时出错: ${e.message}")
        }
        
        // 10. 清理引用
        currentMediaSource = null
        
        // 11. 释放Cronet引擎引用（使用引用计数）
        if (isUsingCronet) {
            releaseCronetEngine()
            isUsingCronet = false
        }
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
        // 默认通知通道
        private const val DEFAULT_NOTIFICATION_CHANNEL = "BETTER_PLAYER_NOTIFICATION"
        // 通知ID
        private const val NOTIFICATION_ID = 20772077
        
        // Cronet引擎全局管理
        @Volatile
        private var globalCronetEngine: CronetEngine? = null
        private val cronetRefCount = AtomicInteger(0)
        private val cronetLock = Any()
        
        // 获取Cronet引擎（带引用计数）
        @JvmStatic
        private fun getCronetEngine(context: Context): CronetEngine? {
            synchronized(cronetLock) {
                if (globalCronetEngine == null) {
                    try {
                        globalCronetEngine = CronetUtil.buildCronetEngine(
                            context.applicationContext,
                            null,
                            false
                        )
                        if (globalCronetEngine == null) {
                            Log.w(TAG, "Cronet引擎创建失败")
                            return null
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Cronet初始化失败: ${e.message}")
                        return null
                    }
                }
                cronetRefCount.incrementAndGet()
                return globalCronetEngine
            }
        }
        
        // 释放Cronet引擎引用
        @JvmStatic
        private fun releaseCronetEngine() {
            synchronized(cronetLock) {
                if (cronetRefCount.decrementAndGet() == 0) {
                    globalCronetEngine?.shutdown()
                    globalCronetEngine = null
                    Log.d(TAG, "Cronet引擎已关闭")
                }
            }
        }
        
        // Cronet的Executor服务（使用单例模式管理）
        @Volatile
        private var executorService: java.util.concurrent.ExecutorService? = null
        
        // 获取ExecutorService的单例
        @JvmStatic
        @Synchronized
        private fun getExecutorService(): java.util.concurrent.ExecutorService {
            if (executorService == null) {
                executorService = java.util.concurrent.Executors.newFixedThreadPool(4)
            }
            return executorService!!
        }
        
        // 关闭ExecutorService（应在应用退出时调用）
        @JvmStatic
        fun shutdownExecutorService() {
            executorService?.shutdown()
            executorService = null
        }

        // 清除缓存目录
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
                Log.w(TAG, "无法删除文件: ${file.path}")
            }
        }

        // 开始视频预缓存，使用WorkManager执行
        fun preCache(
            context: Context?, dataSource: String?, preCacheSize: Long,
            maxCacheSize: Long, maxCacheFileSize: Long, headers: Map<String, String?>,
            cacheKey: String?, result: MethodChannel.Result
        ) {
            if (context == null || dataSource == null) {
                result.error("INVALID_PARAMS", "Context or dataSource is null", null)
                return
            }
            
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
            
            val cacheWorkRequest = OneTimeWorkRequest.Builder(CacheWorker::class.java)
                .addTag(dataSource)
                .setInputData(dataBuilder.build()).build()
            WorkManager.getInstance(context).enqueue(cacheWorkRequest)
            
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
