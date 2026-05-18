# Anaconda/Git OpenSSL often point OPENSSLDIR at a path without openssl.cnf
if (-not $env:OPENSSL_CONF -or -not (Test-Path $env:OPENSSL_CONF)) {
    $opensslExe = (Get-Command openssl -ErrorAction Stop).Source
    $candidate = Join-Path (Split-Path (Split-Path $opensslExe -Parent) -Parent) "ssl\openssl.cnf"
    if (Test-Path $candidate) {
        $env:OPENSSL_CONF = $candidate
    }
}

openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -subj "/CN=Local Dev CA" -out ca.crt
