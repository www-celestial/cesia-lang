# Installs Cesia on Windows, from its releases:
#   irm https://raw.githubusercontent.com/www-celestial/cesia-lang/main/install.ps1 | iex
# The archive (bin\cesia.exe and lib\, every C library it uses) goes into %USERPROFILE%\.cesia once its fingerprint is checked,
# with ce.exe beside cesia.exe, and that folder goes on the Path of the user. Then cesia upgrade keeps it up to date.
# CESIA_HOME changes the folder; CESIA_RELEASES=file:///folder reads a folder instead of GitHub.
$ErrorActionPreference = "Stop"
$archive = "cesia-windows-x86_64.zip"
$releases = if ($env:CESIA_RELEASES) { $env:CESIA_RELEASES } else { "https://github.com/www-celestial/cesia-lang/releases/latest/download" }
$target = if ($env:CESIA_HOME) { $env:CESIA_HOME } else { Join-Path $env:USERPROFILE ".cesia" }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cesia-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null

function Fetch($url, $file) {
  if ($url.StartsWith("file://")) { Copy-Item $url.Substring(7) $file } else { Invoke-WebRequest $url -OutFile $file -UseBasicParsing }
}

try {
  Fetch "$releases/$archive" "$tmp\$archive"
  Fetch "$releases/$archive.sha256" "$tmp\$archive.sha256"
  $want = (Get-Content "$tmp\$archive.sha256" -Raw).Trim().Split(" ")[0]
  $have = (Get-FileHash "$tmp\$archive" -Algorithm SHA256).Hash.ToLower()
  if ($have -ne $want) { throw "The download of $archive doesn't match its fingerprint: nothing installed." }
  Expand-Archive "$tmp\$archive" -DestinationPath "$tmp\new"
  $version = & "$tmp\new\bin\cesia.exe" version
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  foreach ($part in "bin", "lib") {
    $old = Join-Path $target $part
    if (Test-Path $old) { Remove-Item -Recurse -Force $old }
    Move-Item (Join-Path "$tmp\new" $part) $old
  }
  Copy-Item "$target\bin\cesia.exe" "$target\bin\ce.exe"
  $path = [Environment]::GetEnvironmentVariable("Path", "User")
  if (-not (($path -split ";") -contains "$target\bin")) {
    [Environment]::SetEnvironmentVariable("Path", "$path;$target\bin", "User")
    Write-Output "Added $target\bin to your Path: open a new terminal."
  }
  Write-Output "Installed $version in $target."
} finally {
  Remove-Item -Recurse -Force $tmp
}
