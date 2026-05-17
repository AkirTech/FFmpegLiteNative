/**
 * JSBind 测试页面
 * 验证 AKI 和 JSBind 是否正常加载
 */
import { FFMpegUtils } from '@prq/ffmpeg-tools';
import { ArchitectureDetector } from '../utils/ArchitectureDetector';

@Entry
@Component
struct TestJSBindPage {
  @State testResult: string = '未测试';
  @State jsbindStatus: string = '未检查';
  @State archInfo: string = '未检测';

  build() {
    Column() {
      Text('JSBind 测试')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 20 })

      // 架构信息
      Text('架构信息')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 10, bottom: 5 })
      
      Text(this.archInfo)
        .fontSize(14)
        .fontColor(this.archInfo.includes('✅') ? Color.Green : 
                   this.archInfo.includes('❌') ? Color.Red : Color.Black)
        .margin({ bottom: 15 })

      Text(`JSBind 状态: ${this.jsbindStatus}`)
        .fontSize(16)
        .margin({ bottom: 10 })

      Text(`测试结果: ${this.testResult}`)
        .fontSize(16)
        .margin({ bottom: 20 })

      Button('检测架构兼容性')
        .width('80%')
        .onClick(() => {
          this.detectArchitecture();
        })
        .margin({ bottom: 10 })

      Button('测试 JSBind 加载')
        .width('80%')
        .onClick(() => {
          this.testJSBindLoading();
        })
        .margin({ bottom: 10 })

      Button('测试 FFMpegUtils')
        .width('80%')
        .onClick(() => {
          this.testFFMpegUtils();
        })
        .margin({ bottom: 10 })

      Button('测试简单命令')
        .width('80%')
        .onClick(() => {
          this.testSimpleCommand();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(20)
  }

  /**
   * 检测架构兼容性
   */
  private detectArchitecture(): void {
    try {
      const compatibility = ArchitectureDetector.checkCompatibility();
      
      this.archInfo = `设备架构: ${compatibility.deviceArch}\n` +
                      `支持架构: ${compatibility.supportedArchs.join(', ')}\n` +
                      `兼容性: ${compatibility.isCompatible ? '✅ 兼容' : '❌ 不兼容'}`;
      
      console.info('[TestJSBind] 架构检测结果:\n' + 
                   ArchitectureDetector.getDiagnosticInfo());
      
      if (!compatibility.isCompatible) {
        this.jsbindStatus = '⚠️ 架构不兼容';
        this.testResult = '❌ 请使用 arm64-v8a 设备';
      }
    } catch (error) {
      const err = error as Error;
      this.archInfo = `❌ 检测失败: ${err.message}`;
      console.error('[TestJSBind] 架构检测失败:', error);
    }
  }

  /**
   * 测试 JSBind 是否正确加载
   */
  private testJSBindLoading(): void {
    try {
      // 检查 FFMpegUtils 是否存在
      if (!FFMpegUtils) {
        this.jsbindStatus = '❌ FFMpegUtils 未定义';
        return;
      }

      // 检查关键方法是否存在
      const hasExecute = typeof FFMpegUtils.executeFFmpegCommand === 'function';
      const hasShowLog = typeof FFMpegUtils.showLog === 'function';

      if (hasExecute && hasShowLog) {
        this.jsbindStatus = '✅ JSBind 加载成功';
        console.info('[TestJSBind] JSBind 加载成功');
      } else {
        this.jsbindStatus = `⚠️ 方法不完整 (execute: ${hasExecute}, showLog: ${hasShowLog})`;
        console.warn('[TestJSBind] 方法不完整');
      }
    } catch (error) {
      const err = error as Error;
      this.jsbindStatus = `❌ 加载失败: ${err.message}`;
      console.error('[TestJSBind] 加载失败:', error);
    }
  }

  /**
   * 测试 FFMpegUtils 基本功能
   */
  private testFFMpegUtils(): void {
    try {
      // 测试 showLog 方法
      FFMpegUtils.showLog(true);
      this.testResult = '✅ showLog 方法调用成功';
      console.info('[TestJSBind] showLog 调用成功');
    } catch (error) {
      const err = error as Error;
      this.testResult = `❌ 测试失败: ${err.message}`;
      console.error('[TestJSBind] 测试失败:', error);
    }
  }

  /**
   * 测试简单 FFmpeg 命令
   */
  private async testSimpleCommand(): Promise<void> {
    try {
      this.testResult = '⏳ 执行中...';
      
      // 执行一个简单的测试命令
      const result = await FFMpegUtils.executeFFmpegCommand({
        cmds: ['-version'],
        onFFmpegProgress: (progress: number) => {
          console.info(`[TestJSBind] 进度: ${progress}%`);
        },
        onFFmpegFail: (code: number, msg: string) => {
          console.error(`[TestJSBind] 失败: ${code} - ${msg}`);
          this.testResult = `❌ 命令失败: ${msg}`;
        },
        onFFmpegSuccess: () => {
          console.info('[TestJSBind] 命令成功');
          this.testResult = '✅ FFmpeg 命令执行成功';
        }
      });

      console.info(`[TestJSBind] 返回码: ${result}`);
      if (result === 0) {
        this.testResult = '✅ FFmpeg 工作正常';
      }
    } catch (error) {
      const err = error as Error;
      this.testResult = `❌ 执行异常: ${err.message}`;
      console.error('[TestJSBind] 执行异常:', error);
    }
  }
}
