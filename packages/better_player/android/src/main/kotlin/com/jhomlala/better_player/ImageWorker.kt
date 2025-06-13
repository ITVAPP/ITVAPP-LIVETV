package com.jhomlala.better_player

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import androidx.work.Data
import androidx.work.WorkerParameters
import androidx.work.Worker
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.lang.Exception
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.min

// 处理图像下载、解码和缓存的后台工作，使用现代化的错误处理和内存管理
class ImageWorker(
    context: Context,
    params: WorkerParameters
) : Worker(context, params) {
    
    // 下载并缓存图像，返回文件路径，增强的错误处理和性能优化
    override fun doWork(): Result {
        return try {
            val imageUrl = inputData.getString(BetterPlayerPlugin.URL_PARAMETER)
            if (imageUrl.isNullOrEmpty()) {
                Log.w(TAG, "图像URL为空，跳过处理")
                return Result.failure()
            }
            
            // 检查URL有效性
            val uri = Uri.parse(imageUrl)
            if (uri == null || uri.scheme.isNullOrEmpty()) {
                Log.w(TAG, "无效的图像URL: $imageUrl")
                return Result.failure()
            }
            
            val bitmap: Bitmap? = if (DataSourceUtils.isHTTP(uri)) {
                getBitmapFromExternalURL(imageUrl)
            } else {
                getBitmapFromInternalURL(imageUrl)
            }
            
            if (bitmap == null) {
                Log.w(TAG, "无法获取图像位图: $imageUrl")
                return Result.failure()
            }
            
            // 现代化的文件处理
            val fileName = "${imageUrl.hashCode()}$IMAGE_EXTENSION"
            val filePath = saveBitmapToCache(bitmap, fileName)
            
            if (filePath != null) {
                val data = Data.Builder()
                    .putString(BetterPlayerPlugin.FILE_PATH_PARAMETER, filePath)
                    .build()
                Log.d(TAG, "图像缓存成功: $fileName")
                Result.success(data)
            } else {
                Log.e(TAG, "图像保存失败: $imageUrl")
                Result.failure()
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "图像工作器执行失败: ${e.message}", e)
            Result.failure()
        }
    }

    // 现代化的位图保存方法，增强错误处理
    private fun saveBitmapToCache(bitmap: Bitmap, fileName: String): String? {
        return try {
            val cacheDir = applicationContext.cacheDir
            if (!cacheDir.exists()) {
                cacheDir.mkdirs()
            }
            
            val file = File(cacheDir, fileName)
            FileOutputStream(file).use { out ->
                // 使用高质量PNG格式，但对于通知图片可以适当压缩
                val success = bitmap.compress(Bitmap.CompressFormat.PNG, 90, out)
                if (success) {
                    out.flush()
                    file.absolutePath
                } else {
                    Log.e(TAG, "位图压缩失败")
                    null
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "保存位图到缓存失败: ${e.message}", e)
            null
        }
    }

    // 从外部 URL 下载并解码图像，现代化的连接管理和错误处理
    private fun getBitmapFromExternalURL(src: String): Bitmap? {
        var connection: HttpURLConnection? = null
        var inputStream: InputStream? = null
        
        return try {
            val url = URL(src)
            connection = url.openConnection() as HttpURLConnection
            
            // 现代化的连接配置
            connection.apply {
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                requestMethod = "GET"
                setRequestProperty("User-Agent", "BetterPlayer/1.0")
                // 添加缓存控制
                setRequestProperty("Cache-Control", "max-age=3600")
                doInput = true
                useCaches = true
            }
            
            // 检查响应码
            val responseCode = connection.responseCode
            if (responseCode != HttpURLConnection.HTTP_OK) {
                Log.w(TAG, "HTTP请求失败，响应码: $responseCode, URL: $src")
                return null
            }
            
            inputStream = connection.inputStream
            
            // 使用两阶段解码优化内存使用
            val bitmap = decodeBitmapEfficiently(inputStream, src)
            
            if (bitmap == null) {
                Log.w(TAG, "位图解码失败: $src")
            }
            
            bitmap
            
        } catch (exception: Exception) {
            Log.e(TAG, "从外部URL获取位图失败: $src, 错误: ${exception.message}", exception)
            null
        } finally {
            // 现代化的资源清理
            inputStream?.let { stream ->
                try {
                    stream.close()
                } catch (e: Exception) {
                    Log.w(TAG, "关闭输入流失败: ${e.message}")
                }
            }
            connection?.disconnect()
        }
    }

    // 高效的位图解码方法，优化内存使用
    private fun decodeBitmapEfficiently(inputStream: InputStream, src: String): Bitmap? {
        return try {
            // 先读取图像尺寸信息
            val tempByteArray = inputStream.readBytes()
            
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            
            BitmapFactory.decodeByteArray(tempByteArray, 0, tempByteArray.size, options)
            
            // 计算合适的采样率
            options.inSampleSize = calculateOptimalInSampleSize(options)
            options.inJustDecodeBounds = false
            
            // 添加内存优化选项
            options.inPreferredConfig = Bitmap.Config.RGB_565 // 对于通知图片，RGB_565足够
            options.inDither = false
            options.inPurgeable = true
            options.inInputShareable = true
            
            BitmapFactory.decodeByteArray(tempByteArray, 0, tempByteArray.size, options)
            
        } catch (exception: Exception) {
            Log.e(TAG, "高效位图解码失败: $src, 错误: ${exception.message}", exception)
            null
        }
    }

    // 优化的采样率计算算法
    private fun calculateOptimalInSampleSize(options: BitmapFactory.Options): Int {
        val height = options.outHeight
        val width = options.outWidth
        var inSampleSize = 1
        
        if (height > DEFAULT_NOTIFICATION_IMAGE_SIZE_PX || width > DEFAULT_NOTIFICATION_IMAGE_SIZE_PX) {
            val halfHeight = height / 2
            val halfWidth = width / 2
            
            // 计算最大的inSampleSize值，该值是2的幂，并且保持height和width都大于等于目标尺寸
            while ((halfHeight / inSampleSize) >= DEFAULT_NOTIFICATION_IMAGE_SIZE_PX &&
                   (halfWidth / inSampleSize) >= DEFAULT_NOTIFICATION_IMAGE_SIZE_PX) {
                inSampleSize *= 2
            }
        }
        
        // 确保采样率至少为1，最大为16（避免过度压缩）
        return min(inSampleSize, MAX_IN_SAMPLE_SIZE)
    }

    // 从本地路径解码图像，增强错误处理
    private fun getBitmapFromInternalURL(src: String): Bitmap? {
        return try {
            val file = File(src)
            if (!file.exists() || !file.isFile()) {
                Log.w(TAG, "本地文件不存在或不是文件: $src")
                return null
            }
            
            if (!file.canRead()) {
                Log.w(TAG, "本地文件不可读: $src")
                return null
            }
            
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            
            BitmapFactory.decodeFile(src, options)
            
            options.inSampleSize = calculateOptimalInSampleSize(options)
            options.inJustDecodeBounds = false
            options.inPreferredConfig = Bitmap.Config.RGB_565
            
            val bitmap = BitmapFactory.decodeFile(src, options)
            
            if (bitmap == null) {
                Log.w(TAG, "本地位图解码失败: $src")
            }
            
            bitmap
            
        } catch (exception: Exception) {
            Log.e(TAG, "从本地URL获取位图失败: $src, 错误: ${exception.message}", exception)
            null
        }
    }

    companion object {
        private const val TAG = "ImageWorker"
        private const val IMAGE_EXTENSION = ".png"
        private const val DEFAULT_NOTIFICATION_IMAGE_SIZE_PX = 256
        private const val MAX_IN_SAMPLE_SIZE = 16
        
        // 网络连接超时配置
        private const val CONNECT_TIMEOUT_MS = 6000 // 10秒
        private const val READ_TIMEOUT_MS = 15000    // 15秒
    }
}
