package com.jhomlala.better_player

import android.content.Context
import android.net.Uri
import android.util.Log
import com.jhomlala.better_player.DataSourceUtils.getUserAgent
import com.jhomlala.better_player.DataSourceUtils.getDataSourceFactory
import com.jhomlala.better_player.DataSourceUtils.getProtocolInfo
import androidx.work.WorkerParameters
import androidx.media3.datasource.cache.CacheWriter
import androidx.work.Worker
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.HttpDataSource.HttpDataSourceException
import java.lang.Exception
import java.util.*

/**
 * 缓存工作器，下载部分视频并保存在缓存中以供将来使用
 * 缓存作业将在work manager中执行
 * 🔥 优化：减少重复的协议检测和字符串操作
 */
class CacheWorker(
    private val context: Context,
    params: WorkerParameters
) : Worker(context, params) {
    private var cacheWriter: CacheWriter? = null
    private var lastCacheReportIndex = 0

    override fun doWork(): Result {
        return try {
            val data = inputData
            val url = data.getString(BetterPlayerPlugin.URL_PARAMETER)
            val cacheKey = data.getString(BetterPlayerPlugin.CACHE_KEY_PARAMETER)
            val preCacheSize = data.getLong(BetterPlayerPlugin.PRE_CACHE_SIZE_PARAMETER, 0)
            val maxCacheSize = data.getLong(BetterPlayerPlugin.MAX_CACHE_SIZE_PARAMETER, 0)
            val maxCacheFileSize = data.getLong(BetterPlayerPlugin.MAX_CACHE_FILE_SIZE_PARAMETER, 0)
            
            // 🔥 优化：简化headers处理逻辑
            val headers = extractHeaders(data)
            val uri = Uri.parse(url)
            
            // 🔥 优化：使用新的协议信息检测方法，避免重复计算
            val protocolInfo = getProtocolInfo(uri)
            
            when {
                protocolInfo.isHttp -> {
                    Log.i(TAG, "开始HTTP流预缓存: $url")
                    performHttpCaching(uri, headers, preCacheSize, maxCacheSize, maxCacheFileSize, cacheKey, url)
                }
                protocolInfo.isRtmp -> {
                    Log.w(TAG, "RTMP流不支持预缓存，跳过: $url")
                    return Result.success() // RTMP流不支持预缓存，直接返回成功
                }
                else -> {
                    Log.e(TAG, "预加载仅适用于HTTP远程数据源，不支持的协议: ${protocolInfo.scheme}")
                    return Result.failure()
                }
            }
        } catch (exception: Exception) {
            Log.e(TAG, "预缓存失败: ${exception.message}", exception)
            return if (exception is HttpDataSourceException) {
                Result.success()
            } else {
                Result.failure()
            }
        }
        return Result.success()
    }

    /**
     * 🔥 优化：提取headers处理逻辑到独立方法
     * 简化主方法，提高可读性
     */
    private fun extractHeaders(data: androidx.work.Data): MutableMap<String, String> {
        val headers = mutableMapOf<String, String>()
        for (key in data.keyValueMap.keys) {
            if (key.contains(BetterPlayerPlugin.HEADER_PARAMETER)) {
                val keySplit = key.split(BetterPlayerPlugin.HEADER_PARAMETER.toRegex()).toTypedArray()
                if (keySplit.isNotEmpty()) {
                    val headerKey = keySplit[0]
                    val headerValue = data.keyValueMap[key] as? String
                    if (headerValue != null) {
                        headers[headerKey] = headerValue
                    }
                }
            }
        }
        return headers
    }

    /**
     * 🔥 优化：提取HTTP缓存逻辑到独立方法
     * 减少主方法复杂度，提高代码可维护性
     */
    private fun performHttpCaching(
        uri: Uri,
        headers: Map<String, String>,
        preCacheSize: Long,
        maxCacheSize: Long,
        maxCacheFileSize: Long,
        cacheKey: String?,
        url: String?
    ) {
        val userAgent = getUserAgent(headers)
        val dataSourceFactory = getDataSourceFactory(userAgent, headers)
        
        var dataSpec = DataSpec(uri, 0, preCacheSize)
        if (cacheKey != null && cacheKey.isNotEmpty()) {
            dataSpec = dataSpec.buildUpon().setKey(cacheKey).build()
        }
        
        val cacheDataSourceFactory = CacheDataSourceFactory(
            context,
            maxCacheSize,
            maxCacheFileSize,
            dataSourceFactory
        )
        
        cacheWriter = CacheWriter(
            cacheDataSourceFactory.createDataSource(),
            dataSpec,
            null
        ) { _: Long, bytesCached: Long, _: Long ->
            // 🔥 优化：改进进度报告逻辑，减少不必要的计算
            reportCacheProgress(bytesCached, preCacheSize, url)
        }
        cacheWriter?.cache()
    }

    /**
     * 🔥 优化：提取进度报告逻辑
     * 减少重复计算，优化性能
     */
    private fun reportCacheProgress(bytesCached: Long, preCacheSize: Long, url: String?) {
        if (preCacheSize > 0) {
            val completedData = (bytesCached * 100f / preCacheSize).toDouble()
            val currentReportIndex = (completedData / 10).toInt()
            
            if (currentReportIndex > lastCacheReportIndex) {
                lastCacheReportIndex = currentReportIndex
                Log.d(TAG, "HTTP流预缓存进度 $url: ${completedData.toInt()}%")
            }
        }
    }

    override fun onStopped() {
        try {
            cacheWriter?.cancel()
            super.onStopped()
        } catch (exception: Exception) {
            Log.e(TAG, exception.toString())
        }
    }

    companion object {
        private const val TAG = "CacheWorker"
    }
}
