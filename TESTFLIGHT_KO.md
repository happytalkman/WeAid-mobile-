# MARK Mobile 0.2.0 — TestFlight 준비

이 패키지는 TestFlight 배포용 소스와 빌드·업로드 설정입니다. 서명·업로드된 앱이나 초대 링크는 아직 없습니다. 이 작업 환경에서는 Xcode를 실행할 수 없어 실제 iOS 컴파일과 실행은 미검증입니다.

## 포함한 변경

- 0.2.0 버전 및 빌드 번호를 Xcode 설정과 연결.
- 앱 설정에 현재 버전/빌드 표시.
- 앱 사용 중에도 예약 알림을 배너/소리로 표시.
- Mac용 검증 → 아카이브 → TestFlight 업로드 스크립트.
- GitHub Actions의 서명 없는 Release 컴파일 검사.
- TestFlight 설명, 테스트 항목, 심사 안내 초안.

## 준비물

1. Apple Developer Program에 가입된 본인/회사 계정.
2. Xcode 26 이상과 해당 iOS SDK를 갖춘 Mac. iOS 앱의 최소 실행 버전은 17로 유지했습니다. 업로드 SDK 버전과 최소 실행 버전은 다릅니다.
3. 고유 Bundle ID와 App Store Connect의 앱 레코드.
4. 개발 Team 권한 및 Xcode에 로그인한 Apple 계정. 인증서·프로비저닝은 Xcode 자동 서명으로 준비합니다.

Apple의 현재 SDK 최소 요건: https://developer.apple.com/news/upcoming-requirements/?id=04282026a
업로드 시점에 요건이 변경될 수 있으므로 최신 Xcode를 사용하세요.

## 권장: Xcode 화면으로 업로드

1. `MarkMobile.xcodeproj` 열기 → Signing & Capabilities에서 Team 선택.
2. `com.personal.markmobile`을 본인 Bundle ID로 변경. App Store Connect 앱과 일치해야 합니다.
3. 먼저 실제 아이폰에서 실행하여 음성·일정·미리 알림·문자·단축어 기능 확인.
4. 실행 대상을 일반 iOS 기기로 선택 → Product → Archive.
5. Organizer → Validate App → Distribute App → App Store Connect → Upload.
6. App Store Connect에서 처리 완료 후 암호화 관련 질문과 베타 메타데이터 작성.
7. TestFlight 내부 테스트 그룹에 빌드와 본인 계정을 연결.
8. 외부 초대 링크를 사용하려면 외부 테스트 그룹을 만들고 필요한 베타 심사를 진행.

빌드 업로드 성공과 테스트 초대 가능 상태는 별개입니다. Apple 처리, 서명, 계정 계약, 메타데이터, 심사 상태를 확인해야 합니다.

## 명령으로 진행하는 경우

터미널에서 이 문서가 있는 폴더로 이동합니다.

```sh
# 서명 없는 컴파일 검사만 수행
bash scripts/testflight.sh --verify

# 본인의 실제 값으로 설정. 아래 값들은 예시입니다.
export MARK_TEAM_ID='ABCDEFGHIJ'
export MARK_BUNDLE_ID='com.yourcompany.markmobile'
export MARK_BUILD_NUMBER='2'

# 서명된 아카이브만 생성
bash scripts/testflight.sh --archive

# 검증·아카이브 후 App Store Connect에 업로드
bash scripts/testflight.sh --upload
```

동일 버전 재업로드 시 이미 사용한 빌드 번호보다 큰 번호를 사용하세요. 스크립트는 Xcode에 로그인한 계정과 자동 서명을 사용합니다. 인증이 필요한 경우 Xcode Organizer 방식으로 진행하세요. Apple 비밀번호나 인증서 비밀키를 소스/채팅에 넣지 마세요.

`--upload`도 외부 테스터 초대나 심사를 자동으로 신청하지 않습니다. 초대 그룹과 메타데이터는 App Store Connect에서 설정합니다.

## Mac이 없는 경우

이 폴더의 내용을 새 GitHub 저장소 최상위에 올리면 `.github/workflows/ios-build.yml`을 통해 macOS 실행 환경에서 서명 없는 컴파일 검사를 실행할 수 있습니다. ZIP의 바깥 폴더를 한 단계 더 중첩해 올리지 마세요.

자동 빌드는 실제로 실행되지 않았습니다. 이 설정은 컴파일 검사용이며, 서명·IPA 생성·TestFlight 업로드는 하지 않습니다. Mac을 보유하지 않아도 macOS 클라우드 빌드 서비스를 별도로 구성할 수 있지만 Apple 개발자 계정과 서명 설정은 필요합니다.

## App Store Connect에 넣을 정보

`beta/metadata_ko.md`에 앱 설명·테스트 항목·심사 안내 초안을 넣었습니다. 실제 담당자의 연락처와 필요한 테스트 접근 정보를 채워 넣으세요. 존재하지 않는 테스트 계정, 지원 이메일, 개인정보 URL은 만들지 않았습니다.

외부 심사 전에 실제 Google 데이터 처리 방식과 서비스 운영 주체를 반영한 개인정보처리방침 URL을 준비해야 합니다. 개인정보 매니페스트는 App Store Connect의 개인정보 응답을 대체하지 않습니다. 암호화 질문은 실제 구현과 Apple 안내를 확인해 답변하세요.

## 완료 여부

- 소스/프로젝트/업로드 스크립트: 작성 및 정적 검증 완료.
- Apple SDK 컴파일 및 아이폰 기능 테스트: 미실행.
- Apple 서명·업로드·초대 발급: 미실행, 계정 설정 필요.

이 파일과 ZIP을 TestFlight 앱에 직접 넣어 설치할 수는 없습니다. Apple에 업로드된 빌드에 대한 초대가 있어야 TestFlight에서 설치할 수 있습니다.
