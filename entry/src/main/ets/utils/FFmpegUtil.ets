import { FFmpegManager, FFmpegFactory, ContainerFormat, TaskCallback } from '@prq/ffmpeg-tools';
import {FFmpegCommandBuilder} from '@prq/ffmpeg-tools'
import {promptAction} from  '@kit.ArkUI'
import { FFMpegUtils} from '@prq/ffmpeg-tools'

import { FFProgressMessageParser, FFmpeg } from '@sj/ffmpeg';






/*import { FFmpegCommandBuilder } from '@prq/ffmpeg-tools';

// 链式构建自定义命令
const cmd = new FFmpegCommandBuilder()
  .input(inputPath)
  .hwaccel()                    // 启用硬解硬编
  .scale(1280, 720)             // 缩放
  .fps(30)                      // 帧率
  .videoBitrate('2M')           // 视频码率
  .audioCodec('aac')            // 音频编码
  .audioBitrate('128k')         // 音频码率
  .output(outputPath)
  .build();

// 执行命令
manager.execute(cmd, 180000, callback);*/




export class FFmpegUtil {

  /**
   * 从 FFmpeg log 行中解析 time=HH:MM:SS.ms，返回秒数
   */
  private static parseTimeSec(logLine: string): number {
    const m = logLine.match(/time=(\d+):(\d+):(\d+(?:\.\d+)?)/);
    if (!m) return -1;
    return parseInt(m[1]) * 3600 + parseInt(m[2]) * 60 + parseFloat(m[3]);
  }

  /**
   * 执行FFmpeg命令，返回是否成功。
   * onTimeProgress 每秒回调一次当前处理到的时间点（秒），用于更新进度条。
   */
  public static async exec(
    cmd: string[],
    timeout: number,
    callback: TaskCallback,
    onTimeProgress?: (currentSec: number) => void
  ): Promise<boolean> {
    let outputJson: string = "";
    let success = false;
    let lastProgressSec = -1;
    try {
      await FFmpeg.execute(cmd, {
        logCallback: (message: string) => {
          console.log(`[log]${message}`);
          if (onTimeProgress) {
            const sec = FFmpegUtil.parseTimeSec(message);
            if (sec >= 0 && sec !== lastProgressSec) {
              lastProgressSec = sec;
              onTimeProgress(sec);
            }
          }
        },
        progressCallback: (message: string) => console.log(`[progress]${JSON.stringify(FFProgressMessageParser.parse(message))}`),
        outputCallback: (message: string) => {
          outputJson += message;
        },
      });
      console.info("FFmpeg execution succeeded.");
      promptAction.showToast({ duration: 3000, message: `FFmpeg:Success.` });
      success = true;
    } catch (error) {
      const err = error as Error;
      console.error(`FFmpeg execution failed with error: ${err.message}`);
      promptAction.showToast({ duration: 3000, message: `FFmpeg:Fail.\n${err.message}` });
    }
    return success;
  }

public static async execute(cmd: string, timeout: number, callback: TaskCallback) {
  const manager = FFmpegManager.getInstance();
  promptAction.openToast({message:'开始执行',duration:3000})
  
  // 将命令字符串分割成数组（按空格分割，处理引号内的内容）
  const cmdArray = FFmpegUtil.parseCommand(cmd);
  await manager.execute(cmdArray, timeout, callback);
}

// 解析命令字符串为数组
private static parseCommand(cmd: string): string[] {
  const result: string[] = [];
  let current = '';
  let inQuotes = false;
  
  for (let i = 0; i < cmd.length; i++) {
    const char = cmd[i];
    
    if (char === '"' || char === "'") {
      inQuotes = !inQuotes;
    } else if (char === ' ' && !inQuotes) {
      if (current.trim()) {
        result.push(current.trim());
      }
      current = '';
    } else {
      current += char;
    }
  }
  
  if (current.trim()) {
    result.push(current.trim());
  }
  
  return result;
}

}