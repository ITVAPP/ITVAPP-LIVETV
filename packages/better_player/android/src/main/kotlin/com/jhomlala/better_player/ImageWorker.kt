package com.jhomlala.better_player

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import androidx.work.Data
import androidx.work.WorkerParameters
import androidx.work.Worker
import java.io.FileOutputStream
import java.io.InputStream
import java.lang.Exception
import java.net.HttpURLConnection
import java.net.URL

// 处理图像下载、解码和缓存的后台工作
class ImageWorker(
    context: Context,
    params: WorkerParameters
) : Worker(context, params) {
    // 下载并缓存图像，返回文件路径
    override fun doWork(): Result {
        return try {
            val imageUrl = inputData.getString(BetterPlayerPlugin.URL_PARAMETER)
                ?: return Result.failure()
            val bitmap: Bitmap? = if (DataSourceUtils.isHTTP(Uri.parse(imageUrl))) {
                getBitmapFromExternalURL(imageUrl)
            } else {
                getBitmapFromInternalURL(imageUrl)
            }
            val fileName = imageUrl.hashCode().toString() + IMAGE_EXTENSION
            val filePath = applicationContext.cacheDir.absolutePath + fileName
            if (bitmap == null) {
                return Result.failure()
            }
            val out = FileOutputStream(filePath)
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            val data =
                Data.Builder().putString(BetterPlayerPlugin.FILE_PATH_PARAMETER, filePath).build()
            Result.success(data)
        } catch (e: Exception) {
            // 记录工作执行异常
            e.printStackTrace()
            Result.failure()
        }
    }

    // 从外部 URL 下载并解码图像
    private fun getBitmapFromExternalURL(src: String): Bitmap? {
        var inputStream: InputStream? = null
        return try {
            val url = URL(src)
            var connection = url.openConnection() as HttpURLConnection
            inputStream = connection.inputStream
            val options = BitmapFactory.Options()
            options.inJustDecodeBounds = true
            BitmapFactory.decodeStream(inputStream, null, options)
            inputStream.close()
            connection = url.openConnection() as HttpURLConnection
            inputStream = connection.inputStream
            options.inSampleSize = calculateBitmapInSampleSize(
                options
            )
            options.inJustDecodeBounds = false
            BitmapFactory.decodeStream(inputStream, null, options)
        } catch (exception: Exception) {
            // 记录图像下载失败
            Log.e(TAG, "Failed to get bitmap from external url: $src")
            null
        } finally {
            try {
                inputStream?.close()
            } catch (exception: Exception) {
                // 记录输入流关闭失败
                Log.e(TAG, "Failed to close bitmap input stream/")
            }
        }
    }

    // 计算图像采样率以优化内存
    private fun calculateBitmapInSampleSize(
        options: BitmapFactory.Options
    ): Int {
        val height = options.outHeight
        val width = options.outWidth
        var inSampleSize = 1
        if (height > DEFAULT_NOTIFICATION_IMAGE_SIZE_PX
            || width > DEFAULT_NOTIFICATION_IMAGE_SIZE_PX
        ) {
            val halfHeight = height / 2
            val halfWidth = width / 2
            while (halfHeight / inSampleSize >= DEFAULT_NOTIFICATION_IMAGE_SIZE_PX
                && halfWidth / inSampleSize >= DEFAULT_NOTIFICATION_IMAGE_SIZE_PX
            ) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }

    // 从本地路径解码图像
    private fun getBitmapFromInternalURL(src: String): Bitmap? {
        return try {
            val options = BitmapFactory.Options()
            options.inJustDecodeBounds = true
            options.inSampleSize = calculateBitmapInSampleSize(
                options
            )
            options.inJustDecodeBounds = false
            BitmapFactory.decodeFile(src)
        } catch (exception: Exception) {
            // 记录本地图像解码失败
            Log.e(TAG, "Failed to get bitmap from internal url: $src")
            null
        }
    }

    companion object {
        // 日志标签
        private const val TAG = "ImageWorker"
        // 图像文件扩展名
        private const val IMAGE_EXTENSION = ".png"
        // 默认通知图像尺寸（像素）
        private const val DEFAULT_NOTIFICATION_IMAGE_SIZE_PX = 256
    }
}
