# Submissions, HTTP auth, and modern web services

XForms 1.1 has no native support for modern authentication — deliberately.
On the HTTP binding the PROCESSOR completes authorization challenges and
follows redirects; everything else (OAuth, API keys, sessions) is just
HTTP, and the spec's author-facing tool for it is `xf:header`. XFormsKit
keeps the three layers strictly apart; mixing them is what makes "auth"
feel unbounded.

## Layer 1 — the processor: the HTTP protocol (`XFHTTPSubmissionTransport`)

`XFSubmission` decides WHAT to send (URI, method, body, author headers).
The transport decides HOW the conversation runs:

- **Redirects** with a hop limit (`maxRedirects`, default 10). Browser
  method rules: 303 always becomes GET; 301/302 on a non-GET become GET
  and the body is NEVER replayed; 307/308 preserve method and body.
  Relative `Location` resolves against the current URL. On a
  cross-origin hop the author's `Authorization` header stays behind and
  any challenge credentials reset.
- **Cookie jar** (`XFCookieJar`) — one per transport, and ONE TRANSPORT
  PER DOCUMENT (`XFProcessor.defaultTransport`), never the
  process-shared `NSHTTPCookieStorage`. "Login submission, then call the
  API" works because both submissions share the document's jar; `file:`
  and `http:` origins cannot leak into each other, `Secure` cookies stay
  off plain http, `Domain`/`Path`/`Max-Age` honored. A
  `model.transport` override still wins per model (tests keep using
  `XFMapSubmissionTransport`).
- **401 / 407 challenge-response** through the host's `XFSubmissionAuth`
  port: parse `WWW-Authenticate` / `Proxy-Authenticate`, ask the host
  for credentials for the `NSURLProtectionSpace` (host, port, realm,
  scheme), attach `Authorization` (Basic, or Digest MD5/qop=auth — the
  password never travels), retry EXACTLY ONCE, then the response flows
  to `xforms-submit-error` like any other HTTP error (`error-type`
  resource-error, `response-status-code` 401). No new event for 401.
- **Preemptive Basic is off by default** (wrong for shared transports).
  The author opts in with `preemptive-authentication="true"` (Orbeon's
  `xxf:` spelling, any prefix), the host by setting
  `request.preemptiveAuth`.
- TLS client certificates: the `clientCertificateForSpace:` hook exists
  on the protocol; wiring depends on the platform TLS stack and is not
  yet connected on GNUstep's.

Do NOT put OAuth, SAML, or AWS SigV4 inside this layer.

## Layer 2 — the form author: headers and instances

`xf:header` (with `@combine` append | prepend | replace, `@nodeset`
iteration, `xf:name` / `xf:value` expressions — implemented since G-17)
is the correct way to talk to modern services:

```xml
<xf:instance id="auth"><auth xmlns=""><token/></auth></xf:instance>
<xf:submission id="call-api" method="get"
               resource="https://api.example.com/v1/me"
               replace="instance" instance="result">
  <xf:header combine="replace">
    <xf:name>Authorization</xf:name>
    <xf:value value="concat('Bearer ', instance('auth')/token)"/>
  </xf:header>
</xf:submission>
```

Token acquisition is ANOTHER submission (the token endpoint), with
`replace="instance"` writing into `instance('auth')`; later submissions
read it. The same pattern covers `X-Api-Key`, CSRF tokens from a
previous GET, and any custom `X-Auth-*`. OAuth2 password /
client-credentials grants are also just submissions
(`application/x-www-form-urlencoded` body, parse the token out).
Authorization-code + PKCE needs a browser — that is a HOST problem
(`loadRequestHandler`); the processor never opens a WebView and never
gets a built-in OAuth client.

The author's own `Content-Type` / `Accept` / `Authorization` headers win
over anything the transport or serializer would add.

## Layer 3 — the host app: secrets and interactive login

Credentials must not live in the saved XHTML. The host has two ports:

- `XFSubmissionAuth` on the transport: read the Keychain / a secrets
  file / show a login sheet when a challenge arrives.
- `XFHeaderInjectingTransport` (inner + `extraHeaders`): inject an
  `Authorization` from the host's own session, or an API key, without
  touching form markup. Author headers win over injected ones.

## Security rules

- Never log request headers or bodies that carry `Authorization`,
  `Cookie`, or password fields (the designer's submission tester
  redacts them in its history).
- Tokens live in a DEDICATED instance, not the business instance; put
  `relevant="false()"` binds on password/secret nodes so a careless
  `ref="/"` submit does not ship them.
- Cookies and Basic credentials are keyed per host — they never cross
  origins (redirect stripping + host-keyed jar).
- Preemptive Basic only on explicit opt-in.
