import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

@Component
export struct ProfilePage {

  // 获取UIAbilityContext
  private getAbilityContext(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  // 打开浏览器访问GitHub
  private openGitHub() {
    try {
      const context = this.getAbilityContext();
      
      // 构造Want对象
      const wantInfo: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: 'https://github.com/AkirTech/FFmpegLiteNative'
      };

      // 启动浏览器
      context.startAbility(wantInfo)
        .then(() => {
          console.info('成功打开GitHub');
        })
        .catch((err: BusinessError) => {
          console.error('打开GitHub失败: ' + JSON.stringify(err));
        });
        
    } catch (error) {
      console.error('打开浏览器失败: ' + JSON.stringify(error));
    }
  }

  build() {
    Column() {
      // 标题区域
      Column() {
        Text('关于我们')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 8 })
        
        Text('FFactory Lite')
          .fontSize(20)
          .fontColor($r('app.color.text_secondary'))
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .padding({ top: 40, bottom: 30 })
      .alignItems(HorizontalAlign.Center)
      
      // 内容卡片
      Column() {
        // 应用图标区域
        Column() {
          Image($r('app.media.foreground'))
            .width(80)
            .height(80)
            .objectFit(ImageFit.Contain)
        }
        .width(100)
        .height(100)
        .backgroundColor($r('app.color.app_icon_bg'))
        .borderRadius(20)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .margin({ bottom: 24 })
        
        // 应用名称和版本
        Text('FFactory Lite')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 4 })
        
        Text($r('app.string.app_ver'))
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ bottom: 24 })
        
        // 描述文本
        Text('FFactory Lite 是一个轻量级的格式转换工具，致力于为用户提供简洁高效的媒体文件格式转换体验。我们专注于让手机端格式转化变得更加简单直观。')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .lineHeight(24)
          .margin({ bottom: 32, left: 16, right: 16 })
        
        // 功能特色
        Column() {
          Row() {
            Text('✓')
              .fontSize(16)
              .fontColor($r('app.color.success'))
              .margin({ right: 8 })
            Text('简洁直观的界面设计')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .margin({ bottom: 12 })
          
          Row() {
            Text('✓')
              .fontSize(16)
              .fontColor($r('app.color.success'))
              .margin({ right: 8 })
            Text('高效的文件管理功能')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .margin({ bottom: 12 })
          
          Row() {
            Text('✓')
              .fontSize(16)
              .fontColor($r('app.color.success'))
              .margin({ right: 8 })
            Text('支持多种文件格式')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 40 })
        
        // GitHub按钮
        Button('访问 GitHub', { type: ButtonType.Normal })
          .fontSize(16)
          .fontColor($r('app.color.bg_primary'))
          .backgroundColor($r('app.color.github_btn'))
          .borderRadius(8)
          .width('80%')
          .height(44)
          .onClick(() => {
            this.openGitHub();
          })
      }
      .width('90%')
      .padding(24)
      .backgroundColor($r('app.color.bg_primary'))
      .borderRadius(16)
      .shadow({
        radius: 8,
        color: $r('app.color.shadow_light'),
        offsetX: 0,
        offsetY: 2
      })
      .margin({ bottom: 20 })
      .alignItems(HorizontalAlign.Center)
      
      // 底部信息
      Column() {
        Text('© 2026 FFactory Lite')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ bottom: 4 })
        
        Text('All Rights Reserved')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .padding({ bottom: 30 })
      .alignItems(HorizontalAlign.Center)
      
      Blank()
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_secondary'))
    .padding({ left: 16, right: 16 })
  }
}