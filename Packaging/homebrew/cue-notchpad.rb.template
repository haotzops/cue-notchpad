cask "cue-notchpad" do
  version "0.3.0"
  sha256 "30986fe3b04211d122f906dcfe69a33d21895d6f897e296aa7d2985ebc76b6f2"

  url "https://github.com/haotzops/cue-notchpad/releases/download/v#{version}/Cue-Notchpad-#{version}-macOS-universal.zip"
  name "Cue Notchpad"
  desc "Notch-attached prompt editor for command-line workflows"
  homepage "https://github.com/haotzops/cue-notchpad"

  depends_on macos: :ventura

  app "Cue Notchpad.app"
  binary "#{appdir}/Cue Notchpad.app/Contents/MacOS/cue", target: "cue"

  postflight do
    app_path = appdir/"Cue Notchpad.app"
    next unless app_path.exist?

    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", app_path]
  end

  caveats <<~EOS
    Cue Notchpad #{version} 使用 ad-hoc 签名，未经过 Apple 公证。
    Homebrew 安装完成后会自动移除该 app 的 quarantine 属性。
  EOS
end
