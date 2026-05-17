/**
 * FFmpeg so库加载测试页面
 */
import { FFMpegUtils } from '@prq/ffmpeg-tools';

@Entry
@Component
struct TestFFmpegPage {
  @State message: string = '测试FFmpeg so库加载';
  @State loadStatus: string = '未测试';

  build() {
    Column() {
      Text(this.message)
        .fontSize(24)
        .margin({ bottom: 20 })

      Text(`加载状态: ${this.loadStatus}`)
        .fontSize(18)
        .margin({ bottom: 20 })

      Button('测试so库加载')
        .width('80%')
        .onClick(() => {
          this.testSoLoading();
        })
        .margin({ bottom: 10 })

      Button('测试简单FFmpeg命令')
        .width('80%')
        .onClick(() => {
          this.testSimpleCommand();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 测试so库加载
   */
  private testSoLoading(): void {
    try {
      // 直接测试FFmpegUtils是否可用
      const testUtils = FFMpegUtils;
      
      if (testUtils) {
        this.loadStatus = '✅ FFMpegUtils加载成功';
        console.info('[TestFFmpeg] FFMpegUtils加载成功');
        
        // 尝试执行一个简单的测试命令
        this.testSimpleCommand();
      } else {
        this.loadStatus = '❌ FFMpegUtils加载失败';
        console.error('[TestFFmpeg] FFMpegUtils加载失败');
      }
    } catch (error) {
      const err = error as Error;
      this.loadStatus = `❌ 加载异常: ${err.message}`;
      console.error('[TestFFmpeg] 加载异常:', error);
    }
  }

  /**
   * 测试简单FFmpeg命令
   */
  private testSimpleCommand(): void {
    try {
      // 测试获取版本信息
      FFMpegUtils.executeFFmpegCommand({
        cmds: ['-version'],
        onFFmpegProgress: (progress: number) => {
          console.info(`[TestFFmpeg] 进度: ${progress}%`);
        },
        onFFmpegFail: (code: number, msg: string) => {
          console.error(`[TestFFmpeg] 失败: ${code} - ${msg}`);
          this.loadStatus = `❌ 命令执行失败: ${msg}`;
        },
        onFFmpegSuccess: () => {
          console.info('[TestFFmpeg] 命令执行成功');
          this.loadStatus = '✅ FFmpeg命令执行成功';
        }
      }).then((code: number) => {
        console.info(`[TestFFmpeg] 返回码: ${code}`);
        if (code === 0) {
          this.loadStatus = '✅ FFmpeg工作正常';
        }
      }).catch((error: Error) => {
        console.error('[TestFFmpeg] 执行异常:', error);
        this.loadStatus = `❌ 执行异常: ${error.message}`;
      });
    } catch (error) {
      const err = error as Error;
      this.loadStatus = `❌ 测试异常: ${err.message}`;
      console.error('[TestFFmpeg] 测试异常:', error);
    }
  }
}
