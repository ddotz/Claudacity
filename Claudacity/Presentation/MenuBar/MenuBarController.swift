// MARK: - Imports
import AppKit
import SwiftUI
import Combine

// MARK: - Menu Bar Controller
@MainActor
final class MenuBarController: NSObject, ObservableObject {
    // MARK: Properties
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let viewModel: UsageViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: Init
    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    // MARK: Setup
    func setup() {
        setupStatusItem()
        setupPopover()
        observeViewModel()
        viewModel.startAutoRefresh()
    }

    // MARK: Private Methods
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // autosaveName 설정으로 메뉴바 위치 기억 및 다른 앱 아이콘과의 충돌 방지
        statusItem?.autosaveName = "com.claudacity.menubar"

        if let button = statusItem?.button {
            button.action = #selector(togglePopover)
            button.target = self
            updateDisplay()
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(
            width: Dimensions.Popover.width,
            height: Dimensions.Popover.height
        )
        popover?.behavior = .transient
        popover?.animates = true

        let popoverView = PopoverView(viewModel: viewModel)
        popover?.contentViewController = NSHostingController(rootView: popoverView)
    }

    private func observeViewModel() {
        viewModel.$usage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)
        
        // JSONL 사용량 변경 감지
        viewModel.$jsonlUsage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)

        // CLI /usage 결과 변경 감지
        viewModel.$cliUsageResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)
        
        // 설정 변경 감지 (아이콘 스타일, 표시옵션, 표시모드, 애니메이션 등)
        Dependencies.shared.settingsStore.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)
    }


    private func updateDisplay() {
        guard let button = statusItem?.button else { return }

        let settings = Dependencies.shared.settingsStore.settings

        // 표시 모드에 따라 다른 퍼센트 값 사용 (향후 확장을 위해 유지)
        // 현재는 percentage가 직접 사용되지 않지만 displayMode별 분기 로직에서 참조됨

        // Create attributed string for the menu bar
        let attributedTitle = NSMutableAttributedString()

        // Icon - Claudacity 스타일일 때는 동적 생성, 그 외에는 시스템 심볼 사용
        let icon: NSImage?
        if settings.iconStyle == .claudacity {
            // Claudacity 시그니처 아이콘: 75%로 고정
            icon = IconGenerator.shared.createGaugeIcon(forPercentage: 75)
        } else {
            let iconName = settings.iconStyle.systemImageName
            icon = NSImage(systemSymbolName: iconName, accessibilityDescription: "Usage")
            icon?.isTemplate = true
        }
        
        if let icon = icon {
            let iconAttachment = NSTextAttachment()
            iconAttachment.image = icon
            // 수직 가운데 정렬: 폰트 기준선에 맞춰 조정
            let iconSize = icon.size
            iconAttachment.bounds = CGRect(x: 0, y: -4, width: iconSize.width, height: iconSize.height)
            attributedTitle.append(NSAttributedString(attachment: iconAttachment))
            attributedTitle.append(NSAttributedString(string: " "))
        }

        // 메뉴바 텍스트 색상 (시스템 테마에 맞게 자동 조정)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.controlTextColor
        ]

        // Percentage text
        if viewModel.isNotInUse {
            // CLI 사용량 파싱 전: "--%" 표시 (하이픈 2개로 숫자 2자리 크기)
            switch settings.displayMode {
            case .session, .weekly:
                attributedTitle.append(NSAttributedString(string: "--%", attributes: textAttributes))
            case .all:
                // 모두: 세션/주간 둘 다 위아래로 "--%" 표시
                attributedTitle.append(createDualTextAttributedString(
                    top: "--%",
                    bottom: "--%"
                ))
            }
        } else if Dependencies.shared.settingsStore.showPercentage {
            switch settings.displayMode {
            case .session:
                attributedTitle.append(NSAttributedString(string: "\(Int(viewModel.currentPercentage))%", attributes: textAttributes))
            case .weekly:
                attributedTitle.append(NSAttributedString(string: "\(Int(viewModel.weeklyPercentage))%", attributes: textAttributes))
            case .all:
                // 모두: 세션/주간 둘 다 위아래로 표시
                attributedTitle.append(createDualTextAttributedString(
                    top: "\(Int(viewModel.currentPercentage))%",
                    bottom: "\(Int(viewModel.weeklyPercentage))%"
                ))
            }
        }

        // Mini gauge bar or "대기중" status
        if viewModel.isNotInUse {
            // 게이지 바 대신 "대기중" 표시
            attributedTitle.append(NSAttributedString(string: " 대기중", attributes: textAttributes))
        } else if settings.enableAnimations {
            attributedTitle.append(NSAttributedString(string: " "))
            switch settings.displayMode {
            case .session:
                attributedTitle.append(createGaugeAttributedString(percentage: viewModel.currentPercentage))
            case .weekly:
                attributedTitle.append(createGaugeAttributedString(percentage: viewModel.weeklyPercentage))
            case .all:
                // 모두: 세션/주간 게이지 둘 다 표시 (위아래로 쌓기)
                attributedTitle.append(createDualGaugeAttributedString(
                    topPercentage: viewModel.currentPercentage,
                    bottomPercentage: viewModel.weeklyPercentage
                ))
            }
        }

        // Reset time (only when in use)
        if Dependencies.shared.settingsStore.showResetTime, !viewModel.isNotInUse {
            switch settings.displayMode {
            case .session, .weekly:
                let resetTimeString: String?
                switch settings.resetTimeFormat {
                case .absoluteTime:
                    resetTimeString = viewModel.currentResetTime
                case .remaining:
                    resetTimeString = viewModel.remainingTimeString
                }
                
                if let resetTime = resetTimeString {
                    if attributedTitle.length > 0 {
                        attributedTitle.append(NSAttributedString(string: " | "))
                    }
                    attributedTitle.append(NSAttributedString(string: resetTime))
                }
            case .all:
                // 모두: 세션/주간 리셋 시간 둘 다 위아래로 표시
                let sessionTime: String?
                let weeklyTime: String?
                
                switch settings.resetTimeFormat {
                case .absoluteTime:
                    sessionTime = viewModel.sessionResetTimeFormatted
                    weeklyTime = viewModel.weeklyResetTimeFormatted
                case .remaining:
                    sessionTime = viewModel.sessionRemainingTimeString
                    weeklyTime = viewModel.weeklyRemainingTimeString
                }
                
                if let sTime = sessionTime, let wTime = weeklyTime {
                    if attributedTitle.length > 0 {
                        attributedTitle.append(NSAttributedString(string: " | "))
                    }
                    attributedTitle.append(createDualTextAttributedString(top: sTime, bottom: wTime, alignment: .left))
                }
            }
        }

        button.attributedTitle = attributedTitle
        button.image = nil
        button.imagePosition = .noImage
        button.contentTintColor = nil
    }

    // MARK: - 싱글모드 높이 상수
    private let singleModeBarHeight: CGFloat = 6
    private let singleModeTotalHeight: CGFloat = 18

    private func createGaugeAttributedString(percentage: Double) -> NSAttributedString {
        let result = NSMutableAttributedString()
        
        let gaugeImage = createSingleGaugeImage(percentage: percentage)
        
        let attachment = NSTextAttachment()
        attachment.image = gaugeImage
        // 중앙 정렬 (텍스트와 높이 맞춤)
        // 이미지 높이 18 중 바 6이 중앙에 있음.
        // 기존 -5에서 -2.5로 상향 조정하여 텍스트 센터와 맞춤 (시스템 폰트 기준)
        attachment.bounds = CGRect(x: 0, y: -4.5, width: gaugeImage.size.width, height: gaugeImage.size.height)
        
        result.append(NSAttributedString(attachment: attachment))
        return result
    }
    
    private func createSingleGaugeImage(percentage: Double) -> NSImage {
        let totalWidth: CGFloat = 36
        let barHeight: CGFloat = singleModeBarHeight
        let totalHeight: CGFloat = singleModeTotalHeight
        
        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        image.lockFocus()
        
        let activeColor = gaugeColor(for: percentage)
        let inactiveColor = NSColor.tertiaryLabelColor
        
        // 수직 중앙 정렬
        let yOffset = (totalHeight - barHeight) / 2
        
        // 게이지 그리기
        let filledWidth = CGFloat(percentage / 100.0) * totalWidth
        
        activeColor.setFill()
        NSRect(x: 0, y: yOffset, width: filledWidth, height: barHeight).fill()
        
        inactiveColor.setFill()
        NSRect(x: filledWidth, y: yOffset, width: totalWidth - filledWidth, height: barHeight).fill()
        
        image.unlockFocus()
        image.isTemplate = false
        
        return image
    }

    // MARK: - 듀얼모드 공통 높이 상수
    private let dualModeHeight: CGFloat = 18
    private let dualModeLineHeight: CGFloat = 7
    private let dualModeGap: CGFloat = 2

    /// 위아래로 쌓인 듀얼 게이지 생성 (모두 모드용) - 싱글모드 스타일 이미지
    private func createDualGaugeAttributedString(topPercentage: Double, bottomPercentage: Double) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let gaugeImage = createDualGaugeImage(topPercentage: topPercentage, bottomPercentage: bottomPercentage)

        let attachment = NSTextAttachment()
        attachment.image = gaugeImage
        // 메뉴바 중앙 정렬
        attachment.bounds = CGRect(x: 0, y: -5, width: gaugeImage.size.width, height: gaugeImage.size.height)

        result.append(NSAttributedString(attachment: attachment))
        return result
    }

    /// 듀얼 게이지 이미지 생성 (싱글모드 █ 스타일 - 연결된 블록)
    private func createDualGaugeImage(topPercentage: Double, bottomPercentage: Double) -> NSImage {
        let totalWidth: CGFloat = 36
        let barHeight: CGFloat = dualModeLineHeight
        let verticalGap: CGFloat = dualModeGap
        let totalHeight = dualModeHeight

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))

        image.lockFocus()

        let topActiveColor = gaugeColor(for: topPercentage)
        let bottomActiveColor = gaugeColor(for: bottomPercentage)
        let inactiveColor = NSColor.tertiaryLabelColor
        
        // 전체 컨텐츠 높이 계산 및 수직 중앙 정렬을 위한 오프셋
        let contentHeight = (barHeight * 2) + verticalGap
        let yOffset = (totalHeight - contentHeight) / 2

        // 상단 바 (세션)
        let topFilledWidth = CGFloat(topPercentage / 100.0) * totalWidth
        topActiveColor.setFill()
        NSRect(x: 0, y: yOffset + barHeight + verticalGap, width: topFilledWidth, height: barHeight).fill()
        inactiveColor.setFill()
        NSRect(x: topFilledWidth, y: yOffset + barHeight + verticalGap, width: totalWidth - topFilledWidth, height: barHeight).fill()

        // 하단 바 (주간)
        let bottomFilledWidth = CGFloat(bottomPercentage / 100.0) * totalWidth
        bottomActiveColor.setFill()
        NSRect(x: 0, y: yOffset, width: bottomFilledWidth, height: barHeight).fill()
        inactiveColor.setFill()
        NSRect(x: bottomFilledWidth, y: yOffset, width: totalWidth - bottomFilledWidth, height: barHeight).fill()

        image.unlockFocus()
        image.isTemplate = false

        return image
    }
    
    private func gaugeColor(for percentage: Double) -> NSColor {
        if percentage >= 50 {
            return NSColor(Color.claudacity.safe)
        } else if percentage >= 30 {
            return NSColor(Color.claudacity.caution)
        } else if percentage >= 10 {
            return NSColor(Color.claudacity.warning)
        } else {
            return NSColor(Color.claudacity.danger)
        }
    }
    
    /// 위아래로 쌓인 듀얼 텍스트 생성 (이미지 기반 - 동일 위치)
    private func createDualTextAttributedString(top: String, bottom: String, alignment: NSTextAlignment = .right) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let textImage = createDualTextImage(top: top, bottom: bottom, alignment: alignment)

        let attachment = NSTextAttachment()
        attachment.image = textImage
        // 메뉴바 중앙 정렬
        attachment.bounds = CGRect(x: 0, y: -5, width: textImage.size.width, height: textImage.size.height)
        
        result.append(NSAttributedString(attachment: attachment))
        return result
    }

    /// 듀얼 텍스트 이미지 생성 (위아래 동일 위치, 정렬 옵션)
    private func createDualTextImage(top: String, bottom: String, alignment: NSTextAlignment) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium)
        let textColor = NSColor.controlTextColor

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]

        let topSize = (top as NSString).size(withAttributes: attrs)
        let bottomSize = (bottom as NSString).size(withAttributes: attrs)

        let maxWidth = max(topSize.width, bottomSize.width)
        let totalHeight = dualModeHeight

        let image = NSImage(size: NSSize(width: maxWidth, height: totalHeight))

        image.lockFocus()

        let topX: CGFloat
        let bottomX: CGFloat

        switch alignment {
        case .left:
            topX = 0
            bottomX = 0
        case .right:
            topX = maxWidth - topSize.width
            bottomX = maxWidth - bottomSize.width
        default:
            topX = (maxWidth - topSize.width) / 2
            bottomX = (maxWidth - bottomSize.width) / 2
        }
        
        // 게이지와 동일한 수직 위치 계산 로직 적용
        let barHeight = dualModeLineHeight
        let verticalGap = dualModeGap
        let contentHeight = (barHeight * 2) + verticalGap
        let yOffset = (totalHeight - contentHeight) / 2
        
        // 텍스트/게이지 센터 정렬을 위한 보정
        // 텍스트(숫자)는 보통 layout rect의 중앙보다 약간 위에 시각적 중심이 있음 (descender 공간 때문)
        // 따라서 텍스트를 약간 내려야(y 감소) 게이지와 센터가 맞음
        let dummyText = "0%" as NSString
        let textHeight = dummyText.size(withAttributes: attrs).height
        let verticalCorrection = (textHeight - barHeight) / 2

        // 상단 텍스트 (위쪽 절반)
        let topY = yOffset + barHeight + verticalGap - verticalCorrection
        (top as NSString).draw(at: NSPoint(x: topX, y: topY), withAttributes: attrs)

        // 하단 텍스트 (아래쪽 절반)
        let bottomY = yOffset - verticalCorrection
        (bottom as NSString).draw(at: NSPoint(x: bottomX, y: bottomY), withAttributes: attrs)

        image.unlockFocus()

        return image
    }

    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // 앱을 먼저 활성화하여 팝오버 내 요소가 즉시 반응하도록 함
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // 팝오버 윈도우를 key window로 설정
            DispatchQueue.main.async {
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
}
