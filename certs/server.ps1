# Anaconda/Git OpenSSL often point OPENSSLDIR at a path without openssl.cnf
if (-not $env:OPENSSL_CONF -or -not (Test-Path $env:OPENSSL_CONF)) {
    $opensslExe = (Get-Command openssl -ErrorAction Stop).Source
    $candidate = Join-Path (Split-Path (Split-Path $opensslExe -Parent) -Parent) "ssl\openssl.cnf"
    if (Test-Path $candidate) {
        $env:OPENSSL_CONF = $candidate
    }
}

# Server cert
openssl genrsa -out server.key 2048

openssl req -new -key server.key -subj "/CN=localhost" -out server.csr

@"
subjectAltName=DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth
"@ | Set-Content -Path server.ext -Encoding ascii

openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial `
    -out server.crt -days 365 -sha256 `
    -extfile server.ext
