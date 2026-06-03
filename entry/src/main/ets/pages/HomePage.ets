import { picker, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import fs from '@ohos.file.fs';
import { image } from '@kit.ImageKit';
import { promptAction } from '@kit.ArkUI';
import {FFmpegUtil} from "../utils/FFmpegUtil"
import { FFmpegCommandBuilder, FFmpegManager,TaskCallback } from '@prq/ffmpeg-tools';
import { media } from '@kit.MediaKit';
import { FFProgressMessageParser, FFmpeg } from '@sj/ffmpeg';



class MyCallback implements TaskCallback {
  onStart(): void {
    promptAction.showToast({
      message: '开始处理...',
      duration: 2000
    });
  }

  onProgress(progress: number): void {
    console.log('进度: ' + progress);
    return;
  }

  onSuccess(): void {
    promptAction.showToast({
      message: '处理完成',
      duration: 2000
    });
  }

  onFailure(): void {
    promptAction.showToast({
      message: '处理失败',
      duration: 2000
    });
  }

  onCancelled?(): void {
   promptAction.showToast({
      message: '已取消',
      duration: 2000
    });
  }

  onTimeout?(): void {
    promptAction.showToast({
      message: '处理超时',
      duration: 2000
    });
  }

  onError?(error: Error): void {
    promptAction.showToast({
      message: '处理错误: '+ error,
      duration: 2000
    });
  }
}




@Component
export struct HomePage {
  // FFmpeg配置相关状态
  @State enableHWaccel: boolean = false;
  @State scaleWidth: number = 0;
  @State scaleHeight: number = 0;
  @State fps: number = 30;
  @State videoBitrate: string = '2M';
  @State audioCodec: string = 'aac';
  @State audioBitrate: string = '128k';
  @State outputFormat: string = '';
  @State outputPath: string = '';
  
  // 文件选择相关状态
  @State selectedFileUri: string = ''
  @State fileName: string = ''
  @State fileSize: string = ''
  @State fileType: string = ''
  @State isMediaFile: boolean = false
  @State isLoading: boolean = false
  @State thumbnailPixelMap: image.PixelMap | null = null

  // 转码进度相关状态
  @State isTranscoding: boolean = false
  @State transcodeProgress: number = 0       // 0–100
  @State transcodeProgressText: string = ''  // 描述文字
  private transcodeStartMs: number = 0       // 发起转码的时间戳

  public static  codecs = ['aac', 'mp3', 'opus', 'vorbis'];

  // 获取UIAbilityContext
  private getAbilityContext(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  // 将URI转换为实际的文件系统路径（FFmpeg需要实际路径，不能识别file://协议）
  private decodeUriPath(uri: string): string {
    try {
      // 使用fileUri.FileUri将URI转换为实际的文件系统路径
      const fileUriObject = new fileUri.FileUri(uri);
      const actualPath = fileUriObject.path;
      
      console.info('URI转换: ' + uri + ' -> ' + actualPath);
      return actualPath;
    } catch (error) {
      console.error('URI转换失败: ' + JSON.stringify(error));
      // 转换失败时返回原始URI
      return uri;
    }
  }

  // 生成输出路径（基于输入路径修改后缀名）
  private generateOutputPath(inputPath: string): string {
    try {
      // 获取文件扩展名
      const lastDotIndex = inputPath.lastIndexOf('.');
      if (lastDotIndex === -1) {
        return inputPath + '_output';
      }
      
      // 提取文件名（不含扩展名）
      const basePath = inputPath.substring(0, lastDotIndex);
      
      // 使用用户选择的输出格式，如果没有选择则使用默认格式
      let outputExtension = this.outputFormat ? `.${this.outputFormat}` : '';
      
      // 如果没有设置输出格式，根据文件类型设置默认格式
      if (!outputExtension) {
        const extension = inputPath.substring(lastDotIndex);
        const extWithoutDot = extension.substring(1).toLowerCase();
        
        const videoExtensions = ['mp4', 'avi', 'mov', 'mkv'];
        const audioExtensions = ['mp3', 'wav', 'aac', 'flac', 'ogg'];
        const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
        
        // 视频文件默认输出为mp4
        if (videoExtensions.includes(extWithoutDot)) {
          outputExtension = '.mp4';
        }
        // 音频文件默认输出为mp3
        else if (audioExtensions.includes(extWithoutDot)) {
          outputExtension = '.mp3';
        }
        // 图片文件保持原格式
        else if (imageExtensions.includes(extWithoutDot)) {
          outputExtension = extension;
        }
        else {
          outputExtension = extension;
        }
      }
      
      return basePath + '_output' + outputExtension;
    } catch (error) {
      console.error('生成输出路径失败: ' + JSON.stringify(error));
      return inputPath + '_output';
    }
  }

  // 获取或创建沙箱工作目录（位于app临时目录，原生代码可访问）
  private ensureSandboxWorkDir(): string {
    const context = this.getAbilityContext();
    const workDir = `${context.tempDir}/ffmpeg_work`;
    console.info('[Sandbox] tempDir: ' + context.tempDir);
    try {
      fs.mkdirSync(workDir);
      console.info('[Sandbox] Work dir created: ' + workDir);
    } catch (e) {
      console.info('[Sandbox] Work dir ready (may already exist): ' + workDir);
    }
    return workDir;
  }

  // 将URI指向的文件拷贝到沙箱目录，返回沙箱路径
  private async copyInputToSandbox(uri: string): Promise<string> {
    const workDir = this.ensureSandboxWorkDir();
    const fileName = decodeURIComponent(uri.split('/').pop() || 'input');
    const sandboxPath = `${workDir}/${fileName}`;

    // 通过read/write方式拷贝（避免copyFileSync在fd→path场景下的兼容性问题）
    const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(srcFile.fd);
    console.info('[Sandbox] Source fd size: ' + stat.size);

    const buffer = new ArrayBuffer(stat.size);
    const bytesRead = fs.readSync(srcFile.fd, buffer);
    fs.closeSync(srcFile);
    console.info('[Sandbox] Read ' + bytesRead + ' bytes from URI');

    const dstFile = fs.openSync(sandboxPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    const bytesWritten = fs.writeSync(dstFile.fd, buffer);
    fs.closeSync(dstFile);
    console.info('[Sandbox] Written ' + bytesWritten + ' bytes to: ' + sandboxPath);

    // 验证文件是否写入成功
    const verifyStat = fs.statSync(sandboxPath);
    console.info('[Sandbox] Verified file exists, size: ' + verifyStat.size);

    return sandboxPath;
  }

  // 生成沙箱中的输出路径
  private getSandboxOutputPath(): string {
    const workDir = this.ensureSandboxWorkDir();
    const outputFileName = this.outputPath.split('/').pop() || 'output';
    return `${workDir}/${outputFileName}`;
  }

  // FFmpeg执行成功后，将输出文件从沙箱拷贝到用户可见位置
  private async saveOutputFile(sandboxOutput: string): Promise<string> {
    const userOutputPath = this.decodeUriPath(this.outputPath);
    try {
      fs.copyFileSync(sandboxOutput, userOutputPath);
      console.info('Output saved to: ' + userOutputPath);
      return userOutputPath;
    } catch (e) {
      // 用户目录不可写时回退到app的files目录
      const context = this.getAbilityContext();
      const outputFileName = sandboxOutput.split('/').pop() || 'output';
      const fallbackPath = `${context.filesDir}/${outputFileName}`;
      fs.copyFileSync(sandboxOutput, fallbackPath);
      console.info('Output saved to fallback: ' + fallbackPath);
      return fallbackPath;
    }
  }

  // 清理沙箱临时文件
  private cleanupSandboxFiles(...paths: string[]) {
    for (const path of paths) {
      try {
        fs.unlinkSync(path);
      } catch (e) {
        // 文件不存在则忽略
      }
    }
  }

  // 格式化文件大小
  private formatFileSize(bytes: number): string {
    if (bytes === 0) return '0 B';
    
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  // 获取文件真实大小
  private async getFileSize(fileUri: string): Promise<string> {
    try {
      const stat = await fs.stat(fileUri);
      return this.formatFileSize(stat.size);
    } catch (error) {
      console.error('获取文件大小失败: ' + JSON.stringify(error));
      return '未知大小';
    }
  }

  // 打开文件选择器（仅媒体文件）
  private async openFilePicker() {
    try {
      this.isLoading = true;
      const context = this.getAbilityContext();
      const documentPicker = new picker.DocumentViewPicker(context);
      
      // 配置文件选择选项，过滤媒体文件
      const documentSelectOptions = new picker.DocumentSelectOptions();
      // 设置文件过滤器，仅选择媒体文件
      documentSelectOptions.fileSuffixFilters = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', 
                                                   '.mp4', '.avi', '.mov', '.mkv', 
                                                   '.mp3', '.wav', '.aac', '.flac', '.ogg'];
      
      const result = await documentPicker.select(documentSelectOptions);
      
      if (result && result.length > 0) {
        const fileUri = result[0];
        this.selectedFileUri = fileUri;
        
        // 解析文件信息
        await this.parseFileInfo(fileUri);
      }
    } catch (error) {
      console.error('文件选择失败: ' + JSON.stringify(error));
      promptAction.showToast({
        message: '文件选择失败，请重试',
        duration: 2000
      });
    } finally {
      this.isLoading = false;
    }
  }

  // 解析文件信息
  private async parseFileInfo(fileUri: string) {
    try {
      // 从URI中提取文件名并解码
      const uriParts = fileUri.split('/');
      const encodedFileName = uriParts[uriParts.length - 1];
      this.fileName = decodeURIComponent(encodedFileName);
      
      // 获取文件真实大小
      this.fileSize = await this.getFileSize(fileUri);
      
      // 根据文件扩展名判断文件类型
      const fileExtension = this.fileName.split('.').pop()?.toLowerCase() || '';
      
      // 判断是否为媒体文件
      const mediaExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 
                               'mp4', 'avi', 'mov', 'mkv', 
                               'mp3', 'wav', 'aac', 'flac', 'ogg'];
      this.isMediaFile = mediaExtensions.includes(fileExtension);
      
      // 设置文件类型显示文本
      if (this.isMediaFile) {
        const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
        const videoExtensions = ['mp4', 'avi', 'mov', 'mkv'];
        const audioExtensions = ['mp3', 'wav', 'aac', 'flac', 'ogg'];
        
        if (imageExtensions.includes(fileExtension)) {
          this.fileType = '图片文件';
          // 设置默认输出格式为原格式
          this.outputFormat = fileExtension === 'jpeg' ? 'jpg' : fileExtension;
          // 生成缩略图
          await this.generateThumbnail(fileUri);
        } else if (videoExtensions.includes(fileExtension)) {
          this.fileType = '视频文件';
          // 设置默认输出格式为mp4
          this.outputFormat = 'mp4';
          // 生成视频缩略图并获取视频宽高
          await this.generateVideoThumbnail(fileUri);
        } else if (audioExtensions.includes(fileExtension)) {
          this.fileType = '音频文件';
          // 设置默认输出格式为mp3
          this.outputFormat = 'mp3';
        } else {
          this.fileType = '媒体文件';
          this.outputFormat = fileExtension;
        }
      } else {
        this.fileType = '其他文件';
        this.outputFormat = fileExtension;
      }
      
      console.info('文件信息解析完成:');
      console.info('文件名: ' + this.fileName);
      console.info('文件大小: ' + this.fileSize);
      console.info('文件类型: ' + this.fileType);
      
      // 生成输出路径
      this.outputPath = this.generateOutputPath(fileUri);
      console.info('输出路径: ' + this.outputPath);
      
    } catch (error) {
      console.error('解析文件信息失败: ' + JSON.stringify(error));
      this.fileSize = '未知大小';
      
      // 解码失败时使用原始文件名
      const uriParts = fileUri.split('/');
      this.fileName = uriParts[uriParts.length - 1];
    }
  }

  // 生成缩略图（仅图片文件）
  private async generateThumbnail(fileUri: string) {
    let imageSource: image.ImageSource | undefined = undefined;
    try {
      // 打开文件获取文件描述符
      const file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY);
      
      // 创建 ImageSource
      imageSource = image.createImageSource(file.fd);
      
      // 获取图片信息
      const imageInfo = await imageSource.getImageInfo(0);
      
      // 保存原始图片尺寸到缩放配置
      this.scaleWidth = imageInfo.size.width;
      this.scaleHeight = imageInfo.size.height;
      
      // 计算缩略图尺寸（保持宽高比，最大边长为200）
      const maxSize = 200;
      let width = imageInfo.size.width;
      let height = imageInfo.size.height;
      
      if (width > height) {
        height = Math.floor(height * maxSize / width);
        width = maxSize;
      } else {
        width = Math.floor(width * maxSize / height);
        height = maxSize;
      }
      
      // 创建缩略图
      const decodingOptions: image.DecodingOptions = {
        desiredSize: { width: width, height: height }
      };
      
      this.thumbnailPixelMap = await imageSource.createPixelMap(decodingOptions);
      
      // 关闭文件
      fs.closeSync(file);
    } catch (error) {
      console.error('生成缩略图失败: ' + JSON.stringify(error));
    } finally {
      // 释放 ImageSource 资源
      if (imageSource) {
        imageSource.release();
      }
    }
  }

  // 生成视频缩略图并获取视频宽高
  private async generateVideoThumbnail(fileUri: string) {
    let file: fs.File | undefined = undefined;
    let avImageGenerator: media.AVImageGenerator | undefined = undefined;
    let avMetadataExtractor: media.AVMetadataExtractor | undefined = undefined;
    
    try {
      // 打开文件获取文件描述符
      file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY);
      
      // 创建 AVMetadataExtractor 获取视频元数据（宽高）
      avMetadataExtractor = await media.createAVMetadataExtractor();
      avMetadataExtractor.fdSrc = { fd: file.fd };
      
      // 获取视频元数据
      const metadata = await avMetadataExtractor.fetchMetadata();
      
      // 设置视频帧宽高到缩放配置
      if (metadata.videoWidth && metadata.videoHeight) {
        this.scaleWidth = parseInt(metadata.videoWidth);
        this.scaleHeight = parseInt(metadata.videoHeight);
        console.info('视频尺寸: ' + this.scaleWidth + ' x ' + this.scaleHeight);
      }
      
      // 释放 AVMetadataExtractor
      await avMetadataExtractor.release();
      avMetadataExtractor = undefined;
      
      // 重新打开文件描述符（不能复用同一个fd）
      fs.closeSync(file);
      file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY);
      
      // 创建 AVImageGenerator 获取视频缩略图
      avImageGenerator = await media.createAVImageGenerator();
      avImageGenerator.fdSrc = { fd: file.fd };
      
      // 计算缩略图尺寸（保持宽高比，最大边长为200）
      const maxSize = 200;
      let thumbWidth = this.scaleWidth || 300;
      let thumbHeight = this.scaleHeight || 300;
      
      if (thumbWidth > thumbHeight) {
        thumbHeight = Math.floor(thumbHeight * maxSize / thumbWidth);
        thumbWidth = maxSize;
      } else {
        thumbWidth = Math.floor(thumbWidth * maxSize / thumbHeight);
        thumbHeight = maxSize;
      }
      
      // 获取视频首帧缩略图
      const timeUs = 0; // 首帧
      const queryOption = media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC;
      const param: media.PixelMapParams = {
        width: thumbWidth,
        height: thumbHeight
      };
      
      this.thumbnailPixelMap = await avImageGenerator.fetchFrameByTime(timeUs, queryOption, param);
      console.info('视频缩略图生成成功');
      
    } catch (error) {
      console.error('生成视频缩略图失败: ' + JSON.stringify(error));
    } finally {
      // 释放资源
      if (avImageGenerator) {
        try {
          await avImageGenerator.release();
        } catch (e) {
          console.error('释放 AVImageGenerator 失败: ' + JSON.stringify(e));
        }
      }
      if (avMetadataExtractor) {
        try {
          await avMetadataExtractor.release();
        } catch (e) {
          console.error('释放 AVMetadataExtractor 失败: ' + JSON.stringify(e));
        }
      }
      if (file) {
        try {
          fs.closeSync(file);
        } catch (e) {
          console.error('关闭文件失败: ' + JSON.stringify(e));
        }
      }
    }
  }

  // 获取媒体文件时长（秒），优先用沙箱路径，失败回退到URI
  private async getMediaDuration(filePath: string): Promise<number> {
    let file: fs.File | undefined;
    let extractor: media.AVMetadataExtractor | undefined;
    try {
      file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = { fd: file.fd };
      const metadata = await extractor.fetchMetadata();
      if (metadata.duration) {
        const durationMs = parseInt(metadata.duration);
        if (durationMs > 0) {
          console.info('媒体时长: ' + durationMs + 'ms');
          return durationMs / 1000;
        }
      }
    } catch (e) {
      console.error('获取时长失败: ' + JSON.stringify(e));
    } finally {
      if (extractor) {
        try { await extractor.release(); } catch (e) {}
      }
      if (file) {
        try { fs.closeSync(file); } catch (e) {}
      }
    }
    return 0;
  }

  // 格式化秒数为 HH:MM:SS
  private formatDuration(sec: number): string {
    if (sec <= 0) return '00:00';
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = Math.floor(sec % 60);
    if (h > 0) {
      return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
    }
    return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
  }

  // 清除选择
  private clearSelection() {
    this.selectedFileUri = '';
    this.fileName = '';
    this.fileSize = '';
    this.fileType = '';
    this.isMediaFile = false;
    this.isLoading = false;
    this.thumbnailPixelMap = null;
    this.outputFormat = '';
    this.outputPath = '';
    
    // 重置配置项为默认值
    this.enableHWaccel = true;
    this.scaleWidth = 0;
    this.scaleHeight = 0;
    this.fps = 30;
    this.videoBitrate = '2M';
    this.audioCodec = 'aac';
    this.audioBitrate = '128k';
    
    // 显示清除成功提示
    promptAction.showToast({
      message: '已清除选择',
      duration: 2000
    });
  }

  // 获取缩略图显示内容
  private getThumbnailContent(): string {
    if (!this.selectedFileUri) {
      return this.isLoading ? '⏳' : '+';
    }
    
    if (this.isMediaFile) {
      return '🎞️';
    } else {
      return '📄';
    }
  }

  build() {
    Column() {
      // 标题
      Text('首页')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ top: 32, bottom: 12 })
        .alignSelf(ItemAlign.Start)
        .padding({ left: 16, right: 16 })

      // 转码进度条
      if (this.isTranscoding) {
        Column() {
          Progress({
            value: this.transcodeProgress,
            total: 100,
            type: ProgressType.Linear
          })
            .width('100%')
            .height(6)
            .style({ strokeWidth: 6, strokeRadius: 3 })
            .color('#1890FF')
            .backgroundColor('#E8E8E8')

          Text(this.transcodeProgressText)
            .fontSize(13)
            .fontColor('#666666')
            .margin({ top: 6 })

          Text(this.isTranscoding ? this.transcodeProgress + '%' : '')
            .fontSize(16)
            .fontColor('#1890FF')
            .fontWeight(FontWeight.Medium)
            .margin({ top: 4 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 20 })
      }

      // 文件选择区域
      Column() {
        // 圆角矩形 - 文件选择按钮
        Column() {
          if (this.isLoading) {
            LoadingProgress()
              .width(32)
              .height(32)
              .color('#1890FF')
          } else if (this.thumbnailPixelMap) {
            // 显示图片缩略图
            Image(this.thumbnailPixelMap)
              .width(120)
              .height(120)
              .objectFit(ImageFit.Cover)
              .borderRadius(16)
          } else {
            Text(this.getThumbnailContent())
              .fontSize(48)
              .fontColor(this.selectedFileUri ? '#666666' : '#999999')
              .fontWeight(FontWeight.Medium)
          }
        }
        .width(120)
        .height(120)
        .backgroundColor(this.selectedFileUri ? '#F0F8FF' : (this.isLoading ? '#F8F8F8' : '#F5F5F5'))
        .borderRadius(16)
        .border({
          width: this.selectedFileUri ? 2 : 1,
          color: this.selectedFileUri ? '#1890FF' : (this.isLoading ? '#CCCCCC' : '#E0E0E0'),
          style: BorderStyle.Solid
        })
        .onClick(() => {
          if (!this.isLoading) {
            this.openFilePicker();
          }
        })

        // 文件信息显示区域
        if (this.selectedFileUri) {
          Column() {
            Text(this.fileName)
              .fontSize(16)
              .fontColor('#333333')
              .fontWeight(FontWeight.Medium)
              .margin({ top: 12 })
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
            
            Text(`${this.fileType} | ${this.fileSize}`)
              .fontSize(14)
              .fontColor('#666666')
              .margin({ top: 4 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 16 })
        } else if (this.isLoading) {
          Text('正在加载文件信息...')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 16 })
        } else {
          Text('点击选择媒体文件')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 16 })
        }
      }
      .width('100%')
      .padding(20)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .margin({ left: 16, right: 16, bottom: 20 })
      .alignItems(HorizontalAlign.Center)

      // 清除选择按钮
      if (this.selectedFileUri) {
        Row(){
          Button('清除选择', { type: ButtonType.Normal })
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#FF4D4F')
            .borderRadius(6)
            .width(120)
            .height(36)
            .margin({ bottom: 20 })
            .onClick(() => {
              this.clearSelection();
            })
          Button('执行转码')
            .fontSize(14)
            .fontColor('#333333')
            .backgroundColor('#F5F5F5')
            .borderRadius(6)
            .width(120)
            .height(36)
            .margin({ bottom: 20 })
            .onClick(() => {
              if (this.selectedFileUri){
                if (this.fileType === '视频文件') {
                  this.execV();
                }
                else if (this.fileType === '音频文件') {
                  this.execA();
                }
                else {
                  this.execI();
                }

              }
            })
        }
        .justifyContent(FlexAlign.SpaceEvenly)

      }

      // 媒体文件配置项区域
      if (this.selectedFileUri && this.isMediaFile) {
        Column() {
          // 配置标题
          Text('配置选项')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .margin({ bottom: 16 })
            .alignSelf(ItemAlign.Start)

          // 可滚动的配置项区域
          Scroll() {
            Column() {
              // 硬件加速开关（仅视频文件）
              if (this.fileType === '视频文件') {
                Row() {
                  Text('硬件加速')
                    .fontSize(14)
                    .fontColor('#333333')
                    .layoutWeight(1)


                  Toggle({ type: ToggleType.Switch, isOn: this.enableHWaccel })
                    .size({ width: 32, height: 16 })
                    .onChange((isOn: boolean) => {
                      this.enableHWaccel = isOn;
                      promptAction.showToast({
                        message: `硬件加速 ${isOn ? '已启用' : '已禁用'} \n注意：x86_64设备可能不支持硬件加速`,
                        duration: 2000
                      });
                    })
                    .selectedColor('#1890FF')
                }
                .width('100%')
                .backgroundColor('#FFFFFF')
                .padding(16)
                .borderRadius(12)
                .margin({ bottom: 12 })
              }

              // 缩放配置（图片和视频文件）
              if (this.fileType === '图片文件' || this.fileType === '视频文件') {
                Row() {
                  Text('缩放尺寸')
                    .fontSize(14)
                    .fontColor('#333333')
                    .layoutWeight(1)

                  Row() {
                    TextInput({ text: this.scaleWidth.toString(), placeholder: '宽' })
                      .width('40%')
                      .height(36)
                      .fontSize(12)
                      .type(InputType.Number)
                      .onChange((value: string) => {
                        const num = parseInt(value);
                        if (!isNaN(num) && num > 0) {
                          this.scaleWidth = num;
                        }
                      })

                    Text(' × ')
                      .fontSize(14)
                      .fontColor('#666666')
                      .margin({ left: 4, right: 4 })

                    TextInput({ text: this.scaleHeight.toString(), placeholder: '高' })
                      .width('40%')
                      .height(36)
                      .fontSize(12)
                      .type(InputType.Number)
                      .onChange((value: string) => {
                        const num = parseInt(value);
                        if (!isNaN(num) && num > 0) {
                          this.scaleHeight = num;
                        }
                      })
                  }
                  .width('55%')
                  .justifyContent(FlexAlign.End)
                }
                .width('100%')
                .backgroundColor('#FFFFFF')
                .padding(16)
                .borderRadius(12)
                .margin({ bottom: 12 })
              }

              // FPS配置（仅视频文件）
              if (this.fileType === '视频文件') {
                Row() {
                  Text(`帧率 (FPS): ${this.fps}`)
                    .fontSize(14)
                    .fontColor('#333333')
                    .layoutWeight(1)

                  Slider({
                    value: this.fps,
                    min: 1,
                    max: 120,
                    step: 1,
                    style: SliderStyle.InSet,
                  })
                    .onChange((value: number) => {
                      this.fps = Math.round(value);
                    })
                    .width('55%')
                    .blockColor('#1890FF')
                    .trackColor('#E0E0E0')
                    .selectedColor('#1890FF')
                }
                .width('100%')
                .backgroundColor('#FFFFFF')
                .padding(16)
                .borderRadius(12)
                .margin({ bottom: 12 })
              }

              // 视频码率配置（仅视频文件）
              if (this.fileType === '视频文件') {
                Row() {

                  Text('视频码率')
                    .fontSize(14)
                    .fontColor('#333333')
                    .layoutWeight(1)

                  TextInput({ text: this.videoBitrate, placeholder: '如: 2M, 2000k' })
                    .width('55%')
                    .height(36)
                    .fontSize(12)
                    .onChange((value: string) => {
                      this.videoBitrate = value;
                    })
                }
                .width('100%')
                .backgroundColor('#FFFFFF')
                .padding(16)
                .borderRadius(12)
                .margin({ bottom: 12 })
                .id('videorate')
              }

              // 音频编码配置（视频和音频文件）
              if (this.fileType === '视频文件' || this.fileType === '音频文件') {
                Row() {
                  Text('音频编码')
                    .fontSize(14)
                    .fontColor('#333333')
                    .layoutWeight(1)

                  Row() {
                    Text(this.audioCodec)
                      .fontSize(12)
                      .fontColor('#333333')
                      .padding({ left: 12, right: 8 })
                    
                    Select([
                      { value: 'aac' },
                      { value: 'mp3' },
                      { value: 'opus' },
                      { value: 'vorbis' }
                    ])
                      .selected(this.audioCodec === 'aac' ? 0 : 
                                this.audioCodec === 'mp3' ? 1 : 
                                this.audioCodec === 'opus' ? 2 : 3)
                      .value(this.audioCodec)
                      .font({ size: 12 })
                      .fontColor('#333333')
                      .selectedOptionFont({ size: 12 })
                      .optionFont({ size: 12 })
                      .onSelect((index: number) => {

                        this.audioCodec = HomePage.codecs[index];
                      })
                  }
                  .width('55%')
                  .justifyContent(FlexAlign.End)
                }
                .width('100%')
                .backgroundColor('#FFFFFF')
                .padding(16)
                .borderRadius(12)
                .margin({ bottom: 12 })
              }

              // 音频码率配置（视频和音频文件）
              if (this.fileType === '视频文件' || this.fileType === '音频文件') {
                Row() {
                  Text('音频码率')
                    .fontSize(14)
                    .fontColor('#333333')
                    .layoutWeight(1)

                  TextInput({ text: this.audioBitrate, placeholder: '如: 128k, 192k' })
                    .width('55%')
                    .height(36)
                    .fontSize(12)
                    .onChange((value: string) => {
                      this.audioBitrate = value;
                    })
                }
                .width('100%')
                .backgroundColor('#FFFFFF')
                .padding(16)
                .borderRadius(12)
                .margin({ bottom: 12 })
              }

              // 输出格式配置（所有文件类型）
              Row() {
                Text('输出格式')
                  .fontSize(14)
                  .fontColor('#333333')
                  .layoutWeight(1)

                Row() {
                  Text(this.outputFormat.toUpperCase())
                    .fontSize(12)
                    .fontColor('#333333')
                    .padding({ left: 12, right: 8 })
                  
                  // 视频文件格式选择
                  if (this.fileType === '视频文件') {
                    Select([
                      { value: 'MP4' },
                      { value: 'AVI' },
                      { value: 'MOV' },
                      { value: 'MKV' },
                      { value: 'MP3' }
                    ])
                      .selected(this.outputFormat === 'mp4' ? 0 : 
                                this.outputFormat === 'avi' ? 1 : 
                                this.outputFormat === 'mov' ? 2 :
                                this.outputFormat === 'mkv' ? 3 : 4)
                      .value(this.outputFormat.toUpperCase())
                      .font({ size: 12 })
                      .fontColor('#333333')
                      .selectedOptionFont({ size: 12 })
                      .optionFont({ size: 12 })
                      .onSelect((index: number) => {
                        const formats = ['mp4', 'avi', 'mov', 'mkv','mp3'];
                        this.outputFormat = formats[index];
                        if (this.outputFormat === 'mp3'){
                          this.audioCodec = 'mp3';
                          promptAction.showToast({duration:3000,message:'选择mp3格式则放弃视频码率等设置'})
                        }
                        // 更新输出路径
                        this.outputPath = this.generateOutputPath(this.selectedFileUri);
                      })
                  }
                  // 图片文件格式选择
                  else if (this.fileType === '图片文件') {
                    Select([
                      { value: 'JPG' },
                      { value: 'PNG' },
                      { value: 'GIF' },
                      { value: 'BMP' },
                      { value: 'WEBP' }
                    ])
                      .selected(this.outputFormat === 'jpg' ? 0 : 
                                this.outputFormat === 'png' ? 1 : 
                                this.outputFormat === 'gif' ? 2 : 
                                this.outputFormat === 'bmp' ? 3 : 4)
                      .value(this.outputFormat.toUpperCase())
                      .font({ size: 12 })
                      .fontColor('#333333')
                      .selectedOptionFont({ size: 12 })
                      .optionFont({ size: 12 })
                      .onSelect((index: number) => {
                        const formats = ['jpg', 'png', 'gif', 'bmp', 'webp'];
                        this.outputFormat = formats[index];
                        // 更新输出路径
                        this.outputPath = this.generateOutputPath(this.selectedFileUri);
                      })
                  }
                  // 音频文件格式选择
                  else if (this.fileType === '音频文件') {
                    Select([
                      { value: 'MP3' },
                      { value: 'WAV' },
                      { value: 'AAC' },
                      { value: 'FLAC' },
                      { value: 'OGG' }
                    ])
                      .selected(this.outputFormat === 'mp3' ? 0 : 
                                this.outputFormat === 'wav' ? 1 : 
                                this.outputFormat === 'aac' ? 2 : 
                                this.outputFormat === 'flac' ? 3 : 4)
                      .value(this.outputFormat.toUpperCase())
                      .font({ size: 12 })
                      .fontColor('#333333')
                      .selectedOptionFont({ size: 12 })
                      .optionFont({ size: 12 })
                      .onSelect((index: number) => {
                        const formats = ['mp3', 'wav', 'aac', 'flac', 'ogg'];
                        this.outputFormat = formats[index];
                        // 更新输出路径
                        this.outputPath = this.generateOutputPath(this.selectedFileUri);
                      })
                  }
                }
                .width('55%')
                .justifyContent(FlexAlign.End)
              }
              .width('100%')
              .backgroundColor('#FFFFFF')
              .padding(16)
              .borderRadius(12)
              .margin({ bottom: 12 })

              // 输出路径显示（所有文件类型）
              Column() {
                Row() {
                  Text('输出路径')
                    .fontSize(14)
                    .fontColor('#333333')
                    .layoutWeight(1)
                }
                .width('100%')
                .margin({ bottom: 8 })

                Text(this.outputPath || '请先选择输入文件')
                  .fontSize(12)
                  .fontColor('#666666')
                  .width('100%')
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding(12)
                  .backgroundColor('#F8F8F8')
                  .borderRadius(8)
              }
              .width('100%')
              .backgroundColor('#FFFFFF')
              .padding(16)
              .borderRadius(12)
              .margin({ bottom: 12 })
            }
            .width('100%')
            .padding(16)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .scrollBarColor('#CCCCCC')
          .scrollBarWidth(4)
          .edgeEffect(EdgeEffect.Spring)
          .backgroundColor('#F8F8F8')
        }
        .width('100%')
        .height(350)
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .margin({ left: 16, right: 16, bottom: 20 })
      }

    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#F8F8F8')
  }

  async execV() {
    try {
      promptAction.showToast({ message: '正在准备文件...', duration: 2000 });

      // 将输入文件拷贝到沙箱（原生FFmpeg只能访问app沙箱路径）
      const sandboxInput = await this.copyInputToSandbox(this.selectedFileUri);
      const sandboxOutput = this.getSandboxOutputPath();
      console.info('[Sandbox] Input: ' + sandboxInput);
      console.info('[Sandbox] Output: ' + sandboxOutput);

      // 获取视频总时长用于进度计算
      const totalDurationSec = await this.getMediaDuration(sandboxInput);

      const cmd = new FFmpegCommandBuilder();

      if (this.outputFormat === 'mp3') {
        cmd
          .input(sandboxInput)
          .output(sandboxOutput)
          .audioCodec(this.audioCodec)
          .audioBitrate(this.audioBitrate);
      } else {
        cmd
          .input(sandboxInput)
          .output(sandboxOutput)
          .scale(this.scaleWidth, this.scaleHeight)
          .fps(this.fps)
          .audioCodec(this.audioCodec)
          .audioBitrate(this.audioBitrate)
          .videoBitrate(this.videoBitrate);
      }

      if (this.enableHWaccel) {
        cmd.hwaccel();
      }
      const cmdStrA = cmd.build();
      console.log(cmd.buildString());

      // 开始转码，更新进度条
      this.isTranscoding = true;
      this.transcodeProgress = 0;
      this.transcodeProgressText = '准备中...';
      this.transcodeStartMs = Date.now();

      const success = await FFmpegUtil.exec(cmdStrA, 18000, new MyCallback(),
        (currentSec: number) => {
          const elapsedSec = Math.floor((Date.now() - this.transcodeStartMs) / 1000);
          if (totalDurationSec > 0) {
            const pct = Math.min(Math.round((currentSec / totalDurationSec) * 100), 99);
            this.transcodeProgress = pct;
            this.transcodeProgressText = '已用时 ' + this.formatDuration(elapsedSec) + '  |  进度 ' + this.formatDuration(currentSec) + ' / ' + this.formatDuration(totalDurationSec);
          } else {
            this.transcodeProgressText = '已用时 ' + this.formatDuration(elapsedSec);
          }
        });

      this.transcodeProgress = success ? 100 : 0;
      this.isTranscoding = false;

      if (success) {
        const savedPath = await this.saveOutputFile(sandboxOutput);
        promptAction.showToast({
          message: '已保存: ' + (savedPath.split('/').pop() || 'output'),
          duration: 3000
        });
      }

      this.cleanupSandboxFiles(sandboxInput, sandboxOutput);
    } catch (error) {
      this.isTranscoding = false;
      const err = error as Error;
      console.error('execV failed: ' + JSON.stringify(err));
      promptAction.showToast({ message: '处理失败: ' + err.message, duration: 3000 });
    }
  };

  async execA() {
    try {
      promptAction.showToast({ message: '正在准备文件...', duration: 2000 });

      const sandboxInput = await this.copyInputToSandbox(this.selectedFileUri);
      const sandboxOutput = this.getSandboxOutputPath();
      console.info('[Sandbox] Input: ' + sandboxInput);
      console.info('[Sandbox] Output: ' + sandboxOutput);

      const totalDurationSec = await this.getMediaDuration(sandboxInput);

      const cmd = new FFmpegCommandBuilder()
        .input(sandboxInput)
        .output(sandboxOutput)
        .audioCodec(this.audioCodec)
        .audioBitrate(this.audioBitrate);

      const cmdStrA = cmd.build();
      console.log(cmd.buildString());

      this.isTranscoding = true;
      this.transcodeProgress = 0;
      this.transcodeProgressText = '准备中...';
      this.transcodeStartMs = Date.now();

      const success = await FFmpegUtil.exec(cmdStrA, 18000, new MyCallback(),
        (currentSec: number) => {
          const elapsedSec = Math.floor((Date.now() - this.transcodeStartMs) / 1000);
          if (totalDurationSec > 0) {
            const pct = Math.min(Math.round((currentSec / totalDurationSec) * 100), 99);
            this.transcodeProgress = pct;
            this.transcodeProgressText = '已用时 ' + this.formatDuration(elapsedSec) + '  |  进度 ' + this.formatDuration(currentSec) + ' / ' + this.formatDuration(totalDurationSec);
          } else {
            this.transcodeProgressText = '已用时 ' + this.formatDuration(elapsedSec);
          }
        });

      this.transcodeProgress = success ? 100 : 0;
      this.isTranscoding = false;

      if (success) {
        const savedPath = await this.saveOutputFile(sandboxOutput);
        promptAction.showToast({
          message: '已保存: ' + (savedPath.split('/').pop() || 'output'),
          duration: 3000
        });
      }

      this.cleanupSandboxFiles(sandboxInput, sandboxOutput);
    } catch (error) {
      this.isTranscoding = false;
      const err = error as Error;
      console.error('execA failed: ' + JSON.stringify(err));
      promptAction.showToast({ message: '处理失败: ' + err.message, duration: 3000 });
    }
  }

  async execI() {
    try {
      promptAction.showToast({ message: '正在准备文件...', duration: 2000 });

      const sandboxInput = await this.copyInputToSandbox(this.selectedFileUri);
      const sandboxOutput = this.getSandboxOutputPath();
      console.info('[Sandbox] Input: ' + sandboxInput);
      console.info('[Sandbox] Output: ' + sandboxOutput);

      const cmd = new FFmpegCommandBuilder()
        .input(sandboxInput)
        .output(sandboxOutput)
        .scale(this.scaleWidth, this.scaleHeight);

      cmd.arg("-frames:v", "1");

      const cmdStrA = cmd.build();
      console.log(cmd.buildString());

      this.isTranscoding = true;
      this.transcodeProgress = 0;
      this.transcodeProgressText = '处理中...';
      this.transcodeStartMs = Date.now();

      const success = await FFmpegUtil.exec(cmdStrA, 18000, new MyCallback(),
        (currentSec: number) => {
          const elapsedSec = Math.floor((Date.now() - this.transcodeStartMs) / 1000);
          this.transcodeProgressText = '已用时 ' + this.formatDuration(elapsedSec);
        });

      this.transcodeProgress = success ? 100 : 0;
      this.isTranscoding = false;

      if (success) {
        const savedPath = await this.saveOutputFile(sandboxOutput);
        promptAction.showToast({
          message: '已保存: ' + (savedPath.split('/').pop() || 'output'),
          duration: 3000
        });
      }

      this.cleanupSandboxFiles(sandboxInput, sandboxOutput);
    } catch (error) {
      this.isTranscoding = false;
      const err = error as Error;
      console.error('execI failed: ' + JSON.stringify(err));
      promptAction.showToast({ message: '处理失败: ' + err.message, duration: 3000 });
    }
  }
}
