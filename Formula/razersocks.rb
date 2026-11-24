class Razersocks < Formula
  desc "Battery level of Razer wireless mice on the command-line"
  homepage "https://github.com/bramvanoost/razersocks"
  url "https://github.com/bramvanoost/razersocks/releases/download/v0.1.0/razersocks-0.1.0-macos-universal.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
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
