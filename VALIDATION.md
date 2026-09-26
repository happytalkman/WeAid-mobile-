# 검증 기록

검증 범위: 소스와 프로젝트의 정적 구조 검증. 실행/빌드 성공을 뜻하지 않습니다.

통과:
- Swift 소스 7개를 tree-sitter-swift로 구문 분석: ERROR/missing 노드 없음.
- Xcode project.pbxproj를 OpenStep 프로젝트 파서로 읽기 성공.
- Info.plist 및 PrivacyInfo.xcprivacy를 plist 파서로 읽기 성공.
- 앱 아이콘 asset JSON 읽기 성공.
- 프로젝트가 참조하는 소스·리소스 파일 존재 확인.
- PC 대시보드 주소/설정 및 PC 연결 코드가 iOS 소스에 없음을 확인.

미실행:
- Swift 컴파일/타입 검사, Xcode 빌드, iOS 시뮬레이터: 현재 환경에 Apple SDK/Xcode 없음.
- 실제 iPhone 설치 및 코드 서명: 사용자 Mac과 Apple 개발 Team 필요.
- Gemini 인증/대화/사진 요청: API 키 미제공.
- 음성 인식, EventKit 저장, 알림 전달, 전화·문자·단축어 실행: 실제 기기 확인 필요.

Mac에서 우선 확인할 순서:
1. README의 xcodebuild 명령으로 시뮬레이터용 빌드.
2. API 키 없이 ‘미리알림 우유 사기’를 입력해 실행 확인 화면이 열리는지 확인.
3. 권한 거절 시 안내 표시, 허용 시 미리 알림에 1건 저장되는지 확인.
4. 일정 저장/취소, 문자 취소/전송 상태가 구분되는지 확인.
5. 1분 뒤 알림을 예약하고 앱을 백그라운드로 이동해 전달 확인.
6. 단축어 ‘손전등 켜기’를 직접 생성한 뒤 연결 실행 확인.
7. Gemini 키를 설정하고 모델을 선택하여 텍스트·사진 요청 확인.
8. 네트워크 차단 시 입력 복원, 요청 중지, 대화 삭제, 녹음 중 앱 전환을 확인.

본 버전은 개인 개발용 초안이며 App Store 심사 제출 준비 완료본이 아닙니다.

## 0.2.0 추가 검증

Swift 7개 구문, Xcode 파일 참조, plist, GitHub Actions YAML, bash 구문 검사 통과. Linux에서는 Xcode 필요 안내와 함께 업로드 전에 종료되는 것을 확인했습니다. Apple SDK 컴파일·서명·기기 실행·업로드는 미실행입니다.
