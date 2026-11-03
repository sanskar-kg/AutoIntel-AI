# Remote Config pricing

Lookup prices are controlled from Firebase Remote Config. No app rebuild or
Cloud Functions redeploy is required for a price change.

Create and publish these parameters in the Firebase Console under Remote
Config:

| Parameter | Default value | Meaning |
| --- | ---: | --- |
| `lookup_rc_price_paise` | `200` | Vehicle Details lookup price (₹2) |
| `lookup_phone_price_paise` | `700` | Owner Phone Search price (₹7) |

Values are integer paise, not rupees. For example, ₹7 is `700`.

The app receives the prices from `GET /v1/config`. The Cloud Function also
reads the published Remote Config template when charging a lookup, with a
short cache and safe defaults if Remote Config is temporarily unavailable.

After publishing a change, allow up to roughly one minute for warm Cloud
Function instances to refresh their cached pricing. A newly started instance
reads the current published template immediately.

## Onboarding wallet controls

Publish these in a Remote Config parameter group such as `onboarding_wallet`:

| Parameter | Type | Default | Meaning |
| --- | --- | ---: | --- |
| `onboarding_wallet_spotlight_enabled` | Boolean | `true` | Show the wallet onboarding experience on first launch |
| `onboarding_wallet_min_recharge` | String | `20` | Minimum recharge in rupees |

The onboarding minimum is stored as a string in rupees because it is a
human-facing amount. Enter `20` for ₹20, not `2000`. The app and backend
convert it to paise internally. Lookup price parameters above remain paise.
