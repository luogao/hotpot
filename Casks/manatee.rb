cask "manatee" do
  version "0.6.3"
  sha256 "84b008db89e0d65fe16b45057c29fa291dc1021f0512ee0cbebdedfda8ff3680"

  url "https://github.com/luogao/manatee/releases/download/v#{version}/Manatee-#{version}.zip"
  name "Manatee"
  desc "See which AI agent is maxing out your Mac, and slow it down without stopping it"
  homepage "https://manatee.rungundam.top"

  depends_on macos: :ventura
  depends_on arch: :arm64

  app "Manatee.app"

  # ad-hoc 签名的应用带 quarantine 会被 Gatekeeper 拦，装完直接去掉，
  # 用户不用再手动 xattr（cask 分发自己的签名产物，风险可控）
  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-dr", "com.apple.quarantine", "{{appdir}}/Manatee.app"],
        writable_paths: ["{{appdir}}/Manatee.app"]
  end

  caveats <<~EOS
    开机自启默认关闭，可在菜单栏图标上右键开启。
    规则表：~/Library/Application Support/Manatee/rules.json
  EOS

  zap trash: [
    "~/Library/Application Support/Manatee",
    "~/Library/Preferences/top.rungundam.manatee.plist",
  ]
end
