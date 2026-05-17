/**
 * 架构检测工具
 * 用于检测设备架构和 Native 库兼容性
 */
import { FFMpegUtils } from '@prq/ffmpeg-tools';

/**
 * 兼容性检查结果接口
 */
export interface CompatibilityResult {
  isCompatible: boolean;
  deviceArch: string;
  supportedArchs: string[];
  message: string;
}

export class ArchitectureDetector {
  private static readonly SUPPORTED_ARCHITECTURES: string[] = ['arm64-v8a'];
  
  /**
   * 获取当前设备架构
   */
  static getDeviceArchitecture(): string {
    try {
      const arch = ArchitectureDetector.detectByNativeModule();
      return arch;
    } catch (error) {
      console.warn('[ArchDetector] 架构检测失败:', error);
      return 'unknown';
    }
  }
  
  /**
   * 通过 Native 模块加载检测架构
   */
  private static detectByNativeModule(): string {
    try {
      // 尝试访问 FFMpegUtils 的方法
      if (FFMpegUtils && typeof FFMpegUtils.showLog === 'function') {
        // Native 模块加载成功，说明架构匹配
        return 'arm64-v8a';
      } else {
        // Native 模块加载失败，可能是架构不匹配
        return 'incompatible';
      }
    } catch (error) {
      return 'incompatible';
    }
  }
  
  /**
   * 检查架构兼容性
   */
  static checkCompatibility(): CompatibilityResult {
    const deviceArch = ArchitectureDetector.getDeviceArchitecture();
    const isCompatible = deviceArch === 'arm64-v8a';
    
    let message = '';
    if (isCompatible) {
      message = '✅ 设备架构兼容，FFmpeg 功能可用';
    } else if (deviceArch === 'incompatible') {
      message = '❌ Native 模块加载失败，可能是架构不匹配。\n' +
                '当前库仅支持 arm64-v8a 架构。\n' +
                '请使用 arm64-v8a 模拟器或真机测试。';
    } else {
      message = '⚠️ 当前设备架构: ' + deviceArch + '\n' +
                '支持的架构: ' + ArchitectureDetector.SUPPORTED_ARCHITECTURES.join(', ') + '\n' +
                '请使用支持的架构设备。';
    }
    
    const result: CompatibilityResult = {
      isCompatible: isCompatible,
      deviceArch: deviceArch,
      supportedArchs: ArchitectureDetector.SUPPORTED_ARCHITECTURES,
      message: message
    };
    
    return result;
  }
  
  /**
   * 获取详细的诊断信息
   */
  static getDiagnosticInfo(): string {
    const compatibility = ArchitectureDetector.checkCompatibility();
    
    let info = '=== 架构诊断信息 ===\n';
    info += '设备架构: ' + compatibility.deviceArch + '\n';
    info += '支持的架构: ' + compatibility.supportedArchs.join(', ') + '\n';
    info += '兼容性: ' + (compatibility.isCompatible ? '✅ 兼容' : '❌ 不兼容') + '\n';
    info += '\n详细信息:\n' + compatibility.message + '\n';
    
    return info;
  }
}
