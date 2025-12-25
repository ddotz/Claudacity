// MARK: - Imports
import Foundation
import SwiftUI

// MARK: - App Settings
struct AppSettings: Codable, Equatable {
    // MARK: Appearance
    var showPercentage: Bool = true
    var showResetTime: Bool = true
    var resetTimeFormat: ResetTimeFormat = .absoluteTime
    var displayMode: DisplayMode = .session
    var theme: Theme = .system

    // MARK: Animation
    var enableAnimations: Bool = true
    var iconStyle: IconStyle = .claudacity

    // MARK: Notifications
    var lowThreshold: Int = 30
    var criticalThreshold: Int = 10
    var enableLowNotification: Bool = true
    var enableCriticalNotification: Bool = true
    var enableFastConsumptionNotification: Bool = true
    var enableResetNotification: Bool = false
    var enableSound: Bool = true
    var notificationSound: String = "default"

    // MARK: General
    var refreshInterval: TimeInterval = 600  // 10 minutes
    var launchAtLogin: Bool = false
    var language: Language = .korean

    // MARK: Subscription
    var subscriptionPlan: SubscriptionPlan = .pro
    var customTokenLimit: Int64? = nil      // Custom 플랜 5시간 한도
    var customWeeklyLimit: Int64? = nil     // Custom 플랜 주간 한도

    // MARK: Weekly Limit Display
    var showWeeklyLimit: Bool = true
    var weeklyLimitWarningThreshold: Int = 30

    static let `default` = AppSettings()
}

// MARK: - Display Mode
enum DisplayMode: String, Codable, CaseIterable, Identifiable {
    case session
    case weekly
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .session: return String(localized: "display.session")
        case .weekly: return String(localized: "display.weekly")
        case .all: return String(localized: "display.all")
        }
    }
}

// MARK: - Reset Time Format
enum ResetTimeFormat: String, Codable, CaseIterable, Identifiable {
    case absoluteTime  // "오후 7:00"
    case remaining     // "2시간 30분 남음"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .absoluteTime: return String(localized: "time_format.absolute")
        case .remaining: return String(localized: "time_format.remaining")
        }
    }
}

// MARK: - Theme
enum Theme: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return String(localized: "theme.system")
        case .light: return String(localized: "theme.light")
        case .dark: return String(localized: "theme.dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Icon Style
enum IconStyle: String, Codable, CaseIterable, Identifiable {
    case claudacity  // 시그니처 아이콘 (75% 게이지)
    case energy
    case minimal
    case classic
    case brain
    case sparkle
    case chart

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudacity: return "Claudacity"
        case .energy: return String(localized: "icon.energy")
        case .minimal: return String(localized: "icon.minimal")
        case .classic: return String(localized: "icon.classic")
        case .brain: return String(localized: "icon.brain")
        case .sparkle: return String(localized: "icon.sparkle")
        case .chart: return String(localized: "icon.chart")
        }
    }

    var systemImageName: String {
        switch self {
        case .claudacity: return "circle.dashed"  // fallback (실제로는 동적 생성)
        case .energy: return "bolt.fill"
        case .minimal: return "circle.fill"
        case .classic: return "gauge.with.needle.fill"
        case .brain: return "brain.head.profile"
        case .sparkle: return "sparkles"
        case .chart: return "chart.bar.fill"
        }
    }
}

// MARK: - Language
enum Language: String, Codable, CaseIterable, Identifiable {
    case korean = "ko"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        }
    }
}

// MARK: - Subscription Plan
enum SubscriptionPlan: String, Codable, CaseIterable, Identifiable {
    case pro = "Pro"
    case max5x = "Max 5x"
    case max20x = "Max 20x"
    case custom = "Custom"

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// 5시간당 토큰 한도 (input + output + cache_creation, cache_read 제외)
    /// Claude.ai 실제 사용량 역산 기반 검증됨 (2025년 12월)
    var estimatedTokenLimit: Int64 {
        switch self {
        case .pro:     return 2_100_000   // Pro 플랜 (~2.1M)
        case .max5x:   return 10_500_000  // Max 5x 플랜 (Pro × 5)
        case .max20x:  return 42_000_000  // Max 20x 플랜 (Pro × 20)
        case .custom:  return 0           // 사용자 정의 (AppSettings.customTokenLimit 사용)
        }
    }

    // MARK: - 주간 한도 (2025년 8월 도입)

    /// 주간 Sonnet 사용 시간 한도 (시간 단위)
    /// 출처: Anthropic 공식 발표 (2025년 8월)
    var estimatedWeeklyHours: ClosedRange<Int> {
        switch self {
        case .pro:     return 40...80
        case .max5x:   return 140...280
        case .max20x:  return 240...480
        case .custom:  return 0...0
        }
    }

    /// 주간 Opus 사용 시간 한도 (Max 플랜만 해당)
    var estimatedWeeklyOpusHours: ClosedRange<Int>? {
        switch self {
        case .max5x:   return 15...35
        case .max20x:  return 24...40
        default:       return nil
        }
    }

    /// 주간 한도 토큰 변환 (시간 → 토큰, 시간당 약 2,000 토큰 기준)
    var estimatedWeeklyTokenLimit: Int64 {
        let avgHours = (estimatedWeeklyHours.lowerBound + estimatedWeeklyHours.upperBound) / 2
        let tokensPerHour: Int64 = 2_000  // 보수적 추정
        return Int64(avgHours) * tokensPerHour
    }

    /// Max 플랜 자동 모델 전환 임계값 (Opus → Sonnet)
    var opusToSonnetFallbackThreshold: Double? {
        switch self {
        case .max5x:   return 0.20  // 20% 사용 시 전환
        case .max20x:  return 0.50  // 50% 사용 시 전환
        default:       return nil
        }
    }

    // MARK: - 리셋 주기

    /// 5시간 세션 리셋 주기
    static let sessionResetInterval: TimeInterval = 5 * 60 * 60  // 5시간

    /// 주간 리셋 주기 (7일)
    static let weeklyResetInterval: TimeInterval = 7 * 24 * 60 * 60  // 7일

    /// 기존 resetInterval 호환성 유지
    @available(*, deprecated, renamed: "sessionResetInterval")
    static let resetInterval: TimeInterval = sessionResetInterval
}
