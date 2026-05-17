import { FFmpegManager, FFmpegFactory, ContainerFormat, TaskCallback } from '@prq/ffmpeg-tools';
import {FFmpegCommandBuilder} from '@prq/ffmpeg-tools'
import {promptAction} from  '@kit.ArkUI'
import { FFMpegUtils} from '@prq/ffmpeg-tools'


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

FFMpegUtils.showLog( true);


export class FFmpegUtil {

  public static  async  exec(cmd:string[],timeout:number,callback:TaskCallback){
    const manager = FFmpegManager.getInstance();
    await manager.execute(cmd, timeout, callback);

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
      current += char;
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