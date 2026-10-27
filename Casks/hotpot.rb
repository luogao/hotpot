cask "hotpot" do
  version "0.3.4"
  sha256 "c26d4c9f801c98ac03ed5531e9dc9e3d74d9a1182749f9c707e495f00855389f"

  url "https://github.com/luogao/hotpot/releases/download/v#{version}/HotPot-#{version}.zip"
  name "HotPot"
  desc "See which AI agent is cooking your Mac, and cool it down"
  homepage "https://github.com/luogao/hotpot"

  depends_on macos: :ventura
  depends_on arch: :arm64

  app "HotPot.app"

  # ad-hoc 签名的应用带 quarantine 会被 Gatekeeper 拦，装完直接去掉，
  # 用户不用再手动 xattr（cask 分发自己的签名产物，风险可控）
  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-dr", "com.apple.quarantine", "{{appdir}}/HotPot.app"],
        writable_paths: ["{{appdir}}/HotPot.app"]
  end

  caveats <<~EOS
    开机自启默认关闭，可在菜单栏图标上右键开启。
    规则表：~/Library/Application Support/HotPot/rules.json
  EOS

  zap trash: [
    "~/Library/Application Support/HotPot",
    "~/Library/Preferences/top.rungundam.hotpot.plist",
  ]
end
