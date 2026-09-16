# The Spaces website

The site — privacy policy, terms, pricing, membership, blog and support — is
**not** served from this repository.

It lives in the Spacechat repository under `spaces/`, and the Spacechat server
serves it at `https://www.spacechat.app/spaces` (see the `/spaces` routes in
`server.js`). That keeps every address the game shows on spacechat.app rather
than on a second host, and means the pages deploy with Spacechat.

The app reaches them through `SpacesLinks`
(`Sources/AI/App/SpacesLinks.swift`), which is the only place in the game that
names a host.

To change a page, edit it in the Spacechat repo and deploy Spacechat.
