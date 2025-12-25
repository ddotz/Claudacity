# Claudacity

<p align="center">
  <img src="Claudacity/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Claudacity Icon" width="128" height="128">
</p>

<p align="center">
  <strong>Claude Code Usage Monitoring macOS Menu Bar App</strong><br>
  <em>Claude Code 사용량 모니터링 macOS 메뉴바 앱</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9+-orange" alt="Swift">
  <img src="https://img.shields.io/badge/version-1.0-green" alt="Version">
  <img src="https://img.shields.io/badge/language-🇰🇷_🇺🇸-lightgrey" alt="Languages">
</p>

---

## ✨ Features / 기능

- 🔍 **Real-time Usage Monitoring** / 실시간 사용량 모니터링
- 📊 **Statistics Charts** / 24시간/7일 사용량 차트
- ⚙️ **Customization** / 메뉴바 표시 형식, 테마 설정
- 🔔 **Notifications** / 사용량 임계치 알림
- 🌙 **Dark Mode** / 시스템 테마 자동 감지
- 🌐 **Multilingual** / 한국어, English 지원

## 🛠 Requirements / 요구 사항

- macOS 14.0 (Sonoma) or later
- Claude Code CLI installed

## 📦 Installation / 설치

### Option 1: Download Release (Recommended)

Download the latest `.app` from [Releases](https://github.com/ddotz/Claudacity/releases) and move it to `/Applications`.

### Option 2: Build from Source

**Requirements:**
- macOS 14.0+ (Sonoma)
- Xcode 15+

**Quick Build:**
```bash
git clone https://github.com/ddotz/Claudacity.git
cd Claudacity
./scripts/build.sh
```

The app will be built at `build/Claudacity.app`. Move it to `/Applications`:
```bash
cp -R build/Claudacity.app /Applications/
```

**Build with Xcode:**
```bash
open Claudacity.xcodeproj
```
Build and run with `⌘ + R` in Xcode

## 🚀 Usage / 사용법

1. Launch the app → Icon appears in menu bar
2. Click the icon to view usage details
3. Configure display format and notifications in Settings

---

1. 앱 실행 시 메뉴바에 아이콘 표시
2. 아이콘 클릭하여 사용량 확인
3. 설정에서 표시 형식 및 알림 설정

## 🌐 Language Support / 다국어 지원

Claudacity automatically follows your system language settings.

| Language | Status |
|----------|--------|
| 🇰🇷 한국어 | ✅ Supported |
| 🇺🇸 English | ✅ Supported |

## 📄 License

MIT License

---

<p align="center">Made with ❤️ for Claude Code users</p>
