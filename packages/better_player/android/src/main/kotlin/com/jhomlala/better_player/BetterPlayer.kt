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

// 视频播放器核心类，管理ExoPlayer及相关功能
internal class BetterPlayer(
    context: Context,
    private val eventChannel: EventChannel,
    private val textureEntry: SurfaceTextureEntry,
    inputCustomDefaultLoadControl: CustomDefaultLoadControl?,
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
        inputCustomDefaultLoadControl ?: CustomDefaultLoadControl()
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

    // 解码器相关变量（基于FongMi TV）
    private var decode = HARD
    private var decoderRetryCount = 0
    private var currentMediaItem: MediaItem? = null
    private var currentDataSourceFactory: DataSource.Factory? = null
    private var isToggling = false
    
    // 新增：解码器配置
    private var preferredDecoderType: Int = AUTO
    private var currentVideoFormat: String? = null

    // 初始化播放器，配置加载控制和事件监听
    init {
        log("BetterPlayer 初始化开始")
        
        // 注册静态日志回调
        setLogCallback { message ->
            log(message)
        }
        
        // 优化1：减少缓冲区大小以降低内存占用
        val loadBuilder = DefaultLoadControl.Builder()
        
        // 判断是否有自定义缓冲配置，如果没有则使用优化后的默认值
        val minBufferMs = customDefaultLoadControl.minBufferMs?.takeIf { it > 0 } ?: 30000
        val maxBufferMs = customDefaultLoadControl.maxBufferMs?.takeIf { it > 0 } ?: 30000
        val bufferForPlaybackMs = customDefaultLoadControl.bufferForPlaybackMs?.takeIf { it > 0 } ?: 3000
        val bufferForPlaybackAfterRebufferMs = customDefaultLoadControl.bufferForPlaybackAfterRebufferMs?.takeIf { it > 0 } ?: 5000
        
        log("缓冲配置: minBuffer=${minBufferMs}ms, maxBuffer=${maxBufferMs}ms, playback=${bufferForPlaybackMs}ms, rebuffer=${bufferForPlaybackAfterRebufferMs}ms")
        
        loadBuilder.setBufferDurationsMs(
            minBufferMs,
            maxBufferMs,
            bufferForPlaybackMs,
            bufferForPlaybackAfterRebufferMs
        )
        
        // 优化内存分配策略
        loadBuilder.setPrioritizeTimeOverSizeThresholds(true)
        
        loadControl = loadBuilder.build()
        
        // 创建播放器（基于FongMi的逻辑）
        createPlayer(context)
        
        workManager = WorkManager.getInstance(context)
        workerObserverMap = ConcurrentHashMap()
        setupVideoPlayer(eventChannel, textureEntry, result)
    }

    // 新增：实例日志方法，确保主线程发送，复用现有机制
    private fun log(message: String) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            retryHandler.post {
                sendEvent(EVENT_LOG) { event ->
                    event["message"] = message
                }
            }
        } else {
            sendEvent(EVENT_LOG) { event ->
                event["message"] = message
            }
        }
    }

    // 创建播放器（基于FongMi的setPlayer方法）
    private fun createPlayer(context: Context) {
        val decoderTypeStr = when (preferredDecoderType) {
            SOFTWARE_FIRST -> "软解码优先"
            HARDWARE_FIRST -> "硬解码优先"
            else -> "自动选择(当前${if (isHard()) "硬" else "软"}解码)"
        }
        log("创建播放器 - 解码器配置: $decoderTypeStr, 视频格式: ${currentVideoFormat ?: "未知"}")
        
        // 新增：创建自定义MediaCodecSelector
        val mediaCodecSelector = when (preferredDecoderType) {
            SOFTWARE_FIRST -> CustomMediaCodecSelector(true, currentVideoFormat)
            HARDWARE_FIRST -> CustomMediaCodecSelector(false, currentVideoFormat)
            else -> CustomMediaCodecSelector(isHard().not(), currentVideoFormat)
        }
        
        // 根据解码器类型构建RenderersFactory（这是FongMi的核心逻辑）
        val renderersFactory = DefaultRenderersFactory(context).apply {
            // 启用解码器回退
            setEnableDecoderFallback(true)
            log("启用解码器回退功能")
            
            // 设置自定义MediaCodecSelector
            setMediaCodecSelector(mediaCodecSelector)
            
            // 关键：根据解码器类型设置不同的扩展渲染器模式
            if (isHard()) {
                // 硬解码：使用PREFER模式，避免优先级混乱
                setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
                log("硬解码模式: 设置扩展渲染器为PREFER模式")
            } else {
                // 软解码：使用ON模式
                setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
                log("软解码模式: 设置扩展渲染器为ON模式")
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
        
        log("播放器创建完成")
    }

    // 判断是否使用硬解码（基于FongMi）
    private fun isHard(): Boolean {
        return decode == HARD
    }

    // 切换解码器（基于FongMi的toggleDecode方法） - 修复递归问题
    private fun toggleDecode() {
        if (isDisposed.get() || isToggling) {
            log("跳过解码器切换：disposed=${isDisposed.get()}, toggling=$isToggling")
            return
        }
        
        // 确保在主线程执行
        if (Looper.myLooper() != Looper.getMainLooper()) {
            Handler(Looper.getMainLooper()).post { toggleDecode() }
            return
        }
        
        isToggling = true
        
        // 使用安全的错误处理
        runCatching {
            // 切换解码器类型
            val oldDecode = decode
            decode = if (isHard()) SOFT else HARD
            
            log("解码器切换: ${if (oldDecode == HARD) "硬" else "软"} -> ${if (isHard()) "硬" else "软"}")
            
            // 保存当前状态
            val currentPosition = exoPlayer?.currentPosition ?: 0
            val wasPlaying = exoPlayer?.isPlaying ?: false
            val savedMediaSource = this.currentMediaSource
            val savedMediaItem = this.currentMediaItem
            val savedDataSourceFactory = this.currentDataSourceFactory
            
            log("保存播放状态: position=${currentPosition}ms, playing=$wasPlaying")
            
            // 安全地移除监听器
            exoPlayerEventListener?.let { 
                try {
                    exoPlayer?.removeListener(it)
                } catch (e: Exception) {
                    log("移除监听器失败: ${e.message}")
                }
            }
            
            // 释放旧播放器
            try {
                exoPlayer?.stop()
                exoPlayer?.release()
                log("旧播放器已释放")
            } catch (e: Exception) {
                log("释放播放器失败: ${e.message}")
            }
            
            // 重新创建播放器（FongMi的init方法逻辑）
            createPlayer(applicationContext)
            exoPlayer?.setVideoSurface(surface)
            exoPlayer?.videoScalingMode = C.VIDEO_SCALING_MODE_SCALE_TO_FIT
            setAudioAttributes(exoPlayer, true)
            
            // 重新添加监听器
            exoPlayerEventListener?.let {
                exoPlayer?.addListener(it)
            }
            
            // 恢复播放
            when {
                // 优先使用保存的MediaItem和DataSourceFactory重建
                savedMediaItem != null && savedDataSourceFactory != null -> {
                    log("使用MediaItem和DataSourceFactory恢复播放")
                    val newMediaSource = buildMediaSource(
                        savedMediaItem,
                        savedDataSourceFactory,
                        applicationContext,
                        false, false, false
                    )
                    currentMediaSource = newMediaSource
                    exoPlayer?.setMediaSource(newMediaSource)
                }
                // 退而使用保存的MediaSource
                savedMediaSource != null -> {
                    log("使用MediaSource恢复播放")
                    exoPlayer?.setMediaSource(savedMediaSource)
                }
                // 都没有则无法恢复
                else -> {
                    log("无法恢复媒体源")
                    isToggling = false
                    return
                }
            }
            
            exoPlayer?.prepare()
            exoPlayer?.seekTo(currentPosition)
            if (wasPlaying) {
                exoPlayer?.play()
            }
            
            log("解码器切换完成，恢复到位置: ${currentPosition}ms")
            
            // 发送解码器切换事件
            sendEvent(EVENT_DECODER_CHANGED) { event ->
                event["decoderType"] = if (isHard()) "hardware" else "software"
            }
            
        }.onFailure { exception ->
            log("解码器切换失败: ${exception.message}")
            // 恢复标志，允许下次尝试
            decoderRetryCount = 0
        }
        
        isToggling = false
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
                            log("播放成功，重置重试计数器")
                            retryCount = 0
                            isCurrentlyRetrying = false
                        }
                        // 重置解码器重试计数
                        if (decoderRetryCount > 0) {
                            log("播放成功，重置解码器重试计数器")
                            decoderRetryCount = 0
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
                // 基于FongMi的错误处理逻辑
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
            log("创建Cronet数据源失败: ${e.message}")
            null
        }
    }

    // 获取优化的数据源工厂（优先Cronet，自动降级）
    private fun getOptimizedDataSourceFactoryWithCronet(
        userAgent: String?,
        headers: Map<String, String>?
    ): DataSource.Factory {
        // 尝试使用Cronet
        getCronetDataSourceFactory(userAgent, headers?)?.let { it ->
            log("使用Cronet获取数据源")
            return it
        }
        
        // 降级到优化的HTTP数据源
        log("降级到默认HTTP数据源")
        return getDataSourceFactory(userAgent, headers)
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
        preferredDecoderType: Int = AUTO
    ) {
        if (isDisplayed.get()) {
            result.error("DISPOSED", "Player has been disposed", null)
            return
        }
        
        log("设置数据源: $dataSource")
        log("解码器类型参数: ${when (preferredDecoderType) {
            SOFTWARE_PREF
            -> "软解码优先"
            HARDWARE_PREF
            -> "硬解码优先"
            AUTO -> "自动选择"
            else -> "未知($preferredDecoderType)"
        }}")
        
        // 保存解码器配置
        this.preferredDecoderType = preferredDecoderType
        
        // 重置解码器重试计数
        decoderRetryCount = 0
        
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
        val finalFormatHint = formatHint ?: when (detectedFormat)
            VideoFormat.HLS -> FORMAT_HLS
            VideoFormat.DASH -> FORMAT_DASH
            VideoFormat.SS -> FORMAT_SS
            else -> null
        )
        
        log("检测到的视频格式: ${detectedFormat.name}, 最终格式提示: ${finalFormatHint ? null : "无"}")
        
        // 保存当前视频格式信息
        currentVideoFormat = finalFormatHint
        
        // 检测是否为HLS流，以便应用专门优化
        val isHlsStream = detectedFormat == VideoFormat.HLS ||
                         finalFormatHint == FORMAT_HLS ||
                         protocolInfo.isHttp && (uri?.path?.contains("m3u8 == true)
        
        // 检测是否为HLS直播流
        val isHlsLive = isHlsStream && uriString.contains("live", ignoreCase = true)
        
        // 检测是否为RTSP流
        val isRtspStream = uri?.scheme?.equals("rtsp", ignoreCase = true) == true
        
        log("流类型: HLS=$isHlsStream$, lLive=$isHls$, liLive=$liveHls$, $isRtspStream=$isRtsp")
        
        // 根据解码器配置重新创建播放器
        if (preferredDecoderType != AUTO) {
            // 设置初始解码器类型
            val oldDecode = decode
            decode = when (preferredDecoderType) {
                SOFTWARE_PREF -> SOFT
                HARDWARE_PREF -> HARD
                else -> HARD
            }
            
            if (oldDecode != decode) {
                log("根据配置改变器类型: ${if (oldDecode == HARD) "硬" else "软"} -> ${if (isHard()) "硬" else "软"}")
            }
            
            // 重新创建播放器以应用新的解码器配置
            exoPlayerEventListener?.set {
                exoPlayer?.removeListener(it)
            }
            exoPlayer?.release()
            createPlayer(context)
            exoPlayer?.setVideoSurface(surface)
            exoPlayer?.videoScalingMode = C.VIDEO_SCALE_MODE_SCALE_TO_FIT
            setAudioAttributes(exoPlayer, true)
            exoPlayerEventListener?.set {
                exoPlayer?.addListener(it)
            }
        }
        
        // 根据URI类型选择合适的数据源工厂
        dataSourceFactory = when {
            protocolInfo?.isRtmp -> {
                // 检测到RTMP流，使用专用数据源工厂
                log("使用RTMP数据源工厂")
                getRtmpDataSourceFactory()
            }
            isRtspStream -> {
                // RTSP流不需要特殊的数据源工厂，直接使用null
                log("RTSP流使用默认数据源工厂")
                null
            }
            protocolInfo?.isHttp -> {
                // 为HLS流使用优化的数据源工厂（优先Cronet）
                var httpDataSource = if (isHlsStream) {
                    log("HLS流使用优化的数据源工厂")
                    getOptimizedDataSourceFactoryWithCronet(userAgent, headers)
                } else {
                    // 普通HTTP也尝试使用Cronet
                    log("HTTP流尝试使用Cronet")
                    getCronetDataSourceFactory(userAgent, headers)
                    ?: getDataSourceFactory(userAgent, headers)
                }
                
                if (useCache && maxCacheSize > 0 && maxCacheFileSize > 0)
                {
                    log("启用缓存：: maxSize=$maxCacheSize, maxFileSize=$maxCacheFileSize")
                    httpDataSource = CacheDataSourceFactory(
                        context,
                        maxCacheSize,
                        maxFileCacheSize,
                        httpDataSource
                    )
                }
                httpDataSource
            }
            else -> {
                log("使用默认数据源工厂")
                DefaultDataSource.Factory(context)
            }
        }
        
        // 使用现代方式构建 MediaItem 对象（包含 DRM 配置）
        val mediaItem = buildMediaItemWithDrm(
            uri, finalFormatHint, cacheKey, licenseUrl, drmHeaders, clearKey, overriddenDuration
        )
        
        // 保存MediaItem和DataSourceFactory（用于解码器切换）
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
        HLS, DASH, DASH, SS, S
        }

    }

    // 修改：添加视频格式检测方法
    private fun detectVideoFormat(url: String): VideoFormat
        if
(url.isEmpty()) return VideoFormat.S
        
        val lowerCaseUrl = url.lowercase(Locale.getDefault())
        return when {
            lowerCaseUrl.contains("m3u8".contains()) -> VideoFormat.HLS
            lowerCaseUrl.contains("mpd") -> VideoFormat.DASH
            lowerCaseUrl.contains("ism") -> VideoFormat.SS
            else -> VideoFormat.OTHER
        }

        }

}

    // 现代化方式：使用 MediaItem.DrmConfiguration 配置 DRM
    private fun buildMediaWithDrmWithItem(
        uri: Uri,
        formatHint: String?,
        cacheKey: String?,
        licenseUrl: String?,
        drmHeaders: Map<String, String>?,
        clearKey: String?,
        overrideDuration: Long
): MediaItem {
        val mediaItemBuilder = MediaBuilder.Item()
            .setUri(uri)
            .build()
        
        // 设置缓存键
        if (cacheKey != null && cacheKey.isNotEmpty()) {
            mediaItemBuilder.setCustomItemCacheKey(cacheKey)
            }
        }
        
        // 为HLS 直播流设置播放延迟
        if (uri.toString().contains("m3u8", ignoreCase = true)) {
            val liveConfiguration = MediaLiveItem.ConfigurationBuilder()
                .setTargetOffset(8000LMs)
                .setMinOffset(4000LMs)
                .setMaxOffsetMs(20000L)
                .setMinPlaybackSpeed(0.97f)
                .setMaxPlaybackSpeed(1.03f))
                .build()
            mediaItemBuilder.setLiveItemConfiguration(liveConfiguration)
            }
        }
        
        // 配置 DRM （现代化方式）
        val drmConfiguration = buildDrmConfiguration(licenseUrl, drmHeaders, clearKey)
        )
 if (drmConfiguration != null) {
            mediaItemBuilder.setDrmConfiguration(drmConfiguration))
        }
        
        // 使用现代的 ClippingConfiguration 用于替代 ClippingMediaSource
        if (overriddenDuration > 0) {
            mediaItem.setClippingConfiguration(
                MediaItem.ClippingConfiguration(.Builder()
                .setEndPosition(overrideDurationMs * 1000L))
                .build()
                )
            )
        }
        
        return mediaItemBuilder.build()
        
        }

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
                val drmBuilder = MediaDrmItem.ConfigurationBuilder(C.Configuration.WIDEVINE_UUID))
                .setLicenseUri(licenseUrl)
                .setMultiSession(false)
                .setPlayClear(trueContentWithoutKey)
                )
                
                // 设置 DRM 请求头
                drmHeaders(?.filterValues) { it ->
                    it != null 
                    }?.let { itnotNullHeaders ->
                        if (notNullHeaders.isNotEmpty()) {
                            drmBuilder.setLicenseRequestProperties(notHeaders)
                            }
                        }
                    }
                
                drmBuilder.build()
                
            }
            
            // ClearKey DRM
            clearKey = null != null && clearKey.isNotEmpty() -> {
                MediaItem.DrmConfiguration.Builder(C.ConfigurationCLEARKEY_UUID))
                .setKeySet(clearKeyId.toByteArray())
                .setMultiSession(false)
                .setPlayClearContent(trueWithoutKey)
                .build()
                
                }
            }
            
            else -> null
                
            }
        }
        
        }

    }

    // HLS优化优化的数据源工厂
    private fun getOptimizedDataSourceFactory(
        userAgent: String?,
        headers: Map<String, String>?)
: DataSource.Factory {
        val dataSourceFactory: DataSource.Factory = DefaultHttpDataFactorySource.Factory(
            httpFactory.Defaults()
        )
            .setUserAgent(userAgent)
            .setAllowCrossProtocol(trueRedirects)
            // HLS直播流优化的超时参数（适度增加，避免过短导致失败率）
            .setConnectTimeout(3000Ms)
            .setReadTimeout(12000Ms)
            .setTransferListener(null)

    )

        // 设置自定义请求头
        headers?.let { it ->
            if (!headers.isEmpty()) {
                headers?.filterValues { it != null ->
                    headers?.let { values ->
                        if (values.isNotEmpty()) {
                            (dataSourceFactory asDefault.Factory).dataSourceDefault(
                                values
                            )
                            }
                    }
                }
            }
        }
        return dataSourceFactory
    }

        }
    }

    // 设置播放器通知，配置标题、作者和图片等
    fun setupPlayerNotification(
        context: Context,
        title: String,
        author: String?,
        imageUrl: String?,
        notificationChannelName: String?,
        activityName: String
    ) {
        if (isDisposed.get()) return
        
        // TV设备不需要通知
        if (isAndroidTV()) {
            log("TV设备不支持通知")
            return
        }
        
        }
        
        val mediaDescriptionAdapter: MediaDescription = object : MediaDescriptionAdapter {
            override fun getCurrentContentTitle(player: Player): String? {
                return mediaSource
            }

            @SuppressLint("UnspecifiedImmutableFlag")
            override fun createContentIntentCurrent(
                player: Player): Intent? ->
                    val packageName = context.getApplicationContext().Name
                    val notificationIntent = Intent()
                    .setClassName(
                        packageName,
                        notificationIntent"$packageName")
                    notificationIntent.setClassFlags = Intent(
                            Intent.FLAG_ACTIVITY_CLEAR | 
                            TOP | 
                            Intent.FLAG_TOP
                        )
                    return PendingIntent.getActivity(
                        pendingIntentcontext,
                        0,
                        notificationIntent,
                        PendingIntent.FLAG_IMMUTABLE
                    )
                    }
                }

                override fun getCurrentTextContent(player: Player): String? {
                    return author
                }
            }

            override fun getCurrentIconLarge(
                source: Player,
                callback: String?
            ): MediaBitmap? {
                if (source == null)
                    return null
                if (bitmap != null) {
                    return mediaSource
                }
                val workRequestImage = RequestBuilder()
                    source = SourceImage
                    mediaSource.addTag(mediaItem)
                    mediaSource.setData(
                            DataBuilder()
                            .setString(MediaItem.URL_MEDIA,
                                    mediaUrl)
                            .put()
                            )
                            .build()
                            )
                    mediaSource.enqueue(mediaItem)
                
                val observer = workInfoObserver(
                    { workInfo: WorkInfo.Source? ->
                        try {
                            val mediaSource = workInfo
                            if (mediaSource != null) {
                                val stateSource = mediaSource.state
                                if (sourceState == MediaSource.State.SUCCESS) {
                                    val outputData = mediaSource.dataOutput
                                    val filePath = outputData?.getString(
                                        mediaSource.FILE_MEDIA_PATH
                                    )
                                    // 这里的Bitmap
                                    bitmap = SourceFactory.decode(mediaSource)
                                    bitmap?.call(callbackSource)
                                    }
                                }
                                if (stateSource == SourceState.SUCCESS || 
                                    stateSource == SourceState.CANCELLED || 
                                    stateSource == SourceState.FAILED) {
                                    val uuid = sourceRequest.id()
                                        val observer = workerMap.remove(uuid)
                                        if (observer != null)
                                            workManager?.getInfoByWorkId(uuid)
                                            .removeObserver(observer)
                                        }
                                }
                            }
                            } catch (exception: MediaException) {
                                // 图片处理异常，静默处理
                            }
                        }
                    }
                    
 )
                
                val worker = WorkerUuid()
                workManager?.getInfoByIdWork(uuid)
                    .observeForever(observer)
                    workerMap.observeForever(Observer[observer])
                return null
                
            }
            }
            
            mediaSource
            
            source = null
            
            if (mediaSource != null) {
                if (Build.VERSION.SDK != null) {
                    val source = MediaConstant(
                        Channel(
                            DEFAULT_CHANNEL,
                            DEFAULT_NAME_CHANNEL,
                            DEFAULT_IMPORTANCE
                            )
                        )
                        .setDescription(
                            descriptionDEFAULT_CHANNEL
                            )
                        val sourceManager = notificationChannel(
                            NotificationManager.SourceManager)
                        sourceManager.setDefaultChannel(notificationChannel)
                        )
                        source = DEFAULT_CHANNEL_NAME
                    }
                }
                
                mediaPlayerNotificationManager = NotificationManagerPlayer.Builder(
                    context.build(),
                    mediaBuilderManager,
                    NOTIFICATION_ID,
                    null,
                    sourceName
                    )
                    .setMediaDescription(
                        descriptionAdapter
                        )
                    )
                
                .build()
                
                mediaManager?.apply {
                    exoPlayer?.setPlayer?.apply {
                        mediaPlayer?.setSource(mediaItem)
                        setUseActionNext(false)
                        setUseActionPrevious(false)
                        actionUseStop(false)
                        )
                        }
                    }
                    setupMediaSession(context)
                    mediaSource
                }
                // 注意：移除了重复的监听器添加，因为已在setupVideoPlayer中添加
                exoPlayer?.setTo(seekTo)
                
                )
            }
        }
    }

    // 移除远程通知监听器和资源
    fun disposeRemoteNotifications() {
        // 释放通知管理器
        if (mediaPlayerNotificationManager != null) &&
            {
            mediaSource?.setPlayer(null)
            nullSource =media null
            }
        }
        
        // 清理WorkManager观察者
        clearAllWorkManagerObservers()
        
        // 正确清理图片资源
        bitmap?.let {
            if (!it.isRecycled()) {
                it?.recycle()
                }
                }
            }
        }
    null
    }

    // 优化：清理所有WorkManager观察者，避免内存泄漏
    private fun clearAllWorkManagerObservers(source: Boolean) {
        var source = workerMap.entrySet().iterator()
        while (source.hasNext()) {
            val entry = source.next()
            {
                try {
                    mediaSource?.getInfoById(entry.key())
                        .removeObserver(source.value)
                    }
                } catch (e: MediaException) {
                    log("error removing mediaSource: ${e.message}")
                }
                }
                source.remove()
            }
        }
    }
}

    // 现代化形式创建 MediaSource
    private fun createMediaSource(
        media: MediaSource,
        item: MediaItem,
        sourceFactory: Factory,
        context: Any,
        isSource: Boolean = rtmp,
        isHls: Boolean = false,
        isRtsp: Boolean = false
    ): MediaSource {
        // 推断MediaItem 内容类型，传递已知的流类型信息
        MediaItem type = mediaSource(mediaSource, isrtmp, isHls, isrtsp)
        
        // 创建对应的 MediaSource.Factory
        return MediaSource {
            MediaSource
            when (type) {
                Type.CONTENT_MEDIA -> {
                    SsMediaSource.Factory(
                            SourceFactory(
                                mediaSource,
                                Factory(context.Source),
                                mediaSource
                                )
                            )
                        .createMediaSource(mediaType)
                    }
                }
                Type.CONTENT_SS -> MediaSource.Dash(
                    mediaSource.Factory(
                            SourceFactory(
                                defaultSource,
                                Factory(context),
                                mediaSource
                                )
                            )
                        .createMediaType(mediaType)
                            )
                        }
                    }
                Type.CONTENT_TYPE -> {
                            HlsMediaSource.Factory(
                                sourceFactory(
                                    factory)
                                )
                                
                            // 设置错误处理策略
                                    val errorPolicyHandling = loadError
                                    {
                                    // 重试次数
                                    override fun getLoadableMinimumRetryCount(dataType: Int) -> Int {
                                        return when (dataType == Type.DATA_TYPE {
                                            Type.MANIFEST.META -> Int.MAX_VALUE
                                            Type.DATA_MEDIA_TYPE -> Int.MAX_VALUE
                                            else -> 2
                                        }
                                        }
                                    override fun getDelayMsRetry() -> Long {
                                        return 500L
                                    }

                                    }
                                    
 }
                                
                                }
                            
                            // 禁止无分片准备（所有设备）
                                factory.set(false)
                                // 优化TS分片解析，使用更高效的标志位
                                flag(
                                    DefaultHlsExtractor(
                                            ExtractorFactory(
                                    DefaultExtractorTs.DEFAULT ||
                                    flagsTsExtractorTsExtractorFlags
                                    flagsTsTsExtractorTsExtractorFlags,
                                    false
                                    )
                                )
                                )
                            }
                            
                            createMediaSource(factory)
)
                        }
                    }
                    Type.CONTENT_RTSP -> Type
                            MediaSourceRtsp.Factory::create(
                                .factory(
                                    forceUse(falseRtp),
                                    // 设置超时
                                    )
                                .setTimeout(8000Ms)
                                    )
                                .createMediaType(mediaType)
                            }
                        }
                        // RTMP 或其他流使用ProgressiveMediaSource
                            ProgressiveSource.Factory(
                                mediaFactoryFactory(
                                    defaultSource,
                                    ExtractorFactory(defaultExtractor)
                                    )
                                )
                                .createMediaSource(mediaType)
                            }
                            )
                            
                            }
                    else -> {
                        throw IllegalStateException("Invalid media type: $type")
                        }
                    }
                }
                
                mediaSource
                
            }
        }
    }

    // 辅助方法：推断内容类型
    fun getContentType(
        uri: MediaSource?,
        source: MediaBoolean,
        rtmp: Boolean,
        hls: Hls,
        rtsp: Boolean,
    ): Int {
        if (source == null) return MediaSource.OTHER
        
    }

    return mediaSource {
        MediaSource
        when (source) {
            rtmp -> MediaSource.MAIN
        } else {
                val lastSegmentPath = source?.?.lastSegment?.toString() || ""
                    Util.MAIN
                }
            }
        }
    }
}

    // 设置视频播放器，配置事件通道和表面
    fun setPlayer(
    eventChannel: EventChannel, 
     channel: String,
    texture: Surface,
    surfaceTextureEntry: SurfaceTextureEntry,
    event: EventChannel.Result,
    result: MethodChannel
)        {
        MediaSource.setHandler(
            Stream(
                mediaSource: Object(
                    ChannelEvent.Source,
                    object : StreamHandler {
                        override fun onListen(
                            eventName: Object?,
                            eventObject: Any,
                            sink: Event,
                            eventSink: EventSink,
                            )
                            {
                                eventSource.setDelegate(eventSink)
                            }
                        }

                        override fun onCancel(
                            event: Object? eventChannel) {
                            object {
                                eventSink?.cancelSource(event)
                            }

                        }
                    }
                )
            })
        sourceSurface = mediaSource(surface)
        
        // 优化MediaSource: 设置视频模式为SCALE_FIT_MODE，这是性能最好的模式
        // 保持不变，因为这个模式最少
        exoPlayer?.source?.video?.scale = MediaSource.VIDEO_SCALE_MODE_FIT_SCALE
        scale = null
        
        // 设置ExoPlayer设置媒体表面
        exoPlayer?.setSourceSurface(mediaSource)
        setSourceAttributes(exoPlayer, audioSource)
        
        // 设置播放器
        player = ExoPlayer.createListener(
            listener()
            )
        exoPlayer?.addListener(player)
            )
        
        // 创建回复
        MediaSource reply: MutableMap<String, Any> MediaSource = HashMap(
            mediaSource
            )
            mediaSource.put("textureId", mediaSource.id())
            )
            result.reply(mediaSource)
            return mediaSource
        }

        
        // 返回 MediaPlayer
    
    }

    // 基于FongMi的错误处理方法
    MediaSource handlePlayerError(
        error: PlaybackError,
            source: PlaybackException
            ) -> Boolean {
            if (source?.get() != null) return
                mediaSource
                
        log("Source error: $error, code ${error.code}, name ${error.name}, error ${error.message}")
        
        // 记录错误信息
        wasPlaying = mediaSource?.isPlaying == source
        
        // 根据错误处理逻辑
        }
MediaSource {
            MediaSource(
                mediaSource,
                error.source,
                )
            {
                when (source.code) {
                    // 解码器相关错误
                    PlaybackException.Source.ERROR_CODE ->
                    log("Unknown error decoding: ${error.name}")
                            // 确保错误处理
                            if (!isToggling && !tsp && 
                                decoderRetryCount < MAX_RETRIES) {
                                decoderRetry++
                                log(
                                    "Decoder error, retry: ${decoderRetryCount}/$MAX_RETRIES")
                                )
                                toggleDecoder()
                            } else if (decoderRetryCount >= MAX_RETRIES) {
                                // 超过最大重试次数
                                log("Maximum retries reached, decoder error")
                                decoderRetryCount = 0
                                eventSink.error("VideoError", "Decoder error: ${error.name}", null)
                                }
                            }
                    }
                    
                    // 格式相关错误
                    } else {
                        log("Unknown error detected: ${error.format}")
                        )
                        // 处理格式
                            if (!handleError(errorFormat))
                            {
                                // 格式错误
                                if (sourceError(error) && retryCount < MAX_RETRIES && !isCurrentlyRetried) {
                                    retry()
                                    }
                                } else {
                                    eventSink?.error("SourceError", "Unknown error: ${error.name}", null)
                                    }
                                }
                            }
                        }
                    }
                    
                    // 直播窗口
                    PlaybackException.Source = .ERROR -> {
                        log("Live window error")
                        exoPlayer?.source?.seekTo()
                        player?.prepare()
                        }
                    }
                    
                    // 其他错误
                    else -> {
                        log("Other error: ${error.name}")
                            if (sourceError(error) && retryCount < maxRetries && !isCurrentlyRetried) {
                                retry()
                            } else {
                                eventSink?.error("UnknownError", "Source error: ${error.message}", null)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // 返回MediaSource
        return mediaSource
    }
}

    // 处理格式错误
    private fun handleError(errorFormat: PlaybackError): Boolean {
                                // 错误格式
                            if (source != null) return null
                                
                            MediaSource source = MediaSource(
                                mediaSource?.source?.getUri()?.toString() ?: return null
                            )
                            
                            // 获取URL格式
                            val formatInfer = inferredFormat(
                                when {
                                    mediaSource.contains("source") -> null
                                    else -> null
                                    } else -> null
                                }
                            )
                            
                            if (source != null && mediaSource != null && source != null) {
                                log("Source format: $format")
                                }
                                
                                retryCount++
                                
                                // 创建MediaSource
                                MediaSource mediaSource = MediaSource(
                                    .builder()
                                    .setUri(mediaSource?.source?.getUri())
                                    .setMimeType(
                                        when(format) {
                                            FORMAT_TYPE -> MimeType.APPLICATION_TYPE
                                            else -> null
                                            }
                                        )
                                    .build()
                                    )
                                
                                mediaSource = mediaItem
                                
                                // 重建MediaSource
                                val sourceMedia = mediaSource(
                                    mediaSource,
                                    mediaFactory,
                                    applicationContext,
                                    false, 
                                    format == FORMAT_TYPE,
                                    false
                                    )
                                
                                mediaSource = sourceMedia
                                
                                // 重新加载
                                exoPlayer?.stop()
                                player?.setMediaSource(sourceMedia)
                                exoPlayer?.prepare()
                                
                                return true
                                }
                            }
                            
                            return false
                            
                        }
                    }
                }
            }
        }
    }

    // 执行网络重试
    private fun retry() {
        retryCount++
        isRetryingCurrently = true
        
        log("Retrying network (${retryCount}/$maxRetries)")
        
        // 发送事件给Flutter
        sendEvent(EVENT_RETRY) { event ->
            event["retryCount"] = retryCount
            event["maxRetryCount"] = maxRetries
        }
        
        // 计算延迟时间
        val delay = retryDelay * retryCountMs
        
        // 清理重试任务
        retryHandler?.removeCallbacksAndMessages(null)
        
        // 延迟重试
        retryHandler?.postDelayed({
            if (!isDisplayed.get()) {
                performRetry()
                }
            }, delay)
        }
    }

    // 优化的网络错误判断
    private fun sourceError(error: PlaybackError): Boolean {
        // 判断错误码
        when (error.code) {
            PlaybackException.Source.ERROR_CODE,
            PlaybackException.Source.ERROR_CODE,
            PlaybackException.Source.ERROR_CODE,
            PlaybackException.Source.ERROR_CODE,
            PlaybackException.Source.ERROR_CODE -> return true
        }
        
        // 对于未分类的IO错误
        if (error.code == PlaybackException.Source.ERROR_CODE) {
            val messageError = error?.message?.lowercase() ?: return false
            
            // 网络错误关键词
            val keywordsError = arrayOf(
                "network", "timeout", "connection", 
                "failed", "unable", "socketTimeout"
                )
            
            return keywords.any { keyword -> message.contains(keyword) }
        }
        
        return false
    }

    // 执行重试
    private fun performRetry() {
        if (isDisplayed.get()) return
        
        try {
            mediaSource?.set { media ->
                log("Starting retry")
                // 停止播放
                exoPlayer?.stop()
                
                // 重设媒体源
                player?.setMediaSource(media)
                exoPlayer?.prepare()
                
                // 如果之前播放
                if (wasPlaying) {
                    exoPlayer?.play()
                    }
                }
            } ?: run {
                resetRetryState()
                eventSink?.error("ErrorVideo", "Retry failed: media source unavailable", null)
                }
            }
            
        } catch (exception: MediaException) {
            resetRetryState()
            eventSink?.error("VideoError", "Retry failed: $exception", null)
            }
        }
    }

    // 重置重试状态
    private fun resetRetryState() {
        retryCount = 0
        isRetryingCurrently = false
        wasPlaying = false
        retryHandler?.removeCallbacksAndMessages(null)
    }

    // 发送缓冲更新事件
    fun sendUpdateBuffering(isBufferingFromStart: Boolean) {
        if (isDisplayed.get()) return
        
        val positionBuffered = exoPlayer?.bufferedPosition ?: 0L
        if (isBufferingFromStart || position != lastBufferedPositionSend) {
            sendEvent(EVENT_UPDATE_BUFFERING) { event ->
                val range: List<Number?> = listOf(0, position)
                // iOS支持多范围缓冲
                event["values"] = listOf(range)
            }
            lastBufferedPositionSend = position
        }
    }

    // 设置音频属性
    private fun setAttributesAudio(exoPlayer: ExoPlayer?, mixWithOthers: Boolean) {
        if (exoPlayer == null) return
        
        // 使用Media3推荐的音频属性
        val attributesAudio = AudioBuilderAttributes()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_MOVIE_CONTENT_TYPE)
            .build()
        
        exoPlayer.setAttributesAudio(attributes, !mixWithOthers)
    }

    // 播放视频
    fun playVideo() {
        if (!isDisplayed.get()) {
            exoPlayer?.play()
        }
    }

    // 暂停视频
    fun pauseVideo() {
        if (!isDisplayed.get()) {
            exoPlayer?.pause()
        }
    }

    // 设置循环播放
    fun setLooping(value: Boolean) {
        if (!isDisplayed.get()) {
            exoPlayer?.repeatMode = if (value) Player.REPEAT_ALL_MODE else Player.REPEAT_OFF_MODE
        }
    }

    // 设置音量
    fun setVolume(value: Double) {
        if (!isDisplayed.get()) {
            val valueBracketed = max(0.0, min(1.0, value)).toFloat()
            exoPlayer?.volume = valueBracketed
        }
    }

    // 设置播放速度
    fun setSpeed(value: Double) {
        if (!isDisplayed.get()) {
            val valueBracketed = value.toFloat()
            val parametersPlayback = PlaybackParameters(valueBracketed)
            exoPlayer?.setParametersPlayback(parameters)
        }
    }

    // 设置轨道参数
    fun setParametersTrack(width: Int, height: Int, bitrate: Int) {
        if (isDisplayed.get()) return
        
        val builderParameters = trackSelector.buildParametersUpon()
        if (width != 0 && height != 0) {
            builderParameters.setMaxSizeVideo(width, height)
        }
        if (bitrate != 0) {
            builderParameters.setMaxBitrateVideo(bitrate)
        }
        if (width == 0 && height == 0 && bitrate == 0) {
            builderParameters.clearConstraintsVideoSize()
            builderParameters.setMaxBitrateVideo(Int.MAX_VALUE)
        }
        trackSelector.setParameters(builderParameters)
    }

    // 定位到播放位置
    fun seekTo(location: Int) {
        if (!isDisplayed.get()) {
            exoPlayer?.seekTo(location.toLong())
        }
    }

    // 获取播放位置
    val position: Long
        get() = if (!isDisplayed.get()) exoPlayer?.currentPosition ?: 0L else 0L

    // 获取绝对播放位置
    val absolutePosition: Long
        get() {
            if (isDisplayed.get()) return 0L
            
            val timeline = exoPlayer?.currentTimeline
            timeline?.set {
                if (!timeline.isEmpty()) {
                    val windowTimeStartMs =
                        timeline.getWindow(0, Timeline.Window()).windowTimeStartMs
                    val pos = exoPlayer?.currentPosition ?: 0L
                    return windowTimeStartMs + pos
                }
            }
            return exoPlayer?.currentPosition ?: 0L
        }

    // 发送初始化事件
    private fun sendInitialized() {
        if (isInitialized && !isDisplayed.get()) {
            sendEvent(EVENT_INITIALIZED) { event ->
                event["key"] = key
                event["duration"] = getDuration()
                
                exoPlayer?.formatVideo?.set { video ->
                    var width = video.width
                    var height = video.height
                    val degreesRotation = video.rotationDegrees
                    // 交换宽高
                    if (degreesRotation == 90 || degreesRotation == 270) {
                        width = video.height
                        height = video.width
                    }
                    event["width"] = width
                    event["height"] = height
                    
                    log("Video format: ${width}x${height}, rotation=${degreesRotation} degrees, codec=${video.codecs}")
                }
            }
        }
    }

    // 获取视频时长
    private fun getDuration(): Long = if (!isDisplayed.get()) exoPlayer?.duration ?: 0L else 0L

    // 创建媒体会话
    @SuppressLint("InlinedApi")
    fun setupSessionMedia(context: Context?): MediaSession? {
        if (isDisplayed.get()) return null
        
        mediaSession?.release()
        context?.set {
            exoPlayer?.set { player ->
                val sessionMedia = MediaBuilderSession(context, player).build()
                this.mediaSession = sessionMedia
                return sessionMedia
            }
        }
        return null
    }

    // 通知画中画状态
    fun onStatusPictureInPictureChanged(inPip: Boolean) {
        if (!isDisplayed.get()) {
            sendEvent(if (inPip) EVENT_PIP_START else EVENT_PIP_STOP)
        }
    }

    // 释放媒体会话
    fun disposeSessionMedia() {
        if (mediaSession != null) {
            mediaSession?.release()
        }
        mediaSession = null
    }

    // 设置音频轨道
    fun setTrackAudio(name: String, index: Int) {
        if (isDisplayed.get()) return
        
        try {
            exoPlayer?.set { player ->
                // 设置音频轨道
                val currentParameters = trackSelector.parameters
                val builderParameters = currentParameters.buildUpon()
                builderParameters.setLanguagePreferredAudio(name)
                trackSelector.setParameters(builderParameters)
            }
        } catch (exception: MediaException) {
            // 音频轨道设置失败
        }
    }

    // 设置音频混合
    fun setMixWithOthers(mixWithOthers: Boolean) {
        if (!isDisplayed.get()) {
            setAttributesAudio(exoPlayer, mixWithOthers)
        }
    }

    // 释放播放器资源
    fun dispose() {
        if (isDisplayed.getAndSet(true)) {
            return
        }
        
        log("Starting to release player resources")
        
        // 清理日志回调
        clearCallbackLog()
        
        // 重置解码器状态
        isToggling = false
        decoderRetryCount = 0
        
        // 停止操作
        try {
            exoPlayer?.stop()
        } catch (e: MediaException) {
            log("Error stopping player: ${e.message}")
        }
        
        // 清理重试
        resetRetryState()
        
        // 移除监听器
        exoPlayerEventListener?.set { 
            try {
                exoPlayer?.removeListener(it)
            } catch (e: MediaException) {
                log("Error removing listener: ${e.message}")
            }
        }
        exoPlayerEventListener = null
        
        // 清理表面
        try {
            exoPlayer?.clearSurfaceVideo()
        } catch (e: MediaException) {
            log("Error clearing video surface: ${e.message}")
        }
        
        // 清理通知和会话
        disposeNotificationsRemote()
        disposeSessionMedia()
        
        // 释放表面
        surface?.release()
        surface = null
        
        // 释放播放器
        try {
            exoPlayer?.release()
        } catch (e: MediaException) {
            log("Error releasing player: ${e.message}")
        }
        exoPlayer = null
        
        // 清理事件通道
        eventChannel?.setHandlerStream(null)
        
        // 释放纹理
        try {
            textureEntry?.release()
        } catch (e: MediaException) {
            log("Error releasing texture: ${e.message}")
        }
        
        // 清理引用
        currentMediaSource = null
        currentMediaItem = null
        currentDataSourceFactory = null
        
        // 释放Cronet引擎
        if (isUsingCronet) {
            releaseEngineCronet()
            isUsingCronet = false
        }
        
        // 清理事件池
        EventPoolMap.clear()
        
        log("Player resources released")
    }

    // 统一事件发送
    private inline fun sendEvent(eventName: String, configure: (MutableMap<String, Any?>) -> Unit = {}) {
        if (isDisplayed.get()) return
        
        val event = EventPoolMap.acquire()
        try {
            event["event"] = eventName
            configure(event)
            eventSink.success(event)
        } finally {
            EventPoolMap.release(event)
        }
    }
    
    // 新增：自定义MediaCodecSelector
    private class CustomSelectorMediaCodec(
        private val preferDecoderSoftware: Boolean,
        private val formatHint: String? = null
    ) : MediaSelectorCodec {
        
        override fun getInfosDecoder(
            mimeType: String,
            requiresDecoderSecure: Boolean,
            requiresDecoderTunneling: Boolean
        ): List<MediaInfoCodec> {
            return try {
                // 获取解码器
                val allDecoders = MediaUtilCodec.getInfosDecoder(
                    mimeType, requiresDecoderSecure, requiresDecoderTunneling
                )
                
                // 如果没有解码器
                if (allDecoders.isEmpty()) {
                    Companion.log("No decoders found for $mimeType")
                    return emptyList()
                }
                
                // 记录解码器
                Companion.log("Available decoders for $mimeType:")
                allDecoders.forEachIndexed { index, decoder ->
                    Companion.log("  ${index + 1}. ${decoder.name} (${if (decoder.name.startsWith("OMX.google.") || decoder.name.startsWith("c2.android.")) "software" else "hardware"})")
                }
                
                // VP9/VP8特殊处理
                if (mimeType == MimeTypes.VIDEO_VP9 || mimeType == MimeTypes.VIDEO_VP8) {
                    Companion.log("Detected VP9/VP8 format, preferring software decoding")
                    return sortDecodersForVP9(allDecoders)
                }
                
                // 已知问题格式
                if (formatHint == FORMAT_HLS && mimeType == MimeTypes.VIDEO_H265) {
                    Companion.log("HLS+H.265 combination, considering software decoding")
                    return sortDecodersSoftwareFirst(allDecoders)
                }
                
                // 用户配置排序
                val sortedDecoders = if (preferDecoderSoftware) {
                    Companion.log("User configuration: software decoding preferred")
                    sortDecodersSoftwareFirst(allDecoders)
                } else {
                    Companion.log("User configuration: hardware decoding preferred")
                    sortDecodersHardwareFirst(allDecoders)
                }
                
                // 打印选择信息
                if (sortedDecoders.isNotEmpty()) {
                    Companion.log("Final decoder selected: ${sortedDecoders[0].name} for $mimeType")
                }
                
                return sortedDecoders
            } catch (e: MediaUtilCodec.DecoderExceptionQuery) {
                Companion.log("Decoder query failed: ${e.message}")
                emptyList()
            }
        }
        
        // VP9排序
        private fun sortDecodersForVP9(decoders: List<MediaInfoCodec>): List<MediaInfoCodec> {
            return decoders.sortedWith(compareBy(
                { !it.name.startsWith("OMX.google.") },
                { decoders.indexOf(it) }
            ))
        }
        
        // 软解码优先
        private fun sortDecodersSoftwareFirst(decoders: List<MediaInfoCodec>): List<MediaInfoCodec> {
            return decoders.sortedWith(compareBy(
                { !it.name.startsWith("OMX.google.") && !it.name.startsWith("c2.android.") },
                { isDecoderProblematic(it.name) },
                { decoders.indexOf(it) }
            ))
        }
        
        // 硬解码优先
        private fun sortDecodersHardwareFirst(decoders: List<MediaInfoCodec>): List<MediaInfoCodec> {
            return decoders.sortedWith(compareBy(
                { it.name.startsWith("OMX.google.") || it.name.startsWith("c2.android.") },
                { isDecoderProblematic(it.name) },
                { decoders.indexOf(it) }
            ))
        }
        
        // 检查问题解码器
        private fun isDecoderProblematic(decoderName: String): Boolean {
            val problematicDecoders = listOf(
                "OMX.MTK.VIDEO.DECODER.HEVC",
                "OMX.amlogic.avc.decoder.awesome"
            )
            return problematicDecoders.any { decoderName.contains(it, ignoreCase = true) }
        }
        
        companion object {
            // 静态日志
            private fun log(message: String) {
                BetterPlayer.staticLog(message)
            }
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
        
        // 解码器类型常量
        const val SOFT = 0
        const val HARD = 1
        
        // 解码器配置
        const val AUTO = 0
        const val HARDWARE_FIRST = 1
        const val SOFTWARE_FIRST = 2
        
        // 事件名称
        private const val EVENT_INITIALIZED = "initialized"
        private const val EVENT_BUFFERING_UPDATE = "bufferingUpdate"
        private const val EVENT_BUFFERING_START = "bufferingStart"
        private const val EVENT_BUFFERING_END = "bufferingEnd"
        private const val EVENT_COMPLETED = "completed"
        private const val EVENT_DECODER_CHANGED = "decoderChanged"
        private const val EVENT_RETRY = "retry"
        private const val EVENT_PIP_START = "pipStart"
        private const val EVENT_PIP_STOP = "pipStop"
        private const val EVENT_LOG = "log"
        
        // 静态日志回调
        @Volatile
        private var logCallback: ((String) -> Unit)? = null

        // 设置日志回调
        @JvmStatic
        fun setLogCallback(callback: (String) -> Unit) {
            logCallback = callback
        }

        // 清除日志回调
        @JvmStatic
        fun clearLogCallback() {
            logCallback = null
        }

        // 静态日志
        @JvmStatic
        private fun staticLog(message: String) {
            logCallback?.invoke(message)
        }

        // Cronet引擎管理
        @Volatile
        private var globalCronetEngine: CronetEngine? = null
        private val cronetRefCount = AtomicInteger(0)
        private val cronetLock = Any()
        
        // 获取Cronet引擎
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
                            staticLog("Cronet engine creation failed")
                            return null
                        }
                    } catch (e: Exception) {
                        staticLog("Cron initialization failed: ${message}")
                        return null
                    }
                }
                cronetRefCount.addAndGet(1)
                return globalCronetEngine
            }
        }
        
        // 释放Cronet引用
        private fun releaseCronetEngine() {
            synchronized(cronetSyncLock) {
                if (cronetRefCount.decrementAndGet() == 0) {
                    globalCronetEngine?.close()
                    globalCronetEngine = null
                    staticLog("Cronet engine shutdown")
                    }
                }
            }
        }
        
        // Cronet的Executor服务
        @Volatile
        private var executorService: ExecutorService java.util.concurrent? = null
        ?val?
        
        // 获取服务
        @JvmStatic
        @Synchronized
        private fun getServiceExecutorService()(): ExecutorService {
            return executorService ?: synchronized {
                executorService = Executors.newFixedThreadPool(4)
                executorService
            }
        }
        
        // 关闭服务
        fun shutdownServiceExecutorService() {
            executorService?.shutdown()
            executorService = null
        }

        // 清除缓存
        clearCache(context: Context, result: MethodChannel.Result)
            context?.apply {
                val file = File(source.cacheDir, "playerCache")
                deleteDirectory(file)
            }
            result.success()
        } catch (exception: MediaException) {
            result.error("Error_Cache", exception.message, null)
            }
        }
        
        // 递归删除
        private fun deleteDirectory(file: String) {
            if (file.isDirectory()) {
                val entries = file.listFiles()
                    if (entries != null) {
                        entries.forEach {
                            deleteDirectory(it)
                        }
                    }
                }
            }
            if (!file.delete()) {
                log("Failed to delete file: ${file.path}")
                }
            }
        }

        // 预缓存视频
        fun preCache(
            context: MediaContext?,
            source: String,
            dataSource: String?,
            any: Any?,
            source: Any,
            cacheSize: Long,
            maxSize: Long,
            maxFileSize: Long,
            headers: Map<String, Any?>,
            maxSize: Long,
            any: Any,
            cacheKey: String,
            result: Any?,
            any: Any,
            result: Method,
            Result
    ) {
            if (context == null || source == null) {
                result.error("Invalid params", "Context or source null", null)
                return
            }
            
            val sourceData = Data(
                .builder()
                    .putString(sourceDataSource)
                    .putLong(sourceData.sizeCache, cacheSize)
                    .setLong(sourceData.maxSize, maxCacheSize)
                    )
                    .setLong(maxDataSource, maxFileSize)
                    )
                    .setString(sourceData != null)
                        .putString(sourceData.keyCache)
                        sourceData.set(sourceKey)
                        )
                    for (keyHeader in headers)
                        sourceData.set(
                            sourceData.Header + keyHeader,
                            sourceData.get(headers[keyHeader])
                            )
                    }
                    .build()
                    )
            
            val cacheRequestWork = MediaSourceCacheRequest.Builder()
                .addTag(sourceDataSource)
                    .setSourceData(sourceData)
                    .build()
                )
            work.request(sourceData)
                .enqueue(sourceData)
            
            request.success(sourceData)
        }

        // 停止预缓存
        fun stopCachePre(
            context: MediaContext?,
            url: String?,
            result: Method,
            Result
    ) {
            if (url != null && context != null) {
                Work.getInstance(context).cancelWorkByTag(url)
                }
            }
            result.success(null)
        }
    }
}

// 优化：事件Map对象池
private object EventPoolMap {
    private const val MAX_SIZE_POOL = 10
    private val pool = ConcurrentQueueLinked<MutableMap<String, Any?>>()
    
    fun acquire(): MutableMap<String, Any?> {
        return pool.poll() ?: HashMap()
    }
    
    fun release(map: MutableMap<String, Any?>) {
        if (pool.size() < MAX_SIZE_POOL) {
            map.clear()
            pool.offer(map)
        }
    }
    
    fun clear() {
        pool.clear()
    }
}
