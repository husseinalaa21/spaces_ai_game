# Version 4 login buttons

Space Dots & AI uses Spacechat's login button hierarchy and native styling while retaining its approved four-Dot logo.

- Primary recovery login: full-width blue gradient capsule, Spacechat logo in a white circle, and a forward arrow.
- Apple: the native black Continue with Apple control, aligned to the same width.
- Google: Spacechat's dark provider button and multicolor Google mark, visible only when the Spaces iOS provider configuration enables it.
- Guest: a separate quiet capsule at launch.
- Phrase and recovery choices: matching rounded cards, colored icon tiles, readable subtitles and chevrons; the create option has a tonal blue background.
- Text can wrap as accessibility sizes grow, with rounded corners retaining space around the label; the page scrolls on smaller displays. Busy and error handling, phrase import/create/recovery routes and authentication payloads remain the existing implementation.

Style references (in the sibling Spacechat repository):

- `ios/App/App/Features/Authentication/Login/LoginView.swift`: `NativeSpacechatLoginButton`, `NativeLoginMethodButtonLabel`, `NativeSocialLoginButtons`.
- `ios/App/App/Features/Authentication/Login/Components/LoginComponents.swift`: `LoginBrand` and `NativeLoginChoiceButton`.
- `client/src/pages/LoginPage.jsx` and `LoginPage.css`: method ordering, gradient, capsule sizing, logo placement and provider treatments.

The Spacechat and Google logo assets come from those existing Spacechat assets. Apple keeps its native control. No authentication endpoints or request/response contracts change in this visual update.

Version metadata: marketing version **4.0**, build **4**, in both the Xcode project and `project.yml`.

## Verification

- Simulator build: passed; built bundle reports version 4.0 / build 4.
- Existing account regression checks: 32 passed.
- Login UI navigation and large-text checks: both passed on iPhone 17 Pro Max / iOS 27.0; the largest accessibility text can be scrolled fully into view.
- Screenshots: `validation/login-v4.png`, `validation/login-recovery-v4.png`, and `validation/login-large-text-v4.png`.
- XCTest result bundle: `/tmp/spacesgameai-login-v4-final.xcresult`.

`Tests/run-login-ui-checks.sh SIMULATOR_UUID BUILT_APP_PATH` creates a temporary XCTest project and exercises the actual app. Requires XcodeGen. The checks do not authenticate against a provider or submit a recovery phrase.
