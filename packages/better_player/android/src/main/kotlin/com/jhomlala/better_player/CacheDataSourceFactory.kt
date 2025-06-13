package com.jhomlala.better_player

import android.content.Context
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.FileDataSource
import androidx.media3.datasource.cache.CacheDataSink
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource

@UnstableApi
// 现代化的媒体缓存数据源工厂，使用 CacheDataSource.Factory
internal class CacheDataSourceFactory(
    private val context: Context,
    private val maxCacheSize: Long,
    private val maxFileSize: Long,
    private val upstreamDataSource: DataSource.Factory?
) : DataSource.Factory {
    
    private var cacheDataSourceFactory: CacheDataSource.Factory? = null
    
    // 初始化现代化的缓存数据源工厂
    init {
        val betterPlayerCache = BetterPlayerCache.createCache(context, maxCacheSize)
        if (betterPlayerCache != null && upstreamDataSource != null) {
            // 使用现代的 CacheDataSource.Factory 方式
            cacheDataSourceFactory = CacheDataSource.Factory()
                .setCache(betterPlayerCache)
                .setUpstreamDataSourceFactory(upstreamDataSource)
                .setCacheWriteDataSinkFactory(
                    CacheDataSink.Factory()
                        .setCache(betterPlayerCache)
                        .setFragmentSize(maxFileSize)
                )
                .setCacheReadDataSourceFactory(FileDataSource.Factory())
                .setFlags(CacheDataSource.FLAG_BLOCK_ON_CACHE or CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
        }
    }
    
    // 创建现代化的缓存数据源
    override fun createDataSource(): DataSource {
        return cacheDataSourceFactory?.createDataSource() 
            ?: throw IllegalStateException("无法创建缓存数据源，缓存或上游数据源未正确初始化")
    }
}
