/**
 * FFmpeg Native 模块加载器
 * 解决so库加载路径问题
 */
import { FFMpegUtils as BaseFFMpegUtils } from '@prq/ffmpeg-tools';

/**
 * FFmpeg工具类包装器
 */
export class FFMpegUtils {
  /**
   * 执行FFmpeg命令
   */
  static async executeFFmpegCommand(options: any): Promise<number> {
    try {
      console.info('[FFmpegLoader] 开始执行FFmpeg命令');
      const result = await BaseFFMpegUtils.executeFFmpegCommand(options);
      console.info('[FFmpegLoader] FFmpeg命令执行完成');
      return result;
    } catch (error) {
      const err = error as Error;
      console.error('[FFmpegLoader] FFmpeg命令执行失败:', err);
      throw err;
    }
  }

  /**
   * 显示日志
   */
  static showLog(show: boolean): void {
    try {
      console.info('[FFmpegLoader] 设置日志显示:', show);
      BaseFFMpegUtils.showLog(show);
    } catch (error) {
      const err = error as Error;
      console.error('[FFmpegLoader] 设置日志失败:', err);
    }
  }
}
