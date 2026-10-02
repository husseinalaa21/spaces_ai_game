# App Review: Guideline 3.1.2(c), auto-renewing subscriptions

Rejected: submission 2e739288-6306-461b-852d-2b59e20872a1, version 1.0 (11),
reviewed 24 September 2026 on iPhone 17 Pro Max.

App Review asks for two things, in two places. The **app** must show the
subscription's title, length, price and working Terms of Use and Privacy links.
The **App Store Connect metadata** must carry a Privacy Policy URL and a Terms
of Use (EULA) link. The app side is done in code (below). The metadata side can
only be changed in App Store Connect.

## 1. In the app (done)

Every screen that sells the subscription (the paywall opened from Settings and
from the menu, and the Store's membership card) now shows, straight from the
StoreKit product and never hardcoded:

| Required | Where it comes from | Shown as |
| --- | --- | --- |
| Title | `Product.displayName` | "Spaces VIP" |
| Length | `subscriptionPeriod` | "1 month, renews automatically" |
| Price (and per unit) | `displayPrice` + period | "$9.99 per month" |
| Terms of Use | `SpacesLinks.terms` | "Terms of Use" link |
| EULA | `SpacesLinks.appleEULA` | "EULA" link (Apple's standard licence) |
| Privacy Policy | `SpacesLinks.privacy` | "Privacy Policy" link |

Restore Purchases and the full auto-renew disclosure sit beside the buy button.
Settings > About also lists the Privacy Policy, Terms of Use and EULA. The code
is `SubscriptionDisclosureView.swift` (shared by both screens) and
`StoreManager.swift`.

All three addresses were checked live on 25 September 2026 and return HTTP 200:

- https://www.spacechat.app/spaces/privacy
- https://www.spacechat.app/spaces/terms (states that Apple's standard EULA applies)
- https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

## 2. In App Store Connect (you do this)

**Privacy Policy field.** App Store Connect > My Apps > Spaces - Dots and AI >
App Information > *Privacy Policy URL*:

```
https://www.spacechat.app/spaces/privacy
```

**Terms of Use (EULA).** The app uses Apple's standard EULA, so add this to the
end of the **App Description** (version page) and leave the *License Agreement*
field on Apple's standard agreement:

```
Spaces VIP is an auto-renewing subscription: $9.99 per month, 1 month, charged to your Apple Account and renewed automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel any time in your Apple Account settings.

Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://www.spacechat.app/spaces/privacy
```

**App Review Information > Notes** (also needed for future submissions):

```
Subscription: Spaces VIP, 1 month, auto-renewing. To see the purchase screen: launch the app, tap "Continue without an account", open the Settings tab (gear icon, top banner), then tap "Premium" under Membership & Purchases. That screen shows the subscription title, length, price, Restore Purchases, and links to the Terms of Use, EULA and Privacy Policy. The same links are in Settings > About. The Privacy Policy URL and the EULA link are also in the App Store metadata.
```

## 3. Reply to App Review

Once the metadata is saved, reply in App Store Connect with a screen recording
(the message asks for one) of: Settings > Premium showing the title, length and
price, then tapping Terms of Use, EULA and Privacy Policy so each page opens.
Suggested reply:

```
Hello, thank you for the review. The Privacy Policy URL is now set in App Information, and the Terms of Use (EULA) link is in the App Description. The purchase screen (Settings > Premium) shows the subscription title, length and price with working links to the Terms of Use, EULA and Privacy Policy. A screen recording is attached.
```

The Terms and Privacy links were already in the paywall in the last committed
code (since 15-16 September), and the review's "Next Steps" only asks for the
metadata update, so the reply can go with the existing build if you'd rather not
wait for a new one. A new build is only needed if you want the recording to show
the clearer title/length/price rows added here. Confirm build 11 is that code
before relying on this.

---

## Second rejection: submission 3852f4a3-419c-45d2-9eff-599025ff77bd (2 October 2026)

Reviewed on iPad Air 11-inch (M3), version 1.0 (30). Same guideline (3.1.2(c)). The
message this time names exactly one gap: **a functional link to the Terms of Use
(EULA) in the App Store metadata.** Nothing in the app is asked for. The Privacy
Policy and in-app links are not mentioned again.

Checked live on 2 October 2026 (all HTTP 200):

- https://www.spacechat.app/spaces/terms
- https://www.spacechat.app/spaces/privacy
- https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

### What to do in App Store Connect

Do **both** of these so the reviewer finds the link wherever they look.

1. **App Description** (the version page, in the language the reviewer sees, usually
   English (U.S.)). Put this at the very end, as plain text, so the URL is tappable:

   ```
   Spaces VIP is an auto-renewing subscription: $9.99 per month, 1 month, charged to your Apple Account and renewed automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel any time in your Apple Account settings.

   Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
   Privacy Policy: https://www.spacechat.app/spaces/privacy
   ```

   (Apple's rule: with the standard Apple EULA, the link goes in the App Description.)
   Leave App Information > *License Agreement* on **Apple's standard agreement**.
   Do not paste the same text only into *Promotional Text* or *What's New*: those are
   not the description.

2. **App Information > Privacy Policy URL**: `https://www.spacechat.app/spaces/privacy`
   (also confirm it is saved for every localisation you ship).

Then make sure the price in that paragraph matches the price in App Store Connect
(Subscriptions > Spaces VIP) and what the app's purchase screen shows.

### App Review Information > Notes (keep this for future submissions)

```
Subscription: Spaces VIP, 1 month, auto-renewing, $9.99 per month. To see the purchase screen: launch the app, tap "Continue without an account", open the Settings tab (gear icon in the top banner), then tap "Premium" under Membership & Purchases. It shows the subscription title, length and price, Restore Purchases, and working links to the Terms of Use, EULA and Privacy Policy (also in Settings > About). The Terms of Use (EULA) link is in the App Description and the Privacy Policy URL is in App Information.
```

### Reply to App Review (with the screen recording they ask for)

Record, on an iPad if you can (that is what they used): Settings > Premium showing the
title, length and price; tap **Terms of Use**, **EULA** and **Privacy Policy** so each
page opens; then show the App Description on the product page with the EULA link at
the bottom. Then reply:

```
Hello, thank you for the review. The Terms of Use (EULA) link is now in the App Description, and the Privacy Policy URL is set in App Information. In the app, Settings > Premium shows the subscription title, length and price with working links to the Terms of Use, EULA and Privacy Policy. A screen recording is attached.
```

### One thing to check before replying

The review says build **1.0 (30)**, while this repository is **2.6 (2)**. Confirm in
App Store Connect which build is attached to the submission and that it contains
`SubscriptionDisclosureView` (the paywall disclosure). If the attached build is older
than that code, attach a newer build; otherwise the metadata change above is all that
is needed.
