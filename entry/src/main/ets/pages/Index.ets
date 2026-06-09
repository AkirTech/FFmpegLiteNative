import { HomePage } from './HomePage';
import { DiscoverPage } from './DiscoverPage';
import { ProfilePage } from './ProfilePage';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;

  build() {
    Column() {
      // 主要内容区域 - 显示对应的子页面
      Column() {
        if (this.currentIndex === 0) {
          HomePage()
        } else if (this.currentIndex === 1) {
          DiscoverPage()
        } else if (this.currentIndex === 2) {
          ProfilePage()
        }
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)

      // 底部导航栏
      Row() {
        this.tabItem('首页', 0)
        this.tabItem('查看元数据', 1)
        this.tabItem('关于', 2)
      }
      .width('100%')
      .height(56)
      .backgroundColor($r('app.color.bg_primary'))
      .border({ width: { top: 1 }, color: $r('app.color.border_nav') })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  tabItem(text: string, index: number) {
    Column() {
      Text(this.getIcon(index))
        .fontSize(20)
      Text(text)
        .fontSize(12)
        .margin({ top: 2 })
    }
    .width('33.33%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.currentIndex === index ? $r('app.color.bg_selected') : $r('app.color.bg_primary'))
    .onClick(() => {
      this.currentIndex = index;
    })
  }

  getIcon(index: number): string {
    const icons = ['🏠', '🔍', '👤'];
    return icons[index] || '●';
  }
}