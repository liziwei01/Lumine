<p align="center"><img src="Lumine/Assets.xcassets/AppIcon.appiconset/icon_128.png" width="96" alt="Lumine 아이콘"></p>
<h1 align="center">Lumine</h1>
<p align="center">시스템 상태를 조용히, 한눈에.</p>
<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ru.md">Русский</a> · <a href="README.ja.md">日本語</a> · <strong>한국어</strong></p>

Lumine은 네이티브 시스템 모니터입니다. macOS에서는 메뉴 막대에, Windows에서는 시스템 트레이에 상주합니다. 작은 보라색 대시보드에서 CPU, 메모리, 저장 공간, 배터리와 네트워크를 확인하고 카드를 클릭해 상세 정보를 볼 수 있습니다.

![macOS용 Lumine의 CPU 상세 정보와 시스템 개요](docs/images/cpu.png)

*macOS의 실제 SwiftUI 화면을 로컬 실측값으로 렌더링한 이미지입니다. Windows 버전은 별도의 WPF 인터페이스를 사용하며 위 이미지에 포함되지 않습니다.*

<details>
<summary>시스템 개요(macOS)</summary>
<p><img src="docs/images/overview.png" width="446" alt="시스템 개요(macOS)"></p>
</details>

<details>
<summary>Windows 대시보드(Windows CI 캡처)</summary>
<p><img src="docs/images/windows.png" width="490" alt="Windows 대시보드(Windows CI 캡처)"></p>
</details>

## 다운로드

[GitHub Releases](https://github.com/liziwei01/Lumine/releases/latest)에서 macOS 유니버설 버전(Apple Silicon 및 Intel), Windows x64, Windows ARM64를 다운로드하세요. 압축을 푼 후 실행하세요. Windows 패키지에는 런타임이 포함됩니다. macOS는 임시 서명만 있으며 공증되지 않았고, Windows 패키지는 서명되지 않았습니다.

## 기능

| 항목 | macOS 13+ | Windows 10/11 |
| --- | --- | --- |
| CPU | 전체·논리 코어별 사용률, 기록, 가동 시간 | 전체 사용률, 논리 프로세서 수, 가동 시간 |
| 메모리 | 사용량, 가용 메모리, 스왑, 프로세스 순위 | 물리 메모리 사용률과 가용 용량 |
| 저장 공간 | 볼륨 용량, 수동 파일 분류 | 로컬 볼륨의 가용·전체 용량 |
| 배터리 | 잔량, 상태, 사이클 수, 지원되는 온도 | 잔량 및 전원 연결 상태 |
| 네트워크 | 인터페이스 선택, 속도, 기간별 사용량, 수동 속도 측정 | 인터페이스별 속도와 누적 카운터 |
| 외장 저장 장치 | 마운트된 로컬 외장 볼륨 | Windows가 이동식으로 식별하는 볼륨 |
| 설정 | 색상, 위젯, 소스, 위치, 갱신 간격, 로그인 시 시작 | 언어 및 갱신 간격 |
| UI 언어 | 영어, 중국어 간체·번체, 러시아어, 일본어, 한국어, 스페인어 | 영어, 중국어 간체, 러시아어, 일본어, 한국어 |

Windows 버전은 초기 네이티브 구현으로 macOS보다 기능이 적습니다. 온도, SMART, 파일 분류, 프로세스 조작, 속도 측정 및 로그인 시 시작은 현재 macOS에서만 지원합니다. 읽을 수 없는 값은 사용 불가로 표시합니다. Windows가 고정 디스크로 식별하는 USB 드라이브는 저장 공간 상세 정보에 표시됩니다.

## 빌드 및 실행

### macOS

Xcode 15 이상을 설치하고 `Lumine.xcodeproj`를 열어 **Lumine** 스킴을 실행하거나 저장소 루트에서 다음을 실행합니다.

```sh
xcodebuild -project Lumine.xcodeproj -scheme Lumine -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
codesign --force --sign - --timestamp=none build/Build/Products/Release/Lumine.app
open build/Build/Products/Release/Lumine.app
```

앱을 `/Applications`에 복사하고 메뉴 막대의 모니터 아이콘을 클릭하세요. Dock 아이콘은 없습니다. 톱니바퀴 메뉴에서 설정 또는 종료를 선택할 수 있습니다. 설치 위치를 고정한 뒤 일반 설정에서 로그인 시 시작을 켤 수 있습니다. 임시 서명은 로컬 빌드용이며 다른 Mac에 배포하려면 적절한 서명과 공증이 필요합니다.

### Windows

Windows에 [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)를 설치하고 실행합니다.

```powershell
dotnet run --project windows/Lumine.Windows -c Release
# 런타임이 포함된 포터블 버전 생성
dotnet publish windows/Lumine.Windows -c Release -r win-x64 --self-contained true -o dist/windows-x64
```

출력 폴더의 모든 파일을 유지하고 `dist/windows-x64/Lumine.exe`를 실행하세요. ARM에서는 `win-arm64`를 사용합니다. 창을 닫으면 트레이로 숨겨지고 아이콘을 클릭하면 다시 열립니다. 모니터링을 중지하려면 종료를 선택하세요. 설정은 `%LOCALAPPDATA%\Lumine\settings.json`에 저장됩니다. 관리자 권한, 드라이버 및 백그라운드 서비스는 필요하지 않습니다.

[빌드 워크플로](.github/workflows/build.yml)는 두 플랫폼을 빌드하고 Windows x64·ARM64 결과물을 생성합니다. x64 스모크 테스트는 실제 Windows 지표를 수집하고 WPF 화면을 이미지로 내보냅니다. Windows x64의 실제 지표 수집과 WPF 렌더링은 [Windows CI](https://github.com/liziwei01/Lumine/actions/runs/40080001959)에서 검증되었습니다. ARM64는 빌드했지만 ARM 기기에서는 아직 실행하지 않았습니다. [Windows 구현 설명(영어)](docs/windows.md)을 참조하세요.

## 데이터와 개인정보

모니터링은 로컬 시스템 인터페이스를 사용합니다. 계정, 분석 및 텔레메트리 기능은 없습니다. CPU와 네트워크 속도에는 두 번의 측정이 필요하므로 첫 측정값은 표시되지 않을 수 있습니다. Windows의 네트워크 합계는 기간별 기록이 아닌 어댑터 누적 카운터이며 어댑터 재시작 시 초기화될 수 있습니다. VPN과 가상 어댑터는 중복 집계를 피하도록 별도로 표시합니다.

macOS 파일 분류는 다시 스캔을 클릭할 때만 실행됩니다. 전체 디스크 접근 권한이 없으면 결과가 불완전할 수 있습니다. 캐시와 트래픽 기록은 `~/Library/Application Support/Lumine/`, 설정은 `~/Library/Preferences/app.lumine.monitor.plist`에 저장됩니다. 수동 속도 측정은 Cloudflare에 연결하여 약 28 MB를 전송합니다. 휴지통 비우기는 확인 후 내용을 영구 삭제하며 프로세스 종료 요청으로 저장하지 않은 작업을 잃을 수 있습니다. 이 작업들은 자동 실행되지 않습니다. 온도 측정 가능 여부는 하드웨어와 시스템 접근 조건에 따라 다릅니다.

전체 설정, 지표 정의, 권한과 제거 방법은 [macOS 가이드(중국어)](docs/macos.zh-CN.md)와 [아키텍처 설명(중국어)](docs/architecture.md)에 있습니다.

## 개발

```sh
dotnet run --project windows/Lumine.Core.Tests -c Release
dotnet build windows/Lumine.Windows -c Release
```

.NET 10이 필요합니다. macOS/Linux에서 교차 컴파일할 수 있지만 Windows 앱을 실행하지는 못합니다. 버그 보고에는 OS 버전, 코드 리비전, 해당 지표와 재현 단계를 포함해 주세요. macOS 번역은 `Lumine/*.lproj/Localizable.strings`, Windows 번역은 `windows/Lumine.Windows/Localization.cs`에 있습니다. 플랫폼 지원이나 설치 방법을 변경할 때는 다섯 README를 함께 갱신해 주세요.

디자인은 CleanMyMac의 메뉴 막대 모니터에서 영감을 받았습니다. Lumine은 MacPaw와 무관한 독립 프로젝트이며 해당 브랜드의 이미지나 소재를 포함하지 않습니다. 요구 사항 및 검토는 liziwei가 담당했으며 설계, 코드와 문서는 OpenAI Codex의 도움을 받아 작성했습니다.

## 라이선스

[MIT](LICENSE). macOS 센서 프로토콜의 참고 자료는 [서드파티 고지](THIRD_PARTY_NOTICES.md)에 있습니다.
