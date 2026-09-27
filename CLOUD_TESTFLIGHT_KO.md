# Mac 없이 TestFlight에 올리기

## 실제 진행 결과

- GitHub macOS 환경에서 Release 시뮬레이터용 Xcode 컴파일 성공.
- 확인 실행: https://github.com/happytalkman/WeAid-mobile-/actions/runs/36277919287
- 실제 기기 실행과 Apple 서명·업로드는 아직 미실행입니다.

## 다음 설정

GitHub 저장소 Settings → Environments → `testflight` 환경을 만듭니다. 이 환경에 다음 값들을 등록해야 수동 업로드 작업을 실행할 수 있습니다.

Variables:
- `APPLE_TEAM_ID`: 본인 Apple 개발 Team ID
- `APP_BUNDLE_ID`: Apple에 등록한 이 앱의 Bundle ID

Secrets:
- `APPLE_CERTIFICATE_P12_BASE64`: Apple Distribution 인증서와 개인키가 포함된 암호화 P12 파일의 Base64
- `APPLE_CERTIFICATE_PASSWORD`: P12 암호
- `APPLE_PROFILE_BASE64`: 같은 Team/Bundle ID의 App Store 배포 프로파일 Base64
- `ASC_KEY_ID`: App Store Connect API 키 ID
- `ASC_ISSUER_ID`: 해당 키의 Issuer ID
- `ASC_PRIVATE_KEY_BASE64`: 해당 API 키 P8 파일의 Base64

이 값들은 소스나 채팅에 올리지 않습니다. 인증서와 프로파일을 준비하지 않았다면 먼저 Apple 개발자 포털에서 발급해야 합니다. Mac이 없는 경우에도 CSR 생성과 인증서 변환은 다른 운영체제에서 가능하지만, 인증서 발급/프로파일 등록과 비밀키의 안전한 보관 절차가 필요합니다. API 키는 App Store Connect 업로드 권한을 가진 본인 계정에서 생성합니다.

## 실행

1. App Store Connect에 Bundle ID가 일치하는 iOS 앱 레코드를 만듭니다.
2. 위 설정이 준비되면 Actions → **TestFlight signed upload** → **Run workflow**.
3. 작업은 컴파일 검증 → 임시 Keychain 서명 → 아카이브 → Apple 업로드 순서로 실행됩니다.
4. 업로드 후 Apple의 처리 완료 및 암호화 질문을 확인합니다.
5. TestFlight 테스트 그룹에 빌드를 연결하고 본인을 추가합니다. 외부 테스트는 필요한 베타 심사를 거칩니다.

빌드 번호는 해당 워크플로 실행 번호에 1000을 더해 사용합니다. 이미 더 큰 번호를 Apple에 업로드했다면 워크플로의 기준값을 조정하세요.

공개 저장소에도 Secrets 값은 커밋되지 않습니다. 워크플로 로그에 인증 정보를 직접 출력하지 마세요. Actions 워크플로를 수정할 수 있는 사람은 비밀값에 영향을 줄 수 있으므로 저장소/환경 접근 권한을 관리하세요.

**현재 업로드 워크플로는 설정과 정적 검증만 마쳤으며, 서명 정보가 없어 실행하지 않았습니다. 컴파일 성공은 TestFlight 등록 완료를 의미하지 않습니다.**
