cask "hotpot" do
  version "0.2.0"
  sha256 "4fffff99889a231af9522596e3d2124c807ef919147c24e952ab52c0acfbb021"

  url "https://github.com/luogao/hotpot/releases/download/v#{version}/HotPot-#{version}.zip",
      verified: "github.com/luogao/hotpot/"
  name "HotPot"
  desc "See which AI agent is cooking your Mac, and cool it down"
  homepage "https://github.com/luogao/hotpot"

  depends_on macos: ">= :ventura"
  depends_on arch: :arm64

  app "HotPot.app"

  caveats <<~EOS
    HotPot 使用 ad-hoc 签名，首次打开需右键 →「打开」，或先执行：
      xattr -d com.apple.quarantine "#{appdir}/HotPot.app"

    开机自启默认关闭，可在菜单栏图标上右键开启。
    规则表：~/Library/Application Support/HotPot/rules.json
  EOS

  zap trash: [
    "~/Library/Application Support/HotPot",
    "~/Library/Preferences/top.rungundam.hotpot.plist",
  ]
end
