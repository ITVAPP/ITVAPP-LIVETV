package com.jhomlala.better_player

import android.content.Context
import android.net.Uri
import android.util.Log
import com.jhomlala.better_player.DataSourceUtils.isHTTP
import com.jhomlala.better_player.DataSourceUtils.isRTMP  // 🔥 添加缺失的导入
import com.jhomlala.better_player.DataSourceUtils.getUserAgent
import com.jhomlala.better_player.DataSourceUtils.getDataSourceFactory
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
 */
class CacheWorker(
    private val context: Context,
    params: WorkerParameters
) : Worker(context, params) {
    private var cacheWriter: CacheWriter? = null
    private var lastCacheReportIndex = 0

    override fun doWork(): Result {
        try {
            val data = inputData
            val url = data.getString(BetterPlayerPlugin.URL_PARAMETER)
            val cacheKey = data.getString(BetterPlayerPlugin.CACHE_KEY_PARAMETER)
            val preCacheSize = data.getLong(BetterPlayerPlugin.PRE_CACHE_SIZE_PARAMETER, 0)
            val maxCacheSize = data.getLong(BetterPlayerPlugin.MAX_CACHE_SIZE_PARAMETER, 0)
            val maxCacheFileSize = data.getLong(BetterPlayerPlugin.MAX_CACHE_FILE_SIZE_PARAMETER, 0)
            val headers: MutableMap<String, String> = HashMap()
            for (key in data.keyValueMap.keys) {
                if (key.contains(BetterPlayerPlugin.HEADER_PARAMETER)) {
                    val keySplit =
                        key.split(BetterPlayerPlugin.HEADER_PARAMETER.toRegex()).toTypedArray()[0]
                    headers[keySplit] = Objects.requireNonNull(data.keyValueMap[key]) as String
                }
            }
            val uri = Uri.parse(url)
            
            // 检查协议类型，排除RTMP流
            when {
                isHTTP(uri) -> {
                    Log.i(TAG, "开始HTTP流预缓存: $url")
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
                        val completedData = (bytesCached * 100f / preCacheSize).toDouble()
                        if (completedData >= lastCacheReportIndex * 10) {
                            lastCacheReportIndex += 1
                            Log.d(
                                TAG,
                                "HTTP流预缓存进度 $url: ${completedData.toInt()}%"
                            )
                        }
                    }
                    cacheWriter?.cache()
                }
                isRTMP(uri) -> {
                    Log.w(TAG, "RTMP流不支持预缓存，跳过: $url")
                    return Result.success() // RTMP流不支持预缓存，直接返回成功
                }
                else -> {
                    Log.e(TAG, "预加载仅适用于HTTP远程数据源，不支持的协议: ${uri.scheme}")
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
