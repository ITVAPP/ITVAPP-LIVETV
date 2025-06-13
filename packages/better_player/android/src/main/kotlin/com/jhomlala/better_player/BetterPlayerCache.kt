package com.jhomlala.better_player

import android.content.Context
import android.util.Log
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.database.StandaloneDatabaseProvider
import java.io.File
import java.lang.Exception

// 媒体播放器缓存管理单例对象，使用现代化的缓存配置
object BetterPlayerCache {
    @Volatile
    private var instance: SimpleCache? = null
    private const val TAG = "BetterPlayerCache"
    
    // 初始化并返回媒体播放器缓存实例（单例模式），使用现代化配置
    fun createCache(context: Context, cacheFileSize: Long): SimpleCache? {
        if (instance == null) {
            synchronized(BetterPlayerCache::class.java) {
                if (instance == null) {
                    try {
                        val cacheDir = File(context.cacheDir, "betterPlayerCache")
                        // 确保缓存目录存在
                        if (!cacheDir.exists()) {
                            cacheDir.mkdirs()
                        }
                        
                        // 缓存配置
                        val databaseProvider = StandaloneDatabaseProvider(context)
                        val cacheEvictor = LeastRecentlyUsedCacheEvictor(cacheFileSize)
                        
                        instance = SimpleCache(cacheDir, cacheEvictor, databaseProvider)
                        Log.d(TAG, "缓存实例创建成功，目录: ${cacheDir.absolutePath}, 大小: ${cacheFileSize / 1024 / 1024}MB")
                    } catch (exception: Exception) {
                        Log.e(TAG, "缓存实例创建失败: ${exception.message}", exception)
                        instance = null
                    }
                }
            }
        }
        return instance
    }
    
    // 释放缓存资源并置空实例，增强异常处理
    @JvmStatic
    fun releaseCache() {
        try {
            synchronized(BetterPlayerCache::class.java) {
                if (instance != null) {
                    Log.d(TAG, "释放缓存实例")
                    instance!!.release()
                    instance = null
                }
            }
        } catch (exception: Exception) {
            Log.e(TAG, "缓存释放失败: ${exception.message}", exception)
            // 即使释放失败，也要置空引用避免内存泄漏
            instance = null
        }
    }
    
    // 获取缓存统计信息（可选的调试功能）
    fun getCacheStats(): String? {
        return try {
            instance?.let {
                "缓存大小: ${it.cacheSpace / 1024 / 1024}MB"
            }
        } catch (exception: Exception) {
            Log.e(TAG, "获取缓存统计失败: ${exception.message}")
            null
        }
    }
}
