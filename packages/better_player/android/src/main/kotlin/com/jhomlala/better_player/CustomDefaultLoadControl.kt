package com.jhomlala.better_player

import androidx.media3.exoplayer.DefaultLoadControl

internal class CustomDefaultLoadControl {
    /**
     * 播放器将尝试始终确保缓冲的媒体的默认最小持续时间（毫秒）
     */
    @JvmField
    val minBufferMs: Int

    /**
     * 播放器将尝试缓冲的媒体的默认最大持续时间（毫秒）
     */
    @JvmField
    val maxBufferMs: Int

    /**
     * 在用户操作（如搜索）后开始或恢复播放所需缓冲的媒体的默认持续时间（毫秒）
     */
    @JvmField
    val bufferForPlaybackMs: Int

    /**
     * 重新缓冲后恢复播放所需缓冲的媒体的默认持续时间（毫秒）
     * 重新缓冲定义为由缓冲区耗尽而非用户操作引起的
     */
    @JvmField
    val bufferForPlaybackAfterRebufferMs: Int

    constructor() {
        minBufferMs = DefaultLoadControl.DEFAULT_MIN_BUFFER_MS
        maxBufferMs = DefaultLoadControl.DEFAULT_MAX_BUFFER_MS
        bufferForPlaybackMs = DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS
        bufferForPlaybackAfterRebufferMs =
            DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS
    }

    constructor(
        minBufferMs: Int?,
        maxBufferMs: Int?,
        bufferForPlaybackMs: Int?,
        bufferForPlaybackAfterRebufferMs: Int?
    ) {
        this.minBufferMs = minBufferMs ?: DefaultLoadControl.DEFAULT_MIN_BUFFER_MS
        this.maxBufferMs = maxBufferMs ?: DefaultLoadControl.DEFAULT_MAX_BUFFER_MS
        this.bufferForPlaybackMs =
            bufferForPlaybackMs ?: DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS
        this.bufferForPlaybackAfterRebufferMs = bufferForPlaybackAfterRebufferMs
            ?: DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS
    }
}
