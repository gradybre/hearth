# Adds the share-extension target to Runner.xcodeproj.
#
# Kept as a script rather than committed as project edits because it cannot be
# used yet: the target needs an App Group, an App Group needs an explicit App
# ID, and registering `com.hearth.hearth` fails with "cannot be registered to
# your development team because it is not available". Until that is settled the
# extension would only break the build, so the app ships without it and this
# turns it back on in one command.
#
#   gem install xcodeproj --user-install
#   cd ios && ruby tools/add_share_extension.rb
#
# Everything else the extension needs is already in the tree: ShareExtension/,
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
  base = runner.build_configurations
    .find { |c| c.name == config.name }&.build_settings || {}

  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.hearth.hearth.share',
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
