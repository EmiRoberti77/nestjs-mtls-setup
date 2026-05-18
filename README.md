# mTLS Sample — NestJS Server + Node Client

A minimal **mutual TLS (mTLS)** demo: a NestJS HTTPS server that requires a client certificate, and a Node.js client that presents one. Both sides trust the same local Certificate Authority (CA).

## What is mTLS?

| | Normal HTTPS | mTLS |
|---|--------------|------|
| Server proves identity | Yes | Yes |
| Client proves identity | No (password/cookie/API key later) | **Yes (certificate)** |
| Anonymous clients | Allowed | **Rejected** (with this config) |

TLS encrypts traffic and authenticates the **server**. mTLS adds authentication of the **client** during the TLS handshake, before HTTP runs.

## Trust model (this project)

All certificates are issued by a **local dev CA** you create with OpenSSL scripts in `certs/`.

```
                    ca.crt  (+ ca.key — keep private)
                   "Local Dev CA"
                          |
          +---------------+---------------+
          |                               |
    server.crt                        client.crt
    CN=localhost                      CN=my-client
    EKU: serverAuth                   EKU: clientAuth
    SAN: localhost, 127.0.0.1
          |                               |
    server.key                        client.key
    (private)                         (private)
```

- **`ca.crt`** — trust anchor. Both server and client load it to decide which peers they accept.
- **`server.crt` + `server.key`** — server identity (TLS server role).
- **`client.crt` + `client.key`** — client identity (TLS client role).

Private keys never leave the machine; the handshake only proves possession of the key.

## Onboarding clients and distributing certificates

You (or your PKI process) are responsible for **issuing** credentials. Callers do not generate their own client certs unless you give them a CSR workflow.

### One CA per environment — new cert per client

| Item | Per new client? | Notes |
|------|-----------------|-------|
| **CA** (`ca.crt` / `ca.key`) | **No** | One CA per trust domain (e.g. dev, prod). All services use the same `ca.crt` to verify peers. |
| **Client cert + key** | **Yes** | Issue a **unique** `client.crt` + `client.key` per integrating service (e.g. `payments`, `reporting`). |
| **Server cert + key** | N/A | One pair for your Nest server, signed by the same CA. |

```
One CA (ca.crt + ca.key — ca.key never leaves your control)
    ├── server.crt + server.key       ← your Nest server
    ├── payments.crt + payments.key   ← client A
    ├── reporting.crt + reporting.key ← client B
    └── ...
```

Create a new CA only for a **new environment** or **security boundary**, not for every new client. To onboard client B, re-run signing (adapt `client.ps1` with a new `-subj "/CN=reporting"`) — do not create `ca.ps1` again.

### Files to give each connecting service

Give the integrating team **three files**:

| File | Purpose |
|------|---------|
| **`ca.crt`** | Trust your HTTPS server (and optionally other internal peers). Same file for all clients in that environment — send once if they do not already have it. |
| **`client.crt`** | Their service identity (signed by your CA). **Unique per client.** |
| **`client.key`** | Private key for that cert. **Secret** — treat like a password; prefer a secrets manager over email. |

They configure them the same way as `src/client/client.tsx` (`ca`, `cert`, `key` on `https.Agent` or equivalent).

### Do not share

| File | Why |
|------|-----|
| **`ca.key`** | Anyone with it can mint trusted certificates. |
| **`server.key`** | Your server private key. |
| **`server.crt`** | Usually unnecessary — TLS sends it during the handshake; clients trust it via `ca.crt`. |
| **Another team's `client.key`** | Each client gets only their own key. |
| **`*.csr`, `*.ext`, `*.srl`, `*.ps1`** | Generation artifacts; not used at runtime. |

### What you keep on the server

| File | Role |
|------|------|
| `ca.crt` | Verify incoming client certificates |
| `server.crt` + `server.key` | Present server identity to clients |

In production, distribute bundles via Vault, Kubernetes secrets, cert-manager, or a service mesh — not ad-hoc file shares.

## Project layout

```
mtls_server/
├── certs/                 # PKI assets (generated locally, gitignored)
│   ├── ca.ps1             # Create CA
│   ├── server.ps1         # Server cert + SAN
│   ├── client.ps1         # Client cert + clientAuth
│   ├── ca.crt / ca.key
│   ├── server.crt / server.key
│   └── client.crt / client.key
├── src/
│   ├── main.ts            # Nest HTTPS + mTLS options
│   └── client/
│       └── client.tsx     # axios + https.Agent (mTLS client)
└── package.json
```

## How mTLS exchanges data (overview)

```mermaid
flowchart TB
    subgraph AppLayer["Application layer (after TLS)"]
        HTTP["HTTP: GET / → JSON/text response"]
    end

    subgraph TLS["TLS record layer (encrypted)"]
        REC["Encrypted records: headers + body"]
    end

    subgraph Handshake["TLS handshake (once per connection)"]
        H["Certificate exchange + key agreement + Finished"]
    end

    Client["client.tsx"] --> Handshake
    Handshake --> Server["main.ts / NestJS"]
    Handshake --> TLS
    TLS --> AppLayer
```

1. **Handshake** — negotiate TLS version/ciphers; exchange and verify certificates; derive session keys.
2. **Record layer** — all HTTP bytes are encrypted/authenticated inside TLS records.
3. **HTTP** — Nest sees a normal `IncomingMessage`; TLS is already done in Node's `https` server.

## TLS handshake (detailed sequence)

This is what happens when you run `pnpm run client` against `pnpm run start`:

```mermaid
sequenceDiagram
    autonumber
    participant C as Client (client.tsx)
    participant S as Server (main.ts)

    Note over C,S: ClientHello / ServerHello<br/>Agree TLS version and ciphers

    S->>C: Certificate (server.crt)
    Note over C: Verify server.crt signed by ca.crt<br/>Check SAN matches localhost

    S->>C: CertificateRequest
    Note over S: requestCert: true

    C->>S: Certificate (client.crt)
    Note over C: Prove ownership of client.key<br/>(sign handshake data)

    Note over S: Verify client.crt signed by ca.crt<br/>rejectUnauthorized: true

    C->>S: Finished (encrypted)
    S->>C: Finished (encrypted)

    Note over C,S: Session keys derived — channel is encrypted

    C->>S: GET / (HTTP inside TLS)
    S->>C: 200 Hello World! (HTTP inside TLS)
```

If any verification step fails, Node aborts the connection — your Nest controller never runs.

## What each side configures

### Server (`src/main.ts`)

```typescript
httpsOptions: {
  key: server.key,
  cert: server.crt,
  ca: ca.crt,                    // which client CAs to trust
  requestCert: true,             // ask client for a certificate
  rejectUnauthorized: true,      // reject if client cert invalid/missing
}
```

| Option | Effect |
|--------|--------|
| `key` / `cert` | Server presents its identity to clients |
| `ca` | Only client certs signed by this CA are accepted |
| `requestCert` | Enables mutual TLS (client must send a cert) |
| `rejectUnauthorized` | Do not allow connections without a valid client cert |

### Client (`src/client/client.tsx`)

```typescript
new https.Agent({
  ca: ca.crt,                    // trust server certs from this CA
  cert: client.crt,              // client identity
  key: client.key,
  rejectUnauthorized: true,      // reject if server cert invalid
})
```

| Field | Effect |
|-------|--------|
| `ca` | Trust server only if `server.crt` chains to this CA |
| `cert` / `key` | Present client identity when server requests it |
| `rejectUnauthorized` | Fail if server cert is wrong/expired/wrong host |

## Certificate generation

Certificate files (`*.crt`, `*.key`, etc.) are listed in `.gitignore`. Generate them locally before running the app.

From `certs/` (requires OpenSSL; PowerShell scripts set `OPENSSL_CONF` for Anaconda/Git OpenSSL on Windows):

```powershell
cd certs
.\ca.ps1       # ca.key, ca.crt (10-year self-signed CA)
.\server.ps1   # server.key, server.crt (SAN: localhost, 127.0.0.1)
.\client.ps1   # client.key, client.crt (EKU: clientAuth)
```

**Extensions matter:**

- **Server** — `subjectAltName` so `https://localhost` validates; `extendedKeyUsage=serverAuth`.
- **Client** — `extendedKeyUsage=clientAuth` so the cert is valid for client authentication.

## Running the demo

This project uses **pnpm** (`pnpm-lock.yaml`).

```powershell
# From project root (mtls_server/)
pnpm install

# If pnpm reports ERR_PNPM_IGNORED_BUILDS, approve builds first:
#   pnpm approve-builds --all
# Then set allowBuilds in pnpm-workspace.yaml to true for @nestjs/core, esbuild, unrs-resolver

pnpm run start          # Terminal 1 — HTTPS on :3000

pnpm run client         # Terminal 2 — mTLS GET https://localhost:3000
```

Expected client output: `Hello World!` (or your controller response).

## What fails without mTLS pieces

| Scenario | Result |
|----------|--------|
| Browser / curl without client cert | TLS handshake fails (server requires cert) |
| Client without `ca.crt` matching server | Client rejects server |
| Client with random cert (not signed by `ca.crt`) | Server rejects client |
| `rejectUnauthorized: false` | May connect but **skips verification** — not secure |

## Data flow after the handshake (one HTTP request)

```mermaid
flowchart LR
    subgraph ClientProcess["Node client process"]
        A1["axios.get(url, { httpsAgent })"]
        A2["TLS encrypts HTTP request"]
    end

    subgraph Network["TCP :3000"]
        N["Ciphertext on the wire"]
    end

    subgraph ServerProcess["Node server process"]
        B1["TLS decrypts → plain HTTP"]
        B2["Nest routing → AppController"]
        B3["TLS encrypts response"]
    end

    A1 --> A2 --> N --> B1 --> B2 --> B3 --> N --> A2
```

- **On the wire:** only encrypted TLS records (certificates are sent during the handshake; application data is encrypted afterward).
- **In Nest:** `req` / `res` look like normal HTTP; certificate details are available on `req.socket` if you want to read the client CN later.

## Optional: reading the client identity in Nest

TLS verification happens in Node before Nest. To use the client name in app logic:

```typescript
const cert = req.socket.getPeerCertificate();
// cert.subject.CN → e.g. "my-client"
```

This sample does not implement that guard yet — any cert signed by your CA is accepted.

## mTLS vs API keys in HTTP headers

Client certificates and API keys both authenticate callers, but at **different layers** and for **different jobs**.

### What mTLS replaces well

If an API key in a header only means **“this integrated system is allowed to connect”**, mTLS can replace it:

| API key in header | mTLS equivalent |
|-------------------|-----------------|
| `Authorization: Bearer …` or `X-API-Key: …` | Valid **`client.crt` + `client.key`** during the TLS handshake |
| Shared secret rotated manually | Per-client cert you issue or revoke |
| “Is this request from an approved integration?” | Node verifies the cert **before** Nest runs (`requestCert` + `rejectUnauthorized` in `main.ts`) |

This sample has **no** API-key guard — TLS is the gate. A caller without your client cert never reaches your controllers.

### What mTLS does not replace by itself

| API keys / tokens often handle | mTLS alone |
|--------------------------------|------------|
| **End-user identity** (Alice vs Bob) | Identifies the **service** (`CN=my-client`), not the human user |
| **Scopes** (`read:orders`, `admin`) | Requires app logic (e.g. map cert CN → roles) |
| **Per-resource authorization** | Still JWT, sessions, or policy in Nest guards |
| **Browser / mobile public APIs** | mTLS is awkward in browsers; JWT or API keys are common |

**Short version:**

- **mTLS** → “Which **machine / service** is calling?”
- **API key / JWT** → “Which **user** or **token** is allowed to do **what**?”

### Common production patterns

| Pattern | Use when |
|---------|----------|
| **mTLS only** | Service-to-service; identity = client cert CN |
| **mTLS + JWT** | TLS proves the service; JWT proves the user or action inside the service |
| **mTLS + API key** | Rare redundancy for machine clients |
| **API key + public HTTPS only** | Simpler ops; no client cert lifecycle (still use TLS for encryption) |

## Security notes (local dev only)

- **`ca.key`** is highly sensitive; do not commit or share it.
- This CA is **not** in browsers' trust stores — only your client uses it via `ca: fs.readFileSync('ca.crt')`.
- Certificates here are for **learning**; use proper PKI/HSM/processes in production.
- Rotating certs: re-run the `.ps1` scripts and restart server/client.

## Scripts reference

| Script | Command |
|--------|---------|
| Start server | `pnpm run start` |
| Start server (watch) | `pnpm run start:dev` |
| Run mTLS client | `pnpm run client` |
| Build | `pnpm run build` |

## Dependencies

- **Server:** NestJS with Node `https` options passed to `NestFactory.create`.
- **Client:** `axios` + Node `https.Agent`.
- **Client runner:** `tsx` (`pnpm run client`).

## Troubleshooting

| Problem | Check |
|---------|--------|
| `ENOENT` on cert paths | Generate certs in `certs/`; run server from project root (`process.cwd()/certs`) |
| `UNABLE_TO_VERIFY_LEAF_SIGNATURE` | Client `ca` must be your `ca.crt` |
| `alert bad certificate` / handshake failure | Client must send `client.crt` + `client.key`; server needs `requestCert: true` |
| Hostname mismatch | Use `https://localhost` and ensure `server.crt` SAN includes it |
| `pnpm run build` fails on install | Run `pnpm approve-builds`; set `allowBuilds` to `true` in `pnpm-workspace.yaml` for packages with install scripts |
| OpenSSL `openssl.cnf` not found (Windows) | Scripts in `certs/*.ps1` set `OPENSSL_CONF` automatically |

## Further reading

- [Node.js TLS documentation](https://nodejs.org/api/tls.html)
- [RFC 8446 — TLS 1.3](https://datatracker.ietf.org/doc/html/rfc8446)
- [NestJS FAQ — HTTP adapter](https://docs.nestjs.com/faq/http-adapter)

-
Emi Roberti
