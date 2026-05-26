import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import fs from '@ohos.file.fs';
import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';

@Component
export struct DiscoverPage {
  @State thumbnailPixelMap: image.PixelMap | null = null;
  @State searchText: string = ''
  @State selectedFileUri: string = ''
  @State fileName: string = ''
  @State fileSize: string = ''
  @State fileType: string = ''
  @State isMediaFile: boolean = false
  @State isLoading: boolean = false
  @State metadataText: string = ''
  @State scaleWidth: number = 0;
  @State scaleHeight: number = 0;

  // 获取UIAbilityContext
  private getAbilityContext(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
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
      // 使用fs.stat获取文件统计信息
      const stat = await fs.stat(fileUri);
      return this.formatFileSize(stat.size);
    } catch (error) {
      console.error('获取文件大小失败: ' + JSON.stringify(error));
      return '未知大小';
    }
  }

  // 打开文件选择器
  private async openFilePicker() {
    try {
      this.isLoading = true;
      const context = this.getAbilityContext();
      const documentPicker = new picker.DocumentViewPicker(context);
      
      const result = await documentPicker.select();
      
      if (result && result.length > 0) {
        const fileUri = result[0];
        this.selectedFileUri = fileUri;
        
        // 解析文件信息
        await this.parseFileInfo(fileUri);
      }
    } catch (error) {
      console.error('文件选择失败: ' + JSON.stringify(error));
    } finally {
      this.isLoading = false;
    }
  }

  // 解析文件信息
  private async parseFileInfo(fileUri: string) {
    try {
      // 从URI中提取文件名并使用内置decodeURIComponent解码
      const uriParts = fileUri.split('/');
      const encodedFileName = uriParts[uriParts.length - 1];
      
      // 使用ArkTS内置的decodeURIComponent函数
      this.fileName = decodeURIComponent(encodedFileName);
      
      // 获取文件真实大小
      this.fileSize = await this.getFileSize(fileUri);
      
      // 根据文件扩展名判断文件类型
      const fileExtension = this.fileName.split('.').pop()?.toLowerCase() || '';
      
      // 判断是否为媒体文件
      const mediaExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'mp4', 'avi', 'mov', 'mkv', 'mp3', 'wav', 'aac', 'flac', 'ogg'];
      this.isMediaFile = mediaExtensions.includes(fileExtension);
      
      // 如果是媒体文件，提取元数据
      if (this.isMediaFile) {
        this.extractMetadata(fileUri).catch((err: BusinessError) => console.error('提取元数据失败:', err));
      }
      
      // 设置文件类型显示文本
      if (this.isMediaFile) {
        const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
        const videoExtensions = ['mp4', 'avi', 'mov', 'mkv'];
        const audioExtensions = ['mp3', 'wav', 'aac', 'flac', 'ogg'];
        
        if (imageExtensions.includes(fileExtension)) {
          this.fileType = '图片文件';
          // 生成图片缩略图
          await this.generateThumbnail(fileUri);
        } else if (videoExtensions.includes(fileExtension)) {
          this.fileType = '视频文件';
          // 生成视频缩略图
          await this.generateVideoThumbnail(fileUri);
        } else if (audioExtensions.includes(fileExtension)) {
          this.fileType = '音频文件';
        } else {
          this.fileType = '媒体文件';
        }
      } else {
        const documentExtensions = ['txt', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'];
        const archiveExtensions = ['zip', 'rar', '7z', 'tar', 'gz'];
        
        if (documentExtensions.includes(fileExtension)) {
          this.fileType = '文档文件';
        } else if (archiveExtensions.includes(fileExtension)) {
          this.fileType = '压缩文件';
        } else {
          this.fileType = '其他文件';
        }
      }
      
      console.info('文件信息解析完成:');
      console.info('文件名: ' + this.fileName);
      console.info('文件大小: ' + this.fileSize);
      console.info('文件类型: ' + this.fileType);
      
    } catch (error) {
      console.error('解析文件信息失败: ' + JSON.stringify(error));
      this.fileSize = '未知大小';
      
      // 解码失败时使用原始文件名
      const uriParts = fileUri.split('/');
      this.fileName = uriParts[uriParts.length - 1];
    }
  }

  // 提取媒体文件元数据
  private async extractMetadata(fileUri: string) {
    try {
      // 判断是否为图片文件
      const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif', 'dng'];
      const fileExtension = this.fileName.split('.').pop()?.toLowerCase() || '';
      const isImage = imageExtensions.includes(fileExtension);
      
      if (isImage) {
        // 使用 ImageSource 提取图片元数据
        await this.extractImageMetadata(fileUri);
      } else {
        // 使用 AVMetadataExtractor 提取音视频元数据
        await this.extractAVMetadata(fileUri);
      }
    } catch (error) {
      console.error('提取元数据失败: ' + JSON.stringify(error));
      this.metadataText = '无法提取元数据';
    }
  }
  
  // 提取图片元数据
  private async extractImageMetadata(fileUri: string) {
    let imageSource: image.ImageSource | undefined = undefined;
    try {
      // 打开文件获取文件描述符
      const file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY);
      
      // 创建 ImageSource
      imageSource = image.createImageSource(file.fd);
      
      // 获取图片基本信息
      const imageInfo = await imageSource.getImageInfo(0);
      
      // 定义要获取的 EXIF 属性键
      const propertyKeys = [
        image.PropertyKey.IMAGE_WIDTH,
        image.PropertyKey.IMAGE_LENGTH,
        image.PropertyKey.ORIENTATION,
        image.PropertyKey.DATE_TIME,
        image.PropertyKey.MAKE,
        image.PropertyKey.MODEL,
        image.PropertyKey.F_NUMBER,
        image.PropertyKey.EXPOSURE_TIME,
        image.PropertyKey.ISO_SPEED_RATINGS,
        image.PropertyKey.FOCAL_LENGTH,
        image.PropertyKey.GPS_LATITUDE,
        image.PropertyKey.GPS_LONGITUDE,
        image.PropertyKey.GPS_LATITUDE_REF,
        image.PropertyKey.GPS_LONGITUDE_REF
      ];
      
      // 批量获取 EXIF 属性
      const properties = await imageSource.getImageProperties(propertyKeys);
      
      // 格式化元数据为字符串
      let metadataStr = '=== 图片基本信息 ===\n';
      metadataStr += `宽度: ${imageInfo.size.width} px\n`;
      metadataStr += `高度: ${imageInfo.size.height} px\n`;
      metadataStr += `像素格式: ${imageInfo.pixelFormat}\n`;
      
      metadataStr += '\n=== EXIF 信息 ===\n';
      
      // 图片尺寸
      const width = properties[image.PropertyKey.IMAGE_WIDTH];
      const height = properties[image.PropertyKey.IMAGE_LENGTH];
      if (width && height) {
        metadataStr += `原始尺寸: ${width} × ${height}\n`;
      }
      
      // 方向
      const orientation = properties[image.PropertyKey.ORIENTATION];
      if (orientation) {
        metadataStr += `拍摄方向: ${orientation}\n`;
      }
      
      // 拍摄时间
      const dateTime = properties[image.PropertyKey.DATE_TIME];
      if (dateTime) {
        metadataStr += `拍摄时间: ${dateTime}\n`;
      }
      
      // 相机制造商
      const make = properties[image.PropertyKey.MAKE];
      if (make) {
        metadataStr += `相机制造商: ${make}\n`;
      }
      
      // 相机型号
      const model = properties[image.PropertyKey.MODEL];
      if (model) {
        metadataStr += `相机型号: ${model}\n`;
      }
      
      // 光圈值
      const fNumber = properties[image.PropertyKey.F_NUMBER];
      if (fNumber) {
        metadataStr += `光圈: f/${fNumber}\n`;
      }
      
      // 曝光时间
      const exposureTime = properties[image.PropertyKey.EXPOSURE_TIME];
      if (exposureTime) {
        metadataStr += `曝光时间: ${exposureTime} s\n`;
      }
      
      // ISO 感光度
      const isoSpeed = properties[image.PropertyKey.ISO_SPEED_RATINGS];
      if (isoSpeed) {
        metadataStr += `ISO 感光度: ${isoSpeed}\n`;
      }
      
      // 焦距
      const focalLength = properties[image.PropertyKey.FOCAL_LENGTH];
      if (focalLength) {
        metadataStr += `焦距: ${focalLength} mm\n`;
      }
      
      // GPS 信息
      const gpsLat = properties[image.PropertyKey.GPS_LATITUDE];
      const gpsLatRef = properties[image.PropertyKey.GPS_LATITUDE_REF];
      const gpsLon = properties[image.PropertyKey.GPS_LONGITUDE];
      const gpsLonRef = properties[image.PropertyKey.GPS_LONGITUDE_REF];
      
      if (gpsLat && gpsLon) {
        metadataStr += '\n=== GPS 信息 ===\n';
        metadataStr += `纬度: ${gpsLat} ${gpsLatRef || ''}\n`;
        metadataStr += `经度: ${gpsLon} ${gpsLonRef || ''}\n`;
      }
      
      this.metadataText = metadataStr;
      
      // 关闭文件
      fs.closeSync(file);
    } catch (error) {
      console.error('提取图片元数据失败: ' + JSON.stringify(error));
      this.metadataText = '无法提取图片元数据';
    } finally {
      // 释放 ImageSource 资源
      if (imageSource) {
        imageSource.release();
      }
    }
  }
  
  // 提取音视频元数据
  private async extractAVMetadata(fileUri: string) {
    try {
      // 打开文件获取文件描述符
      const file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY);
      const stat = await fs.stat(fileUri);
      
      // 创建元数据提取器
      const extractor: media.AVMetadataExtractor = await media.createAVMetadataExtractor();
      
      // 设置文件描述符源
      const avFileDescriptor: media.AVFileDescriptor = {
        fd: file.fd,
        offset: 0,
        length: stat.size
      };
      extractor.fdSrc = avFileDescriptor;
      
      // 获取元数据
      const metadata = await extractor.fetchMetadata();
      
      // 格式化元数据为字符串
      let metadataStr = '';
      metadataStr += `宽度: ${metadata.videoWidth || 'N/A'}\n`;
      metadataStr += `高度: ${metadata.videoHeight || 'N/A'}\n`;
      let duration:number = 0;
      if (metadata.duration){
        duration  = Number(metadata.duration);
        duration = duration / 1000;
        duration.toFixed(2);
      }
      metadataStr += `时长: ${metadata.duration ? duration + ' s' : 'N/A'}\n`;
      metadataStr += `编码格式: ${metadata.mimeType || 'N/A'}\n`;
      // metadataStr += `比特率: ${metadata.bitrate || 'N/A'}\n`;
      metadataStr += `轨道数: ${metadata.trackCount || 'N/A'}\n`;
      
      this.metadataText = metadataStr;
      
      // 释放提取器资源
      extractor.release();
      fs.closeSync(file);
    } catch (error) {
      console.error('提取音视频元数据失败: ' + JSON.stringify(error));
      this.metadataText = '无法提取元数据';
    }
  }

  // 清除选择
  private clearSelection() {
    this.selectedFileUri = '';
    this.fileName = '';
    this.fileSize = '';
    this.fileType = '';
    this.isMediaFile = false;
    this.isLoading = false;
    this.metadataText = '';
    this.thumbnailPixelMap = null;
    this.scaleWidth = 0;
    this.scaleHeight = 0;
    
    // 显示清除成功提示
    promptAction.showToast({
      message: '已清除选择',
      duration: 2000
    });
  }
  
  // 复制元数据信息到剪贴板
  private async copyMetadata() {
    try {
      if (!this.metadataText) {
        promptAction.showToast({
          message: '没有元数据信息可复制',
          duration: 2000
        });
        return;
      }
      
      // 获取系统剪贴板
      const pasteboardData = pasteboard.createPlainTextData(this.metadataText);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      
      // 将数据写入剪贴板
      await systemPasteboard.setData(pasteboardData);
      
      // 显示成功提示
      promptAction.showToast({
        message: '元数据信息已复制到剪贴板',
        duration: 2000
      });
      
      console.info('元数据信息已复制到剪贴板');
    } catch (error) {
      console.error('复制元数据失败: ' + JSON.stringify(error));
      promptAction.showToast({
        message: '复制失败，请重试',
        duration: 2000
      });
    }
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


  build() {
    Column() {
      // 搜索框

      Text("查看元数据")
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .padding({ left: 16, right: 16 })
        .margin({ top: 32 ,bottom: 20})
        .alignSelf(ItemAlign.Start)

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
            // 显示图片/视频缩略图
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
          Text('点击选择文件')
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
      
      // 元数据显示区域
      if (this.selectedFileUri && this.isMediaFile) {
        Column() {
          TextArea({ text: this.metadataText })
            .width('100%')
            .height(200)
            .fontSize(14)
            .fontColor('#333333')
            .backgroundColor('#FFFFFF')
            .padding(10)
            .borderRadius(8)
            .border({ width: 1, color: '#E0E0E0' })
            .enabled(false)
          
          // 按钮组
          Row() {
            // 复制按钮
            Button('复制信息', { type: ButtonType.Normal })
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor('#1890FF')
              .borderRadius(6)
              .width(110)
              .height(36)
              .onClick(() => {
                this.copyMetadata();
              })
            
            Blank().width(16)
            
            // 清除按钮
            Button('清除选择', { type: ButtonType.Normal })
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor('#FF4D4F')
              .borderRadius(6)
              .width(110)
              .height(36)
              .onClick(() => {
                this.clearSelection();
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 16 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .margin({ left: 16, right: 16, bottom: 20 })
      }
      
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F8F8')
  }
}