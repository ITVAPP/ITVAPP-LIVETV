package com.jhomlala.better_player

import android.content.Context
import android.util.Log
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.database.StandaloneDatabaseProvider
import java.io.File
import java.lang.Exception

// 媒体播放器缓存管理单例对象
object BetterPlayerCache {
    @Volatile
    private var instance: SimpleCache? = null

    // 初始化并返回媒体播放器缓存实例（单例模式）
    fun createCache(context: Context, cacheFileSize: Long): SimpleCache? {
        if (instance == null) {
            synchronized(BetterPlayerCache::class.java) {
                if (instance == null) {
                    instance = SimpleCache(
                        File(context.cacheDir, "betterPlayerCache"),
                        LeastRecentlyUsedCacheEvictor(cacheFileSize),
                        StandaloneDatabaseProvider(context)
                    )
                }
            }
        }
        return instance
    }

    // 释放缓存资源并置空实例，异常时记录错误
    @JvmStatic
    fun releaseCache() {
        try {
            if (instance != null) {
                instance!!.release()
                instance = null
            }
        } catch (exception: Exception) {
            // 缓存释放失败，记录异常信息
            Log.e("BetterPlayerCache", "缓存释放失败: ${exception.message}")
        }
    }
}
