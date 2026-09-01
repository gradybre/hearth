# Adds the share-extension target to Runner.xcodeproj.
#
# The target is already in the committed project — this is how it got there,
# kept so the change is reproducible rather than a 200-line diff nobody can
# read or redo. Run it after a regenerated project, or to rebuild the target
# from scratch; it is a no-op when the target is already present.
#
#   gem install xcodeproj --user-install
#   cd ios && ruby tools/add_share_extension.rb
#
# The extension needs an App Group, an App Group needs an explicit App ID, and
# `com.hearth.hearth` turned out to be registered to somebody else's team —
# which is why the app is `com.brendangrady.hearth`.
#
# Everything else the extension needs is in the tree: ShareExtension/,
# Runner/SharedContentChannel.swift, Runner/Runner.entitlements, and the
# `hearth` URL scheme in Runner/Info.plist.
require 'xcodeproj'

project = Xcodeproj::Project.open('Runner.xcodeproj')
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'no Runner target' unless runner

if project.targets.any? { |t| t.name == 'ShareExtension' }
  puts 'ShareExtension already present'
  exit 0
end

extension = project.new_target(
  :app_extension, 'ShareExtension', :ios, runner.deployment_target
)

group = project.new_group('ShareExtension', 'ShareExtension')
extension.add_file_references([group.new_reference('ShareViewController.swift')])
group.new_reference('Info.plist')
group.new_reference('ShareExtension.entitlements')

extension.build_configurations.each do |config|
  twin = runner.build_configurations.find { |c| c.name == config.name }
  base = twin&.build_settings || {}

  # The same xcconfig Runner uses, which is where FLUTTER_BUILD_NAME and
  # FLUTTER_BUILD_NUMBER come from. Without it the extension's Info.plist
  # resolves them to empty strings and installd refuses the whole app:
  # "does not have a CFBundleVersion key with a non-zero length string value".
  # Sharing the file also keeps the extension's version in step with the app's,
  # which the App Store requires of them.
  config.base_configuration_reference = twin&.base_configuration_reference

  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.brendangrady.hearth.share',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'INFOPLIST_FILE' => 'ShareExtension/Info.plist',
    'CODE_SIGN_ENTITLEMENTS' => 'ShareExtension/ShareExtension.entitlements',
    'CODE_SIGN_STYLE' => 'Automatic',
    'DEVELOPMENT_TEAM' => base['DEVELOPMENT_TEAM'] || 'PG69N6TCSW',
    'IPHONEOS_DEPLOYMENT_TARGET' =>
      base['IPHONEOS_DEPLOYMENT_TARGET'] || runner.deployment_target,
    'SWIFT_VERSION' => base['SWIFT_VERSION'] || '5.0',
    'TARGETED_DEVICE_FAMILY' => base['TARGETED_DEVICE_FAMILY'] || '1,2',
    'SKIP_INSTALL' => 'YES',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    # Plain UIKit — no Flutter engine, no plugins. It writes a file and gets
    # out of the way.
    'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES' => 'NO',
  )
end

# The app signs the same App Group, and must build and embed the extension.
runner.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end
project.main_group['Runner'].new_reference('Runner.entitlements')
runner.add_dependency(extension)

embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
# Before Thin Binary, which walks what has already been copied.
thin = runner.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
if thin
  runner.build_phases.delete(embed)
  runner.build_phases.insert(thin, embed)
end
embed.add_file_reference(extension.product_reference).settings = {
  'ATTRIBUTES' => ['RemoveHeadersOnCopy'],
}

project.save
puts "added ShareExtension (#{project.targets.map(&:name).join(', ')})"
