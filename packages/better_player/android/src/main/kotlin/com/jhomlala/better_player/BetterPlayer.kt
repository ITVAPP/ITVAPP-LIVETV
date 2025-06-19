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
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo
import androidx.media3.exoplayer.DefaultRenderersFactory
import org.chromium.net.CronetEngine
import android.util.Log
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
    
    // 修改：添加标记是否已经尝试过Cronet降级
    private var hasCronetFailed = false

    // 保存当前MediaItem用于重建
    private var currentMediaItem: MediaItem? = null
    private var currentDataSourceFactory: DataSource.Factory? = null
    
    // 新增：解码器配置
    private var preferredDecoderType: Int = SOFTWARE_FIRST  // 默认解码优先设置
    private var currentVideoFormat: String? = null  // 当前视频格式
    
    // 修改：保存headers用于降级重试
    private var currentHeaders: Map<String, String>? = null
    private var currentUserAgent: String? = null

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
        
        // 创建播放器
        createPlayer(context)
        
        workManager = WorkManager.getInstance(context)
        workerObserverMap = ConcurrentHashMap()
        setupVideoPlayer(eventChannel, textureEntry, result)
    }

    // 创建播放器
    private fun createPlayer(context: Context) {
        // 修改：使用 DefaultRenderersFactory 替代 NextRenderersFactory
        val renderersFactory = DefaultRenderersFactory(context).apply {	
            // 启用解码器回退 - 这是关键！让ExoPlayer自动处理解码器失败
            setEnableDecoderFallback(true)
            
            // 根据解码器类型设置扩展渲染器模式
            if (preferredDecoderType == SOFTWARE_FIRST) {
            	// 软解码优先
                setMediaCodecSelector(CustomMediaCodecSelector(true, currentVideoFormat))
                setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
            } else {
            	// 硬解码优先
                setMediaCodecSelector(CustomMediaCodecSelector(false, currentVideoFormat))
                setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
            }
            
            // 禁用视频拼接（所有设备）
            setAllowedVideoJoiningTimeMs(0L)
            
            // 禁用音频处理器以提高性能（所有设备）
            setEnableAudioTrackPlaybackParams(false)
        }
        
        exoPlayer = ExoPlayer.Builder(context, renderersFactory)
            .setTrackSelector(trackSelector)
            .setLoadControl(loadControl)
            .build()
    }

    // 创建Player监听器实例 - 简化版本
    private fun createPlayerListener(): Player.Listener {
        return object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (isDisposed.get()) return
                
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        sendBufferingUpdate(true)
                        sendEvent(EVENT_BUFFERING_START)
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
                        sendEvent(EVENT_BUFFERING_END)
                    }
                    Player.STATE_ENDED -> {
                        sendEvent(EVENT_COMPLETED) { event ->
                            event["key"] = key
                        }
                    }
                    Player.STATE_IDLE -> {
                        // 无操作
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                if (isDisposed.get()) return
                // 优化后的错误处理逻辑
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
                .setReadTimeoutMs(15000)
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
        // 修改：如果Cronet已经失败过，直接使用HTTP
        if (hasCronetFailed) {
            Log.d(TAG, "Cronet已失败，直接使用HTTP数据源")
            return getOptimizedDataSourceFactory(userAgent, headers)
        }
        
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
        clearKey: String?,
        preferredDecoderType: Int
    ) {
        if (isDisposed.get()) {
            result.error("DISPOSED", "播放器已释放", null)
            return
        }
        
       // 验证解码器类型
        this.preferredDecoderType = when (preferredDecoderType) {
            AUTO, HARDWARE_FIRST, SOFTWARE_FIRST -> if (preferredDecoderType == AUTO) HARDWARE_FIRST else preferredDecoderType
            else -> {
                Log.w(TAG, "无效解码器类型 $preferredDecoderType，使用硬件解码")
                HARDWARE_FIRST
            }
        }
        
        this.key = key
        isInitialized = false
        
        // 修改：保存headers和userAgent
        this.currentHeaders = headers
        val userAgent = getUserAgent(headers)
        this.currentUserAgent = userAgent
        
        val uri = Uri.parse(dataSource)
        var dataSourceFactory: DataSource.Factory?
        
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
        
        // 保存当前视频格式信息
        currentVideoFormat = finalFormatHint
        
        // 检测是否为HLS流，以便应用专门优化
        val isHlsStream = detectedFormat == VideoFormat.HLS ||
                         finalFormatHint == FORMAT_HLS ||
                         protocolInfo.isHttp && (uri.path?.contains("m3u8") == true)
        
        // 检测是否为HLS直播流
        val isHlsLive = isHlsStream && uriString.contains("live", ignoreCase = true)
        
        // 检测是否为RTSP流
        val isRtspStream = uri.scheme?.equals("rtsp", ignoreCase = true) == true
        
        // 根据URI类型选择合适的数据源工厂
        dataSourceFactory = when {
            protocolInfo.isRtmp -> {
                // 检测到RTMP流，使用专用数据源工厂
                getRtmpDataSourceFactory()
            }
            isRtspStream -> {
                // RTSP流不需要特殊的数据源工厂，直接使用null
                null
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
        
        // 保存MediaItem和DataSourceFactory（用于重建）
        this.currentMediaItem = mediaItem
        this.currentDataSourceFactory = dataSourceFactory
        
        // 构建 MediaSource，传递已知的流类型信息
        val mediaSource = buildMediaSource(mediaItem, dataSourceFactory, context, protocolInfo.isRtmp, isHlsStream, isRtspStream)
        
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
    
    // 优化：优化视频格式检测方法，避免多次contains调用
    private fun detectVideoFormat(url: String): VideoFormat {
        if (url.isEmpty()) return VideoFormat.OTHER
        
        val lowerCaseUrl = url.lowercase(Locale.getDefault())
        
        // 优化：使用单次遍历检测所有格式
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
            // HLS直播流优化的超时参数
            .setConnectTimeoutMs(3000) 
            .setReadTimeoutMs(15000)
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
        
        // 优化：确保异常情况下也能清理观察者
        var currentWorkerId: UUID? = null
        
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
                
                // 保存当前worker ID
                currentWorkerId = imageWorkRequest.id
                
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
                        // 优化：确保清理观察者
                        currentWorkerId?.let { id ->
                            val observer = workerObserverMap.remove(id)
                            if (observer != null) {
                                try {
                                    workManager.getWorkInfoByIdLiveData(id).removeObserver(observer)
                                } catch (e: Exception) {
                                    Log.e(TAG, "清理WorkManager观察者失败: ${e.message}")
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

    // 优化：确保清理所有WorkManager观察者，避免内存泄漏
    private fun clearAllWorkManagerObservers() {
        val iterator = workerObserverMap.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            try {
                workManager.getWorkInfoByIdLiveData(entry.key).removeObserver(entry.value)
            } catch (e: Exception) {
                Log.e(TAG, "移除WorkManager观察者失败: ${e.message}")
            }
            iterator.remove()
        }
    }

    // 现代化的 MediaSource 构建方法
    private fun buildMediaSource(
        mediaItem: MediaItem,
        mediaDataSourceFactory: DataSource.Factory?,
        context: Context,
        isRtmpStream: Boolean = false,
        isHlsStream: Boolean = false,
        isRtspStream: Boolean = false
    ): MediaSource {
        // 推断内容类型，传递已知的流类型信息
        val type = inferContentType(mediaItem.localConfiguration?.uri, isRtmpStream, isHlsStream, isRtspStream)
        
        // 创建对应的 MediaSource.Factory
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
            C.CONTENT_TYPE_RTSP -> {
                // RTSP 使用专门的 RtspMediaSource
                RtspMediaSource.Factory()
                    .setForceUseRtpTcp(false) // 默认使用UDP，失败时自动切换到TCP
                    .setTimeoutMs(8000) // 8秒超时
                    .createMediaSource(mediaItem)
            }
            C.CONTENT_TYPE_OTHER -> {
                // RTMP和其他流使用ProgressiveMediaSource
                ProgressiveMediaSource.Factory(
                    mediaDataSourceFactory!!,
                    DefaultExtractorsFactory()
                ).createMediaSource(mediaItem)
            }
            else -> {
                throw IllegalStateException("不支持的媒体类型: $type")
            }
        }
    }

    // 优化：统一内容类型推断，避免重复代码
    private fun inferContentType(uri: Uri?, isRtmpStream: Boolean, isHlsStream: Boolean, isRtspStream: Boolean): Int {
        if (uri == null) return C.CONTENT_TYPE_OTHER
        
        return when {
            isRtmpStream -> C.CONTENT_TYPE_OTHER
            isRtspStream -> C.CONTENT_TYPE_RTSP
            isHlsStream -> C.CONTENT_TYPE_HLS  // 使用传递的HLS检测结果，避免重复检测
            else -> {
                // 复用detectVideoFormat的结果来推断类型
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

    // 优化后的错误处理方法
    private fun handlePlayerError(error: PlaybackException) {
        if (isDisposed.get()) return
        
        Log.e(TAG, "播放错误: ${error.errorCode}, ${error.message}")
        
        // 记录当前播放状态
        wasPlayingBeforeError = exoPlayer?.isPlaying == true
        
        when (error.errorCode) {
            // 解码器相关错误：依赖ExoPlayer的自动回退
            PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
            PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED,
            PlaybackException.ERROR_CODE_DECODING_FAILED -> {
                Log.d(TAG, "解码器错误，ExoPlayer将自动尝试其他解码器")
                // 修改：不再立即发送解码器错误事件，等待ExoPlayer的自动解码器切换
                // 如果最终失败，会再次触发错误处理
            }
            
            // 格式相关错误
            PlaybackException.ERROR_CODE_IO_UNSPECIFIED,
            PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED,
            PlaybackException.ERROR_CODE_PARSING_MANIFEST_MALFORMED,
            PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED,
            PlaybackException.ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED -> {
                // 尝试格式修正
                if (!handleFormatError(error)) {
                    // 格式修正失败，尝试网络重试
                    if (isNetworkError(error) && retryCount < maxRetryCount && !isCurrentlyRetrying) {
                        performNetworkRetry()
                    } else {
                        eventSink.error("VideoError", "格式错误: ${error.errorCodeName}", "")
                    }
                }
            }
            
            // 直播窗口落后错误：重新定位到默认位置
            PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW -> {
                Log.d(TAG, "直播窗口落后，重新定位")
                exoPlayer?.seekToDefaultPosition()
                exoPlayer?.prepare()
            }
            
            // 其他错误：网络重试或直接报错
            else -> {
                if (isNetworkError(error) && retryCount < maxRetryCount && !isCurrentlyRetrying) {
                    performNetworkRetry()
                } else {
                    // 修改：检查是否是Cronet相关的网络错误，如果是则尝试降级
                    if (isUsingCronet && isNetworkError(error) && !hasCronetFailed) {
                        Log.d(TAG, "Cronet网络错误，尝试降级到HTTP")
                        hasCronetFailed = true
                        performCronetFallback()
                    } else {
                        eventSink.error("VideoError", "播放错误: ${error.errorCodeName}", "")
                    }
                }
            }
        }
    }

    // 修改：添加Cronet降级方法
    private fun performCronetFallback() {
        if (currentMediaItem == null || currentVideoFormat == null) {
            eventSink.error("VideoError", "无法执行Cronet降级：缺少必要信息", "")
            return
        }
        
        Log.d(TAG, "执行Cronet降级，使用标准HTTP数据源")
        
        // 重建数据源工厂，使用标准HTTP
        val httpDataSourceFactory = getOptimizedDataSourceFactory(currentUserAgent, currentHeaders)
        
        // 检测流类型
        val uri = currentMediaItem?.localConfiguration?.uri
        val isHlsStream = currentVideoFormat == FORMAT_HLS
        val isRtspStream = uri?.scheme?.equals("rtsp", ignoreCase = true) == true
        val protocolInfo = DataSourceUtils.getProtocolInfo(uri!!)
        
        // 重建MediaSource
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
        
        // 停止当前播放并重新加载
        exoPlayer?.stop()
        exoPlayer?.setMediaSource(newMediaSource)
        exoPlayer?.prepare()
        
        // 如果之前在播放，继续播放
        if (wasPlayingBeforeError) {
            exoPlayer?.play()
        }
        
        // 重置Cronet使用标记
        isUsingCronet = false
    }

    // 格式错误处理
    private fun handleFormatError(error: PlaybackException): Boolean {
        // 检查是否已经尝试过格式修正
        if (retryCount >= maxRetryCount) return false
        
        val currentUrl = currentMediaItem?.localConfiguration?.uri?.toString() ?: return false
        
        // 根据错误和URL推断格式
        val inferredFormat = when {
            currentUrl.contains(".m3u8", ignoreCase = true) -> FORMAT_HLS
            currentUrl.contains(".mpd", ignoreCase = true) -> FORMAT_DASH  
            currentUrl.contains(".ism", ignoreCase = true) -> FORMAT_SS
            else -> null
        }
        
        if (inferredFormat != null && currentMediaItem != null && currentDataSourceFactory != null) {
            Log.d(TAG, "尝试使用推断的格式: $inferredFormat")
            
            retryCount++
            
            // 重建MediaItem with新格式
            val newMediaItem = MediaItem.Builder()
                .setUri(currentMediaItem!!.localConfiguration?.uri)
                .setMimeType(when(inferredFormat) {
                    FORMAT_HLS -> MimeTypes.APPLICATION_M3U8
                    FORMAT_DASH -> MimeTypes.APPLICATION_MPD
                    FORMAT_SS -> MimeTypes.APPLICATION_SS
                    else -> null
                })
                .build()
            
            currentMediaItem = newMediaItem
            
            // 重建MediaSource
            val newMediaSource = buildMediaSource(
                newMediaItem,
                currentDataSourceFactory,
                applicationContext,
                false, 
                inferredFormat == FORMAT_HLS,
                false
            )
            
            currentMediaSource = newMediaSource
            
            // 重新加载
            exoPlayer?.stop()
            exoPlayer?.setMediaSource(newMediaSource)
            exoPlayer?.prepare()
            
            return true
        }
        
        return false
    }

    // 执行网络重试
    private fun performNetworkRetry() {
        retryCount++
        isCurrentlyRetrying = true
        
        // 修改：不再发送重试事件
        Log.d(TAG, "执行网络重试 $retryCount/$maxRetryCount")
        
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
            sendEvent(EVENT_BUFFERING_UPDATE) { event ->
                val range: List<Number?> = listOf(0, bufferedPosition)
                // iOS supports a list of buffered ranges, so here is a list with a single range.
                event["values"] = listOf(range)
            }
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
            sendEvent(EVENT_INITIALIZED) { event ->
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
            }
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
            sendEvent(if (inPip) EVENT_PIP_START else EVENT_PIP_STOP)
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
        currentMediaItem = null
        currentDataSourceFactory = null
        currentHeaders = null
        currentUserAgent = null
        
        // 11. 释放Cronet引擎引用（使用引用计数）
        if (isUsingCronet) {
            releaseCronetEngine()
            isUsingCronet = false
        }
        
        // 12. 清理事件池
        EventMapPool.clear()
        
        // 13. 重置Cronet失败标记
        hasCronetFailed = false
    }

    // 优化：统一的事件发送方法，使用对象池
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

    // 新增：自定义MediaCodecSelector实现
    private class CustomMediaCodecSelector(
        private val preferSoftwareDecoder: Boolean,
        private val formatHint: String? = null
    ) : MediaCodecSelector {
        
        override fun getDecoderInfos(
            mimeType: String,
            requiresSecureDecoder: Boolean,
            requiresTunnelingDecoder: Boolean
        ): List<MediaCodecInfo> {
            return try {
                // 获取所有可用的解码器
                val allDecoders = MediaCodecUtil.getDecoderInfos(
                    mimeType, requiresSecureDecoder, requiresTunnelingDecoder
                )
                
                // 如果没有找到解码器，返回空列表
                if (allDecoders.isEmpty()) {
                    Log.w(TAG, "没有找到支持 $mimeType 的解码器")
                    return emptyList()
                }
                
                // VP9/VP8格式特殊处理 - 许多硬件解码器不支持
                if (mimeType == MimeTypes.VIDEO_VP9 || mimeType == MimeTypes.VIDEO_VP8) {
                    Log.d(TAG, "检测到VP9/VP8格式，优先使用软解码")
                    return sortDecodersForVP9(allDecoders)
                }
                
                // 检测已知的问题格式
                if (formatHint == FORMAT_HLS && mimeType == MimeTypes.VIDEO_H265) {
                    // 某些设备的H.265硬解码对HLS支持不好
                    Log.d(TAG, "HLS+H.265组合，考虑使用软解码")
                    return sortDecodersSoftwareFirst(allDecoders)
                }
                
                // 根据用户配置排序
                val sortedDecoders = if (preferSoftwareDecoder) {
                    sortDecodersSoftwareFirst(allDecoders)
                } else {
                    sortDecodersHardwareFirst(allDecoders)
                }
                
                // 打印解码器选择信息
                if (sortedDecoders.isNotEmpty()) {
                    Log.d(TAG, "选择解码器: ${sortedDecoders[0].name} for $mimeType")
                }
                
                return sortedDecoders
            } catch (e: MediaCodecUtil.DecoderQueryException) {
                Log.e(TAG, "查询解码器失败: ${e.message}")
                emptyList()
            }
        }
        
        // VP9特殊排序：软解码优先
        private fun sortDecodersForVP9(decoders: List<MediaCodecInfo>): List<MediaCodecInfo> {
            return decoders.sortedWith(compareBy(
                // 软解码优先
                { !it.name.startsWith("OMX.google.") },
                // 然后按原始顺序
                { decoders.indexOf(it) }
            ))
        }
        
        // 软解码优先排序
        private fun sortDecodersSoftwareFirst(decoders: List<MediaCodecInfo>): List<MediaCodecInfo> {
            return decoders.sortedWith(compareBy(
                // 软解码（Google解码器）优先
                { !it.name.startsWith("OMX.google.") && !it.name.startsWith("c2.android.") },
                // 避免已知问题的解码器
                { isProblematicDecoder(it.name) },
                // 保持原始顺序
                { decoders.indexOf(it) }
            ))
        }
        
        // 硬解码优先排序
        private fun sortDecodersHardwareFirst(decoders: List<MediaCodecInfo>): List<MediaCodecInfo> {
            return decoders.sortedWith(compareBy(
                // 硬解码优先
                { it.name.startsWith("OMX.google.") || it.name.startsWith("c2.android.") },
                // 避免已知问题的解码器
                { isProblematicDecoder(it.name) },
                // 保持原始顺序
                { decoders.indexOf(it) }
            ))
        }
        
        // 检查是否是已知有问题的解码器
        private fun isProblematicDecoder(decoderName: String): Boolean {
            // 这里可以添加已知有问题的解码器黑名单
            val problematicDecoders = listOf(
                "OMX.MTK.VIDEO.DECODER.HEVC",  // 某些MTK芯片的HEVC解码器有问题
                "OMX.amlogic.avc.decoder.awesome"  // 某些Amlogic解码器不稳定
            )
            return problematicDecoders.any { decoderName.contains(it, ignoreCase = true) }
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
        
        // 新增：解码器配置常量
        const val AUTO = 0
        const val HARDWARE_FIRST = 1
        const val SOFTWARE_FIRST = 2
        
        // 事件名称常量
        private const val EVENT_INITIALIZED = "initialized"
        private const val EVENT_BUFFERING_UPDATE = "bufferingUpdate"
        private const val EVENT_BUFFERING_START = "bufferingStart"
        private const val EVENT_BUFFERING_END = "bufferingEnd"
        private const val EVENT_COMPLETED = "completed"
        private const val EVENT_RETRY = "retry"
        private const val EVENT_PIP_START = "pipStart"
        private const val EVENT_PIP_STOP = "pipStop"
        
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

// 优化：事件Map对象池，减少GC压力
private object EventMapPool {
    private const val MAX_POOL_SIZE = 10
    private val pool = ConcurrentLinkedQueue<MutableMap<String, Any?>>()
    
    fun acquire(): MutableMap<String, Any?> {
        return pool.poll() ?: HashMap()
    }
    
    fun release(map: MutableMap<String, Any?>) {
        if (pool.size < MAX_POOL_SIZE) {
            map.clear()
            pool.offer(map)
        }
    }
    
    fun clear() {
        pool.clear()
    }
}
