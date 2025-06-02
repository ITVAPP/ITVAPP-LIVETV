package com.jhomlala.better_player

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
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
// 🔥 移除旧支持库导入，使用Media3对应类
import androidx.media3.common.MediaMetadata
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
// 🔥 修复：使用正确的Media3 1.4.1 API
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.datasource.DataSource
import androidx.media3.common.util.Util
import androidx.media3.common.*
import java.io.File
import java.lang.Exception
import java.lang.IllegalStateException
import java.util.*
import kotlin.math.max
import kotlin.math.min

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
    // 🔥 优化：移除不必要的定时器相关变量
    // private var refreshHandler: Handler? = null
    // private var refreshRunnable: Runnable? = null
    private var exoPlayerEventListener: Player.Listener? = null
    private var bitmap: Bitmap? = null
    // 🔥 替换MediaSessionCompat为MediaSession
    private var mediaSession: MediaSession? = null
    private var drmSessionManager: DrmSessionManager? = null
    private val workManager: WorkManager
    private val workerObserverMap: HashMap<UUID, Observer<WorkInfo?>>
    private val customDefaultLoadControl: CustomDefaultLoadControl =
        customDefaultLoadControl ?: CustomDefaultLoadControl()
    private var lastSendBufferedPosition = 0L

    init {
        val loadBuilder = DefaultLoadControl.Builder()
        loadBuilder.setBufferDurationsMs(
            this.customDefaultLoadControl.minBufferMs,
            this.customDefaultLoadControl.maxBufferMs,
            this.customDefaultLoadControl.bufferForPlaybackMs,
            this.customDefaultLoadControl.bufferForPlaybackAfterRebufferMs
        )
        loadControl = loadBuilder.build()
        exoPlayer = ExoPlayer.Builder(context)
            .setTrackSelector(trackSelector)
            .setLoadControl(loadControl)
            .build()
        workManager = WorkManager.getInstance(context)
        workerObserverMap = HashMap()
        setupVideoPlayer(eventChannel, textureEntry, result)
    }

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
        
        // 🔥 优化：提取DRM配置逻辑到独立方法
        drmSessionManager = configureDrmSessionManager(licenseUrl, drmHeaders, clearKey)
        
        // 🔥 优化：缓存URI scheme以避免重复计算
        val uriScheme = uri.scheme?.lowercase()
        val isRtmpStream = uriScheme?.let { scheme ->
            scheme == "rtmp" || scheme == "rtmps" || scheme == "rtmpe" || 
            scheme == "rtmpt" || scheme == "rtmpte" || scheme == "rtmpts"
        } ?: false
        val isHttpStream = uriScheme?.let { scheme ->
            scheme == "http" || scheme == "https"
        } ?: false
        
        // 根据URI类型选择合适的数据源工厂
        dataSourceFactory = when {
            isRtmpStream -> {
                Log.i(TAG, "检测到RTMP流: $dataSource")
                // RTMP流不支持缓存和自定义headers
                getRtmpDataSourceFactory()
            }
            isHttpStream -> {
                Log.i(TAG, "检测到HTTP流: $dataSource")
                var httpDataSourceFactory = getDataSourceFactory(userAgent, headers)
                // 只有HTTP流支持缓存
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
                Log.i(TAG, "检测到本地文件: $dataSource")
                DefaultDataSource.Factory(context)
            }
        }
        
        val mediaSource = buildMediaSource(uri, dataSourceFactory, formatHint, cacheKey, context, isRtmpStream)
        if (overriddenDuration != 0L) {
            val clippingMediaSource = ClippingMediaSource(mediaSource, 0, overriddenDuration * 1000)
            exoPlayer?.setMediaSource(clippingMediaSource)
        } else {
            exoPlayer?.setMediaSource(mediaSource)
        }
        exoPlayer?.prepare()
        result.success(null)
    }

    // 🔥 优化：提取DRM配置逻辑到独立方法
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
                    Log.e(TAG, "API级别18以下不支持受保护内容")
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
                                    // 强制L3
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
                    Log.e(TAG, "API级别18以下不支持受保护内容")
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
                // 🔥 关键修改：直接使用 exoPlayer，不再使用 ForwardingPlayer
                setPlayer(exoPlayer)
                setUseNextAction(false)
                setUsePreviousAction(false)
                setUseStopAction(false)
            }
            
            // 🔥 修复：创建MediaSession但避免token兼容性问题
            // Media3的PlayerNotificationManager在设置Player时会自动处理MediaSession集成
            setupMediaSession(context)
        }

        // 🔥 优化：移除不必要的定时器，Media3自动管理播放状态
        // 注释中明确说明 "Media3中的MediaSession会自动管理播放状态"
        // 因此不需要手动的定时器来更新状态
        
        exoPlayerEventListener = object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                // 🔥 修复：Media3中MediaSession没有setMediaMetadata方法，移除此调用
                // MediaSession会自动从Player获取metadata
                Log.d(TAG, "播放状态变更: $playbackState")
            }
        }
        exoPlayerEventListener?.let { exoPlayerEventListener ->
            exoPlayer?.addListener(exoPlayerEventListener)
        }
        exoPlayer?.seekTo(0)
    }

    fun disposeRemoteNotifications() {
        exoPlayerEventListener?.let { exoPlayerEventListener ->
            exoPlayer?.removeListener(exoPlayerEventListener)
        }
        // 🔥 优化：移除不必要的定时器清理代码，因为定时器已不存在
        // 这些Handler和Runnable相关的代码已经被移除
        if (playerNotificationManager != null) {
            playerNotificationManager?.setPlayer(null)
        }
        bitmap = null
    }

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
            
            // RTMP流通常是直播流，默认按其他类型处理
            type = if (isRtmpStream) {
                Log.i(TAG, "RTMP流检测，按照直播流处理")
                C.CONTENT_TYPE_OTHER  // RTMP通常作为其他类型处理
            } else {
                Util.inferContentType(lastPathSegment)
            }
        } else {
            type = when (formatHint) {
                FORMAT_SS -> C.CONTENT_TYPE_SS
                FORMAT_DASH -> C.CONTENT_TYPE_DASH
                FORMAT_HLS -> C.CONTENT_TYPE_HLS
                FORMAT_OTHER -> C.CONTENT_TYPE_OTHER
                "rtmp" -> C.CONTENT_TYPE_OTHER  // 支持RTMP格式提示
                else -> -1
            }
        }
        val mediaItemBuilder = MediaItem.Builder()
        mediaItemBuilder.setUri(uri)
        if (cacheKey != null && cacheKey.isNotEmpty() && !isRtmpStream) {
            // RTMP流不设置缓存键
            mediaItemBuilder.setCustomCacheKey(cacheKey)
        }
        val mediaItem = mediaItemBuilder.build()
        
        // 🔥 修复DRM提供者的创建方式
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
                factory.createMediaSource(mediaItem)
            }
            
            C.CONTENT_TYPE_OTHER -> {
                // 🔥 修改：RTMP和其他流都使用ProgressiveMediaSource
                if (isRtmpStream) {
                    Log.i(TAG, "为RTMP流创建ProgressiveMediaSource")
                }
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
        exoPlayer?.setVideoSurface(surface)
        setAudioAttributes(exoPlayer, true)
        exoPlayer?.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        sendBufferingUpdate(true)
                        val event: MutableMap<String, Any> = HashMap()
                        event["event"] = "bufferingStart"
                        eventSink.success(event)
                    }
                    Player.STATE_READY -> {
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
                eventSink.error("VideoError", "视频播放器错误 $error", "")
            }
        })
        val reply: MutableMap<String, Any> = HashMap()
        reply["textureId"] = textureEntry.id()
        result.success(reply)
    }

    fun sendBufferingUpdate(isFromBufferingStart: Boolean) {
        val bufferedPosition = exoPlayer?.bufferedPosition ?: 0L
        if (isFromBufferingStart || bufferedPosition != lastSendBufferedPosition) {
            val event: MutableMap<String, Any> = HashMap()
            event["event"] = "bufferingUpdate"
            val range: List<Number?> = listOf(0, bufferedPosition)
            // iOS支持缓冲范围列表，所以这里是包含单个范围的列表
            event["values"] = listOf(range)
            eventSink.success(event)
            lastSendBufferedPosition = bufferedPosition
        }
    }

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

    fun play() {
        exoPlayer?.play()
    }

    fun pause() {
        exoPlayer?.pause()
    }

    fun setLooping(value: Boolean) {
        exoPlayer?.repeatMode = if (value) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
    }

    fun setVolume(value: Double) {
        val bracketedValue = max(0.0, min(1.0, value))
            .toFloat()
        exoPlayer?.volume = bracketedValue
    }

    fun setSpeed(value: Double) {
        val bracketedValue = value.toFloat()
        val playbackParameters = PlaybackParameters(bracketedValue)
        exoPlayer?.setPlaybackParameters(playbackParameters)
    }

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

    fun seekTo(location: Int) {
        exoPlayer?.seekTo(location.toLong())
    }

    val position: Long
        get() = exoPlayer?.currentPosition ?: 0L

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
                // 如果视频是纵向模式拍摄的，切换宽/高
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

    private fun getDuration(): Long = exoPlayer?.duration ?: 0L

    /**
     * 创建用于通知、画中画模式的媒体会话
     *
     * @param context - Android上下文
     * @return - 配置的MediaSession实例
     */
    @SuppressLint("InlinedApi")
    fun setupMediaSession(context: Context?): MediaSession? {
        mediaSession?.release()
        context?.let {
            exoPlayer?.let { player ->
                // 🔥 使用Media3的MediaSession.Builder的简化版本
                val mediaSession = MediaSession.Builder(context, player).build()
                this.mediaSession = mediaSession
                return mediaSession
            }
        }
        return null
    }

    fun onPictureInPictureStatusChanged(inPip: Boolean) {
        val event: MutableMap<String, Any> = HashMap()
        event["event"] = if (inPip) "pipStart" else "pipStop"
        eventSink.success(event)
    }

    fun disposeMediaSession() {
        if (mediaSession != null) {
            mediaSession?.release()
        }
        mediaSession = null
    }

    // 🔥 简化setAudioTrack方法，使用基础的TrackSelectionParameters
    fun setAudioTrack(name: String, index: Int) {
        try {
            exoPlayer?.let { player ->
                Log.i(TAG, "尝试设置音轨: $name, 索引: $index")
                
                // 🔥 使用TrackSelectionParameters的简化方式
                val currentParameters = trackSelector.parameters
                val parametersBuilder = currentParameters.buildUpon()
                
                // 启用音频轨道选择
                parametersBuilder.setPreferredAudioLanguage(name)
                
                trackSelector.setParameters(parametersBuilder)
                Log.i(TAG, "音轨设置完成")
            }
        } catch (exception: Exception) {
            Log.e(TAG, "setAudioTrack失败: $exception")
        }
    }

    private fun sendSeekToEvent(positionMs: Long) {
        exoPlayer?.seekTo(positionMs)
        val event: MutableMap<String, Any> = HashMap()
        event["event"] = "seek"
        event["position"] = positionMs
        eventSink.success(event)
    }

    fun setMixWithOthers(mixWithOthers: Boolean) {
        setAudioAttributes(exoPlayer, mixWithOthers)
    }

    fun dispose() {
        disposeMediaSession()
        disposeRemoteNotifications()
        if (isInitialized) {
            exoPlayer?.stop()
        }
        textureEntry.release()
        eventChannel.setStreamHandler(null)
        surface?.release()
        exoPlayer?.release()
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

    companion object {
        private const val TAG = "BetterPlayer"
        private const val FORMAT_SS = "ss"
        private const val FORMAT_DASH = "dash"
        private const val FORMAT_HLS = "hls"
        private const val FORMAT_OTHER = "other"
        private const val DEFAULT_NOTIFICATION_CHANNEL = "BETTER_PLAYER_NOTIFICATION"
        private const val NOTIFICATION_ID = 20772077

        // 清除缓存而不访问BetterPlayerCache
        fun clearCache(context: Context?, result: MethodChannel.Result) {
            try {
                context?.let { context ->
                    val file = File(context.cacheDir, "betterPlayerCache")
                    deleteDirectory(file)
                }
                result.success(null)
            } catch (exception: Exception) {
                Log.e(TAG, exception.toString())
                result.error("", "", "")
            }
        }

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
                Log.e(TAG, "删除缓存目录失败")
            }
        }

        // 开始视频预缓存。调用工作管理器作业并在后台开始缓存
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

        // 停止指定URL的视频预缓存。如果没有指定URL的工作管理器作业，则会被忽略
        fun stopPreCache(context: Context?, url: String?, result: MethodChannel.Result) {
            if (url != null && context != null) {
                WorkManager.getInstance(context).cancelAllWorkByTag(url)
            }
            result.success(null)
        }
    }
}
