#!/bin/sh
# Usage: render-formula.sh <version> <sha256> [owner/repo]
# Prints the Homebrew formula for a release.
set -eu
version=$1
sha256=$2
repo=${3:-bramvanoost/razersocks}

cat <<EOF
class Razersocks < Formula
  desc "Battery level of Razer wireless mice on the command-line"
  homepage "https://github.com/$repo"
  url "https://github.com/$repo/releases/download/v$version/razersocks-$version-macos-universal.tar.gz"
  sha256 "$sha256"
  license "MIT"

  depends_on :macos

  def install
    bin.install "razersocks"
  end

  def caveats
    <<~EOS
      razersocks needs Input Monitoring permission for the app that runs it:
        System Settings > Privacy & Security > Input Monitoring
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/razersocks --version")
  end
end
EOF
