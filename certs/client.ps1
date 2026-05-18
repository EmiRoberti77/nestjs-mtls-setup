# Anaconda/Git OpenSSL often point OPENSSLDIR at a path without openssl.cnf
if (-not $env:OPENSSL_CONF -or -not (Test-Path $env:OPENSSL_CONF)) {
    $opensslExe = (Get-Command openssl -ErrorAction Stop).Source
    $candidate = Join-Path (Split-Path (Split-Path $opensslExe -Parent) -Parent) "ssl\openssl.cnf"
    if (Test-Path $candidate) {
        $env:OPENSSL_CONF = $candidate
    }
}

# Client cert
openssl genrsa -out client.key 2048

openssl req -new -key client.key -subj "/CN=my-client" -out client.csr

@"
extendedKeyUsage=clientAuth
"@ | Set-Content -Path client.ext -Encoding ascii

openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial `
    -out client.crt -days 365 -sha256 `
    -extfile client.ext
