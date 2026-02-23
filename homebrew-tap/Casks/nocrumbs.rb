cask "nocrumbs" do
  version "0.4.2"
  sha256 "PLACEHOLDER"

  url "https://github.com/geneyoo/nocrumbs/releases/download/v#{version}/NoCrumbs-#{version}.zip"
  name "NoCrumbs"
  desc "Catch every crumb your agent leaves behind"
  homepage "https://nocrumbs.ai"

  depends_on macos: ">= :sonoma"

  conflicts_with formula: "nocrumbs"

  preflight do
    # Clean up stale symlinks left by the old formula install
    %w[/usr/local/bin/nocrumbs /opt/homebrew/bin/nocrumbs].each do |path|
      if File.symlink?(path) && !File.exist?(path)
        File.delete(path)
      end
    end
  end

  app "NoCrumbs.app"
  binary "#{appdir}/NoCrumbs.app/Contents/Resources/nocrumbs"

  zap trash: [
    "~/Library/Application Support/NoCrumbs",
  ]
end
